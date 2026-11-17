Option Explicit On
Option Strict On

Imports System.Linq

' The Releases tab (canon S0092, RELEASE-LEDGER 0.1): one row per registered project, read from 'pq releases -Json' -
' the last build, and per channel kind the live version and what is in flight. Read-only: the panel never records a
' build or a publication and never probes a channel; each project's ledger is written by releases/release-ledger.ps1.

Public Class ReleaseCell
    Public Property Text As String = ""
    Public Property Tip As String = ""
    ' 0 nothing recorded, 1 live, 2 pending or submitted, 3 withdrawn, 4 blocked or rejected.
    Public Property Severity As Integer = 0
End Class

Public Class ReleaseRepo
    Public Property Key As String = ""
    Public Property Path As String = ""
    Public Property Dir As String = ""
    Public Property HasLedger As Boolean
    Public Property ErrorText As String = ""
    Public Property LastBuild As String = ""
    Public Property LastBuildAt As String = ""
    Public Property BuildsTip As String = ""
    Public Property Unpublished As New List(Of String)()
    Public Property Warnings As New List(Of String)()
    Public Property Cells As New Dictionary(Of String, ReleaseCell)(StringComparer.Ordinal)
End Class

Public Class ReleasesSnapshot
    ' One grid column per probe kind of RELEASE-LEDGER rule 3; url, manual and any kind the panel does not know go to
    ' "Other", so a new channel shows up without a panel change.
    Public Shared ReadOnly Columns As (Column As String, Header As String, Kind As String)() = {
        ("colRelGithub", "GitHub", "github"),
        ("colRelWinget", "winget", "winget"),
        ("colRelStore", "MS Store", "msstore"),
        ("colRelPlay", "Play", "play"),
        ("colRelChrome", "Chrome", "chrome"),
        ("colRelEdge", "Edge", "edge"),
        ("colRelVscode", "VS Code", "vscode"),
        ("colRelOther", "Other", "other")
    }

    Public Property Ok As Boolean
    Public Property ErrorText As String = ""
    Public Property ReadAt As DateTime = DateTime.Now
    Public Property Repos As New List(Of ReleaseRepo)()

    Public Shared Function Failed(message As String) As ReleasesSnapshot
        Return New ReleasesSnapshot With {.Ok = False, .ErrorText = message}
    End Function

    Public Shared Function Parse(json As String) As ReleasesSnapshot
        Dim snap As New ReleasesSnapshot With {.Ok = True}
        Using doc = JsonDocument.Parse(json)
            Dim reposEl As JsonElement
            If Not doc.RootElement.TryGetProperty("repos", reposEl) OrElse reposEl.ValueKind <> JsonValueKind.Array Then
                Return Failed("pq releases -Json gave no 'repos'")
            End If
            For Each e In reposEl.EnumerateArray()
                Dim r As New ReleaseRepo With {
                    .Key = Text(e, "key"), .Path = Text(e, "path"), .Dir = Text(e, "dir"),
                    .HasLedger = Bool(e, "hasLedger"), .ErrorText = Text(e, "error")
                }
                Dim lb As JsonElement
                If e.TryGetProperty("lastBuild", lb) AndAlso lb.ValueKind = JsonValueKind.Object Then
                    r.LastBuild = $"{Text(lb, "version")} {Text(lb, "kind")}".Trim()
                    r.LastBuildAt = Day(Text(lb, "builtAt"))
                End If
                Dim tip As New StringBuilder()
                For Each b In Items(e, "builds")
                    If tip.Length > 0 Then tip.AppendLine()
                    tip.Append($"{Text(b, "package")}/{Text(b, "flavor")} {Text(b, "kind")} {Text(b, "version")}  {Text(b, "builtAt").Replace("T", " ")}")
                Next
                r.BuildsTip = tip.ToString()
                For Each u In Items(e, "unpublished")
                    r.Unpublished.Add($"{Text(u, "package")}/{Text(u, "flavor")} {Text(u, "version")} built {Day(Text(u, "builtAt"))}")
                Next
                For Each w In Items(e, "warnings")
                    If w.ValueKind = JsonValueKind.String Then r.Warnings.Add(w.GetString())
                Next
                ' Several channels of one kind (two Play tracks, two forum threads, two packages) share the cell.
                Dim byColumn = New Dictionary(Of String, List(Of JsonElement))(StringComparer.Ordinal)
                For Each c In Items(e, "channels")
                    Dim kind = Text(c, "kind")
                    Dim col = If(Columns.Any(Function(x) x.Kind = kind), kind, "other")
                    If Not byColumn.ContainsKey(col) Then byColumn(col) = New List(Of JsonElement)()
                    byColumn(col).Add(c)
                Next
                For Each kv In byColumn
                    Dim cell As New ReleaseCell()
                    Dim texts As New List(Of String)()
                    Dim tips As New List(Of String)()
                    For Each c In kv.Value
                        Dim label = If(kv.Value.Count > 1, Text(c, "key") & " ", "")
                        Dim live As JsonElement
                        Dim liveVer = ""
                        Dim liveAt = ""
                        If c.TryGetProperty("live", live) AndAlso live.ValueKind = JsonValueKind.Object Then
                            liveVer = Text(live, "version")
                            liveAt = Day(Text(live, "at"))
                        End If
                        Dim flight = Items(c, "inFlight").Select(Function(f) $"{Text(f, "version")} {Text(f, "state")}").ToList()
                        Dim piece = label & If(liveVer <> "", liveVer, "-")
                        If flight.Count > 0 Then piece &= " → " & String.Join(", ", flight)
                        texts.Add(piece)
                        Dim status = Text(c, "status")
                        tips.Add($"{Text(c, "key")} ({Text(c, "package")}): {status}" &
                                 If(liveVer <> "", $"; live {liveVer} since {liveAt}", "") &
                                 If(flight.Count > 0, "; in flight " & String.Join(", ", flight), ""))
                        cell.Severity = Math.Max(cell.Severity, SeverityOf(status))
                    Next
                    cell.Text = String.Join("; ", texts)
                    cell.Tip = String.Join(Environment.NewLine, tips)
                    r.Cells(kv.Key) = cell
                Next
                snap.Repos.Add(r)
            Next
        End Using
        Return snap
    End Function

    Private Shared Function SeverityOf(status As String) As Integer
        Select Case status
            Case "live" : Return 1
            Case "pending", "submitted" : Return 2
            Case "withdrawn" : Return 3
            Case "blocked", "rejected" : Return 4
            Case Else : Return 0
        End Select
    End Function

    Private Shared Function Items(e As JsonElement, name As String) As IEnumerable(Of JsonElement)
        Dim v As JsonElement
        If e.ValueKind = JsonValueKind.Object AndAlso e.TryGetProperty(name, v) AndAlso v.ValueKind = JsonValueKind.Array Then
            Return v.EnumerateArray().ToList()
        End If
        Return New List(Of JsonElement)()
    End Function

    Private Shared Function Day(iso As String) As String
        Return If(iso.Length >= 10, iso.Substring(0, 10), iso)
    End Function

    Private Shared Function Bool(e As JsonElement, name As String) As Boolean
        Dim v As JsonElement
        Return e.ValueKind = JsonValueKind.Object AndAlso e.TryGetProperty(name, v) AndAlso v.ValueKind = JsonValueKind.True
    End Function

    Private Shared Function Text(e As JsonElement, name As String) As String
        Dim v As JsonElement
        If e.ValueKind <> JsonValueKind.Object OrElse Not e.TryGetProperty(name, v) Then Return ""
        Select Case v.ValueKind
            Case JsonValueKind.String : Return v.GetString()
            Case JsonValueKind.Null, JsonValueKind.Undefined : Return ""
            Case Else : Return v.GetRawText()
        End Select
    End Function
