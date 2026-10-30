Option Explicit On
Option Strict On

''' <summary>
''' Specification draft capture dialog per APP-BEHAVIOUR, BUTTONS, and APP-STYLE.
''' </summary>
Public Class FormNewSpec
    Inherits Form

    Private cmbProject As ComboBox
    Private rdoFeature As RadioButton
    Private rdoBug As RadioButton
    Private rdoHotfix As RadioButton
    Private txtSlug As TextBox
    Private cmbComplexity As ComboBox
    Private chkPin As CheckBox
    Private txtDescription As TextBox
    Private btnDraft As Button
    Private btnCancel As Button
    Private lblStatus As Label

    Private _defaultProjectKey As String = ""
    Private _pinTickedByType As Boolean = False

    ' What spec-draft printed, for the main window's console.
    Public Property ResultText As String = ""

    Public Sub New(Optional defaultProjectKey As String = "")
        _defaultProjectKey = defaultProjectKey
        InitializeComponent()
    End Sub

    Private Sub InitializeComponent()
        Me.Text = "New Specification (/spec-draft) - Capture Task or Problem"
        Me.AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        Me.AutoScaleMode = AutoScaleMode.Font
        Me.ClientSize = New Size(780, 620)
        Me.MinimumSize = New Size(700, 540)
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)
        Me.SuspendLayout()

        ' --- Bottom Panel (Status & Buttons, docked bottom) ---
        Dim pnlBottom As New Panel With {
            .Name = "pnlBottom",
            .Dock = DockStyle.Bottom,
            .Height = 84,
            .Padding = New Padding(20, 4, 20, 10)
        }

        lblStatus = New Label With {
            .Name = "lblStatus",
            .Dock = DockStyle.Top,
            .Height = 26,
            .TextAlign = ContentAlignment.MiddleLeft,
            .Font = New Font("Segoe UI", 9.0F)
        }

        Dim pnlButtons As New FlowLayoutPanel With {
            .Name = "pnlButtons",
            .Dock = DockStyle.Bottom,
            .Height = 42,
            .FlowDirection = FlowDirection.RightToLeft,
            .WrapContents = False,
            .Margin = Padding.Empty,
            .Padding = Padding.Empty
        }

        btnCancel = New Button With {
            .Name = "btnCancel",
            .Text = "Cancel",
            .Size = New Size(110, 36),
            .Margin = New Padding(0, 2, 0, 0),
            .AccessibleName = "Cancel Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnCancel.Click, Sub() Me.DialogResult = DialogResult.Cancel

        btnDraft = New Button With {
            .Name = "btnDraft",
            .Text = "📝 &Create Specification",
            .Size = New Size(240, 36),
            .Margin = New Padding(0, 2, 12, 0),
            .Font = New Font("Segoe UI", 9.5F, FontStyle.Bold),
            .AccessibleName = "Create Specification Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnDraft.Click, AddressOf BtnDraft_Click

        pnlButtons.Controls.AddRange({btnCancel, btnDraft})
        pnlBottom.Controls.AddRange({pnlButtons, lblStatus})

        ' --- Top Controls (Adaptive 4-column TableLayoutPanel, zero overlapping at any DPI) ---
        Dim tblTop As New TableLayoutPanel With {
            .Name = "tblTop",
            .Dock = DockStyle.Top,
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .Padding = New Padding(20, 16, 20, 6),
            .ColumnCount = 4,
            .RowCount = 4
        }
        tblTop.SuspendLayout()

        tblTop.ColumnStyles.Add(New ColumnStyle(SizeType.AutoSize))
        tblTop.ColumnStyles.Add(New ColumnStyle(SizeType.Percent, 45.0F))
        tblTop.ColumnStyles.Add(New ColumnStyle(SizeType.AutoSize))
        tblTop.ColumnStyles.Add(New ColumnStyle(SizeType.Percent, 55.0F))

        For i = 0 To 3
            tblTop.RowStyles.Add(New RowStyle(SizeType.AutoSize))
        Next

        ' Row 0: Target Project & Complexity
        Dim lblProj As New Label With {
            .Name = "lblProj",
            .Text = "Target &Project:",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(0, 0, 8, 8)
        }
        cmbProject = New ComboBox With {
            .Name = "cmbProject",
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .Dock = DockStyle.Fill,
            .Margin = New Padding(0, 0, 16, 8),
            .AccessibleName = "Target Project Dropdown"
        }

        Dim lblComp As New Label With {
            .Name = "lblComp",
            .Text = "&Complexity:",
            .AutoSize = True,
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(8, 0, 8, 8)
        }
        cmbComplexity = New ComboBox With {
            .Name = "cmbComplexity",
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .Dock = DockStyle.Fill,
            .Margin = New Padding(0, 0, 0, 8),
            .AccessibleName = "Complexity Dropdown"
        }
        cmbComplexity.Items.AddRange({
            "medium - not assessed at capture",
            "light - simple fix or small chore",
            "hard - complex task or deep defect"
        })
        cmbComplexity.SelectedIndex = 0

        tblTop.Controls.Add(lblProj, 0, 0)
        tblTop.Controls.Add(cmbProject, 1, 0)
        tblTop.Controls.Add(lblComp, 2, 0)
        tblTop.Controls.Add(cmbComplexity, 3, 0)

        ' Row 1: Type / Prefix Row
        Dim pnlType As New FlowLayoutPanel With {
            .Name = "pnlType",
            .Dock = DockStyle.Fill,
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .WrapContents = True,
            .FlowDirection = FlowDirection.LeftToRight,
            .Margin = New Padding(0, 2, 0, 8)
        }
        Dim lblType As New Label With {
            .Name = "lblType",
            .Text = "Type:",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Margin = New Padding(0, 3, 16, 0)
        }
        rdoFeature = New RadioButton With {
            .Name = "rdoFeature",
            .Text = "&Feature / Task",
            .AutoSize = True,
            .Checked = True,
            .Margin = New Padding(0, 0, 20, 0)
        }
        AddHandler rdoFeature.CheckedChanged, AddressOf RdoType_CheckedChanged

        rdoBug = New RadioButton With {
            .Name = "rdoBug",
            .Text = "&Bug / Defect (bugfix-)",
            .AutoSize = True,
            .Margin = New Padding(0, 0, 20, 0)
        }
        AddHandler rdoBug.CheckedChanged, AddressOf RdoType_CheckedChanged

        rdoHotfix = New RadioButton With {
            .Name = "rdoHotfix",
            .Text = "&Urgent Blocker (hotfix-)",
            .AutoSize = True,
            .Margin = New Padding(0, 0, 0, 0)
        }
        AddHandler rdoHotfix.CheckedChanged, AddressOf RdoType_CheckedChanged

        pnlType.Controls.AddRange({lblType, rdoFeature, rdoBug, rdoHotfix})
        tblTop.Controls.Add(pnlType, 0, 1)
        tblTop.SetColumnSpan(pnlType, 4)

        ' Row 2: Ticket Slug & Pin
        Dim lblSlug As New Label With {
            .Name = "lblSlug",
            .Text = "Ticket &Slug (optional):",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(0, 0, 8, 8)
        }
        txtSlug = New TextBox With {
            .Name = "txtSlug",
            .Dock = DockStyle.Fill,
            .Font = New Font("Consolas", 9.5F),
            .Margin = New Padding(0, 0, 16, 8),
            .AccessibleName = "Ticket Slug Input"
        }
        chkPin = New CheckBox With {
            .Name = "chkPin",
            .Text = "Pin to &top of queue (-Pin)",
            .AutoSize = True,
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(8, 0, 0, 8),
            .AccessibleName = "Pin to top checkbox"
        }

        tblTop.Controls.Add(lblSlug, 0, 2)
        tblTop.Controls.Add(txtSlug, 1, 2)
        tblTop.Controls.Add(chkPin, 2, 2)
        tblTop.SetColumnSpan(chkPin, 2)

        ' Row 3: Description Header
        Dim lblDesc As New Label With {
            .Name = "lblDesc",
            .Text = "&Task or Problem Description (in your own words; spec-draft will turn this into an aligned spec):",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Margin = New Padding(0, 4, 0, 4)
        }
        tblTop.Controls.Add(lblDesc, 0, 3)
        tblTop.SetColumnSpan(lblDesc, 4)

        tblTop.ResumeLayout(False)
        tblTop.PerformLayout()

        ' --- Center Content: Task Description Multiline Editor ---
        Dim pnlContent As New Panel With {
            .Name = "pnlContent",
            .Dock = DockStyle.Fill,
            .Padding = New Padding(20, 0, 20, 0)
        }
        txtDescription = New TextBox With {
            .Name = "txtDescription",
            .Dock = DockStyle.Fill,
            .Multiline = True,
            .AcceptsReturn = True,
            .ScrollBars = ScrollBars.Vertical,
            .Font = New Font("Segoe UI", 9.5F),
            .AccessibleName = "Task Description Text"
        }
        pnlContent.Controls.Add(txtDescription)

        ' Container assembly in correct docking z-order
        Me.Controls.Add(pnlContent)
        Me.Controls.Add(tblTop)
        Me.Controls.Add(pnlBottom)
        pnlContent.BringToFront()

        ' APP-BEHAVIOUR Rule 1
        Me.AcceptButton = btnDraft
        Me.CancelButton = btnCancel

        ' Tab Order
        cmbProject.TabIndex = 0
        cmbComplexity.TabIndex = 1
        rdoFeature.TabIndex = 2
        rdoBug.TabIndex = 3
        rdoHotfix.TabIndex = 4
        txtSlug.TabIndex = 5
        chkPin.TabIndex = 6
        txtDescription.TabIndex = 7
        btnDraft.TabIndex = 8
        btnCancel.TabIndex = 9

        Me.ResumeLayout(False)
        Me.PerformLayout()
    End Sub

    Protected Overrides Sub OnLoad(e As EventArgs)
        MyBase.OnLoad(e)
        LoadProjects()
        ThemeService.ApplyTheme(Me)
        AddHandler ThemeService.ThemeChanged, Sub() ThemeService.ApplyTheme(Me)
    End Sub

    Private Sub LoadProjects()
        cmbProject.Items.Clear()
        Dim repos = PortfolioState.GetRepos()
        Dim selIdx = -1

        For i = 0 To repos.Count - 1
            Dim r = repos(i)
            cmbProject.Items.Add(r.Key)
            If Not String.IsNullOrWhiteSpace(_defaultProjectKey) AndAlso r.Key.Equals(_defaultProjectKey, StringComparison.OrdinalIgnoreCase) Then
                selIdx = i
            End If
        Next

        If selIdx >= 0 Then
            cmbProject.SelectedIndex = selIdx
        ElseIf cmbProject.Items.Count > 0 Then
            cmbProject.SelectedIndex = 0
        End If
    End Sub

    Private Sub RdoType_CheckedChanged(sender As Object, e As EventArgs)
        Dim current = txtSlug.Text.Trim()
        Dim baseSlug = current
        For Each prefix In {"bugfix-", "hotfix-"}
            If baseSlug.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) Then
                baseSlug = baseSlug.Substring(prefix.Length)
            End If
        Next

        If rdoBug.Checked Then
            txtSlug.Text = "bugfix-" & baseSlug
        ElseIf rdoHotfix.Checked Then
            txtSlug.Text = "hotfix-" & baseSlug
        Else
            txtSlug.Text = baseSlug
        End If

        ' An urgent blocker goes first in the queue: the type ticks the pin box, and leaving the type takes back only
        ' a tick the type made.
        If rdoHotfix.Checked AndAlso Not chkPin.Checked Then
            chkPin.Checked = True
            _pinTickedByType = True
        ElseIf Not rdoHotfix.Checked AndAlso _pinTickedByType Then
            chkPin.Checked = False
            _pinTickedByType = False
        End If
    End Sub

    Private Async Sub BtnDraft_Click(sender As Object, e As EventArgs)
        Dim projKey = cmbProject.SelectedItem?.ToString()
        Dim slug = txtSlug.Text.Trim()
        Dim desc = txtDescription.Text.Trim()
        Dim comp = cmbComplexity.SelectedItem?.ToString()
        Dim pin = chkPin.Checked

        If String.IsNullOrWhiteSpace(projKey) Then
            SetStatus("Please select a target repository project.", isError:=True)
            Return
        End If

        ' An empty slug or the bare type prefix is fine: spec-draft names the ticket from the description.
        If String.IsNullOrWhiteSpace(desc) Then
            SetStatus("Please provide a description of the task or defect.", isError:=True)
            txtDescription.Focus()
            Return
        End If

        Dim compToken = "medium"
        If comp.StartsWith("light") Then
            compToken = "light"
        ElseIf comp.StartsWith("hard") Then
            compToken = "hard"
        End If

        btnDraft.Enabled = False
        btnCancel.Enabled = False
        SetStatus("Generating ticket specification via spec-draft.ps1...", isError:=False)

        Dim res = Await PqCli.DraftSpecAsync(projKey, slug, desc, compToken, pin)
        If res.Success Then
            ResultText = res.Output.Trim()
            Me.DialogResult = DialogResult.OK
        Else
            SetStatus(res.Message, isError:=True)
            btnDraft.Enabled = True
            btnCancel.Enabled = True
        End If
    End Sub

    Private Sub SetStatus(msg As String, isError As Boolean)
        lblStatus.Text = msg
        lblStatus.ForeColor = If(isError, ThemeService.Palette.StatusDanger, ThemeService.Palette.Accent)
    End Sub
End Class
