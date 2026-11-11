Option Explicit On
Option Strict On

Imports System.Linq

Partial Class MainForm
    Private _isRefreshing As Boolean = False
    Private _isCliBusy As Boolean = False
    Private _boldRepos As Font
    Private _boldWorkers As Font
    Private _consoleExpandedHeight As Integer = 140
    Private _consoleCollapsed As Boolean = False
    Private _baseTitle As String = ""
    ' The registry as the last refresh read it: a double-click resolves a row's project key against it.
    Private _repos As New List(Of RepoInfo)()

    ' The console keeps the tail of the session; a panel left open for days must not grow without bound.
    Private Const ConsoleMaxChars As Integer = 200000

    ' What waits for the owner, one column per inbox kind (pq inbox): the grid column, its header, the kind, and what
    ' the kind means to the owner.
    Private Shared ReadOnly InboxColumns As (Column As String, Header As String, Kind As String, Meaning As String)() = {
        ("colAsk", "Ask", "questions", "waiting for your answers (BlockQuestions)"),
        ("colTest", "Test", "tests", "waiting for your manual test (BlockNeedUserTest)"),
        ("colOutside", "Outside", "outside", "waiting for someone outside the project (BlockExternal)"),
        ("colChain", "Chain", "chain", "waiting for another ticket, here or in another project (BlockByOtherTask)"),
        ("colUnbuilt", "Unbuilt", "unbuilt", "built, waiting for the audit to Verified (Implemented)")
    }

    ' The inbox takes seconds to read (every ledger, the chain walk): it is read on load, by Refresh and every
    ' 15th tick (60 s), never twice at once, and the grid shows the last reading in between.
    Private _inbox As InboxSnapshot = Nothing
    Private _isInboxBusy As Boolean = False
    Private _ticks As Integer = 0
    Private Const InboxEveryTicks As Integer = 15

    Public Sub New()
        InitializeComponent()
        _boldRepos = New Font(dgvRepos.Font, FontStyle.Bold)
        _boldWorkers = New Font(dgvWorkers.Font, FontStyle.Bold)
        _baseTitle = Me.Text
        ConfigureGrids()
    End Sub

    Protected Overrides Sub OnLoad(e As EventArgs)
        MyBase.OnLoad(e)

        ' 1. Restore persistent UI layout and state per APP-BEHAVIOUR Rule 9
        Dim state = UiState.Load()
        UiState.ApplyBoundsSafely(Me, state)

        If state.MainSplitterDistance.HasValue AndAlso state.MainSplitterDistance.Value > 100 AndAlso state.MainSplitterDistance.Value < Me.Width - 100 Then
            Try
                splitMain.SplitterDistance = state.MainSplitterDistance.Value
            Catch
            End Try
        End If

        If state.MonitorSplitterDistance.HasValue AndAlso state.MonitorSplitterDistance.Value > 50 AndAlso state.MonitorSplitterDistance.Value < splitRightMonitor.Height - 50 Then
            Try
                splitRightMonitor.SplitterDistance = state.MonitorSplitterDistance.Value
            Catch
            End Try
        End If

        chkAutoRefresh.Checked = state.AutoRefresh
        _consoleCollapsed = state.ConsoleCollapsed
        _consoleExpandedHeight = Math.Max(240, state.ConsoleHeight)

        If _consoleCollapsed Then
            pnlBottom.Height = pnlBottomBar.Height
            btnToggleConsole.Text = "▲ Console"
        Else
            pnlBottom.Height = _consoleExpandedHeight
            btnToggleConsole.Text = "▼ Console"
        End If

        ' 2. Restore Theme
        Dim mode As AppThemeMode
        If [Enum].TryParse(Of AppThemeMode)(state.Theme, mode) Then
            ThemeService.Mode = mode
        Else
            ThemeService.Mode = AppThemeMode.System
        End If
        UpdateThemeButtonText()
        ThemeService.ApplyTheme(Me)

        ' 3. Display paths
        lblPqPath.Text = $"Script: {PqCli.PqScriptPath}   Root: {PortfolioState.PortfolioRoot}"
        If Not File.Exists(PqCli.PqScriptPath) Then
            LogConsole($"pq.ps1 not found at {PqCli.PqScriptPath} - set SZA_PQ_SCRIPT to its full path.")
        End If

        WireEvents()
        RefreshAll()
        RefreshInboxAsync()

        tmrRefresh.Interval = 4000
        tmrRefresh.Enabled = chkAutoRefresh.Checked
    End Sub

    Private Sub ConfigureGrids()
        dgvRepos.Columns.Clear()
        AddTextColumn(dgvRepos, "colOrder", "#", 32)
        AddTextColumn(dgvRepos, "colKey", "Project", 115)
        AddTextColumn(dgvRepos, "colStatus", "Status", 80)
        AddTextColumn(dgvRepos, "colQueued", "Queued", 55)
        For Each c In InboxColumns
            AddTextColumn(dgvRepos, c.Column, c.Header, 50)
        Next
        AddTextColumn(dgvRepos, "colPerm", "Permission", 115)
        AddButtonColumn(dgvRepos, "colNewSpec", "Spec", "+ Spec...", 65)
        AddButtonColumn(dgvRepos, "colQueue", "Tickets", "Open Queue", 85)
        AddButtonColumn(dgvRepos, "colFolder", "Folder", "Open VSCode", 95)
        AddButtonColumn(dgvRepos, "colSession", "Session", "Claude", 70)
        AddButtonColumn(dgvRepos, "colStartRepo", "Worker", "Start here", 80)

        dgvWorkers.Columns.Clear()
        AddTextColumn(dgvWorkers, "colSlot", "Slot", 45)
        AddTextColumn(dgvWorkers, "colPid", "PID", 60)
        AddTextColumn(dgvWorkers, "colWorkerRepo", "Project", 95)
        AddTextColumn(dgvWorkers, "colWorkerTicket", "Ticket", 90)
        AddTextColumn(dgvWorkers, "colWorkerTitle", "Title", 180)
        AddTextColumn(dgvWorkers, "colElapsed", "Running", 80)
        AddTextColumn(dgvWorkers, "colSeen", "Last seen", 120)
        AddTextColumn(dgvWorkers, "colWorkerAlive", "State", 60)

        dgvPasses.Columns.Clear()
        AddTextColumn(dgvPasses, "colTime", "Finished", 95)
        AddTextColumn(dgvPasses, "colPassRepo", "Project", 90)
        AddTextColumn(dgvPasses, "colPassTicket", "Ticket", 70)
        AddTextColumn(dgvPasses, "colStatusMove", "Status", 140)
        AddTextColumn(dgvPasses, "colOutcome", "Outcome", 85)
        AddTextColumn(dgvPasses, "colModel", "Model", 60)
        AddTextColumn(dgvPasses, "colDur", "Sec", 50)
        AddTextColumn(dgvPasses, "colExit", "Exit", 40)

        dgvQueue.Columns.Clear()
        AddTextColumn(dgvQueue, "colQPackage", "Pkg", 45)
        AddTextColumn(dgvQueue, "colQRepo", "Project", 115)
        AddTextColumn(dgvQueue, "colQTicket", "Ticket", 80)
        AddTextColumn(dgvQueue, "colQStatus", "Status", 130)
        AddTextColumn(dgvQueue, "colQHeld", "Held", 50)
    End Sub

    Private Shared Sub AddTextColumn(grid As DataGridView, name As String, header As String, width As Integer)
        grid.Columns.Add(name, header)
        grid.Columns(name).Width = grid.LogicalToDeviceUnits(width)
        grid.Columns(name).SortMode = DataGridViewColumnSortMode.NotSortable
    End Sub

    Private Shared Sub AddButtonColumn(grid As DataGridView, name As String, header As String, text As String, width As Integer)
        grid.Columns.Add(New DataGridViewButtonColumn With {
            .Name = name,
            .HeaderText = header,
            .Text = text,
            .UseColumnTextForButtonValue = True,
            .Width = grid.LogicalToDeviceUnits(width)
        })
    End Sub

    Private Sub WireEvents()
        AddHandler btnStartLoop.Click, Sub() Launch("Launching 'pq start' in a new terminal..", "start")
        AddHandler btnStartOne.Click, Sub() Launch("Launching 'pq start -MaxTickets 1' in a new terminal..", "start", "-MaxTickets", "1")
        AddHandler btnStartDrain.Click, Sub() Launch("Launching 'pq start -Drain' in a new terminal..", "start", "-Drain")
        AddHandler btnStop.Click, AddressOf BtnStop_Click
        AddHandler btnKill.Click, AddressOf BtnKill_Click
        AddHandler btnPause.Click, Async Sub()
                                       LogConsole("Pausing: no worker launches a new pass, passes in flight finish ('pq pause')..")
                                       Await RunOwnerVerbAsync(btnPause, "pause")
                                   End Sub
        AddHandler btnResume.Click, Async Sub()
                                        LogConsole("Resuming ('pq resume')..")
                                        Await RunOwnerVerbAsync(btnResume, "resume")
                                    End Sub
        AddHandler btnReport.Click, Async Sub()
                                        LogConsole("The last day in numbers ('pq report -Days 1')..")
                                        Await RunOwnerVerbAsync(btnReport, "report", "-Days", "1")
                                    End Sub
        AddHandler btnProblems.Click, Async Sub()
                                          LogConsole("The open findings of the last seven days ('pq problems')..")
                                          Await RunOwnerVerbAsync(btnProblems, "problems")
                                      End Sub
        AddHandler btnNewSpec.Click, Sub() ShowNewSpec(SelectedRepoKey())
        AddHandler btnDoctor.Click, AddressOf BtnDoctor_Click
        AddHandler btnGuide.Click, AddressOf BtnGuide_Click
        AddHandler btnRegister.Click, AddressOf BtnRegister_Click
        AddHandler btnProviders.Click, AddressOf BtnProviders_Click
        AddHandler btnTheme.Click, AddressOf BtnTheme_Click

        AddHandler btnOpenQueue.Click, AddressOf BtnOpenQueue_Click
        AddHandler btnDryRun.Click, AddressOf BtnDryRun_Click
        AddHandler btnArrange.Click, AddressOf BtnArrange_Click
        AddHandler btnUp.Click, Sub() MoveProjectAsync(-1)
        AddHandler btnDown.Click, Sub() MoveProjectAsync(1)
        AddHandler btnPin.Click, Sub() SteerAsync("pin", requireTicket:=True)
        AddHandler btnRunNow.Click, Sub() RunNowAsync()
        AddHandler btnHold.Click, Sub() SteerAsync("hold", requireTicket:=False)
        AddHandler btnRelease.Click, Sub() SteerAsync("release", requireTicket:=False)

        AddHandler dgvRepos.CellClick, AddressOf DgvRepos_CellClick
        AddHandler dgvRepos.SelectionChanged, AddressOf DgvRepos_SelectionChanged
        AddHandler dgvWorkers.CellDoubleClick, Sub(s, e) SteerAndOpenFromRow(dgvWorkers, e.RowIndex, "colWorkerRepo", "colWorkerTicket")
        AddHandler dgvPasses.CellDoubleClick, Sub(s, e) SteerAndOpenFromRow(dgvPasses, e.RowIndex, "colPassRepo", "colPassTicket")
        AddHandler dgvQueue.CellDoubleClick, Sub(s, e) SteerAndOpenFromRow(dgvQueue, e.RowIndex, "colQRepo", "colQTicket")

        AddHandler splBottom.SplitterMoved, AddressOf SplBottom_SplitterMoved
        AddHandler splBottom.DoubleClick, AddressOf BtnToggleConsole_Click

        AddHandler btnToggleConsole.Click, AddressOf BtnToggleConsole_Click
        AddHandler btnClearConsole.Click, Sub() txtConsole.Clear()
        AddHandler btnCopyConsole.Click, AddressOf BtnCopyConsole_Click
        ' The file changes only when pq syncs it (each pass end, every steering verb); the button syncs first, so a
        ' ticket written or moved in a repository since then shows up now.
        AddHandler btnRefreshNow.Click, Async Sub()
                                            Await RunLoggedAsync(btnRefreshNow, "sync")
                                            RefreshInboxAsync()
                                        End Sub
        AddHandler chkAutoRefresh.CheckedChanged, Sub() tmrRefresh.Enabled = chkAutoRefresh.Checked
        AddHandler tmrRefresh.Tick, Sub()
                                        RefreshAll()
                                        _ticks += 1
                                        If _ticks Mod InboxEveryTicks = 0 Then RefreshInboxAsync()
                                    End Sub

        AddHandler ThemeService.ThemeChanged, AddressOf OnThemeChanged
    End Sub

    Protected Overrides Sub OnKeyDown(e As KeyEventArgs)
        MyBase.OnKeyDown(e)
        If e.KeyCode = Keys.F1 Then
            btnGuide.PerformClick()
            e.Handled = True
        ElseIf e.KeyCode = Keys.F5 Then
            RefreshAll()
            e.Handled = True
        ElseIf e.Control AndAlso e.KeyCode = Keys.N Then
            btnNewSpec.PerformClick()
            e.Handled = True
        ElseIf e.Control AndAlso e.KeyCode = Keys.R Then
            btnRegister.PerformClick()
            e.Handled = True
        ElseIf e.Control AndAlso e.KeyCode = Keys.D Then
            btnDoctor.PerformClick()
            e.Handled = True
        End If
    End Sub

    Private Sub BtnTheme_Click(sender As Object, e As EventArgs)
        Select Case ThemeService.Mode
            Case AppThemeMode.System
                ThemeService.Mode = AppThemeMode.Dark
            Case AppThemeMode.Dark
                ThemeService.Mode = AppThemeMode.Light
            Case Else
                ThemeService.Mode = AppThemeMode.System
        End Select
        UpdateThemeButtonText()
    End Sub

    Private Sub UpdateThemeButtonText()
        Dim modeText = ThemeService.Mode.ToString()
        If ThemeService.Mode = AppThemeMode.System Then
            modeText &= If(ThemeService.IsDark, " (Dark)", " (Light)")
        End If
        btnTheme.Text = $"🎨 {modeText}"
    End Sub

    Private Sub OnThemeChanged(sender As Object, e As EventArgs)
        UpdateThemeButtonText()
        ThemeService.ApplyTheme(Me)
        RefreshAll()
    End Sub

    Private Sub BtnToggleConsole_Click(sender As Object, e As EventArgs)
        If _consoleCollapsed Then
            pnlBottom.Height = Math.Max(_consoleExpandedHeight, 180)
            btnToggleConsole.Text = "▼ Console"
            _consoleCollapsed = False
        Else
            _consoleExpandedHeight = Math.Max(pnlBottom.Height, 180)
            pnlBottom.Height = pnlBottomBar.Height
            btnToggleConsole.Text = "▲ Console"
            _consoleCollapsed = True
        End If
    End Sub

    Private Sub SplBottom_SplitterMoved(sender As Object, e As SplitterEventArgs)
        If Not _consoleCollapsed AndAlso pnlBottom.Height > pnlBottomBar.Height + 20 Then
            _consoleExpandedHeight = pnlBottom.Height
        End If
    End Sub

    Private Sub BtnCopyConsole_Click(sender As Object, e As EventArgs)
        If txtConsole.TextLength > 0 Then
            Clipboard.SetText(txtConsole.Text)
            LogConsole("Console contents copied to clipboard.")
        End If
    End Sub

    Public Sub LogConsole(msg As String)
        Dim stamp = DateTime.Now.ToString("HH:mm:ss")
        If txtConsole.TextLength > ConsoleMaxChars Then
            txtConsole.Text = txtConsole.Text.Substring(txtConsole.TextLength - ConsoleMaxChars \ 2)
        End If
        txtConsole.AppendText($"[{stamp}] {msg.TrimEnd()}{Environment.NewLine}")
        txtConsole.SelectionStart = txtConsole.TextLength
        txtConsole.ScrollToCaret()
    End Sub

    Public Sub RefreshAll()
        If _isRefreshing Then Return
        _isRefreshing = True

        Try
            Dim stopInfo = PortfolioState.GetStopInfo()
            Dim workers = PortfolioState.GetActiveWorkers()
            Dim liveCount = workers.Where(Function(w) w.Alive).Count()
            Dim queue = PortfolioState.ReadQueue()
            Dim repos = PortfolioState.GetRepos(queue)
            _repos = repos
            Dim p = ThemeService.Palette

            ' 1. Banner
            If stopInfo.Present AndAlso liveCount > 0 Then
                pnlBanner.BackColor = Color.FromArgb(140, 30, 30)
                lblStatus.Text = $"🛑 STOP ({stopInfo.Level}) - draining {liveCount} worker(s).."
            ElseIf stopInfo.Present Then
                pnlBanner.BackColor = Color.FromArgb(90, 40, 40)
                lblStatus.Text = $"⏹ STOPPED ({stopInfo.Level}) - the next start clears it"
            ElseIf liveCount > 0 Then
                pnlBanner.BackColor = Color.FromArgb(20, 90, 45)
                lblStatus.Text = $"🟢 ACTIVE - {liveCount} worker(s) running"
            Else
                pnlBanner.BackColor = If(ThemeService.IsDark, Color.FromArgb(22, 27, 34), Color.FromArgb(33, 43, 54))
                lblStatus.Text = "⚪ IDLE - no worker running"
            End If

            ' 1b. Who spends tokens now: the provider order, with a provider marked while its usage limit is spent
            Dim providerLine = PortfolioState.GetProviderLine()
            Me.Text = If(providerLine = "", _baseTitle, $"{_baseTitle}  |  Providers: {providerLine}")

            ' 2. Queue top
            If Not queue.Present Then
                lblNextCandidate.Text = "No PORTFOLIO_QUEUE.md - Open Queue writes one ('pq queue -Init')"
            Else
                Dim top = PortfolioState.GetQueueTop(queue, repos)
                lblNextCandidate.Text = If(top Is Nothing,
                    "Queue top: nothing dispatchable",
                    $"Queue top: {top.Target}{If(top.Status <> "", $"  ({top.Status})", "")}   - Dry-Run for pq's exact plan")
            End If

            ' 3. Workers
            Dim workersScroll = FirstVisibleRow(dgvWorkers)
            dgvWorkers.Rows.Clear()
            For Each w In workers
                Dim idx = dgvWorkers.Rows.Add(w.Slot, w.Pid, w.Repository, w.Ticket, w.Title, w.Elapsed, w.LastSeenText, If(w.Alive, "Alive", "Dead"))
                If w.Alive Then
                    dgvWorkers.Rows(idx).DefaultCellStyle.ForeColor = p.StatusSuccess
                    dgvWorkers.Rows(idx).DefaultCellStyle.Font = _boldWorkers
                Else
                    dgvWorkers.Rows(idx).DefaultCellStyle.ForeColor = p.TextMuted
                End If
            Next
            RestoreScroll(dgvWorkers, workersScroll)

            ' 4. Passes, newest first
            Dim passesScroll = FirstVisibleRow(dgvPasses)
            dgvPasses.Rows.Clear()
            For Each pass In PortfolioState.GetRecentPasses(25)
                Dim finTime = pass.FinishedAt
                If finTime.Length >= 16 Then finTime = finTime.Substring(5, 11).Replace("T", " ")
                Dim move = If(pass.StatusBefore = "" AndAlso pass.StatusAfter = "", "", $"{pass.StatusBefore} → {pass.StatusAfter}")
                Dim idx = dgvPasses.Rows.Add(finTime, pass.Repo, pass.Id, move, pass.Outcome, pass.Model, Math.Round(pass.Seconds, 1), pass.ExitCode)
                Dim outcomeColor = If(pass.Outcome = "ok" OrElse pass.Moved, p.StatusSuccess, If(pass.Outcome = "unmoved", p.StatusWarning, p.StatusDanger))
                dgvPasses.Rows(idx).Cells("colOutcome").Style.ForeColor = outcomeColor
            Next
            RestoreScroll(dgvPasses, passesScroll)

            ' 4b. The queue file's ticket rows, in the order the runner reads them, then the held ones
            Dim queueScroll = FirstVisibleRow(dgvQueue)
            dgvQueue.Rows.Clear()
            For Each q In queue.Rows.Select(Function(r) (Row:=r, Held:=False)).Concat(queue.Held.Select(Function(r) (Row:=r, Held:=True)))
                Dim pkg = If(q.Row.Package = PortfolioState.Unscheduled, "--", If(q.Row.Package < 0, "", CStr(q.Row.Package)))
                Dim idx = dgvQueue.Rows.Add(pkg, q.Row.Repo, If(q.Row.Id, ""), q.Row.Status, If(q.Held, "held", ""))
                If q.Row.Id Is Nothing Then
                    dgvQueue.Rows(idx).Cells("colQTicket").ToolTipText = "a project row: every ticket of the project, in its own order - no single spec to open"
                End If
                If q.Held Then dgvQueue.Rows(idx).DefaultCellStyle.ForeColor = p.TextMuted
            Next
            RestoreScroll(dgvQueue, queueScroll)

            ' 5. Repositories
            Dim selKey = SelectedRepoKey()
            Dim reposScroll = FirstVisibleRow(dgvRepos)
            dgvRepos.Rows.Clear()
            Dim selIdx = -1
            For Each r In repos
                Dim statusText = If(r.IsHeld, If(r.RegistryHold, "Held (reg)", "Held"), If(r.Enabled, "Enabled", "Disabled"))
                Dim idx = dgvRepos.Rows.Add()
                Dim row = dgvRepos.Rows(idx)
                row.Cells("colOrder").Value = idx + 1
                row.Cells("colKey").Value = r.Key
                row.Cells("colStatus").Value = statusText
                row.Cells("colQueued").Value = If(r.RunnableRows > 0, CStr(r.RunnableRows), "")
                row.Cells("colPerm").Value = r.PermissionMode
                row.Tag = r
                row.Cells("colKey").ToolTipText = r.Path
                row.Cells("colQueued").ToolTipText = $"{r.RunnableRows} the runner would take, of {r.QueuedRows} rows in the queue file (blocked, idle-held, held and unknown rows are not taken)" &
                    If(r.IdleRows > 0, $"; {r.IdleRows} idle-held: the last runs of each ended without moving its status, so the runner passes it over until a run of it moves the status (naming the ticket runs it anyway)", "")
                FillInboxCells(row, r.Key, p)
                row.Cells("colOrder").ToolTipText = $"rank {r.Rank}"
                row.Cells("colStartRepo").ToolTipText = $"Starts a worker that takes tickets of '{r.Key}' only, in their order ('pq start -Repo {r.Key}'). Holds, STOP and the other safeguards apply as for any start."
                row.Cells("colSession").ToolTipText = $"Opens a terminal in {r.Path} running claude - an interactive session with the project's own commands and hooks, no VS Code window"

                Dim statusCell = row.Cells("colStatus")
                If r.IsHeld Then
                    statusCell.Style.ForeColor = p.StatusWarning
                    statusCell.Style.Font = _boldRepos
                ElseIf Not r.Enabled Then
                    statusCell.Style.ForeColor = p.TextMuted
                Else
                    statusCell.Style.ForeColor = p.StatusSuccess
                End If
                If r.Enabled AndAlso String.IsNullOrWhiteSpace(r.PermissionMode) Then
                    row.Cells("colPerm").Value = "(none - start refuses)"
                    row.Cells("colPerm").Style.ForeColor = p.StatusDanger
                End If

                If r.Key.Equals(selKey, StringComparison.Ordinal) Then selIdx = idx
            Next
            dgvRepos.ClearSelection()
            If selIdx >= 0 Then
                dgvRepos.Rows(selIdx).Selected = True
                dgvRepos.CurrentCell = dgvRepos.Rows(selIdx).Cells(0)
            End If
            RestoreScroll(dgvRepos, reposScroll)
        Catch ex As Exception
            LogConsole($"Refresh error: {ex.Message}")
        Finally
            _isRefreshing = False
        End Try
    End Sub

    ' The five counts of one project; '?' wherever the inbox could not say: not read yet, the read failed, or pq
    ' skipped the project. A zero stays empty, as in the Queued column.
    Private Sub FillInboxCells(row As DataGridViewRow, repoKey As String, p As ThemePalette)
        Dim reason As String = Nothing
        If _inbox Is Nothing Then
            reason = "not read yet - the inbox ('pq inbox') is read a few seconds after the panel opens"
        ElseIf Not _inbox.Ok Then
            reason = $"the inbox could not be read: {_inbox.ErrorText}"
        ElseIf _inbox.Skipped.ContainsKey(repoKey) Then
            reason = $"pq inbox skipped this project: {_inbox.Skipped(repoKey)}"
        End If
        For Each c In InboxColumns
            Dim cell = row.Cells(c.Column)
            If reason IsNot Nothing Then
                cell.Value = "?"
                cell.ToolTipText = reason
                cell.Style.ForeColor = p.TextMuted
                Continue For
            End If
            Dim n = _inbox.Tickets(repoKey, c.Kind).Count
            cell.Value = If(n > 0, CStr(n), "")
            cell.ToolTipText = $"{n} {c.Meaning}; read {_inbox.ReadAt:HH:mm:ss}" & If(n > 0, " - click to list them in the console", "")
            If n > 0 Then cell.Style.ForeColor = p.StatusWarning
        Next
    End Sub

    Private Async Sub RefreshInboxAsync()
        If _isInboxBusy Then Return
        _isInboxBusy = True
        Try
            Dim res = Await PqCli.RunSilentAsync("inbox", "-Json")
            If IsDisposed Then Return
            Dim snap As InboxSnapshot
            If res.Success Then
                Try
                    snap = InboxSnapshot.Parse(res.Output)
                Catch ex As JsonException
                    snap = InboxSnapshot.Failed($"pq inbox -Json gave unreadable JSON ({ex.Message})")
                End Try
            Else
                snap = InboxSnapshot.Failed($"pq inbox -Json failed (exit {res.ExitCode}): {LastLines(res.Message, 2)}")
            End If
            ' A failure is logged once when it starts, not every minute it lasts.
            If Not snap.Ok AndAlso (_inbox Is Nothing OrElse _inbox.Ok) Then LogConsole(snap.ErrorText)
            If snap.Ok AndAlso snap.Skipped.Count > 0 AndAlso (_inbox Is Nothing OrElse Not _inbox.Ok OrElse _inbox.Skipped.Count <> snap.Skipped.Count) Then
                LogConsole("pq inbox skipped: " & String.Join("; ", snap.Skipped.Select(Function(kv) $"{kv.Key} - {kv.Value}")))
            End If
            _inbox = snap
        Finally
            _isInboxBusy = False
        End Try
        If Not IsDisposed Then RefreshAll()
    End Sub

    ' A click on a count: the tickets behind it, with the command that clears the kind.
    Private Sub ListInbox(r As RepoInfo, column As String)
        Dim c = InboxColumns.First(Function(x) x.Column = column)
        If _inbox Is Nothing OrElse Not _inbox.Ok Then
            LogConsole($"{c.Header} of '{r.Key}': {If(_inbox Is Nothing, "the inbox has not been read yet", _inbox.ErrorText)}")
            Return
        End If
        If _inbox.Skipped.ContainsKey(r.Key) Then
            LogConsole($"{c.Header} of '{r.Key}': unknown - pq inbox skipped this project: {_inbox.Skipped(r.Key)}")
            Return
        End If
        Dim list = _inbox.Tickets(r.Key, c.Kind)
        If list.Count = 0 Then
            LogConsole($"{c.Header} of '{r.Key}': nothing {c.Meaning}.")
            Return
        End If
        Dim clearCmd As String = Nothing
        _inbox.Clear.TryGetValue(c.Kind, clearCmd)
        Dim sb As New StringBuilder()
        sb.Append($"{c.Header} of '{r.Key}': {list.Count} {c.Meaning}")
        If Not String.IsNullOrEmpty(clearCmd) Then sb.Append($" - clear: {clearCmd}")
        For Each t In list
            sb.AppendLine()
            sb.Append($"  {t.Repo}:{t.Id}")
            If t.WaitsOn <> "" Then sb.Append($"  waits on {t.WaitsOn}")
            If t.Age <> "" Then sb.Append($"  age {t.Age}")
            If t.Note <> "" Then sb.Append("  " & If(t.Note.Length > 100, t.Note.Substring(0, 100) & "..", t.Note))
        Next
        LogConsole(sb.ToString())
    End Sub

    Private Shared Function FirstVisibleRow(grid As DataGridView) As Integer
        Return If(grid.Rows.Count > 0, grid.FirstDisplayedScrollingRowIndex, -1)
    End Function

    Private Shared Sub RestoreScroll(grid As DataGridView, index As Integer)
        If index >= 0 AndAlso index < grid.Rows.Count Then
            Try
                grid.FirstDisplayedScrollingRowIndex = index
            Catch
            End Try
        End If
    End Sub

    Private Function SelectedRepoKey() As String
        If dgvRepos.SelectedRows.Count = 0 Then Return ""
        Return If(dgvRepos.SelectedRows(0).Cells("colKey").Value?.ToString(), "")
    End Function

    Private Sub Launch(message As String, ParamArray arguments As String())
        LogConsole(message)
        Dim err = PqCli.LaunchInteractive(arguments)
        If err IsNot Nothing Then LogConsole($"Launch failed: {err}")
        RefreshAll()
    End Sub

    ' Runs a pq verb hidden and logs output; guarded by busy lock per APP-BEHAVIOUR Rule 3
    Private Async Function RunLoggedAsync(button As Button, ParamArray arguments As String()) As Task(Of CliResult)
        If _isCliBusy Then
            LogConsole("A CLI command is already executing in the background, please wait...")
            Dim busyRes As New CliResult With {.ExitCode = -1, .ErrorOutput = "CLI busy"}
            Return busyRes
        End If

        _isCliBusy = True
        If button IsNot Nothing Then button.Enabled = False
        Dim oldCursor = Me.Cursor
        Me.Cursor = Cursors.WaitCursor

        Try
            Dim res = Await PqCli.RunSilentAsync(arguments)
            Dim verb = String.Join(" ", arguments)
            If res.Success Then
                LogConsole(If(res.Output.Trim() = "", $"pq {verb}: done", res.Output))
            Else
                LogConsole($"pq {verb} failed (exit {res.ExitCode}): {res.Message}")
            End If
            Return res
        Finally
            _isCliBusy = False
            Me.Cursor = oldCursor
            If button IsNot Nothing Then button.Enabled = True
            RefreshAll()
        End Try
    End Function

    ' The owner's controls run outside _isCliBusy: a dry-run or a status takes minutes, and Stop must not wait for it.
    ' Only the clicked button is held, so one control cannot be fired twice while its own command runs.
    Private Async Function RunOwnerVerbAsync(button As Button, ParamArray arguments As String()) As Task
        button.Enabled = False
        Try
            Dim res = Await PqCli.RunSilentAsync(arguments)
            If IsDisposed Then Return
            Dim verb = String.Join(" ", arguments)
            If res.Success Then
                LogConsole(If(res.Output.Trim() = "", $"pq {verb}: done", res.Output))
            Else
                LogConsole($"pq {verb} failed (exit {res.ExitCode}): {res.Message}")
            End If
        Finally
            If Not IsDisposed Then
                button.Enabled = True
                RefreshAll()
            End If
        End Try
    End Function

    Private Async Sub BtnStop_Click(sender As Object, e As EventArgs)
        LogConsole("Requesting a graceful stop: workers finish their current pass, then exit..")
        Await RunOwnerVerbAsync(btnStop, "stop")
    End Sub

    Private Async Sub BtnKill_Click(sender As Object, e As EventArgs)
        Dim confirm = MessageBox.Show(Me,
            "Forcibly terminate the running pass process trees?" & vbCrLf & "The ticket in flight is abandoned mid-pass.",
            "Confirm Force Kill", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2)
        If confirm <> DialogResult.Yes Then Return
        LogConsole("Terminating runner children ('pq stop -Kill')..")
        Await RunOwnerVerbAsync(btnKill, "stop", "-Kill")
    End Sub

    Private Sub ShowNewSpec(projectKey As String)
        Using dlg As New FormNewSpec(projectKey)
            If dlg.ShowDialog(Me) = DialogResult.OK Then
                LogConsole(dlg.ResultText)
                RefreshAll()
            End If
        End Using
    End Sub

    Private Sub BtnDoctor_Click(sender As Object, e As EventArgs)
        Using dlg As New FormDoctor()
            dlg.ShowDialog(Me)
        End Using
    End Sub

    Private Sub BtnGuide_Click(sender As Object, e As EventArgs)
        Dim guide = PqCli.GetGuidePath()
        LogConsole($"Opening the operator guide: {guide}")
        Dim err = PqCli.OpenFileWithDefaultApp(guide)
        If err IsNot Nothing Then LogConsole($"Cannot open the guide: {err}")
    End Sub

    Private Sub BtnRegister_Click(sender As Object, e As EventArgs)
        Using dlg As New FormRegister()
            If dlg.ShowDialog(Me) = DialogResult.OK Then
                LogConsole(dlg.ResultText)
                RefreshAll()
            End If
        End Using
    End Sub

    Private Sub BtnProviders_Click(sender As Object, e As EventArgs)
        Using dlg As New FormProviders()
            If dlg.ShowDialog(Me) = DialogResult.OK Then
                LogConsole(dlg.ResultText)
                RefreshAll()
            End If
        End Using
    End Sub

    Private Async Sub BtnOpenQueue_Click(sender As Object, e As EventArgs)
        If File.Exists(PortfolioState.GetPortfolioQueuePath()) Then
            LogConsole("Syncing and opening PORTFOLIO_QUEUE.md ('pq queue')..")
            Await RunLoggedAsync(btnOpenQueue, "queue")
        Else
            LogConsole("No PORTFOLIO_QUEUE.md yet - writing the first one ('pq queue -Init')..")
            Await RunLoggedAsync(btnOpenQueue, "queue", "-Init")
        End If
    End Sub

    Private Async Sub BtnDryRun_Click(sender As Object, e As EventArgs)
        LogConsole("Running 'pq dry-run' (ranks every enabled repository; this can take a minute)..")
        Await RunLoggedAsync(btnDryRun, "dry-run")
    End Sub

    Private Async Sub MoveProjectAsync(delta As Integer)
        If dgvRepos.SelectedRows.Count = 0 Then Return
        Dim from = dgvRepos.SelectedRows(0).Index
        Dim [to] = from + delta
        If [to] < 0 OrElse [to] >= dgvRepos.Rows.Count Then Return

        Dim keys = dgvRepos.Rows.Cast(Of DataGridViewRow)().Select(Function(r) CStr(r.Cells("colKey").Value)).ToList()
        Dim moved = keys(from)
        keys.RemoveAt(from)
        keys.Insert([to], moved)

        pnlSteer.Enabled = False
        Try
            Dim res = Await PqCli.RunSilentAsync("rank", "-Order", String.Join(",", keys))
            If res.Success Then
                LogConsole($"Project order: {moved} is now #{[to] + 1}. Arrange lines PORTFOLIO_QUEUE.md up by it.")
            Else
                LogConsole($"pq rank failed (exit {res.ExitCode}): {res.Message}")
            End If
        Finally
            pnlSteer.Enabled = True
            RefreshAll()
        End Try
    End Sub

    Private Async Sub BtnArrange_Click(sender As Object, e As EventArgs)
        LogConsole("Lining PORTFOLIO_QUEUE.md up by the project order ('pq arrange')..")
        Await RunLoggedAsync(btnArrange, "arrange")
    End Sub

    Private Async Sub SteerAsync(verb As String, requireTicket As Boolean)
        Dim target = txtSteer.Text.Trim()
        If target = "" Then
            MessageBox.Show(Me, "Enter a target: 'repo' or 'repo:ticket' (select a project, or double-click a worker or a pass).",
                            verb, MessageBoxButtons.OK, MessageBoxIcon.Information)
            Return
        End If
        If requireTicket AndAlso Not target.Contains(":"c) Then
            MessageBox.Show(Me, $"pq pin takes one ticket, 'repo:ticket' - '{target}' names a whole project.",
                            verb, MessageBoxButtons.OK, MessageBoxIcon.Information)
            Return
        End If
        pnlSteer.Enabled = False
        Try
            Await RunLoggedAsync(Nothing, verb, target)
        Finally
            pnlSteer.Enabled = True
        End Try
    End Sub

    ' Run now takes 'repo:ticket' like Pin Top, plus a bare ticket id resolved against the selected project.
    ' Returns "" after telling the user why the steer box is not a runnable target.
    Private Function ResolveRunNowTarget() As String
        Dim target = txtSteer.Text.Trim()
        If target = "" Then
            MessageBox.Show(Me, "Enter a ticket: 'repo:ticket', or a ticket id with a project selected (select a project, or double-click a worker or a pass).",
                            "Run now", MessageBoxButtons.OK, MessageBoxIcon.Information)
            Return ""
        End If
        If Not target.Contains(":"c) Then
            Dim bare = target
            Dim isProject = dgvRepos.Rows.Cast(Of DataGridViewRow)().Any(Function(r) String.Equals(CStr(r.Cells("colKey").Value), bare, StringComparison.Ordinal))
            Dim selected = SelectedRepoKey()
            If isProject Then
                MessageBox.Show(Me, $"Run now takes one ticket, 'repo:ticket' - '{target}' names a whole project. Use 'Start here' on its row to work a project.",
                                "Run now", MessageBoxButtons.OK, MessageBoxIcon.Information)
                Return ""
            End If
            If selected = "" Then
                MessageBox.Show(Me, $"'{target}' has no project - use 'repo:ticket', or select a project first.",
                                "Run now", MessageBoxButtons.OK, MessageBoxIcon.Information)
                Return ""
            End If
            target = $"{selected}:{target}"
        End If
        Dim colon = target.IndexOf(":"c)
        If colon <= 0 OrElse colon = target.Length - 1 OrElse target.IndexOf(":"c, colon + 1) >= 0 OrElse target.Contains(" "c) Then
            MessageBox.Show(Me, $"'{target}' is not a ticket target - use 'repo:ticket', for example 'fms-web:S0028'.",
                            "Run now", MessageBoxButtons.OK, MessageBoxIcon.Information)
            Return ""
        End If
        txtSteer.Text = target
        Return target
    End Function

    ' 'pq start -Ticket repo:id' is one pass on exactly that ticket, then pq exits, so the panel waits for it. A pass
    ' takes minutes: it runs hidden and outside _isCliBusy (Stop and the steering verbs stay usable), and only this
    ' button is held until it ends. Exit 3 is "valid target, not run" - the reason line is what the owner needs.
    Private _isRunNowBusy As Boolean = False

    Private Async Sub RunNowAsync()
        If _isRunNowBusy Then
            LogConsole("A Run now pass is already executing, please wait..")
            Return
        End If
        Dim target = ResolveRunNowTarget()
        If target = "" Then Return

        _isRunNowBusy = True
        btnRunNow.Enabled = False
        Try
            LogConsole($"Run now: 'pq start -Ticket {target}' - one pass on exactly this ticket, then it stops. A pass takes minutes; the result is logged here..")
            Dim res = Await PqCli.RunSilentAsync("start", "-Ticket", target)
            If IsDisposed Then Return
            If res.Success Then
                LogConsole($"Run now {target}: the pass ran (exit 0).{Environment.NewLine}{LastLines(res.Output, 6)}")
            ElseIf res.ExitCode = 3 Then
                Dim reason = NotRunReason(res)
                LogConsole($"Run now {target}: not run (exit 3) - {reason}")
                MessageBox.Show(Me, $"'{target}' was not run.{Environment.NewLine}{Environment.NewLine}{reason}", "Run now", MessageBoxButtons.OK, MessageBoxIcon.Information)
            Else
                LogConsole($"pq start -Ticket {target} failed (exit {res.ExitCode}): {res.Message}")
                MessageBox.Show(Me, $"pq start -Ticket {target} failed (exit {res.ExitCode}).{Environment.NewLine}{Environment.NewLine}{LastLines(res.Message, 4)}", "Run now", MessageBoxButtons.OK, MessageBoxIcon.Warning)
            End If
        Finally
            _isRunNowBusy = False
            If Not IsDisposed Then
                btnRunNow.Enabled = True
                RefreshAll()
            End If
        End Try
    End Sub

    ' The last 'pq: ticket ... not run - <cause>' line of the output; failing that, the last line pq printed.
    Private Shared Function NotRunReason(res As CliResult) As String
        Dim lines = (res.Output & Environment.NewLine & res.ErrorOutput).Split({ControlChars.Cr, ControlChars.Lf}, StringSplitOptions.RemoveEmptyEntries).Select(Function(l) l.Trim()).Where(Function(l) l <> "").ToList()
        Dim hit = lines.LastOrDefault(Function(l) l.StartsWith("pq: ticket", StringComparison.Ordinal) AndAlso l.Contains(" not run"))
        If hit IsNot Nothing Then Return hit
        Return If(lines.Count > 0, lines(lines.Count - 1), "pq gave no reason line (see the console of a manual run).")
    End Function

    Private Shared Function LastLines(text As String, count As Integer) As String
        Dim lines = text.Split({ControlChars.Cr, ControlChars.Lf}, StringSplitOptions.RemoveEmptyEntries).Select(Function(l) l.TrimEnd()).Where(Function(l) l <> "").ToList()
        If lines.Count = 0 Then Return ""
        Return String.Join(Environment.NewLine, lines.Skip(Math.Max(0, lines.Count - count)))
    End Function

    Private Sub DgvRepos_SelectionChanged(sender As Object, e As EventArgs)
        If _isRefreshing Then Return
        Dim key = SelectedRepoKey()
        If key <> "" AndAlso Not txtSteer.Text.Trim().StartsWith(key & ":", StringComparison.Ordinal) Then
            txtSteer.Text = key
        End If
    End Sub

    Private Sub SteerFromRow(grid As DataGridView, rowIndex As Integer, repoColumn As String, ticketColumn As String)
        If rowIndex < 0 Then Return
        Dim repo = grid.Rows(rowIndex).Cells(repoColumn).Value?.ToString()
        Dim ticket = grid.Rows(rowIndex).Cells(ticketColumn).Value?.ToString()
        If String.IsNullOrWhiteSpace(repo) Then Return
        txtSteer.Text = If(String.IsNullOrWhiteSpace(ticket), repo, $"{repo}:{ticket}")
    End Sub

    ' A double-click on a worker, a pass or a queue row: the steer box is filled as before, and the ticket's spec opens.
    Private Sub SteerAndOpenFromRow(grid As DataGridView, rowIndex As Integer, repoColumn As String, ticketColumn As String)
        If rowIndex < 0 Then Return
        SteerFromRow(grid, rowIndex, repoColumn, ticketColumn)
        OpenTicketSpec(grid.Rows(rowIndex).Cells(repoColumn).Value?.ToString(), grid.Rows(rowIndex).Cells(ticketColumn).Value?.ToString())
    End Sub

    ' Opens the spec the project's ledger names for exactly this id; a row without a ticket, or an id no ledger row
    ' names, opens nothing and says so.
    Private Sub OpenTicketSpec(repoKey As String, id As String)
        If String.IsNullOrWhiteSpace(repoKey) OrElse String.IsNullOrWhiteSpace(id) Then
            LogConsole("This row names no ticket - nothing to open.")
            Return
        End If
        Dim repo = _repos.FirstOrDefault(Function(r) r.Key.Equals(repoKey, StringComparison.Ordinal))
        If repo Is Nothing Then
            LogConsole($"'{repoKey}' is not a registered project - cannot find the spec of {repoKey}:{id}.")
            Return
        End If
        Dim spec = PortfolioState.FindTicketSpecFile(repo, id)
        If spec = "" Then
            LogConsole($"No spec file for {repoKey}:{id}: no row of its ledger names an existing file for this id.")
            Return
        End If
        LogConsole($"Opening the spec of {repoKey}:{id}: {spec}")
        Dim err = PqCli.OpenFileWithDefaultApp(spec)
        If err IsNot Nothing Then LogConsole($"Cannot open {spec}: {err}")
    End Sub

    Private Sub DgvRepos_CellClick(sender As Object, e As DataGridViewCellEventArgs)
        If e.RowIndex < 0 OrElse e.ColumnIndex < 0 Then Return
        Dim r = TryCast(dgvRepos.Rows(e.RowIndex).Tag, RepoInfo)
        If r Is Nothing Then Return

        Dim column = dgvRepos.Columns(e.ColumnIndex).Name
        Select Case column
            Case "colAsk", "colTest", "colOutside", "colChain", "colUnbuilt"
                ListInbox(r, column)
            Case "colNewSpec"
                ShowNewSpec(r.Key)
            Case "colQueue"
                Dim queuePath = PortfolioState.GetTicketQueuePath(r)
                If File.Exists(queuePath) Then
                    LogConsole($"Opening ticket queue of '{r.Key}': {queuePath}")
                    Dim err = PqCli.OpenFileWithDefaultApp(queuePath)
                    If err IsNot Nothing Then LogConsole($"Cannot open {queuePath}: {err}")
                Else
                    LogConsole($"Ticket queue file missing for '{r.Key}': {queuePath}")
                    MessageBox.Show(Me, $"No ticket queue file found at:{Environment.NewLine}{queuePath}{Environment.NewLine}{Environment.NewLine}A ticket queue is created when the first ticket is drafted in this project.", "Ticket Queue Missing", MessageBoxButtons.OK, MessageBoxIcon.Information)
                End If
            Case "colFolder"
                LogConsole($"Opening folder in VS Code: {r.Path}")
                Dim err = PqCli.OpenVsCode(r.Path)
                If err IsNot Nothing Then LogConsole($"Cannot open VS Code for {r.Path}: {err}")
            Case "colSession"
                LogConsole($"Opening a Claude session in '{r.Key}': a terminal running claude in {r.Path}")
                Dim err = PqCli.OpenClaudeSession(r.Path)
                If err IsNot Nothing Then
                    LogConsole($"Cannot open a Claude session for {r.Path}: {err}")
                    MessageBox.Show(Me, $"Cannot open a Claude session in '{r.Key}':{Environment.NewLine}{err}", "Claude session", MessageBoxButtons.OK, MessageBoxIcon.Warning)
                End If
            Case "colStartRepo"
                ' A worker for one project runs for as long as the project has tickets: a visible terminal like Start,
                ' where pq's own refusal (unknown or held project, STOP, no agent) stays on screen.
                ' A click anywhere in the cell, or a double click, must not start two workers that spend tokens: ask first.
                If MessageBox.Show(Me, $"Start a worker that takes tickets of '{r.Key}' only?", "Start on this project", MessageBoxButtons.YesNo, MessageBoxIcon.Question) <> DialogResult.Yes Then Exit Select
                LogConsole($"Launching 'pq start -Repo {r.Key}' in a new terminal..")
                Dim err = PqCli.LaunchInteractive("start", "-Repo", r.Key)
                If err IsNot Nothing Then
                    LogConsole($"Launch failed: {err}")
                    MessageBox.Show(Me, $"Cannot start a worker on '{r.Key}':{Environment.NewLine}{err}", "Start on this project", MessageBoxButtons.OK, MessageBoxIcon.Warning)
                End If
                RefreshAll()
        End Select
    End Sub

    Protected Overrides Sub OnFormClosing(e As FormClosingEventArgs)
        ' Save layout state per APP-BEHAVIOUR Rule 9
        Dim state As New UiStateData With {
            .WindowX = If(WindowState = FormWindowState.Normal, Me.Location.X, Me.RestoreBounds.Location.X),
            .WindowY = If(WindowState = FormWindowState.Normal, Me.Location.Y, Me.RestoreBounds.Location.Y),
            .WindowWidth = If(WindowState = FormWindowState.Normal, Me.Width, Me.RestoreBounds.Width),
            .WindowHeight = If(WindowState = FormWindowState.Normal, Me.Height, Me.RestoreBounds.Height),
            .WindowMaximized = (Me.WindowState = FormWindowState.Maximized),
            .MainSplitterDistance = splitMain.SplitterDistance,
            .MonitorSplitterDistance = splitRightMonitor.SplitterDistance,
            .ConsoleHeight = If(_consoleCollapsed, _consoleExpandedHeight, pnlBottom.Height),
            .ConsoleCollapsed = _consoleCollapsed,
            .AutoRefresh = chkAutoRefresh.Checked,
            .Theme = ThemeService.Mode.ToString()
        }
        UiState.Save(state)

        MyBase.OnFormClosing(e)
    End Sub

    Protected Overrides Sub OnFormClosed(e As FormClosedEventArgs)
        tmrRefresh.Enabled = False
        MyBase.OnFormClosed(e)
        _boldRepos.Dispose()
        _boldWorkers.Dispose()
    End Sub
End Class
