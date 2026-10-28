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

        ' --- Bottom Panel (docked cleanly, ensures status & action buttons are never cut off) ---
        Dim pnlBottom As New Panel With {
            .Dock = DockStyle.Bottom,
            .Height = 84,
            .Padding = New Padding(20, 2, 20, 8)
        }

        lblStatus = New Label With {
            .Dock = DockStyle.Top,
            .Height = 28,
            .TextAlign = ContentAlignment.MiddleLeft,
            .Font = New Font("Segoe UI", 9.0F)
        }

        Dim pnlButtons As New FlowLayoutPanel With {
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

        ' --- Row 1: Target Project & Complexity ---
        Dim lblProj As New Label With {
            .Text = "Target &Project:",
            .Location = New Point(20, 16),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        cmbProject = New ComboBox With {
            .Location = New Point(140, 13),
            .Size = New Size(220, 26),
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .AccessibleName = "Target Project Dropdown"
        }

        Dim lblComp As New Label With {
            .Text = "&Complexity:",
            .Location = New Point(380, 16),
            .AutoSize = True
        }
        cmbComplexity = New ComboBox With {
            .Location = New Point(470, 13),
            .Size = New Size(290, 26),
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .AccessibleName = "Complexity Dropdown"
        }
        cmbComplexity.Items.AddRange({
            "medium - not assessed at capture",
            "light - simple fix or small chore",
            "hard - complex task or deep defect"
        })
        cmbComplexity.SelectedIndex = 0

        ' --- Row 2: Type / Prefix Row (FlowLayoutPanel ensures zero overlapping radio buttons) ---
        Dim pnlType As New FlowLayoutPanel With {
            .Location = New Point(20, 50),
            .Size = New Size(740, 32),
            .FlowDirection = FlowDirection.LeftToRight,
            .WrapContents = False
        }
        Dim lblType As New Label With {
            .Text = "Type:",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Margin = New Padding(0, 3, 20, 0)
        }
        rdoFeature = New RadioButton With {
            .Text = "&Feature / Task",
            .AutoSize = True,
            .Checked = True,
            .Margin = New Padding(0, 0, 24, 0)
        }
        AddHandler rdoFeature.CheckedChanged, AddressOf RdoType_CheckedChanged

        rdoBug = New RadioButton With {
            .Text = "&Bug / Defect (bugfix-)",
            .AutoSize = True,
            .Margin = New Padding(0, 0, 24, 0)
        }
        AddHandler rdoBug.CheckedChanged, AddressOf RdoType_CheckedChanged

        rdoHotfix = New RadioButton With {
            .Text = "&Urgent Blocker (hotfix-)",
            .AutoSize = True,
            .Margin = New Padding(0, 0, 0, 0)
        }
        AddHandler rdoHotfix.CheckedChanged, AddressOf RdoType_CheckedChanged

        pnlType.Controls.AddRange({lblType, rdoFeature, rdoBug, rdoHotfix})

        ' --- Row 3: Ticket Slug & Pin ---
        Dim lblSlug As New Label With {
            .Text = "Ticket &Slug:",
            .Location = New Point(20, 88),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        txtSlug = New TextBox With {
            .Location = New Point(140, 85),
            .Size = New Size(360, 26),
            .Font = New Font("Consolas", 9.5F),
            .AccessibleName = "Ticket Slug Input"
        }
        chkPin = New CheckBox With {
            .Text = "Pin to &top of queue (-Pin)",
            .Location = New Point(520, 87),
            .AutoSize = True,
            .AccessibleName = "Pin to top checkbox"
        }

        ' --- Row 4: Description Header ---
        Dim lblDesc As New Label With {
            .Text = "&Task or Problem Description (in your own words; spec-draft will turn this into an aligned spec):",
            .Location = New Point(20, 122),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }

        ' --- Description Text Box (expands smoothly above docked pnlBottom) ---
        txtDescription = New TextBox With {
            .Location = New Point(20, 146),
            .Size = New Size(740, 375),
            .Multiline = True,
            .AcceptsReturn = True,
            .ScrollBars = ScrollBars.Vertical,
            .Font = New Font("Segoe UI", 9.5F),
            .Anchor = AnchorStyles.Top Or AnchorStyles.Bottom Or AnchorStyles.Left Or AnchorStyles.Right,
            .AccessibleName = "Task Description Text"
        }

        Me.Controls.AddRange({lblProj, cmbProject, lblComp, cmbComplexity, pnlType, lblSlug, txtSlug, chkPin, lblDesc, txtDescription, pnlBottom})

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

        If String.IsNullOrWhiteSpace(slug) Then
            SetStatus("Please enter a ticket slug (e.g. 'player-crash-on-seek').", isError:=True)
            txtSlug.Focus()
            Return
        End If

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