End Class

Partial Class MainForm
    Private _tabReleases As TabPage
    Private _dgvReleases As DataGridView
    Private _releases As ReleasesSnapshot = Nothing
    Private _isReleasesBusy As Boolean = False

    ' Called from the constructor, after ConfigureGrids and before the theme is applied, so the grid is themed with the rest.
    Private Sub InitReleasesTab()
        _dgvReleases = New DataGridView With {
            .Name = "dgvReleases",
            .Dock = DockStyle.Fill,
            .AllowUserToAddRows = False,
            .AllowUserToDeleteRows = False,
            .ReadOnly = True,
            .SelectionMode = DataGridViewSelectionMode.FullRowSelect,
            .RowHeadersVisible = False
        }
        AddTextColumn(_dgvReleases, "colRelRepo", "Project", 115)
        AddTextColumn(_dgvReleases, "colRelBuild", "Last build", 150)
        AddTextColumn(_dgvReleases, "colRelBuilt", "Built", 80)
        For Each c In ReleasesSnapshot.Columns
            AddTextColumn(_dgvReleases, c.Column, c.Header, 120)
        Next
        _tabReleases = New TabPage With {
            .Name = "tabReleases",
            .Text = "Releases",
            .ToolTipText = "the release ledger of every project (pq releases): last build, the live version per channel, what is in flight; double-click a row to open its RELEASES.md"
        }
        _tabReleases.Controls.Add(_dgvReleases)
        tabLeft.TabPages.Add(_tabReleases)
        AddHandler _dgvReleases.CellDoubleClick, AddressOf DgvReleases_CellDoubleClick
        AddHandler tabLeft.SelectedIndexChanged, Sub()
                                                     If tabLeft.SelectedTab Is _tabReleases Then RefreshReleasesAsync()
                                                 End Sub
    End Sub

    ' Read when the tab is opened and with the inbox cadence while it is open; never twice at once.
    Private Async Sub RefreshReleasesAsync()
        If _isReleasesBusy OrElse _dgvReleases Is Nothing Then Return
        _isReleasesBusy = True
        Try
            Dim res = Await PqCli.RunSilentAsync("releases", "-Json")
            If IsDisposed Then Return
            Dim snap As ReleasesSnapshot
            If res.Success Then
                Try
                    snap = ReleasesSnapshot.Parse(res.Output)
                Catch ex As JsonException
                    snap = ReleasesSnapshot.Failed($"pq releases -Json gave unreadable JSON ({ex.Message})")
                End Try
            Else
                snap = ReleasesSnapshot.Failed($"pq releases -Json failed (exit {res.ExitCode}): {LastLines(res.Message, 2)}")
            End If
            If Not snap.Ok AndAlso (_releases Is Nothing OrElse _releases.Ok) Then LogConsole(snap.ErrorText)
            _releases = snap
            FillReleasesGrid()
        Finally
            _isReleasesBusy = False
        End Try
    End Sub

    Private Sub FillReleasesGrid()
        If _dgvReleases Is Nothing OrElse _releases Is Nothing OrElse Not _releases.Ok Then Return
        Dim p = ThemeService.Palette
        Dim scroll = FirstVisibleRow(_dgvReleases)
        _dgvReleases.Rows.Clear()
        For Each r In _releases.Repos
            Dim idx = _dgvReleases.Rows.Add(r.Key)
            Dim row = _dgvReleases.Rows(idx)
            If r.ErrorText <> "" Then
                row.Cells("colRelBuild").Value = "error"
                row.Cells("colRelBuild").ToolTipText = r.ErrorText
                row.Cells("colRelBuild").Style.ForeColor = p.StatusDanger
                Continue For
            End If
            If Not r.HasLedger Then
                row.Cells("colRelBuild").Value = "no ledger"
                row.Cells("colRelBuild").ToolTipText = $"no {r.Dir} folder - run 'release-ledger init' in that project (its adoption ticket)"
                row.DefaultCellStyle.ForeColor = p.TextMuted
                Continue For
            End If
            row.Cells("colRelBuild").Value = If(r.LastBuild <> "", r.LastBuild, "-")
            row.Cells("colRelBuilt").Value = r.LastBuildAt
            Dim buildTip = If(r.BuildsTip <> "", r.BuildsTip, "no build recorded")
            If r.Unpublished.Count > 0 Then
                buildTip &= Environment.NewLine & "built, not published:" & Environment.NewLine & String.Join(Environment.NewLine, r.Unpublished)
                row.Cells("colRelBuild").Style.ForeColor = p.StatusWarning
            End If
            If r.Warnings.Count > 0 Then buildTip &= Environment.NewLine & "warnings:" & Environment.NewLine & String.Join(Environment.NewLine, r.Warnings)
            row.Cells("colRelBuild").ToolTipText = buildTip
            For Each c In ReleasesSnapshot.Columns
                Dim cell As ReleaseCell = Nothing
                If Not r.Cells.TryGetValue(c.Kind, cell) Then Continue For
                Dim gridCell = row.Cells(c.Column)
                gridCell.Value = cell.Text
                gridCell.ToolTipText = cell.Tip
                gridCell.Style.ForeColor = If(cell.Severity >= 3, p.StatusDanger, If(cell.Severity = 2, p.StatusWarning, If(cell.Severity = 1, p.StatusSuccess, p.TextMuted)))
            Next
        Next
        RestoreScroll(_dgvReleases, scroll)
    End Sub

    Private Sub DgvReleases_CellDoubleClick(sender As Object, e As DataGridViewCellEventArgs)
        If e.RowIndex < 0 OrElse _releases Is Nothing OrElse Not _releases.Ok Then Return
        Dim key = If(_dgvReleases.Rows(e.RowIndex).Cells("colRelRepo").Value?.ToString(), "")
        Dim r = _releases.Repos.FirstOrDefault(Function(x) x.Key = key)
        If r Is Nothing Then Return
        If Not r.HasLedger Then
            LogConsole($"'{key}' keeps no release ledger yet ({r.Dir}); its adoption ticket runs 'release-ledger init' there.")
            Return
        End If
        Dim rendered = System.IO.Path.Combine(r.Path, r.Dir.Replace("/"c, System.IO.Path.DirectorySeparatorChar), "RELEASES.md")
        Dim err = PqCli.OpenFileWithDefaultApp(rendered)
        If err IsNot Nothing Then LogConsole($"RELEASES.md of '{key}': {err}")
    End Sub
End Class
