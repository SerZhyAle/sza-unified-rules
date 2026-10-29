Option Explicit On
Option Strict On

Imports System.Globalization
Imports System.Linq

''' <summary>
''' Provider order dialog: which model providers spend tokens and in what order. The first checked provider works
''' until its usage limit is spent; the next one takes over only then. 'pq agents' reads and writes the choice
''' (agentOrder in repos.json); a running worker applies it to the next ticket it takes.
''' </summary>
Public Class FormProviders
    Inherits Form

    ' One list entry: what 'pq agents -Json' said about a provider.
    Private Class ProviderRow
        Public Property Id As String = ""
        Public Property Label As String = ""
        Public Property CliFound As Boolean
        Public Property CliNote As String = ""
        Public Property Position As Integer
        Public Property Held As Boolean
        Public Property HoldKind As String = ""
        Public Property HoldUntil As String = ""

        Public Overrides Function ToString() As String
            Dim state As String = ""
            If Not CliFound Then
                state = CliNote
            ElseIf Held Then
                Dim parsed As DateTimeOffset
                Dim whenText As String = HoldUntil
                If DateTimeOffset.TryParse(HoldUntil, CultureInfo.InvariantCulture, DateTimeStyles.None, parsed) Then
                    whenText = parsed.LocalDateTime.ToString("yyyy-MM-dd HH:mm")
                End If
                state = If(HoldKind = "resets", $"usage limit spent, back at {whenText}", $"usage limit spent, probed again at {whenText}")
            End If
            Return If(state = "", Label, $"{Label}  -  {state}")
        End Function
    End Class

    Private lstProviders As CheckedListBox
    Private btnUp As Button
    Private btnDown As Button
    Private btnClearLimit As Button
    Private btnApply As Button
    Private btnClose As Button
    Private lblMsg As Label
    Private _loading As Boolean = False

    ' What pq printed, for the main window's console.
    Public Property ResultText As String = ""

    Public Sub New()
        InitializeComponent()
    End Sub

    Private Sub InitializeComponent()
        Me.Text = "Model Providers"
        Me.AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        Me.AutoScaleMode = AutoScaleMode.Font
        Me.ClientSize = New Size(620, 400)
        Me.FormBorderStyle = FormBorderStyle.FixedDialog
        Me.MaximizeBox = False
        Me.MinimizeBox = False
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)

        Dim lblInfo As New Label With {
            .Text = "Check the providers that may spend tokens and put them in order. The first one works until its usage limit is spent; the next one takes over only then, and the first is tried again when its limit lifts.",
            .Location = New Point(20, 16),
            .Size = New Size(580, 44)
        }

        lstProviders = New CheckedListBox With {
            .Location = New Point(20, 70),
            .Size = New Size(450, 220),
            .CheckOnClick = True,
            .IntegralHeight = False,
            .HorizontalScrollbar = True,
            .AccessibleName = "Providers list"
        }
        AddHandler lstProviders.ItemCheck, AddressOf LstProviders_ItemCheck

        btnUp = New Button With {
            .Name = "btnProviderUp",
            .Text = "▲ Up",
            .Location = New Point(485, 70),
            .Size = New Size(115, 32),
            .AccessibleName = "Move provider up",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnUp.Click, Sub() MoveSelected(-1)

        btnDown = New Button With {
            .Name = "btnProviderDown",
            .Text = "▼ Down",
            .Location = New Point(485, 108),
            .Size = New Size(115, 32),
            .AccessibleName = "Move provider down",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnDown.Click, Sub() MoveSelected(1)

        btnClearLimit = New Button With {
            .Name = "btnProviderClearLimit",
            .Text = "Clear &limit",
            .Location = New Point(485, 170),
            .Size = New Size(115, 32),
            .AccessibleName = "Clear the usage limit of the selected provider",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnClearLimit.Click, AddressOf BtnClearLimit_Click

        Dim lblHint As New Label With {
            .Text = "Clear limit: try the selected provider again now, e.g. after topping up.",
            .Location = New Point(485, 208),
            .Size = New Size(115, 82)
        }

        lblMsg = New Label With {
            .Location = New Point(20, 300),
            .Size = New Size(580, 44)
        }

        btnApply = New Button With {
            .Name = "btnProviderApply",
            .Text = "&Apply",
            .Location = New Point(385, 352),
            .Size = New Size(110, 34),
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .AccessibleName = "Apply provider order",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnApply.Click, AddressOf BtnApply_Click

        btnClose = New Button With {
            .Name = "btnProviderClose",
            .Text = "Close",
            .Location = New Point(505, 352),
            .Size = New Size(95, 34),
            .AccessibleName = "Close",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnClose.Click, Sub() Me.DialogResult = DialogResult.Cancel

        Me.Controls.AddRange({lblInfo, lstProviders, btnUp, btnDown, btnClearLimit, lblHint, lblMsg, btnApply, btnClose})

        Me.AcceptButton = btnApply
        Me.CancelButton = btnClose

        lstProviders.TabIndex = 0
        btnUp.TabIndex = 1
        btnDown.TabIndex = 2
        btnClearLimit.TabIndex = 3
        btnApply.TabIndex = 4
        btnClose.TabIndex = 5
    End Sub

    Protected Overrides Sub OnShown(e As EventArgs)
        MyBase.OnShown(e)
        ThemeService.ApplyTheme(Me)
        AddHandler ThemeService.ThemeChanged, Sub() ThemeService.ApplyTheme(Me)
        LoadProviders()
    End Sub

    Private Shared Function GetStr(e As JsonElement, name As String) As String
        Dim v As JsonElement
        If e.TryGetProperty(name, v) AndAlso v.ValueKind = JsonValueKind.String Then Return If(v.GetString(), "")
        Return ""
    End Function

    Private Shared Function GetBool(e As JsonElement, name As String) As Boolean
        Dim v As JsonElement
        Return e.TryGetProperty(name, v) AndAlso v.ValueKind = JsonValueKind.True
    End Function

    Private Shared Function GetInt(e As JsonElement, name As String) As Integer
        Dim v As JsonElement
        If e.TryGetProperty(name, v) AndAlso v.ValueKind = JsonValueKind.Number Then Return v.GetInt32()
        Return 0
    End Function

    ' Providers in the order pq reports them: the chosen ones first, in their order, then the rest.
    Private Async Sub LoadProviders()
        lblMsg.ForeColor = ThemeService.Palette.Accent
        lblMsg.Text = "Reading the providers.."
        btnApply.Enabled = False
        Dim res = Await PqCli.RunSilentAsync("agents", "-Json")
        If Not res.Success Then
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = res.Message
            Return
        End If

        Dim rows As New List(Of ProviderRow)
        Try
            Using doc = JsonDocument.Parse(res.Output.Trim())
                For Each item In doc.RootElement.EnumerateArray()
                    rows.Add(New ProviderRow With {
                        .Id = GetStr(item, "id"),
                        .Label = GetStr(item, "label"),
                        .CliFound = GetBool(item, "cliFound"),
                        .CliNote = GetStr(item, "cliNote"),
                        .Position = GetInt(item, "position"),
                        .Held = GetBool(item, "held"),
                        .HoldKind = GetStr(item, "holdKind"),
                        .HoldUntil = GetStr(item, "holdUntil")
                    })
                Next
            End Using
        Catch ex As Exception
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = $"Cannot read what pq reported: {ex.Message}"
            Return
        End Try

        Dim ordered = rows.Where(Function(r) r.Position > 0).OrderBy(Function(r) r.Position).Concat(rows.Where(Function(r) r.Position = 0)).ToList()
        _loading = True
        lstProviders.Items.Clear()
        For Each r In ordered
            lstProviders.Items.Add(r, r.Position > 0)
        Next
        If lstProviders.Items.Count > 0 Then lstProviders.SelectedIndex = 0
        _loading = False
        lblMsg.Text = ""
        btnApply.Enabled = True
    End Sub

    ' A provider whose CLI is missing cannot be chosen: pq would refuse it, and the note says what to install.
    Private Sub LstProviders_ItemCheck(sender As Object, e As ItemCheckEventArgs)
        If _loading Then Return
        Dim row = TryCast(lstProviders.Items(e.Index), ProviderRow)
        If row IsNot Nothing AndAlso e.NewValue = CheckState.Checked AndAlso Not row.CliFound Then
            e.NewValue = CheckState.Unchecked
            lblMsg.ForeColor = ThemeService.Palette.StatusWarning
            lblMsg.Text = $"{row.Label}: {row.CliNote}"
        End If
    End Sub

    Private Sub MoveSelected(delta As Integer)
        Dim i = lstProviders.SelectedIndex
        Dim j = i + delta
        If i < 0 OrElse j < 0 OrElse j >= lstProviders.Items.Count Then Return
        Dim item = lstProviders.Items(i)
        Dim isChecked = lstProviders.GetItemChecked(i)
        _loading = True
        lstProviders.Items.RemoveAt(i)
        lstProviders.Items.Insert(j, item)
        lstProviders.SetItemChecked(j, isChecked)
        lstProviders.SelectedIndex = j
        _loading = False
    End Sub

    Private Async Sub BtnApply_Click(sender As Object, e As EventArgs)
        Dim ids As New List(Of String)
        For i = 0 To lstProviders.Items.Count - 1
            Dim row = TryCast(lstProviders.Items(i), ProviderRow)
            If row IsNot Nothing AndAlso lstProviders.GetItemChecked(i) Then ids.Add(row.Id)
        Next
        If ids.Count = 0 Then
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = "Check at least one provider."
            Return
        End If

        lblMsg.ForeColor = ThemeService.Palette.Accent
        lblMsg.Text = "Writing the order.."
        btnApply.Enabled = False
        Dim res = Await PqCli.RunSilentAsync("agents", "-Order", String.Join(",", ids))
        If res.Success Then
            ResultText = $"Provider order: {String.Join(" > ", ids)}. A running worker uses it from its next ticket."
            Me.DialogResult = DialogResult.OK
        Else
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = res.Message
            btnApply.Enabled = True
        End If
    End Sub

    Private Async Sub BtnClearLimit_Click(sender As Object, e As EventArgs)
        Dim row = TryCast(lstProviders.SelectedItem, ProviderRow)
        If row Is Nothing Then Return
        btnClearLimit.Enabled = False
        Dim res = Await PqCli.RunSilentAsync("agents", "-Release", row.Id)
        btnClearLimit.Enabled = True
        If res.Success Then
            LoadProviders()
        Else
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = res.Message
        End If
    End Sub
End Class
