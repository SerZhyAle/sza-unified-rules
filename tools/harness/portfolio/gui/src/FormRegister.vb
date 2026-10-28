Option Explicit On
Option Strict On

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
        Me.Size = New Size(540, 310)
        Me.FormBorderStyle = FormBorderStyle.FixedDialog
        Me.MaximizeBox = False
        Me.MinimizeBox = False
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)

        Dim lblPath As New Label With {.Text = "Repository Path:", .Location = New Point(20, 20), .AutoSize = True}
        txtPath = New TextBox With {.Location = New Point(20, 42), .Size = New Size(390, 25)}

        btnBrowse = New Button With {.Text = "Browse..", .Location = New Point(420, 40), .Size = New Size(85, 27)}
        AddHandler btnBrowse.Click, AddressOf BtnBrowse_Click

        ' Left empty, pq derives the key from the folder name with its own rule (^[a-z][a-z0-9-]*$).
        Dim lblKey As New Label With {.Text = "Repository Key (optional):", .Location = New Point(20, 80), .AutoSize = True}
        txtKey = New TextBox With {.Location = New Point(20, 102), .Size = New Size(240, 25), .PlaceholderText = "derived by pq from the folder name"}

        Dim lblPerm As New Label With {.Text = "Permission Mode:", .Location = New Point(280, 80), .AutoSize = True}
        cmbPermission = New ComboBox With {.Location = New Point(280, 102), .Size = New Size(225, 25), .DropDownStyle = ComboBoxStyle.DropDownList}
        cmbPermission.Items.AddRange({"bypassPermissions", "acceptEdits", "auto", "manual", "dontAsk", "plan"})
        cmbPermission.SelectedIndex = 0

        ' pq's own default: a repository joins disabled, so doctor can look at it before robots do.
        chkEnable = New CheckBox With {
            .Text = "Enable repository for unattended work immediately (-Enable)",
            .Location = New Point(20, 145),
            .Size = New Size(480, 25),
            .Checked = False
        }

        lblMsg = New Label With {
            .Location = New Point(20, 180),
            .Size = New Size(485, 35),
            .ForeColor = Color.DarkRed
        }

        btnRegister = New Button With {.Text = "Register", .Location = New Point(310, 225), .Size = New Size(95, 32), .UseVisualStyleBackColor = True}
        AddHandler btnRegister.Click, AddressOf BtnRegister_Click

        btnCancel = New Button With {.Text = "Cancel", .Location = New Point(415, 225), .Size = New Size(90, 32), .UseVisualStyleBackColor = True}
        AddHandler btnCancel.Click, Sub() Me.DialogResult = DialogResult.Cancel

        Me.Controls.AddRange({lblPath, txtPath, btnBrowse, lblKey, txtKey, lblPerm, cmbPermission, chkEnable, lblMsg, btnRegister, btnCancel})
        Me.AcceptButton = btnRegister
        Me.CancelButton = btnCancel
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
            lblMsg.Text = "Please select a valid existing directory path."
            Return
        End If

        lblMsg.ForeColor = Color.DarkSlateBlue
        lblMsg.Text = "Registering repository in portfolio registry..."
        btnRegister.Enabled = False

        Dim args As New List(Of String) From {"register", "-Path", Path.GetFullPath(repoPath)}
        If Not String.IsNullOrWhiteSpace(repoKey) Then args.AddRange({"-Key", repoKey})
        If Not String.IsNullOrWhiteSpace(permMode) Then args.AddRange({"-PermissionMode", permMode})
        If enable Then args.Add("-Enable")

        Dim res = Await PqCli.RunSilentAsync(args.ToArray())
        If res.Success Then
            ' 'registered <key>' or 'already registered <key>'
            ResultText = res.Output.Trim()
            Me.DialogResult = DialogResult.OK
        Else
            lblMsg.ForeColor = Color.DarkRed
            lblMsg.Text = res.Message
            btnRegister.Enabled = True
        End If
    End Sub
End Class
