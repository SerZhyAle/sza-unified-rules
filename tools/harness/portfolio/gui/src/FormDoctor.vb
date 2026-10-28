Option Explicit On
Option Strict On

Imports System.Text.RegularExpressions

''' <summary>
''' Diagnostic report inspection dialog per DIAGNOSTIC-REPORT and APP-BEHAVIOUR Rule 1.
''' </summary>
Public Class FormDoctor
    Inherits Form

    Private txtOutput As RichTextBox
    Private btnRerun As Button
    Private btnCopy As Button
    Private btnClose As Button
    Private pnlBottom As Panel
    Private pnlHeader As Panel
    Private lblTitle As Label
    Private lblStatusBadge As Label

    Private _rawReportText As String = ""

    Public Sub New()
        InitializeComponent()
    End Sub

    Private Sub InitializeComponent()
        Me.Text = "PQ Doctor - Repository Health & Diagnostics"
        Me.AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        Me.AutoScaleMode = AutoScaleMode.Font
        Me.ClientSize = New Size(780, 560)
        Me.MinimumSize = New Size(650, 450)
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)

        ' Header panel with title and outcome badge
        pnlHeader = New Panel With {
            .Dock = DockStyle.Top,
            .Height = 44,
            .Padding = New Padding(12, 6, 12, 6)
        }

        lblTitle = New Label With {
            .Dock = DockStyle.Left,
            .Width = 360,
            .Text = "PQ Doctor Report (pq doctor -All)",
            .Font = New Font("Segoe UI", 11.0F, FontStyle.Bold),
            .TextAlign = ContentAlignment.MiddleLeft
        }

        lblStatusBadge = New Label With {
            .Dock = DockStyle.Right,
            .Width = 260,
            .Text = "● Ready",
            .Font = New Font("Segoe UI", 9.5F, FontStyle.Bold),
            .TextAlign = ContentAlignment.MiddleRight
        }

        pnlHeader.Controls.AddRange({lblTitle, lblStatusBadge})

        ' Output RichTextBox
        txtOutput = New RichTextBox With {
            .Dock = DockStyle.Fill,
            .Font = New Font("Consolas", 10.0F),
            .ReadOnly = True,
            .BorderStyle = BorderStyle.None
        }

        ' Bottom button bar
        pnlBottom = New Panel With {
            .Dock = DockStyle.Bottom,
            .Height = 48,
            .Padding = New Padding(12, 8, 12, 8)
        }

        btnRerun = New Button With {
            .Text = "↻ &Re-run Doctor",
            .Size = New Size(140, 32),
            .Location = New Point(12, 8),
            .AccessibleName = "Re-run Doctor diagnostic checks",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnRerun.Click, AddressOf BtnRerun_Click

        btnCopy = New Button With {
            .Text = "📋 &Copy Report",
            .Size = New Size(130, 32),
            .Location = New Point(160, 8),
            .AccessibleName = "Copy report text to clipboard",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnCopy.Click, AddressOf BtnCopy_Click

        btnClose = New Button With {
            .Text = "Close",
            .Size = New Size(100, 32),
            .Anchor = AnchorStyles.Right Or AnchorStyles.Top,
            .Location = New Point(Me.ClientSize.Width - 112, 8),
            .AccessibleName = "Close dialog",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnClose.Click, Sub() Me.Close()

        pnlBottom.Controls.AddRange({btnRerun, btnCopy, btnClose})

        Me.Controls.Add(txtOutput)
        Me.Controls.Add(pnlBottom)
        Me.Controls.Add(pnlHeader)

        ' APP-BEHAVIOUR Rule 1: Escape = Cancel = Close box
        Me.CancelButton = btnClose
        Me.AcceptButton = btnClose

        ' Tab Order
        btnRerun.TabIndex = 0
        btnCopy.TabIndex = 1
        btnClose.TabIndex = 2
        txtOutput.TabIndex = 3
    End Sub

    Protected Overrides Async Sub OnShown(e As EventArgs)
        MyBase.OnShown(e)
        ThemeService.ApplyTheme(Me)
        AddHandler ThemeService.ThemeChanged, Sub() ThemeService.ApplyTheme(Me)
        Await RunDoctorAsync()
    End Sub

    Private Async Sub BtnRerun_Click(sender As Object, e As EventArgs)
        Await RunDoctorAsync()
    End Sub

    Private Sub BtnCopy_Click(sender As Object, e As EventArgs)
        If Not String.IsNullOrEmpty(_rawReportText) Then
            Clipboard.SetText(_rawReportText)
            lblStatusBadge.Text = "✓ Report copied to clipboard"
        End If
    End Sub

    Private Async Function RunDoctorAsync() As Task
        btnRerun.Enabled = False
        btnCopy.Enabled = False
        lblStatusBadge.Text = "⏳ Running diagnostics..."
        lblStatusBadge.ForeColor = ThemeService.Palette.TextMuted

        txtOutput.Clear()
        txtOutput.SelectionColor = ThemeService.Palette.StatusInfo
        txtOutput.AppendText("Running 'pq doctor -All' in background... Please wait." & vbCrLf & vbCrLf)

        Dim res = Await PqCli.RunSilentAsync("doctor", "-All")
        _rawReportText = res.Output
        If Not String.IsNullOrWhiteSpace(res.ErrorOutput) Then
            _rawReportText &= vbCrLf & "[stderr]" & vbCrLf & res.ErrorOutput
        End If

        txtOutput.Clear()
        FormatAndAppendReport(_rawReportText)

        ' Evaluate outcome
        Dim hasFail = _rawReportText.IndexOf("FAIL", StringComparison.OrdinalIgnoreCase) >= 0 OrElse res.ExitCode <> 0
        Dim hasWarn = _rawReportText.IndexOf("WARN", StringComparison.OrdinalIgnoreCase) >= 0

        If hasFail Then
            lblStatusBadge.Text = "● FAIL: Issues detected"
            lblStatusBadge.ForeColor = ThemeService.Palette.StatusDanger
        ElseIf hasWarn Then
            lblStatusBadge.Text = "● WARN: Warnings reported"
            lblStatusBadge.ForeColor = ThemeService.Palette.StatusWarning
        Else
            lblStatusBadge.Text = "● PASS: All checks clean"
            lblStatusBadge.ForeColor = ThemeService.Palette.StatusSuccess
        End If

        btnRerun.Enabled = True
        btnCopy.Enabled = True
    End Function

    Private Sub FormatAndAppendReport(report As String)
        Dim lines = report.Split({vbCrLf, vbLf, vbCr}, StringSplitOptions.None)
        Dim p = ThemeService.Palette

        For Each line In lines
            If line.Contains("FAIL") OrElse line.Contains("Error:") Then
                txtOutput.SelectionColor = p.StatusDanger
            ElseIf line.Contains("WARN") OrElse line.Contains("warning") Then
                txtOutput.SelectionColor = p.StatusWarning
            ElseIf line.Contains("OK") OrElse line.Contains("PASS") Then
                txtOutput.SelectionColor = p.StatusSuccess
            ElseIf line.StartsWith("#") OrElse line.StartsWith("===") Then
                txtOutput.SelectionColor = p.StatusInfo
            Else
                txtOutput.SelectionColor = p.ConsoleText
            End If

            txtOutput.AppendText(line & vbCrLf)
        Next
    End Sub
End Class
