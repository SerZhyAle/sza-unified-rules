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

    ' The console keeps the tail of the session; a panel left open for days must not grow without bound.
    Private Const ConsoleMaxChars As Integer = 200000

    Public Sub New()
        InitializeComponent()
        _boldRepos = New Font(dgvRepos.Font, FontStyle.Bold)
        _boldWorkers = New Font(dgvWorkers.Font, FontStyle.Bold)
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

        tmrRefresh.Interval = 4000
        tmrRefresh.Enabled = chkAutoRefresh.Checked
    End Sub

    Private Sub ConfigureGrids()
        dgvRepos.Columns.Clear()
        AddTextColumn(dgvRepos, "colOrder", "#", 32)
        AddTextColumn(dgvRepos, "colKey", "Project", 115)
        AddTextColumn(dgvRepos, "colStatus", "Status", 80)
        AddTextColumn(dgvRepos, "colQueued", "Queued", 55)
        AddTextColumn(dgvRepos, "colPerm", "Permission", 115)
        AddButtonColumn(dgvRepos, "colNewSpec", "Spec", "+ Spec...", 65)
        AddButtonColumn(dgvRepos, "colQueue", "Tickets", "Open Queue", 85)
        AddButtonColumn(dgvRepos, "colFolder", "Folder", "Open VSCode", 95)

        dgvWorkers.Columns.Clear()
        AddTextColumn(dgvWorkers, "colSlot", "Slot", 45)
        AddTextColumn(dgvWorkers, "colPid", "PID", 60)
        AddTextColumn(dgvWorkers, "colWorkerRepo", "Project", 95)
        AddTextColumn(dgvWorkers, "colWorkerTicket", "Ticket", 90)
        AddTextColumn(dgvWorkers, "colWorkerTitle", "Title", 180)
        AddTextColumn(dgvWorkers, "colElapsed", "Running", 80)
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
        AddHandler btnNewSpec.Click, Sub() ShowNewSpec(SelectedRepoKey())
        AddHandler btnDoctor.Click, AddressOf BtnDoctor_Click
        AddHandler btnGuide.Click, AddressOf BtnGuide_Click
        AddHandler btnRegister.Click, AddressOf BtnRegister_Click
        AddHandler btnTheme.Click, AddressOf BtnTheme_Click

        AddHandler btnOpenQueue.Click, AddressOf BtnOpenQueue_Click
        AddHandler btnDryRun.Click, AddressOf BtnDryRun_Click
        AddHandler btnArrange.Click, AddressOf BtnArrange_Click
        AddHandler btnUp.Click, Sub() MoveProjectAsync(-1)
        AddHandler btnDown.Click, Sub() MoveProjectAsync(1)
        AddHandler btnPin.Click, Sub() SteerAsync("pin", requireTicket:=True)
        AddHandler btnHold.Click, Sub() SteerAsync("hold", requireTicket:=False)
        AddHandler btnRelease.Click, Sub() SteerAsync("release", requireTicket:=False)

        AddHandler dgvRepos.CellClick, AddressOf DgvRepos_CellClick
        AddHandler dgvRepos.SelectionChanged, AddressOf DgvRepos_SelectionChanged
        AddHandler dgvWorkers.CellDoubleClick, Sub(s, e) SteerFromRow(dgvWorkers, e.RowIndex, "colWorkerRepo", "colWorkerTicket")
        AddHandler dgvPasses.CellDoubleClick, Sub(s, e) SteerFromRow(dgvPasses, e.RowIndex, "colPassRepo", "colPassTicket")

        AddHandler splBottom.SplitterMoved, AddressOf SplBottom_SplitterMoved
        AddHandler splBottom.DoubleClick, AddressOf BtnToggleConsole_Click

        AddHandler btnToggleConsole.Click, AddressOf BtnToggleConsole_Click
        AddHandler btnClearConsole.Click, Sub() txtConsole.Clear()
        AddHandler btnCopyConsole.Click, AddressOf BtnCopyConsole_Click
        AddHandler btnRefreshNow.Click, Sub() RefreshAll()
        AddHandler chkAutoRefresh.CheckedChanged, Sub() tmrRefresh.Enabled = chkAutoRefresh.Checked
        AddHandler tmrRefresh.Tick, Sub() RefreshAll()

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
                Dim idx = dgvWorkers.Rows.Add(w.Slot, w.Pid, w.Repository, w.Ticket, w.Title, w.Elapsed, If(w.Alive, "Alive", "Dead"))
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

            ' 5. Repositories
            Dim selKey = SelectedRepoKey()
            Dim reposScroll = FirstVisibleRow(dgvRepos)
            dgvRepos.Rows.Clear()
            Dim selIdx = -1
            For Each r In repos
                Dim statusText = If(r.IsHeld, If(r.RegistryHold, "Held (reg)", "Held"), If(r.Enabled, "Enabled", "Disabled"))
                Dim idx = dgvRepos.Rows.Add(dgvRepos.Rows.Count + 1, r.Key, statusText, If(r.QueuedRows > 0, CStr(r.QueuedRows), ""), r.PermissionMode)
                Dim row = dgvRepos.Rows(idx)
                row.Tag = r
                row.Cells("colKey").ToolTipText = r.Path
                row.Cells("colOrder").ToolTipText = $"rank {r.Rank}"

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

    Private Async Sub BtnStop_Click(sender As Object, e As EventArgs)
        LogConsole("Requesting a graceful stop: workers finish their current pass, then exit..")
        Await RunLoggedAsync(btnStop, "stop")
    End Sub

    Private Async Sub BtnKill_Click(sender As Object, e As EventArgs)
        Dim confirm = MessageBox.Show(Me,
            "Forcibly terminate the running pass process trees?" & vbCrLf & "The ticket in flight is abandoned mid-pass.",
            "Confirm Force Kill", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2)
        If confirm <> DialogResult.Yes Then Return
        LogConsole("Terminating runner children ('pq stop -Kill')..")
        Await RunLoggedAsync(btnKill, "stop", "-Kill")
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

    Private Sub DgvRepos_CellClick(sender As Object, e As DataGridViewCellEventArgs)
        If e.RowIndex < 0 OrElse e.ColumnIndex < 0 Then Return
        Dim r = TryCast(dgvRepos.Rows(e.RowIndex).Tag, RepoInfo)
        If r Is Nothing Then Return

        Dim column = dgvRepos.Columns(e.ColumnIndex).Name
        Select Case column
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
