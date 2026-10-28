Option Explicit On
Option Strict On

''' <summary>
''' Repository registration dialog per APP-BEHAVIOUR, BUTTONS, and APP-STYLE.
''' </summary>
Public Class FormRegister
    Inherits Form

    Private txtPath As TextBox
    Private btnBrowse As Button
    Private txtKey As TextBox
    Private cmbPermission As ComboBox
    Private chkEnable As CheckBox
    Private btnRegister As Button
    Private btnCancel As Button
    Private lblMsg As Label

    ' What pq printed, for the main window's console.
    Public Property ResultText As String = ""

    Public Sub New()
        InitializeComponent()
    End Sub

    Private Sub InitializeComponent()
        Me.Text = "Register Repository into Portfolio"
        Me.AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        Me.AutoScaleMode = AutoScaleMode.Font
        Me.ClientSize = New Size(580, 340)
        Me.FormBorderStyle = FormBorderStyle.FixedDialog
        Me.MaximizeBox = False
        Me.MinimizeBox = False
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)

        Dim lblPath As New Label With {
            .Text = "Repository &Path:",
            .Location = New Point(20, 20),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        txtPath = New TextBox With {
            .Location = New Point(20, 42),
            .Size = New Size(430, 26),
            .AccessibleName = "Repository Path Text"
        }

        btnBrowse = New Button With {
            .Name = "btnBrowse",
            .Text = "&Browse...",
            .Location = New Point(460, 40),
            .Size = New Size(100, 30),
            .AccessibleName = "Browse Folder Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnBrowse.Click, AddressOf BtnBrowse_Click

        ' Left empty, pq derives the key from the folder name with its own rule (^[a-z][a-z0-9-]*$).
        Dim lblKey As New Label With {
            .Text = "Repository &Key (optional):",
            .Location = New Point(20, 80),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        txtKey = New TextBox With {
            .Location = New Point(20, 102),
            .Size = New Size(245, 26),
            .PlaceholderText = "derived by pq from folder name",
            .AccessibleName = "Repository Key Input"
        }

        Dim lblPerm As New Label With {
            .Text = "Permission &Mode:",
            .Location = New Point(285, 80),
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        cmbPermission = New ComboBox With {
            .Location = New Point(285, 102),
            .Size = New Size(275, 26),
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .AccessibleName = "Permission Mode Dropdown"
        }
        cmbPermission.Items.AddRange({"bypassPermissions", "acceptEdits", "auto", "manual", "dontAsk", "plan"})
        cmbPermission.SelectedIndex = 0

        ' pq's own default: a repository joins disabled, so doctor can look at it before robots do.
        chkEnable = New CheckBox With {
            .Text = "&Enable repository for unattended work immediately (-Enable)",
            .Location = New Point(20, 146),
            .AutoSize = True,
            .Checked = False,
            .AccessibleName = "Enable immediately checkbox"
        }

        lblMsg = New Label With {
            .Location = New Point(20, 180),
            .Size = New Size(540, 42)
        }

        btnRegister = New Button With {
            .Name = "btnRegister",
            .Text = "➕ &Register",
            .Location = New Point(345, 280),
            .Size = New Size(110, 34),
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .AccessibleName = "Register Repository Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnRegister.Click, AddressOf BtnRegister_Click

        btnCancel = New Button With {
            .Name = "btnCancel",
            .Text = "Cancel",
            .Location = New Point(465, 280),
            .Size = New Size(95, 34),
            .AccessibleName = "Cancel Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnCancel.Click, Sub() Me.DialogResult = DialogResult.Cancel

        Me.Controls.AddRange({lblPath, txtPath, btnBrowse, lblKey, txtKey, lblPerm, cmbPermission, chkEnable, lblMsg, btnRegister, btnCancel})

        ' APP-BEHAVIOUR Rule 1
        Me.AcceptButton = btnRegister
        Me.CancelButton = btnCancel

        ' Tab Order
        txtPath.TabIndex = 0
        btnBrowse.TabIndex = 1
        txtKey.TabIndex = 2
        cmbPermission.TabIndex = 3
        chkEnable.TabIndex = 4
        btnRegister.TabIndex = 5
        btnCancel.TabIndex = 6
    End Sub

    Protected Overrides Sub OnShown(e As EventArgs)
        MyBase.OnShown(e)
        ThemeService.ApplyTheme(Me)
        AddHandler ThemeService.ThemeChanged, Sub() ThemeService.ApplyTheme(Me)
    End Sub

    Private Sub BtnBrowse_Click(sender As Object, e As EventArgs)
        Using dlg As New FolderBrowserDialog()
            dlg.Description = "Select Repository Root Folder (must contain .sza-canon.json)"
            If dlg.ShowDialog(Me) = DialogResult.OK Then
                txtPath.Text = dlg.SelectedPath
            End If
        End Using
    End Sub

    Private Async Sub BtnRegister_Click(sender As Object, e As EventArgs)
        Dim repoPath = txtPath.Text.Trim()
        Dim repoKey = txtKey.Text.Trim()
        Dim permMode = cmbPermission.SelectedItem?.ToString()
        Dim enable = chkEnable.Checked

        If String.IsNullOrWhiteSpace(repoPath) OrElse Not Directory.Exists(repoPath) Then
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = "Please select a valid existing directory path."
            Return
        End If

        lblMsg.ForeColor = ThemeService.Palette.Accent
        lblMsg.Text = "Registering repository in portfolio registry..."
        btnRegister.Enabled = False

        Dim args As New List(Of String) From {"register", "-Path", Path.GetFullPath(repoPath)}
        If Not String.IsNullOrWhiteSpace(repoKey) Then args.AddRange({"-Key", repoKey})
        If Not String.IsNullOrWhiteSpace(permMode) Then args.AddRange({"-PermissionMode", permMode})
        If enable Then args.Add("-Enable")

        Dim res = Await PqCli.RunSilentAsync(args.ToArray())
        If res.Success Then
            ResultText = res.Output.Trim()
            Me.DialogResult = DialogResult.OK
        Else
            lblMsg.ForeColor = ThemeService.Palette.StatusDanger
            lblMsg.Text = res.Message
            btnRegister.Enabled = True
        End If
    End Sub
End Class
