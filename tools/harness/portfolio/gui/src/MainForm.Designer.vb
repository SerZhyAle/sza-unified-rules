Option Explicit On
Option Strict On

Partial Class MainForm
    Inherits Form

    Private components As System.ComponentModel.IContainer = Nothing

    Friend pnlTopActions As FlowLayoutPanel
    Friend btnStartLoop As Button
    Friend btnStartOne As Button
    Friend btnStartDrain As Button
    Friend btnStop As Button
    Friend btnKill As Button
    Friend btnNewSpec As Button
    Friend btnDoctor As Button
    Friend btnGuide As Button
    Friend btnRegister As Button
    Friend btnProviders As Button

    Friend pnlBanner As Panel
    Friend lblStatus As Label
    Friend lblNextCandidate As Label
    Friend btnTheme As Button

    Friend splitMain As SplitContainer
    Friend pnlLeftHeader As Panel
    Friend btnOpenQueue As Button
    Friend btnDryRun As Button
    Friend btnArrange As Button
    Friend btnUp As Button
    Friend btnDown As Button
    Friend pnlSteer As Panel
    Friend lblSteer As Label
    Friend txtSteer As TextBox
    Friend btnPin As Button
    Friend btnHold As Button
    Friend btnRelease As Button
    Friend dgvRepos As DataGridView

    Friend splitRightMonitor As SplitContainer
    Friend pnlWorkersHeader As Panel
    Friend lblWorkers As Label
    Friend dgvWorkers As DataGridView
    Friend pnlPassesHeader As Panel
    Friend lblPasses As Label
    Friend dgvPasses As DataGridView

    Friend pnlBottom As Panel
    Friend splBottom As Splitter
    Friend pnlBottomBar As Panel
    Friend btnToggleConsole As Button
    Friend chkAutoRefresh As CheckBox
    Friend btnRefreshNow As Button
    Friend btnClearConsole As Button
    Friend btnCopyConsole As Button
    Friend lblPqPath As Label
    Friend txtConsole As TextBox
    Friend tmrRefresh As Timer
    Friend tipMain As ToolTip

    Protected Overrides Sub Dispose(disposing As Boolean)
        Try
            If disposing AndAlso (components IsNot Nothing) Then
                components.Dispose()
            End If
        Finally
            MyBase.Dispose(disposing)
        End Try
    End Sub

    Private Sub InitializeComponent()
        Me.components = New System.ComponentModel.Container()
        Me.tipMain = New ToolTip(Me.components)

        Me.pnlTopActions = New FlowLayoutPanel()
        Me.btnStartLoop = New Button()
        Me.btnStartOne = New Button()
        Me.btnStartDrain = New Button()
        Me.btnStop = New Button()
        Me.btnKill = New Button()
        Me.btnNewSpec = New Button()
        Me.btnDoctor = New Button()
        Me.btnGuide = New Button()
        Me.btnRegister = New Button()
        Me.btnProviders = New Button()

        Me.pnlBanner = New Panel()
        Me.lblStatus = New Label()
        Me.btnTheme = New Button()
        Me.lblNextCandidate = New Label()

        Me.splitMain = New SplitContainer()
        Me.pnlLeftHeader = New Panel()
        Me.btnOpenQueue = New Button()
        Me.btnDryRun = New Button()
        Me.btnArrange = New Button()
        Me.btnUp = New Button()
        Me.btnDown = New Button()
        Me.pnlSteer = New Panel()
        Me.lblSteer = New Label()
        Me.txtSteer = New TextBox()
        Me.btnPin = New Button()
        Me.btnHold = New Button()
        Me.btnRelease = New Button()
        Me.dgvRepos = New DataGridView()

        Me.splitRightMonitor = New SplitContainer()
        Me.pnlWorkersHeader = New Panel()
        Me.lblWorkers = New Label()
        Me.dgvWorkers = New DataGridView()
        Me.pnlPassesHeader = New Panel()
        Me.lblPasses = New Label()
        Me.dgvPasses = New DataGridView()

        Me.pnlBottom = New Panel()
        Me.splBottom = New Splitter()
        Me.pnlBottomBar = New Panel()
        Me.btnToggleConsole = New Button()
        Me.chkAutoRefresh = New CheckBox()
        Me.btnRefreshNow = New Button()
        Me.btnClearConsole = New Button()
        Me.btnCopyConsole = New Button()
        Me.lblPqPath = New Label()
        Me.txtConsole = New TextBox()
        Me.tmrRefresh = New Timer(Me.components)

        CType(Me.splitMain, System.ComponentModel.ISupportInitialize).BeginInit()
        Me.splitMain.Panel1.SuspendLayout()
        Me.splitMain.Panel2.SuspendLayout()
        Me.splitMain.SuspendLayout()

        CType(Me.splitRightMonitor, System.ComponentModel.ISupportInitialize).BeginInit()
        Me.splitRightMonitor.Panel1.SuspendLayout()
        Me.splitRightMonitor.Panel2.SuspendLayout()
        Me.splitRightMonitor.SuspendLayout()

        CType(Me.dgvRepos, System.ComponentModel.ISupportInitialize).BeginInit()
        CType(Me.dgvWorkers, System.ComponentModel.ISupportInitialize).BeginInit()
        CType(Me.dgvPasses, System.ComponentModel.ISupportInitialize).BeginInit()
        Me.SuspendLayout()

        ' --- pnlTopActions ---
        Me.pnlTopActions.Dock = DockStyle.Top
        Me.pnlTopActions.AutoSize = True
        Me.pnlTopActions.AutoSizeMode = AutoSizeMode.GrowAndShrink
        Me.pnlTopActions.WrapContents = True
        Me.pnlTopActions.Padding = New Padding(8, 6, 8, 6)

        ' Primary Action per BUTTONS Contract
        Me.btnStartLoop.Name = "btnStartLoop"
        Me.btnStartLoop.Text = "▶ &Start Worker (Loop)"
        Me.btnStartLoop.Size = New Size(170, 36)
        Me.btnStartLoop.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.btnStartLoop.AccessibleName = "Start Continuous Worker Loop"
        Me.btnStartLoop.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnStartLoop, "Launches continuous runner worker in an independent PowerShell terminal ('pq start')")

        Me.btnStartOne.Name = "btnStartOne"
        Me.btnStartOne.Text = "▶ Start &1 Pass"
        Me.btnStartOne.Size = New Size(125, 36)
        Me.btnStartOne.AccessibleName = "Start Single Pass Worker"
        Me.btnStartOne.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnStartOne, "Runs one ticket pass and terminates ('pq start -MaxTickets 1')")

        Me.btnStartDrain.Name = "btnStartDrain"
        Me.btnStartDrain.Text = "▶ Start &Drain"
        Me.btnStartDrain.Size = New Size(115, 36)
        Me.btnStartDrain.AccessibleName = "Start Drain Mode"
        Me.btnStartDrain.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnStartDrain, "Processes all currently dispatchable tickets until queue is empty ('pq start -Drain')")

        ' Warning Action
        Me.btnStop.Name = "btnStop"
        Me.btnStop.Text = "⏹ S&top Workers"
        Me.btnStop.Size = New Size(130, 36)
        Me.btnStop.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.btnStop.AccessibleName = "Gracefully Stop Workers"
        Me.btnStop.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnStop, "Signals active workers to finish their current ticket and exit gracefully ('pq stop')")

        ' Destructive Action
        Me.btnKill.Name = "btnKill"
        Me.btnKill.Text = "✖ Force &Kill"
        Me.btnKill.Size = New Size(115, 36)
        Me.btnKill.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.btnKill.AccessibleName = "Force Kill Worker Trees"
        Me.btnKill.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnKill, "Emergency stop: forcefully terminates worker process trees mid-pass ('pq stop -Kill')")

        ' Parameterized command with ellipsis per BUTTONS
        Me.btnNewSpec.Name = "btnNewSpec"
        Me.btnNewSpec.Text = "📝 &New Spec..."
        Me.btnNewSpec.Size = New Size(130, 36)
        Me.btnNewSpec.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.btnNewSpec.AccessibleName = "New Ticket Specification"
        Me.btnNewSpec.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnNewSpec, "Opens specification capture dialog to draft a new ticket via spec-draft.ps1 (Ctrl+N)")

        Me.btnDoctor.Name = "btnDoctor"
        Me.btnDoctor.Text = "🩺 Doc&tor"
        Me.btnDoctor.Size = New Size(100, 36)
        Me.btnDoctor.AccessibleName = "Run Diagnostic Doctor"
        Me.btnDoctor.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnDoctor, "Performs health and stamp checks across all registered repositories (Ctrl+D)")

        Me.btnGuide.Name = "btnGuide"
        Me.btnGuide.Text = "📖 &Guide (F1)"
        Me.btnGuide.Size = New Size(105, 36)
        Me.btnGuide.AccessibleName = "Open Operator Guide"
        Me.btnGuide.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnGuide, "Opens the canonical portfolio operator guide in default markdown reader (F1)")

        ' Parameterized command with ellipsis
        Me.btnRegister.Name = "btnRegister"
        Me.btnRegister.Text = "➕ &Register..."
        Me.btnRegister.Size = New Size(120, 36)
        Me.btnRegister.AccessibleName = "Register Repository"
        Me.btnRegister.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnRegister, "Registers a repository into the portfolio registry repos.json ('pq register') (Ctrl+R)")

        ' Parameterized command with ellipsis: which model providers spend tokens, and in what order
        Me.btnProviders.Name = "btnProviders"
        Me.btnProviders.Text = "🔀 Pro&viders..."
        Me.btnProviders.Size = New Size(125, 36)
        Me.btnProviders.AccessibleName = "Model Providers"
        Me.btnProviders.AccessibleRole = AccessibleRole.PushButton
        Me.tipMain.SetToolTip(Me.btnProviders, "Chooses which model providers (OpenAI, Anthropic, Gemini, z.ai) spend tokens and in what order ('pq agents')")

        Me.pnlTopActions.Controls.AddRange({Me.btnStartLoop, Me.btnStartOne, Me.btnStartDrain, Me.btnStop, Me.btnKill, Me.btnNewSpec, Me.btnDoctor, Me.btnGuide, Me.btnRegister, Me.btnProviders})

        ' --- pnlBanner ---
        Me.pnlBanner.Name = "pnlBanner"
        Me.pnlBanner.Dock = DockStyle.Top
        Me.pnlBanner.Height = 38
        Me.pnlBanner.Padding = New Padding(12, 0, 12, 0)

        Me.lblStatus.Name = "lblStatus"
        Me.lblStatus.Dock = DockStyle.Left
        Me.lblStatus.AutoSize = False
        Me.lblStatus.Width = 380
        Me.lblStatus.TextAlign = ContentAlignment.MiddleLeft
        Me.lblStatus.Font = New Font("Segoe UI", 9.75F, FontStyle.Bold)
        Me.lblStatus.ForeColor = Color.White
        Me.lblStatus.Text = "● READY (No active workers)"

        Me.btnTheme.Name = "btnTheme"
        Me.btnTheme.Dock = DockStyle.Right
        Me.btnTheme.Width = 100
        Me.btnTheme.Text = "🎨 Theme"
        Me.btnTheme.FlatStyle = FlatStyle.Flat
        Me.btnTheme.FlatAppearance.BorderSize = 0
        Me.btnTheme.ForeColor = Color.FromArgb(200, 225, 255)
        Me.btnTheme.Font = New Font("Segoe UI", 8.5F)
        Me.btnTheme.AccessibleName = "Toggle Theme"
        Me.tipMain.SetToolTip(Me.btnTheme, "Toggles between System, Dark, and Light themes per APP-STYLE")

        Me.lblNextCandidate.Name = "lblNextCandidate"
        Me.lblNextCandidate.Dock = DockStyle.Fill
        Me.lblNextCandidate.TextAlign = ContentAlignment.MiddleRight
        Me.lblNextCandidate.Font = New Font("Segoe UI", 9.0F)
        Me.lblNextCandidate.ForeColor = Color.FromArgb(200, 225, 255)
        Me.lblNextCandidate.Text = "Next: ..."

        Me.pnlBanner.Controls.Add(Me.lblNextCandidate)
        Me.pnlBanner.Controls.Add(Me.btnTheme)
        Me.pnlBanner.Controls.Add(Me.lblStatus)

        ' --- splitMain ---
        Me.splitMain.Name = "splitMain"
        Me.splitMain.Dock = DockStyle.Fill
        Me.splitMain.SplitterDistance = 600
        Me.splitMain.SplitterWidth = 5

        ' --- Left: Projects & Queues ---
        Me.pnlLeftHeader.Name = "pnlLeftHeader"
        Me.pnlLeftHeader.Dock = DockStyle.Top
        Me.pnlLeftHeader.Height = 44
        Me.pnlLeftHeader.Padding = New Padding(8, 6, 8, 6)

        Dim lblLeftTitle As New Label With {
            .Name = "lblLeftTitle",
            .Text = "Projects & Queues",
            .UseMnemonic = False,
            .Font = New Font("Segoe UI", 10.0F, FontStyle.Bold),
            .Dock = DockStyle.Left,
            .Width = 160,
            .TextAlign = ContentAlignment.MiddleLeft
        }

        Me.btnOpenQueue.Name = "btnOpenQueue"
        Me.btnOpenQueue.Text = "📝 &Open Portfolio Queue"
        Me.btnOpenQueue.Size = New Size(210, 32)
        Me.btnOpenQueue.Dock = DockStyle.Right
        Me.btnOpenQueue.AccessibleName = "Open Portfolio Queue"
        Me.tipMain.SetToolTip(Me.btnOpenQueue, "Syncs and opens PORTFOLIO_QUEUE.md in system default editor ('pq queue')")

        Me.btnDryRun.Name = "btnDryRun"
        Me.btnDryRun.Text = "🔍 &Dry-Run"
        Me.btnDryRun.Size = New Size(100, 32)
        Me.btnDryRun.Dock = DockStyle.Right
        Me.btnDryRun.AccessibleName = "Preview dry-run ranking"
        Me.tipMain.SetToolTip(Me.btnDryRun, "Ranks all projects and previews next dispatched tickets ('pq dry-run')")

        Me.btnArrange.Name = "btnArrange"
        Me.btnArrange.Text = "⇅ &Arrange"
        Me.btnArrange.Size = New Size(100, 32)
        Me.btnArrange.Dock = DockStyle.Right
        Me.btnArrange.AccessibleName = "Arrange Queue File"
        Me.tipMain.SetToolTip(Me.btnArrange, "Lines PORTFOLIO_QUEUE.md up in the order of work: projects as in this list, each project's rows together ('pq arrange')")

        Me.pnlLeftHeader.Controls.AddRange({lblLeftTitle, Me.btnArrange, Me.btnDryRun, Me.btnOpenQueue})

        ' Steer Toolbar
        Me.pnlSteer.Name = "pnlSteer"
        Me.pnlSteer.Dock = DockStyle.Top
        Me.pnlSteer.Height = 44
        Me.pnlSteer.Padding = New Padding(8, 6, 8, 6)

        Me.lblSteer.Name = "lblSteer"
        Me.lblSteer.Text = "Ticket / Project:"
        Me.lblSteer.AutoSize = True
        Me.lblSteer.Location = New Point(8, 14)

        Me.txtSteer.Name = "txtSteer"
        Me.txtSteer.Location = New Point(115, 9)
        Me.txtSteer.Size = New Size(180, 26)
        Me.txtSteer.AccessibleName = "Steer Target Input"
        Me.tipMain.SetToolTip(Me.txtSteer, "Enter project key (e.g. 'fms-web') or ticket token (e.g. 'fms-web:S0028')")

        Me.btnPin.Name = "btnPin"
        Me.btnPin.Text = "&Pin Top"
        Me.btnPin.Location = New Point(302, 6)
        Me.btnPin.Size = New Size(75, 32)
        Me.btnPin.AccessibleName = "Pin ticket to top"
        Me.tipMain.SetToolTip(Me.btnPin, "Pins ticket to top of PORTFOLIO_QUEUE.md ('pq pin <target>')")

        Me.btnHold.Name = "btnHold"
        Me.btnHold.Text = "&Hold"
        Me.btnHold.Location = New Point(382, 6)
        Me.btnHold.Size = New Size(65, 32)
        Me.btnHold.AccessibleName = "Hold ticket or project"
        Me.tipMain.SetToolTip(Me.btnHold, "Marks ticket or project as held ('pq hold <target>')")

        Me.btnRelease.Name = "btnRelease"
        Me.btnRelease.Text = "Re&lease"
        Me.btnRelease.Location = New Point(452, 6)
        Me.btnRelease.Size = New Size(75, 32)
        Me.btnRelease.AccessibleName = "Release held ticket or project"
        Me.tipMain.SetToolTip(Me.btnRelease, "Removes hold from ticket or project ('pq release <target>')")

        Me.btnUp.Name = "btnUp"
        Me.btnUp.Text = "▲"
        Me.btnUp.Location = New Point(534, 6)
        Me.btnUp.Size = New Size(36, 32)
        Me.btnUp.AccessibleName = "Move project up in rank"
        Me.tipMain.SetToolTip(Me.btnUp, "Moves selected project higher in rank order")

        Me.btnDown.Name = "btnDown"
        Me.btnDown.Text = "▼"
        Me.btnDown.Location = New Point(574, 6)
        Me.btnDown.Size = New Size(36, 32)
        Me.btnDown.AccessibleName = "Move project down in rank"
        Me.tipMain.SetToolTip(Me.btnDown, "Moves selected project lower in rank order")

        Me.pnlSteer.Controls.AddRange({Me.lblSteer, Me.txtSteer, Me.btnPin, Me.btnHold, Me.btnRelease, Me.btnUp, Me.btnDown})

        ' DataGridView Repos
        Me.dgvRepos.Name = "dgvRepos"
        Me.dgvRepos.Dock = DockStyle.Fill
        Me.dgvRepos.AllowUserToAddRows = False
        Me.dgvRepos.AllowUserToDeleteRows = False
        Me.dgvRepos.ReadOnly = True
        Me.dgvRepos.SelectionMode = DataGridViewSelectionMode.FullRowSelect
        Me.dgvRepos.RowHeadersVisible = False

        Me.splitMain.Panel1.Controls.Add(Me.dgvRepos)
        Me.splitMain.Panel1.Controls.Add(Me.pnlSteer)
        Me.splitMain.Panel1.Controls.Add(Me.pnlLeftHeader)

        ' --- Right: Live Monitor ---
        Me.splitRightMonitor.Name = "splitRightMonitor"
        Me.splitRightMonitor.Dock = DockStyle.Fill
        Me.splitRightMonitor.Orientation = Orientation.Horizontal
        Me.splitRightMonitor.SplitterDistance = 180
        Me.splitRightMonitor.SplitterWidth = 5

        ' Upper Right: Workers
        Me.pnlWorkersHeader.Name = "pnlWorkersHeader"
        Me.pnlWorkersHeader.Dock = DockStyle.Top
        Me.pnlWorkersHeader.Height = 32
        Me.pnlWorkersHeader.Padding = New Padding(8, 4, 8, 4)
        Me.lblWorkers.Name = "lblWorkers"
        Me.lblWorkers.Text = "Active Workers (run/worker-*.json)"
        Me.lblWorkers.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.lblWorkers.Dock = DockStyle.Fill
        Me.lblWorkers.TextAlign = ContentAlignment.MiddleLeft
        Me.pnlWorkersHeader.Controls.Add(Me.lblWorkers)

        Me.dgvWorkers.Name = "dgvWorkers"
        Me.dgvWorkers.Dock = DockStyle.Fill
        Me.dgvWorkers.AllowUserToAddRows = False
        Me.dgvWorkers.AllowUserToDeleteRows = False
        Me.dgvWorkers.ReadOnly = True
        Me.dgvWorkers.SelectionMode = DataGridViewSelectionMode.FullRowSelect
        Me.dgvWorkers.RowHeadersVisible = False

        Me.splitRightMonitor.Panel1.Controls.Add(Me.dgvWorkers)
        Me.splitRightMonitor.Panel1.Controls.Add(Me.pnlWorkersHeader)

        ' Lower Right: Passes
        Me.pnlPassesHeader.Name = "pnlPassesHeader"
        Me.pnlPassesHeader.Dock = DockStyle.Top
        Me.pnlPassesHeader.Height = 32
        Me.pnlPassesHeader.Padding = New Padding(8, 4, 8, 4)
        Me.lblPasses.Name = "lblPasses"
        Me.lblPasses.Text = "Recent Passes (runs.jsonl)"
        Me.lblPasses.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.lblPasses.Dock = DockStyle.Fill
        Me.lblPasses.TextAlign = ContentAlignment.MiddleLeft
        Me.pnlPassesHeader.Controls.Add(Me.lblPasses)

        Me.dgvPasses.Name = "dgvPasses"
        Me.dgvPasses.Dock = DockStyle.Fill
        Me.dgvPasses.AllowUserToAddRows = False
        Me.dgvPasses.AllowUserToDeleteRows = False
        Me.dgvPasses.ReadOnly = True
        Me.dgvPasses.SelectionMode = DataGridViewSelectionMode.FullRowSelect
        Me.dgvPasses.RowHeadersVisible = False

        Me.splitRightMonitor.Panel2.Controls.Add(Me.dgvPasses)
        Me.splitRightMonitor.Panel2.Controls.Add(Me.pnlPassesHeader)

        Me.splitMain.Panel2.Controls.Add(Me.splitRightMonitor)

        ' --- pnlBottom (Console) ---
        Me.pnlBottom.Name = "pnlBottom"
        Me.pnlBottom.Dock = DockStyle.Bottom
        Me.pnlBottom.Height = 240
        Me.pnlBottom.MinimumSize = New Size(0, 36)
        Me.pnlBottom.Padding = New Padding(8, 4, 8, 6)

        ' --- splBottom (Splitter to resize console) ---
        Me.splBottom.Name = "splBottom"
        Me.splBottom.Dock = DockStyle.Bottom
        Me.splBottom.Height = 6
        Me.splBottom.Cursor = Cursors.HSplit
        Me.splBottom.MinSize = 36
        Me.splBottom.MinExtra = 200

        Me.pnlBottomBar.Name = "pnlBottomBar"
        Me.pnlBottomBar.Dock = DockStyle.Top
        Me.pnlBottomBar.Height = 36

        Me.btnToggleConsole.Name = "btnToggleConsole"
        Me.btnToggleConsole.Text = "▼ Console"
        Me.btnToggleConsole.Location = New Point(2, 3)
        Me.btnToggleConsole.Size = New Size(95, 30)
        Me.btnToggleConsole.AccessibleName = "Toggle Console Visibility"
        Me.tipMain.SetToolTip(Me.btnToggleConsole, "Expands or collapses the CLI console output pane")

        Me.chkAutoRefresh.Name = "chkAutoRefresh"
        Me.chkAutoRefresh.Text = "Auto-refresh (4s)"
        Me.chkAutoRefresh.Checked = True
        Me.chkAutoRefresh.Location = New Point(105, 7)
        Me.chkAutoRefresh.AutoSize = True

        Me.btnRefreshNow.Name = "btnRefreshNow"
        Me.btnRefreshNow.Text = "↻ &Refresh (F5)"
        Me.btnRefreshNow.Location = New Point(235, 3)
        Me.btnRefreshNow.Size = New Size(115, 30)
        Me.btnRefreshNow.AccessibleName = "Refresh All Data"
        Me.tipMain.SetToolTip(Me.btnRefreshNow, "Refreshes registry, active workers, queue ranking and passes immediately (F5)")

        Me.btnClearConsole.Name = "btnClearConsole"
        Me.btnClearConsole.Text = "Clear"
        Me.btnClearConsole.Location = New Point(356, 3)
        Me.btnClearConsole.Size = New Size(65, 30)
        Me.btnCopyConsole.AccessibleName = "Clear console log"
        Me.tipMain.SetToolTip(Me.btnClearConsole, "Clears current console output buffer")

        Me.btnCopyConsole.Name = "btnCopyConsole"
        Me.btnCopyConsole.Text = "Copy"
        Me.btnCopyConsole.Location = New Point(426, 3)
        Me.btnCopyConsole.Size = New Size(65, 30)
        Me.btnCopyConsole.AccessibleName = "Copy console log"
        Me.tipMain.SetToolTip(Me.btnCopyConsole, "Copies entire console log to clipboard")

        Me.lblPqPath.Name = "lblPqPath"
        Me.lblPqPath.Location = New Point(500, 9)
        Me.lblPqPath.AutoSize = True
        Me.lblPqPath.Text = "Script: ..."

        Me.pnlBottomBar.Controls.AddRange({Me.btnToggleConsole, Me.chkAutoRefresh, Me.btnRefreshNow, Me.btnClearConsole, Me.btnCopyConsole, Me.lblPqPath})

        Me.txtConsole.Name = "txtConsole"
        Me.txtConsole.Dock = DockStyle.Fill
        Me.txtConsole.Multiline = True
        Me.txtConsole.ReadOnly = True
        Me.txtConsole.ScrollBars = ScrollBars.Vertical
        Me.txtConsole.Font = New Font("Consolas", 9.0F)
        Me.txtConsole.BorderStyle = BorderStyle.None

        Me.pnlBottom.Controls.Add(Me.txtConsole)
        Me.pnlBottom.Controls.Add(Me.pnlBottomBar)
        Me.pnlBottomBar.SendToBack()

        ' Form Setup
        Me.AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        Me.AutoScaleMode = AutoScaleMode.Font
        Me.ClientSize = New Size(1260, 740)
        Me.MinimumSize = New Size(1000, 600)
        Me.Text = "PQ Control Panel - Portfolio Queue Shell"
        Me.Font = New Font("Segoe UI", 9.0F)
        Me.StartPosition = FormStartPosition.CenterScreen
        Me.KeyPreview = True

        Me.Controls.Add(Me.splitMain)
        Me.Controls.Add(Me.splBottom)
        Me.Controls.Add(Me.pnlBottom)
        Me.Controls.Add(Me.pnlBanner)
        Me.Controls.Add(Me.pnlTopActions)

        ' Tab Index sequence per APP-BEHAVIOUR Rule 8
        Me.btnStartLoop.TabIndex = 0
        Me.btnStartOne.TabIndex = 1
        Me.btnStartDrain.TabIndex = 2
        Me.btnStop.TabIndex = 3
        Me.btnKill.TabIndex = 4
        Me.btnNewSpec.TabIndex = 5
        Me.btnDoctor.TabIndex = 6
        Me.btnGuide.TabIndex = 7
        Me.btnRegister.TabIndex = 8
        Me.btnProviders.TabIndex = 9
        Me.btnTheme.TabIndex = 9
        Me.btnOpenQueue.TabIndex = 10
        Me.btnDryRun.TabIndex = 11
        Me.btnArrange.TabIndex = 12
        Me.txtSteer.TabIndex = 13
        Me.btnPin.TabIndex = 14
        Me.btnHold.TabIndex = 15
        Me.btnRelease.TabIndex = 16
        Me.btnUp.TabIndex = 17
        Me.btnDown.TabIndex = 18
        Me.dgvRepos.TabIndex = 19
        Me.dgvWorkers.TabIndex = 20
        Me.dgvPasses.TabIndex = 21
        Me.btnToggleConsole.TabIndex = 22
        Me.chkAutoRefresh.TabIndex = 23
        Me.btnRefreshNow.TabIndex = 24
        Me.btnClearConsole.TabIndex = 25
        Me.btnCopyConsole.TabIndex = 26
        Me.txtConsole.TabIndex = 27

        Me.splitMain.Panel1.ResumeLayout(False)
        Me.splitMain.Panel2.ResumeLayout(False)
        CType(Me.splitMain, System.ComponentModel.ISupportInitialize).EndInit()
        Me.splitMain.ResumeLayout(False)

        Me.splitRightMonitor.Panel1.ResumeLayout(False)
        Me.splitRightMonitor.Panel2.ResumeLayout(False)
        CType(Me.splitRightMonitor, System.ComponentModel.ISupportInitialize).EndInit()
        Me.splitRightMonitor.ResumeLayout(False)

        CType(Me.dgvRepos, System.ComponentModel.ISupportInitialize).EndInit()
        CType(Me.dgvWorkers, System.ComponentModel.ISupportInitialize).EndInit()
        CType(Me.dgvPasses, System.ComponentModel.ISupportInitialize).EndInit()
        Me.ResumeLayout(False)
        Me.PerformLayout()
    End Sub
End Class
