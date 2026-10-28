Option Explicit On
Option Strict On

Public Class FormDoctor
    Inherits Form

    Private txtOutput As RichTextBox
    Private btnRerun As Button
    Private btnClose As Button
    Private pnlBottom As Panel
    Private lblTitle As Label

    Public Sub New()
        InitializeComponent()
    End Sub

    Private Sub InitializeComponent()
        Me.Text = "PQ Doctor - Repository Health & Diagnostics"
        Me.Size = New Size(750, 550)
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)

        lblTitle = New Label With {
            .Dock = DockStyle.Top,
            .Height = 35,
            .Text = "  PQ Doctor Diagnostic Report (pq doctor -All)",
            .Font = New Font("Segoe UI", 11.0F, FontStyle.Bold),
            .TextAlign = ContentAlignment.MiddleLeft,
            .BackColor = Color.FromArgb(240, 243, 246)
        }

        txtOutput = New RichTextBox With {
            .Dock = DockStyle.Fill,
            .Font = New Font("Consolas", 10.0F),
            .ReadOnly = True,
            .BackColor = Color.FromArgb(30, 30, 30),
            .ForeColor = Color.Gainsboro
        }

        pnlBottom = New Panel With {
            .Dock = DockStyle.Bottom,
            .Height = 45,
            .BackColor = Color.FromArgb(240, 243, 246)
        }

        btnRerun = New Button With {
            .Text = "↻ Re-run Doctor",
            .Size = New Size(130, 32),
            .Location = New Point(12, 6),
            .UseVisualStyleBackColor = True
        }
        AddHandler btnRerun.Click, AddressOf BtnRerun_Click

        btnClose = New Button With {
            .Text = "Close",
            .Size = New Size(100, 32),
            .Anchor = AnchorStyles.Right Or AnchorStyles.Top,
            .Location = New Point(Me.ClientSize.Width - 112, 6),
            .UseVisualStyleBackColor = True
        }
        AddHandler btnClose.Click, Sub() Me.Close()

        pnlBottom.Controls.Add(btnRerun)
        pnlBottom.Controls.Add(btnClose)

        Me.Controls.Add(txtOutput)
        Me.Controls.Add(pnlBottom)
        Me.Controls.Add(lblTitle)
    End Sub

    Protected Overrides Async Sub OnShown(e As EventArgs)
        MyBase.OnShown(e)
        Await RunDoctorAsync()
    End Sub

    Private Async Sub BtnRerun_Click(sender As Object, e As EventArgs)
        Await RunDoctorAsync()
    End Sub

    Private Async Function RunDoctorAsync() As Task
        btnRerun.Enabled = False
        txtOutput.Clear()
        txtOutput.SelectionColor = Color.LightSkyBlue
        txtOutput.AppendText("Running 'pq doctor -All' in background... Please wait." & vbCrLf & vbCrLf)

        Dim res = Await PqCli.RunSilentAsync("doctor -All")

        txtOutput.Clear()
        Dim full = res.Output
        If Not String.IsNullOrWhiteSpace(res.ErrorOutput) Then
            full &= vbCrLf & "ERRORS:" & vbCrLf & res.ErrorOutput
        End If

        ' Each check line starts with its verdict: 'PASS <key> <check> - <detail>'.
        For Each line In full.Split({vbCr, vbLf}, StringSplitOptions.RemoveEmptyEntries)
            If line.StartsWith("PASS ") Then
                txtOutput.SelectionColor = Color.LightGreen
            ElseIf line.StartsWith("FAIL ") OrElse line.StartsWith("pq: ") Then
                txtOutput.SelectionColor = Color.Salmon
            ElseIf line.StartsWith("WARN ") Then
                txtOutput.SelectionColor = Color.Gold
            Else
                txtOutput.SelectionColor = Color.Gainsboro
            End If
            txtOutput.AppendText(line & vbCrLf)
        Next

        ' pq's exit codes: 0 clean, 1 a check failed, anything else the doctor itself could not run.
        Dim verdict = If(res.ExitCode = 0, "OK", If(res.ExitCode = 1, "doctor found a failure", "doctor did not run"))
        txtOutput.SelectionColor = If(res.Success, Color.LightGreen, Color.Salmon)
        txtOutput.AppendText(vbCrLf & $"Exit code: {res.ExitCode} ({verdict})" & vbCrLf)

        btnRerun.Enabled = True
    End Function
End Class
