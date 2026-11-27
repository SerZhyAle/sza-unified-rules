Option Explicit On
Option Strict On

''' <summary>
''' About PQ Control Panel per ABOUT-PAGE rules 1 to 5: the description, the version of this build, the author block,
''' the program page, the operator guide and the documentation. Opening it contacts nothing: an address opens only on
''' a click.
''' </summary>
Public Class FormAbout
    Inherits Form

    Private Const AuthorSiteUrl As String = "https://sza.od.ua"
    Private Const ProgramPageUrl As String = "https://github.com/SerZhyAle/sza-unified-rules"
    Private Const DocumentationUrl As String = "https://github.com/SerZhyAle/sza-unified-rules/blob/main/tools/harness/portfolio/README.md"
    Private Const TextWidth As Integer = 420

    Private ReadOnly _links As New List(Of LinkLabel)()
    Private tblAbout As TableLayoutPanel
    Private btnClose As Button

    Public Sub New()
        InitializeComponent()
    End Sub

    Private Sub InitializeComponent()
        SuspendLayout()
        Text = "About PQ Control Panel"
        AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        AutoScaleMode = AutoScaleMode.Font
        Font = New Font("Segoe UI", 9.0F)
        AutoSize = True
        AutoSizeMode = AutoSizeMode.GrowAndShrink
        FormBorderStyle = FormBorderStyle.FixedDialog
        MaximizeBox = False
        MinimizeBox = False
        ShowInTaskbar = False
        StartPosition = FormStartPosition.CenterParent

        tblAbout = New TableLayoutPanel With {
            .Name = "tblAbout",
            .ColumnCount = 1,
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .Padding = New Padding(16, 12, 16, 12)
        }

        Dim lblTitle = AddText("lblTitle", "PQ Control Panel")
        lblTitle.Font = New Font("Segoe UI", 12.0F, FontStyle.Bold)
        AddText("lblDescription", "One window over pq, the portfolio queue: its robots, tickets and releases across every registered project.")
        AddText("lblVersion", $"Version {Application.ProductVersion}")

        ' The author block (rule 3): on the surface itself, above the other links.
        Dim lblAuthor = AddText("lblAuthor", "Author: Serhii Zhyhunenko")
        lblAuthor.Margin = New Padding(0, 10, 0, 0)
        AddLink("lnkAuthorSite", AuthorSiteUrl, Function() PqCli.OpenUrl(AuthorSiteUrl))

        Dim lnkPage = AddLink("lnkProgramPage", "Program page", Function() PqCli.OpenUrl(ProgramPageUrl))
        lnkPage.Margin = New Padding(0, 10, 0, 3)
        ' No row that leads nowhere (rule 2): the local guide is offered only where the file is.
        Dim guide = PqCli.GetGuidePath()
        If File.Exists(guide) Then AddLink("lnkGuide", "Help: operator guide", Function() PqCli.OpenFileWithDefaultApp(guide))
        AddLink("lnkDocumentation", "Documentation", Function() PqCli.OpenUrl(DocumentationUrl))

        btnClose = New Button With {
            .Name = "btnClose",
            .Text = "Close",
            .Size = New Size(100, 32),
            .Anchor = AnchorStyles.Right,
            .Margin = New Padding(0, 12, 0, 0),
            .AccessibleName = "Close dialog",
            .AccessibleRole = AccessibleRole.PushButton,
            .DialogResult = DialogResult.Cancel
        }
        tblAbout.Controls.Add(btnClose)
        Controls.Add(tblAbout)

        ' APP-BEHAVIOUR Rule 1: Escape = Cancel = Close box
        CancelButton = btnClose
        AcceptButton = btnClose
        ActiveControl = btnClose

        ResumeLayout(False)
        PerformLayout()
    End Sub

    Private Function AddText(name As String, text As String) As Label
        Dim lbl As New Label With {
            .Name = name,
            .Text = text,
            .AutoSize = True,
            .UseMnemonic = False,
            .MaximumSize = New Size(TextWidth, 0)
        }
        tblAbout.Controls.Add(lbl)
        Return lbl
    End Function

    Private Function AddLink(name As String, text As String, open As Func(Of String)) As LinkLabel
        Dim link As New LinkLabel With {
            .Name = name,
            .Text = text,
            .AutoSize = True,
            .UseMnemonic = False,
            .MaximumSize = New Size(TextWidth, 0)
        }
        AddHandler link.LinkClicked,
            Sub(s, e)
                Dim err = open()
                If err IsNot Nothing Then MessageBox.Show(Me, err, Me.Text, MessageBoxButtons.OK, MessageBoxIcon.Warning)
            End Sub
        tblAbout.Controls.Add(link)
        _links.Add(link)
        Return link
    End Function

    Protected Overrides Sub OnShown(e As EventArgs)
        MyBase.OnShown(e)
        ApplyAboutTheme()
        AddHandler ThemeService.ThemeChanged, AddressOf OnThemeChanged
    End Sub

    Protected Overrides Sub OnFormClosed(e As FormClosedEventArgs)
        RemoveHandler ThemeService.ThemeChanged, AddressOf OnThemeChanged
        MyBase.OnFormClosed(e)
    End Sub

    Private Sub OnThemeChanged(sender As Object, e As EventArgs)
        ApplyAboutTheme()
    End Sub

    ' ThemeService colours a LinkLabel as a label; its link colours are separate properties.
    Private Sub ApplyAboutTheme()
        ThemeService.ApplyTheme(Me)
        Dim p = ThemeService.Palette
        Dim linkColor = If(ThemeService.IsDark, p.StatusInfo, p.Accent)
        For Each link In _links
            link.LinkColor = linkColor
            link.VisitedLinkColor = linkColor
            link.ActiveLinkColor = p.AccentHover
        Next
    End Sub
End Class
