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

    Friend pnlBanner As Panel
    Friend lblStatus As Label
    Friend lblNextCandidate As Label

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
    Friend chkAutoRefresh As CheckBox
    Friend btnRefreshNow As Button
    Friend lblPqPath As Label
    Friend txtConsole As TextBox
    Friend tmrRefresh As Timer

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

        Me.pnlBanner = New Panel()
        Me.lblStatus = New Label()
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
        Me.chkAutoRefresh = New CheckBox()
        Me.btnRefreshNow = New Button()
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
        Me.pnlTopActions.Height = 48
        Me.pnlTopActions.Padding = New Padding(6, 6, 6, 4)
        Me.pnlTopActions.BackColor = Color.FromArgb(245, 247, 250)

        Me.btnStartLoop.Text = "▶ Start Worker (Loop)"
        Me.btnStartLoop.Size = New Size(150, 34)
        Me.btnStartLoop.BackColor = Color.FromArgb(220, 245, 225)
        Me.btnStartLoop.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.btnStartLoop.UseVisualStyleBackColor = False

        Me.btnStartOne.Text = "▶ Start 1 Pass"
        Me.btnStartOne.Size = New Size(110, 34)
        Me.btnStartOne.BackColor = Color.FromArgb(225, 240, 255)
        Me.btnStartOne.UseVisualStyleBackColor = False

        Me.btnStartDrain.Text = "▶ Start Drain"
        Me.btnStartDrain.Size = New Size(105, 34)
        Me.btnStartDrain.BackColor = Color.FromArgb(240, 240, 245)
        Me.btnStartDrain.UseVisualStyleBackColor = False

        Me.btnStop.Text = "⏹ Stop Workers"
        Me.btnStop.Size = New Size(120, 34)
        Me.btnStop.BackColor = Color.FromArgb(255, 243, 205)
        Me.btnStop.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.btnStop.UseVisualStyleBackColor = False

        Me.btnKill.Text = "✖ Force Kill"
        Me.btnKill.Size = New Size(95, 34)
        Me.btnKill.BackColor = Color.FromArgb(255, 220, 220)
        Me.btnKill.ForeColor = Color.DarkRed
        Me.btnKill.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.btnKill.UseVisualStyleBackColor = False

        Me.btnNewSpec.Text = "📝 New Spec..."
        Me.btnNewSpec.Size = New Size(120, 34)
        Me.btnNewSpec.BackColor = Color.FromArgb(220, 245, 245)
        Me.btnNewSpec.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.btnNewSpec.UseVisualStyleBackColor = False

        Me.btnDoctor.Text = "🩺 Doctor"
        Me.btnDoctor.Size = New Size(90, 34)
        Me.btnDoctor.UseVisualStyleBackColor = True

        Me.btnGuide.Text = "📖 Guide"
        Me.btnGuide.Size = New Size(80, 34)
        Me.btnGuide.UseVisualStyleBackColor = True

        Me.btnRegister.Text = "➕ Register..."
        Me.btnRegister.Size = New Size(100, 34)
        Me.btnRegister.UseVisualStyleBackColor = True

        Me.pnlTopActions.Controls.AddRange({Me.btnStartLoop, Me.btnStartOne, Me.btnStartDrain, Me.btnStop, Me.btnKill, Me.btnNewSpec, Me.btnDoctor, Me.btnGuide, Me.btnRegister})

        ' --- pnlBanner ---
        Me.pnlBanner.Dock = DockStyle.Top
        Me.pnlBanner.Height = 36
        Me.pnlBanner.BackColor = Color.FromArgb(33, 43, 54)
        Me.pnlBanner.Padding = New Padding(12, 0, 12, 0)

        Me.lblStatus.Dock = DockStyle.Left
        Me.lblStatus.AutoSize = False
        Me.lblStatus.Width = 380
        Me.lblStatus.TextAlign = ContentAlignment.MiddleLeft
        Me.lblStatus.Font = New Font("Segoe UI", 9.75F, FontStyle.Bold)
        Me.lblStatus.ForeColor = Color.White
        Me.lblStatus.Text = "● READY (No active workers)"

        Me.lblNextCandidate.Dock = DockStyle.Fill
        Me.lblNextCandidate.TextAlign = ContentAlignment.MiddleRight
        Me.lblNextCandidate.Font = New Font("Segoe UI", 9.0F)
        Me.lblNextCandidate.ForeColor = Color.FromArgb(200, 225, 255)
        Me.lblNextCandidate.Text = "Next: ..."

        Me.pnlBanner.Controls.Add(Me.lblNextCandidate)
        Me.pnlBanner.Controls.Add(Me.lblStatus)

        ' --- splitMain ---
        Me.splitMain.Dock = DockStyle.Fill
        Me.splitMain.SplitterDistance = 600
        Me.splitMain.SplitterWidth = 5

        ' --- Left: Projects & Queues ---
        Me.pnlLeftHeader.Dock = DockStyle.Top
        Me.pnlLeftHeader.Height = 38
        Me.pnlLeftHeader.BackColor = Color.FromArgb(240, 243, 246)
        Me.pnlLeftHeader.Padding = New Padding(6, 4, 6, 4)

        Dim lblLeftTitle As New Label With {
            .Text = "Projects & Queues",
            .UseMnemonic = False,
            .Font = New Font("Segoe UI", 9.75F, FontStyle.Bold),
            .Dock = DockStyle.Left,
            .Width = 150,
            .TextAlign = ContentAlignment.MiddleLeft
        }

        Me.btnOpenQueue.Text = "📝 Open PORTFOLIO_QUEUE.md"
        Me.btnOpenQueue.Size = New Size(200, 28)
        Me.btnOpenQueue.Dock = DockStyle.Right
        Me.btnOpenQueue.UseVisualStyleBackColor = True

        Me.btnDryRun.Text = "🔍 Dry-Run"
        Me.btnDryRun.Size = New Size(90, 28)
        Me.btnDryRun.Dock = DockStyle.Right
        Me.btnDryRun.UseVisualStyleBackColor = True

        Me.btnArrange.Text = "⇅ Arrange"
        Me.btnArrange.Size = New Size(90, 28)
        Me.btnArrange.Dock = DockStyle.Right
        Me.btnArrange.UseVisualStyleBackColor = True

        Me.pnlLeftHeader.Controls.AddRange({lblLeftTitle, Me.btnArrange, Me.btnDryRun, Me.btnOpenQueue})

        ' Steer Toolbar
        Me.pnlSteer.Dock = DockStyle.Top
        Me.pnlSteer.Height = 36
        Me.pnlSteer.BackColor = Color.FromArgb(248, 249, 250)
        Me.pnlSteer.Padding = New Padding(6, 4, 6, 4)

        Me.lblSteer.Text = "Ticket / Project:"
        Me.lblSteer.AutoSize = True
        Me.lblSteer.Location = New Point(8, 9)

        Me.txtSteer.Location = New Point(105, 6)
        Me.txtSteer.Size = New Size(185, 23)

        Me.btnPin.Text = "Pin Top"
        Me.btnPin.Location = New Point(296, 5)
        Me.btnPin.Size = New Size(62, 26)
        Me.btnPin.UseVisualStyleBackColor = True

        Me.btnHold.Text = "Hold"
        Me.btnHold.Location = New Point(362, 5)
        Me.btnHold.Size = New Size(56, 26)
        Me.btnHold.UseVisualStyleBackColor = True

        Me.btnRelease.Text = "Release"
        Me.btnRelease.Location = New Point(422, 5)
        Me.btnRelease.Size = New Size(66, 26)
        Me.btnRelease.UseVisualStyleBackColor = True

        Me.btnUp.Text = "▲"
        Me.btnUp.Location = New Point(502, 5)
        Me.btnUp.Size = New Size(30, 26)
        Me.btnUp.UseVisualStyleBackColor = True

        Me.btnDown.Text = "▼"
        Me.btnDown.Location = New Point(534, 5)
        Me.btnDown.Size = New Size(30, 26)
        Me.btnDown.UseVisualStyleBackColor = True

        Me.pnlSteer.Controls.AddRange({Me.lblSteer, Me.txtSteer, Me.btnPin, Me.btnHold, Me.btnRelease, Me.btnUp, Me.btnDown})

        ' DataGridView Repos
        Me.dgvRepos.Dock = DockStyle.Fill
        Me.dgvRepos.AllowUserToAddRows = False
        Me.dgvRepos.AllowUserToDeleteRows = False
        Me.dgvRepos.ReadOnly = True
        Me.dgvRepos.SelectionMode = DataGridViewSelectionMode.FullRowSelect
        Me.dgvRepos.RowHeadersVisible = False
        Me.dgvRepos.BackgroundColor = Color.White
        Me.dgvRepos.BorderStyle = BorderStyle.None

        Me.splitMain.Panel1.Controls.Add(Me.dgvRepos)
        Me.splitMain.Panel1.Controls.Add(Me.pnlSteer)
        Me.splitMain.Panel1.Controls.Add(Me.pnlLeftHeader)

        ' --- Right: Live Monitor ---
        Me.splitRightMonitor.Dock = DockStyle.Fill
        Me.splitRightMonitor.Orientation = Orientation.Horizontal
        Me.splitRightMonitor.SplitterDistance = 180
        Me.splitRightMonitor.SplitterWidth = 4

        ' Upper Right: Workers
        Me.pnlWorkersHeader.Dock = DockStyle.Top
        Me.pnlWorkersHeader.Height = 28
        Me.pnlWorkersHeader.BackColor = Color.FromArgb(240, 243, 246)
        Me.lblWorkers.Text = " Active Workers (run/worker-*.json)"
        Me.lblWorkers.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.lblWorkers.Dock = DockStyle.Fill
        Me.lblWorkers.TextAlign = ContentAlignment.MiddleLeft
        Me.pnlWorkersHeader.Controls.Add(Me.lblWorkers)

        Me.dgvWorkers.Dock = DockStyle.Fill
        Me.dgvWorkers.AllowUserToAddRows = False
        Me.dgvWorkers.AllowUserToDeleteRows = False
        Me.dgvWorkers.ReadOnly = True
        Me.dgvWorkers.SelectionMode = DataGridViewSelectionMode.FullRowSelect
        Me.dgvWorkers.RowHeadersVisible = False
        Me.dgvWorkers.BackgroundColor = Color.White
        Me.dgvWorkers.BorderStyle = BorderStyle.None

        Me.splitRightMonitor.Panel1.Controls.Add(Me.dgvWorkers)
        Me.splitRightMonitor.Panel1.Controls.Add(Me.pnlWorkersHeader)

        ' Lower Right: Passes
        Me.pnlPassesHeader.Dock = DockStyle.Top
        Me.pnlPassesHeader.Height = 28
        Me.pnlPassesHeader.BackColor = Color.FromArgb(240, 243, 246)
        Me.lblPasses.Text = " Recent Passes (runs.jsonl)"
        Me.lblPasses.Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        Me.lblPasses.Dock = DockStyle.Fill
        Me.lblPasses.TextAlign = ContentAlignment.MiddleLeft
        Me.pnlPassesHeader.Controls.Add(Me.lblPasses)

        Me.dgvPasses.Dock = DockStyle.Fill
        Me.dgvPasses.AllowUserToAddRows = False
        Me.dgvPasses.AllowUserToDeleteRows = False
        Me.dgvPasses.ReadOnly = True
        Me.dgvPasses.SelectionMode = DataGridViewSelectionMode.FullRowSelect
        Me.dgvPasses.RowHeadersVisible = False
        Me.dgvPasses.BackgroundColor = Color.White
        Me.dgvPasses.BorderStyle = BorderStyle.None

        Me.splitRightMonitor.Panel2.Controls.Add(Me.dgvPasses)
        Me.splitRightMonitor.Panel2.Controls.Add(Me.pnlPassesHeader)

        Me.splitMain.Panel2.Controls.Add(Me.splitRightMonitor)

        ' --- pnlBottom ---
        Me.pnlBottom.Dock = DockStyle.Bottom
        Me.pnlBottom.Height = 120
        Me.pnlBottom.BackColor = Color.FromArgb(245, 247, 250)
        Me.pnlBottom.Padding = New Padding(6, 4, 6, 6)

        Dim pnlBottomBar As New Panel With {
            .Dock = DockStyle.Top,
            .Height = 30
        }

        Me.chkAutoRefresh.Text = "Auto-refresh (4s)"
        Me.chkAutoRefresh.Checked = True
        Me.chkAutoRefresh.Location = New Point(4, 5)
        Me.chkAutoRefresh.AutoSize = True

        Me.btnRefreshNow.Text = "↻ Refresh Now"
        Me.btnRefreshNow.Location = New Point(135, 2)
        Me.btnRefreshNow.Size = New Size(110, 26)
        Me.btnRefreshNow.UseVisualStyleBackColor = True

        Me.lblPqPath.Location = New Point(260, 6)
        Me.lblPqPath.AutoSize = True
        Me.lblPqPath.ForeColor = Color.DimGray
        Me.lblPqPath.Text = "Script: ..."

        pnlBottomBar.Controls.AddRange({Me.chkAutoRefresh, Me.btnRefreshNow, Me.lblPqPath})

        Me.txtConsole.Dock = DockStyle.Fill
        Me.txtConsole.Multiline = True
        Me.txtConsole.ReadOnly = True
        Me.txtConsole.ScrollBars = ScrollBars.Vertical
        Me.txtConsole.Font = New Font("Consolas", 8.5F)
        Me.txtConsole.BackColor = Color.FromArgb(30, 30, 30)
        Me.txtConsole.ForeColor = Color.LightGray

        Me.pnlBottom.Controls.Add(Me.txtConsole)
        Me.pnlBottom.Controls.Add(pnlBottomBar)

        ' Form Setup
        Me.AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        Me.AutoScaleMode = AutoScaleMode.Font
        Me.ClientSize = New Size(1240, 720)
        Me.MinimumSize = New Size(1000, 600)
        Me.Text = "PQ Control Panel - Portfolio Queue Shell"
        Me.Font = New Font("Segoe UI", 9.0F)
        Me.StartPosition = FormStartPosition.CenterScreen

        Me.Controls.Add(Me.splitMain)
        Me.Controls.Add(Me.pnlBottom)
        Me.Controls.Add(Me.pnlBanner)
        Me.Controls.Add(Me.pnlTopActions)

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
    End Sub
End Class
