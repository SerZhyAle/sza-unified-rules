Option Explicit On
Option Strict On

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
        Me.Size = New Size(720, 580)
        Me.MinimumSize = New Size(640, 500)
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)

        ' --- Project Row ---
        Dim lblProj As New Label With {
            .Text = "Target Project:",
            .Location = New Point(20, 16),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        cmbProject = New ComboBox With {
            .Location = New Point(125, 13),
            .Size = New Size(260, 25),
            .DropDownStyle = ComboBoxStyle.DropDownList
        }

        ' --- Complexity Row ---
        Dim lblComp As New Label With {
            .Text = "Complexity:",
            .Location = New Point(405, 16),
            .AutoSize = True
        }
        cmbComplexity = New ComboBox With {
            .Location = New Point(480, 13),
            .Size = New Size(205, 25),
            .DropDownStyle = ComboBoxStyle.DropDownList
        }
        cmbComplexity.Items.AddRange({
            "medium - not assessed at capture",
            "light - simple fix or small chore",
            "hard - complex task or deep defect"
        })
        cmbComplexity.SelectedIndex = 0

        ' --- Type / Prefix Row ---
        Dim pnlType As New Panel With {
            .Location = New Point(20, 48),
            .Size = New Size(665, 30)
        }
        Dim lblType As New Label With {
            .Text = "Type:",
            .Location = New Point(0, 5),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        rdoFeature = New RadioButton With {
            .Text = "Feature / Task",
            .Location = New Point(105, 3),
            .AutoSize = True,
            .Checked = True
        }
        AddHandler rdoFeature.CheckedChanged, AddressOf RdoType_CheckedChanged

        rdoBug = New RadioButton With {
            .Text = "Bug / Defect (bugfix-)",
            .Location = New Point(230, 3),
            .AutoSize = True
        }
        AddHandler rdoBug.CheckedChanged, AddressOf RdoType_CheckedChanged

        rdoHotfix = New RadioButton With {
            .Text = "Urgent Blocker (hotfix-)",
            .Location = New Point(400, 3),
            .AutoSize = True
        }
        AddHandler rdoHotfix.CheckedChanged, AddressOf RdoType_CheckedChanged

        pnlType.Controls.AddRange({lblType, rdoFeature, rdoBug, rdoHotfix})

        ' --- Slug Row ---
        Dim lblSlug As New Label With {
            .Text = "Ticket Slug:",
            .Location = New Point(20, 86),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        txtSlug = New TextBox With {
            .Location = New Point(125, 83),
            .Size = New Size(370, 25),
            .Font = New Font("Consolas", 9.5F)
        }
        chkPin = New CheckBox With {
            .Text = "Pin to top of queue (-Pin)",
            .Location = New Point(510, 85),
            .AutoSize = True
        }

        ' --- Description Header ---
        Dim lblDesc As New Label With {
            .Text = "Problem Description / Requirements (exact words captured byte-for-byte):",
            .Location = New Point(20, 120),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }

        ' --- Description Text Box ---
        txtDescription = New TextBox With {
            .Location = New Point(20, 142),
            .Size = New Size(665, 310),
            .Multiline = True,
            .AcceptsReturn = True,
            .ScrollBars = ScrollBars.Vertical,
            .Font = New Font("Segoe UI", 9.5F),
            .Anchor = AnchorStyles.Top Or AnchorStyles.Bottom Or AnchorStyles.Left Or AnchorStyles.Right
        }

        ' --- Status Label ---
        lblStatus = New Label With {
            .Location = New Point(20, 460),
            .Size = New Size(665, 30),
            .ForeColor = Color.DarkSlateBlue,
            .Anchor = AnchorStyles.Bottom Or AnchorStyles.Left Or AnchorStyles.Right
        }

        ' --- Buttons ---
        btnDraft = New Button With {
            .Text = "📝 Create Draft (/spec-draft)",
            .Size = New Size(220, 36),
            .Location = New Point(345, 495),
            .BackColor = Color.FromArgb(220, 245, 225),
            .Font = New Font("Segoe UI", 9.5F, FontStyle.Bold),
            .UseVisualStyleBackColor = False,
            .Anchor = AnchorStyles.Bottom Or AnchorStyles.Right
        }
        AddHandler btnDraft.Click, AddressOf BtnDraft_Click

        btnCancel = New Button With {
            .Text = "Cancel",
            .Size = New Size(110, 36),
            .Location = New Point(575, 495),
            .UseVisualStyleBackColor = True,
            .Anchor = AnchorStyles.Bottom Or AnchorStyles.Right
        }
        AddHandler btnCancel.Click, Sub() Me.DialogResult = DialogResult.Cancel

        Me.Controls.AddRange({lblProj, cmbProject, lblComp, cmbComplexity, pnlType, lblSlug, txtSlug, chkPin, lblDesc, txtDescription, lblStatus, btnDraft, btnCancel})
        Me.AcceptButton = btnDraft
        Me.CancelButton = btnCancel
    End Sub

    Protected Overrides Sub OnLoad(e As EventArgs)
        MyBase.OnLoad(e)
        LoadProjects()
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
        ' Strip existing prefix if present
        If current.StartsWith("bugfix-", StringComparison.OrdinalIgnoreCase) Then
            current = current.Substring(7)
        ElseIf current.StartsWith("hotfix-", StringComparison.OrdinalIgnoreCase) Then
            current = current.Substring(7)
        End If

        If rdoBug.Checked Then
            txtSlug.Text = "bugfix-" & current
            chkPin.Checked = False
        ElseIf rdoHotfix.Checked Then
            txtSlug.Text = "hotfix-" & current
            chkPin.Checked = True
        Else
            txtSlug.Text = current
        End If
    End Sub

    Private Async Sub BtnDraft_Click(sender As Object, e As EventArgs)
        Dim projectKey = cmbProject.SelectedItem?.ToString()
        ' Passed exactly as typed: spec-draft keeps the owner's words byte for byte.
        Dim textContent = txtDescription.Text
        Dim slug = txtSlug.Text.Trim()
        Dim complexity = cmbComplexity.SelectedItem?.ToString()
        Dim pin = chkPin.Checked

        If String.IsNullOrWhiteSpace(projectKey) Then
            lblStatus.ForeColor = Color.DarkRed
            lblStatus.Text = "Please select a target project."
            Return
        End If

        If String.IsNullOrWhiteSpace(textContent) Then
            lblStatus.ForeColor = Color.DarkRed
            lblStatus.Text = "Please enter the problem description or requirements."
            txtDescription.Focus()
            Return
        End If

        ' Auto-generate slug if empty
        If String.IsNullOrWhiteSpace(slug) Then
            Dim prefix = If(rdoHotfix.Checked, "hotfix-", If(rdoBug.Checked, "bugfix-", "task-"))
            Dim stamp = DateTime.Now.ToString("yyMMdd-HHmm")
            slug = $"{prefix}spec-{stamp}"
            txtSlug.Text = slug
        End If

        ' spec-draft's slug rule: [a-z0-9][a-z0-9_-]*, not starting with 'spec_'.
        slug = System.Text.RegularExpressions.Regex.Replace(slug.ToLowerInvariant(), "[^a-z0-9_-]", "-")
        slug = System.Text.RegularExpressions.Regex.Replace(slug, "-+", "-").Trim("-"c, "_"c)
        If slug = "" OrElse slug.StartsWith("spec_") Then
            lblStatus.ForeColor = Color.DarkRed
            lblStatus.Text = "The slug needs a letter or digit first and must not start with 'spec_'."
            txtSlug.Focus()
            Return
        End If
        txtSlug.Text = slug

        btnDraft.Enabled = False
        btnCancel.Enabled = False
        lblStatus.ForeColor = Color.DarkSlateBlue
        lblStatus.Text = $"Capturing the draft into '{projectKey}' via spec-draft.ps1.."

        Dim res = Await PqCli.DraftSpecAsync(projectKey, slug, textContent, complexity, pin)

        If res.Success Then
            ' The last line is the machine-readable result: drafted <key>:<id> file=.. pq=<verdict> position=..
            ResultText = res.Output.Trim()
            MessageBox.Show(Me, $"Captured into '{projectKey}'." & vbCrLf & vbCrLf & ResultText, "Spec Draft Created",
                            MessageBoxButtons.OK, MessageBoxIcon.Information)
            Me.DialogResult = DialogResult.OK
        Else
            btnDraft.Enabled = True
            btnCancel.Enabled = True
            lblStatus.ForeColor = Color.DarkRed
            lblStatus.Text = $"spec-draft exit {res.ExitCode}: {LastLine(res.Message)}"
        End If
    End Sub

    Private Shared Function LastLine(text As String) As String
        Dim lines = text.Split({vbCr, vbLf}, StringSplitOptions.RemoveEmptyEntries)
        Return If(lines.Length = 0, "", lines(lines.Length - 1).Trim())
    End Function
End Class
