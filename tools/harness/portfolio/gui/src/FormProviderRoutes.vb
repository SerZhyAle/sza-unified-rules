Option Explicit On
Option Strict On

Imports System.Globalization
Imports System.Linq

''' <summary>
''' Grade routes dialog (TASK-FLOW 0.32/0.33, canon ticket S0141): which grades each agent record takes and with which
''' model, effort and parallel axis, the raters that grade an ungraded ticket, and escalateBy. It reads
''' 'pq agents -Settings -Json' and writes through 'pq agents -Apply &lt;file&gt;', so the registry check, the merge that keeps
''' every other key of a record and the registry.changed event are pq's, never this dialog's.
''' </summary>
Public Class FormProviderRoutes
    Inherits Form

    Private dgvRoutes As DataGridView
    Private dgvRaters As DataGridView
    Private numEscalate As NumericUpDown
    Private btnApply As Button
    Private btnClose As Button
    Private lblMsg As Label
    Private _agents As New List(Of String)
    Private _escalateWasSet As Boolean
    Private _escalateLoaded As Integer = 2

    ' What pq printed, for the main window's console.
    Public Property ResultText As String = ""

    Public Sub New()
        InitializeComponent()
    End Sub

    Private Sub InitializeComponent()
        Me.Text = "Grade Routes"
        Me.AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        Me.AutoScaleMode = AutoScaleMode.Font
        Me.ClientSize = New Size(760, 600)
        Me.FormBorderStyle = FormBorderStyle.FixedDialog
        Me.MaximizeBox = False
        Me.MinimizeBox = False
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)

        Dim lblRoutes As New Label With {
            .Text = "Routes: a ticket's grade (0-9) goes to the first row of an agent whose Max is at or above it, with that row's model, effort and parallel axis; the agent's last Max is its ceiling, and a ticket above it goes to the next provider. An agent with no rows takes every grade as before. Parallel (ultracode) is read for claude only, on a ticket whose spec carries the Parallel flag.",
            .Location = New Point(20, 12),
            .Size = New Size(720, 62)
        }

        dgvRoutes = New DataGridView With {
            .Name = "dgvRoutes",
            .Location = New Point(20, 78),
            .Size = New Size(720, 250),
            .AllowUserToAddRows = True,
            .AllowUserToDeleteRows = True,
            .RowHeadersVisible = True,
            .SelectionMode = DataGridViewSelectionMode.CellSelect,
            .AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            .AccessibleName = "Grade routes"
        }
        dgvRoutes.Columns.Add(New DataGridViewComboBoxColumn With {.Name = "colAgent", .HeaderText = "Agent", .FillWeight = 30, .FlatStyle = FlatStyle.Flat})
        dgvRoutes.Columns.Add(New DataGridViewTextBoxColumn With {.Name = "colMax", .HeaderText = "Max grade", .FillWeight = 14})
        dgvRoutes.Columns.Add(New DataGridViewTextBoxColumn With {.Name = "colModel", .HeaderText = "Model (empty = the record's)", .FillWeight = 28})
        dgvRoutes.Columns.Add(New DataGridViewTextBoxColumn With {.Name = "colEffort", .HeaderText = "Effort", .FillWeight = 14})
        Dim colParallel As New DataGridViewComboBoxColumn With {.Name = "colParallel", .HeaderText = "Parallel", .FillWeight = 14, .FlatStyle = FlatStyle.Flat}
        colParallel.Items.AddRange("", "ultracode")
        dgvRoutes.Columns.Add(colParallel)
        AddHandler dgvRoutes.DataError, Sub(s, ev) ev.ThrowException = False

        Dim lblRaters As New Label With {
            .Text = "Raters: before its pass an ungraded ticket is graded once by the first rater that answers (no rows: nothing is rated). Keys this table does not show (argsTemplate, env) are kept.",
            .Location = New Point(20, 338),
            .Size = New Size(720, 34)
        }

        dgvRaters = New DataGridView With {
            .Name = "dgvRaters",
            .Location = New Point(20, 374),
            .Size = New Size(720, 110),
            .AllowUserToAddRows = True,
            .AllowUserToDeleteRows = True,
            .RowHeadersVisible = True,
            .SelectionMode = DataGridViewSelectionMode.CellSelect,
            .AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill,
            .AccessibleName = "Raters"
        }
        dgvRaters.Columns.Add(New DataGridViewTextBoxColumn With {.Name = "colRName", .HeaderText = "Name", .FillWeight = 20})
        dgvRaters.Columns.Add(New DataGridViewTextBoxColumn With {.Name = "colRCommand", .HeaderText = "Command", .FillWeight = 20})
        dgvRaters.Columns.Add(New DataGridViewTextBoxColumn With {.Name = "colRModel", .HeaderText = "Model", .FillWeight = 40})
        dgvRaters.Columns.Add(New DataGridViewTextBoxColumn With {.Name = "colRTimeout", .HeaderText = "Timeout, s", .FillWeight = 20})

        Dim lblEscalate As New Label With {
            .Text = "Escalate by (a failed pass raises the ticket's grade by this much; 0 = off):",
            .Location = New Point(20, 496),
            .Size = New Size(450, 24)
        }
        numEscalate = New NumericUpDown With {
            .Name = "numEscalate",
            .Location = New Point(480, 494),
            .Size = New Size(70, 24),
            .Minimum = 0,
            .Maximum = 9,
            .Value = 2,
            .AccessibleName = "Escalate by"
        }

        lblMsg = New Label With {
            .Location = New Point(20, 524),
            .Size = New Size(720, 26)
        }

        btnApply = New Button With {
            .Name = "btnRoutesApply",
            .Text = "&Apply",
            .Location = New Point(525, 554),
            .Size = New Size(110, 34),
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .AccessibleName = "Apply routes, raters and escalate by",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnApply.Click, AddressOf BtnApply_Click

        btnClose = New Button With {
            .Name = "btnRoutesClose",
            .Text = "Close",
            .Location = New Point(645, 554),
            .Size = New Size(95, 34),
            .AccessibleName = "Close",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnClose.Click, Sub() Me.DialogResult = DialogResult.Cancel

        Me.Controls.AddRange({lblRoutes, dgvRoutes, lblRaters, dgvRaters, lblEscalate, numEscalate, lblMsg, btnApply, btnClose})
        Me.CancelButton = btnClose

        dgvRoutes.TabIndex = 0
        dgvRaters.TabIndex = 1
        numEscalate.TabIndex = 2
        btnApply.TabIndex = 3
        btnClose.TabIndex = 4
    End Sub

    Protected Overrides Sub OnShown(e As EventArgs)
        MyBase.OnShown(e)
        ThemeService.ApplyTheme(Me)
        AddHandler ThemeService.ThemeChanged, Sub() ThemeService.ApplyTheme(Me)
        LoadSettings()
    End Sub

    Private Shared Function GetStr(e As JsonElement, name As String) As String
        Dim v As JsonElement
        If e.TryGetProperty(name, v) Then
            If v.ValueKind = JsonValueKind.String Then Return If(v.GetString(), "")
            If v.ValueKind = JsonValueKind.Number Then Return v.GetRawText()
        End If
        Return ""
    End Function

    Private Shared Function GetInt(e As JsonElement, name As String, fallback As Integer) As Integer
        Dim v As JsonElement
        If e.TryGetProperty(name, v) AndAlso v.ValueKind = JsonValueKind.Number Then Return v.GetInt32()
        Return fallback
    End Function

    ' Agents in the provider order, then the ones outside it; each agent's rows by Max.
    Private Async Sub LoadSettings()
        lblMsg.ForeColor = ThemeService.Palette.Accent
        lblMsg.Text = "Reading the routes.."
        btnApply.Enabled = False
        Dim res = Await PqCli.RunSilentAsync("agents", "-Settings", "-Json")
        If IsDisposed Then Return
        If Not res.Success Then
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = res.Message
            Return
        End If
        Try
            Using doc = JsonDocument.Parse(res.Output.Trim())
                Dim root = doc.RootElement
                Dim agents = root.GetProperty("agents").EnumerateArray().ToList()
                Dim ordered = agents.Where(Function(a) GetInt(a, "position", 0) > 0).OrderBy(Function(a) GetInt(a, "position", 0)) _
                    .Concat(agents.Where(Function(a) GetInt(a, "position", 0) = 0)).ToList()
                _agents = ordered.Select(Function(a) GetStr(a, "name")).Where(Function(n) n <> "").ToList()
                Dim colAgent = DirectCast(dgvRoutes.Columns("colAgent"), DataGridViewComboBoxColumn)
                colAgent.Items.Clear()
                For Each n In _agents
                    colAgent.Items.Add(n)
                Next
                dgvRoutes.Rows.Clear()
                For Each a In ordered
                    Dim name = GetStr(a, "name")
                    Dim routes As JsonElement
                    If Not a.TryGetProperty("routes", routes) OrElse routes.ValueKind <> JsonValueKind.Array Then Continue For
                    For Each r In routes.EnumerateArray()
                        dgvRoutes.Rows.Add(name, GetStr(r, "max"), GetStr(r, "model"), GetStr(r, "effort"), GetStr(r, "parallel"))
                    Next
                Next
                dgvRaters.Rows.Clear()
                Dim raters As JsonElement
                If root.TryGetProperty("raters", raters) AndAlso raters.ValueKind = JsonValueKind.Array Then
                    For Each r In raters.EnumerateArray()
                        dgvRaters.Rows.Add(GetStr(r, "name"), GetStr(r, "command"), GetStr(r, "model"), GetStr(r, "timeoutSeconds"))
                    Next
                End If
                _escalateLoaded = GetInt(root, "escalateBy", 2)
                Dim setV As JsonElement
                _escalateWasSet = root.TryGetProperty("escalateBySet", setV) AndAlso setV.ValueKind = JsonValueKind.True
                numEscalate.Value = Math.Max(0, Math.Min(9, _escalateLoaded))
            End Using
        Catch ex As Exception
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = $"Cannot read what pq reported: {ex.Message}"
            Return
        End Try
        lblMsg.Text = ""
        btnApply.Enabled = True
    End Sub

    Private Shared Function CellText(row As DataGridViewRow, column As String) As String
        Dim v = row.Cells(column).Value
        Return If(v Is Nothing, "", Convert.ToString(v, CultureInfo.InvariantCulture)).Trim()
    End Function

    ' A whole number goes as a number, anything else as the text typed, so pq's check names the bad cell.
    Private Shared Sub WriteNumberOrText(w As Utf8JsonWriter, name As String, text As String)
        Dim n As Integer
        If Integer.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, n) Then
            w.WriteNumber(name, n)
        Else
            w.WriteString(name, text)
        End If
    End Sub

    ' Every agent is written: one with no rows gets [] and so loses its routes (it takes every grade again).
    Private Function BuildSettingsJson() As String
        Using ms As New MemoryStream()
            Using w As New Utf8JsonWriter(ms, New JsonWriterOptions With {.Indented = True})
                w.WriteStartObject()
                w.WriteStartObject("routes")
                For Each agentName In _agents
                    w.WriteStartArray(agentName)
                    For Each row As DataGridViewRow In dgvRoutes.Rows
                        If row.IsNewRow Then Continue For
                        If CellText(row, "colAgent") <> agentName Then Continue For
                        w.WriteStartObject()
                        WriteNumberOrText(w, "max", CellText(row, "colMax"))
                        For Each pair In {("model", "colModel"), ("effort", "colEffort"), ("parallel", "colParallel")}
                            Dim t = CellText(row, pair.Item2)
                            If t <> "" Then w.WriteString(pair.Item1, t)
                        Next
                        w.WriteEndObject()
                    Next
                    w.WriteEndArray()
                Next
                w.WriteEndObject()
                w.WriteStartArray("raters")
                For Each row As DataGridViewRow In dgvRaters.Rows
                    If row.IsNewRow Then Continue For
                    If CellText(row, "colRName") = "" AndAlso CellText(row, "colRCommand") = "" AndAlso CellText(row, "colRModel") = "" Then Continue For
                    w.WriteStartObject()
                    w.WriteString("name", CellText(row, "colRName"))
                    w.WriteString("command", CellText(row, "colRCommand"))
                    w.WriteString("model", CellText(row, "colRModel"))
                    Dim t = CellText(row, "colRTimeout")
                    If t <> "" Then WriteNumberOrText(w, "timeoutSeconds", t)
                    w.WriteEndObject()
                Next
                w.WriteEndArray()
                ' An unset escalateBy left at its default stays unset.
                Dim esc = CInt(numEscalate.Value)
                If _escalateWasSet OrElse esc <> _escalateLoaded Then w.WriteNumber("escalateBy", esc)
                w.WriteEndObject()
            End Using
            Return Encoding.UTF8.GetString(ms.ToArray())
        End Using
    End Function

    Private Async Sub BtnApply_Click(sender As Object, e As EventArgs)
        Dim orphan = dgvRoutes.Rows.Cast(Of DataGridViewRow)().FirstOrDefault(Function(r) Not r.IsNewRow AndAlso Not _agents.Contains(CellText(r, "colAgent")))
        If orphan IsNot Nothing Then
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = $"Row {orphan.Index + 1}: choose its agent."
            Return
        End If
        Dim file = Path.Combine(Path.GetTempPath(), $"pq-agent-settings-{Guid.NewGuid():N}.json")
        lblMsg.ForeColor = ThemeService.Palette.Accent
        lblMsg.Text = "Writing the routes.."
        btnApply.Enabled = False
        Try
            System.IO.File.WriteAllText(file, BuildSettingsJson(), New UTF8Encoding(False))
            Dim res = Await PqCli.RunSilentAsync("agents", "-Apply", file)
            If IsDisposed Then Return
            If res.Success Then
                ResultText = "Grade routes, raters and escalate by written. A running worker uses them from its next ticket."
                Me.DialogResult = DialogResult.OK
            Else
                lblMsg.ForeColor = ThemeService.Palette.StatusDanger
                lblMsg.Text = res.Message
                btnApply.Enabled = True
            End If
        Catch ex As Exception
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = ex.Message
            btnApply.Enabled = True
        Finally
            Try
                If System.IO.File.Exists(file) Then System.IO.File.Delete(file)
            Catch
            End Try
        End Try
    End Sub
End Class
