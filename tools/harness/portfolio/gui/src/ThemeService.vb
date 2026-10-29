Option Explicit On
Option Strict On

Imports Microsoft.Win32

Public Enum AppThemeMode
    System = 0
    Light = 1
    Dark = 2
End Enum

''' <summary>
''' Contract-compliant palette role vocabulary per APP-STYLE.
''' </summary>
Public Class ThemePalette
    Public Property WindowBackground As Color       ' surface.window
    Public Property SurfaceRaised As Color          ' surface.raised
    Public Property SurfaceSunken As Color          ' surface.sunken
    Public Property SurfaceSelected As Color        ' surface.selected
    Public Property SurfaceAlternate As Color       ' surface.alternate
    Public Property ControlFace As Color            ' control
    Public Property ControlHover As Color           ' control.hover
    Public Property ControlPressed As Color         ' control.pressed
    Public Property Border As Color                 ' border
    Public Property TextPrimary As Color            ' text.primary
    Public Property TextMuted As Color              ' text.muted
    Public Property TextDisabled As Color           ' text.disabled
    Public Property Accent As Color                 ' accent
    Public Property AccentHover As Color            ' accent.hover
    Public Property AccentText As Color             ' accent.ink
    Public Property StatusDanger As Color           ' status.danger
    Public Property StatusDangerHover As Color
    Public Property StatusDangerText As Color
    Public Property StatusWarning As Color          ' status.warning
    Public Property StatusWarningHover As Color
    Public Property StatusWarningText As Color
    Public Property StatusSuccess As Color          ' status.success
    Public Property StatusInfo As Color             ' info
    Public Property ConsoleBackground As Color      ' console terminal
    Public Property ConsoleText As Color
End Class

''' <summary>
''' Manages application themes, dynamic palette resolution, and OS theme event listening per APP-STYLE and WINDOWS-UI.
''' </summary>
Public Class ThemeService
    Private Shared _mode As AppThemeMode = AppThemeMode.System
    Private Shared _lightPalette As ThemePalette
    Private Shared _darkPalette As ThemePalette
    Private Shared _isSubscribed As Boolean = False

    Public Shared Event ThemeChanged(sender As Object, e As EventArgs)

    Shared Sub New()
        InitializePalettes()
        EnsureSystemEventHook()
    End Sub

    Public Shared Property Mode As AppThemeMode
        Get
            Return _mode
        End Get
        Set(value As AppThemeMode)
            If _mode <> value Then
                _mode = value
                RaiseEvent ThemeChanged(Nothing, EventArgs.Empty)
            End If
        End Set
    End Property

    Public Shared ReadOnly Property IsDark As Boolean
        Get
            Select Case _mode
                Case AppThemeMode.Dark
                    Return True
                Case AppThemeMode.Light
                    Return False
                Case Else
                    Return DetectWindowsDarkTheme()
            End Select
        End Get
    End Property

    Public Shared ReadOnly Property Palette As ThemePalette
        Get
            Return If(IsDark, _darkPalette, _lightPalette)
        End Get
    End Property

    Private Shared Sub InitializePalettes()
        ' Light Palette (per APP-STYLE role vocabulary)
        _lightPalette = New ThemePalette With {
            .WindowBackground = Color.FromArgb(255, 255, 255),
            .SurfaceRaised = Color.FromArgb(248, 249, 250),
            .SurfaceSunken = Color.FromArgb(240, 243, 246),
            .SurfaceSelected = Color.FromArgb(204, 228, 255),
            .SurfaceAlternate = Color.FromArgb(249, 250, 252),
            .ControlFace = Color.FromArgb(243, 244, 246),
            .ControlHover = Color.FromArgb(229, 231, 235),
            .ControlPressed = Color.FromArgb(209, 213, 219),
            .Border = Color.FromArgb(218, 222, 229),
            .TextPrimary = Color.FromArgb(27, 31, 36),
            .TextMuted = Color.FromArgb(101, 109, 118),
            .TextDisabled = Color.FromArgb(140, 149, 159),
            .Accent = Color.FromArgb(9, 105, 218),
            .AccentHover = Color.FromArgb(3, 84, 180),
            .AccentText = Color.FromArgb(255, 255, 255),
            .StatusDanger = Color.FromArgb(207, 34, 46),
            .StatusDangerHover = Color.FromArgb(164, 15, 25),
            .StatusDangerText = Color.FromArgb(255, 255, 255),
            .StatusWarning = Color.FromArgb(255, 243, 205),
            .StatusWarningHover = Color.FromArgb(254, 230, 160),
            .StatusWarningText = Color.FromArgb(102, 60, 0),
            .StatusSuccess = Color.FromArgb(31, 136, 61),
            .StatusInfo = Color.FromArgb(84, 174, 255),
            .ConsoleBackground = Color.FromArgb(30, 30, 30),
            .ConsoleText = Color.FromArgb(220, 220, 220)
        }

        ' Dark Palette (per APP-STYLE role vocabulary)
        _darkPalette = New ThemePalette With {
            .WindowBackground = Color.FromArgb(18, 21, 26),
            .SurfaceRaised = Color.FromArgb(26, 31, 38),
            .SurfaceSunken = Color.FromArgb(33, 38, 45),
            .SurfaceSelected = Color.FromArgb(41, 62, 94),
            .SurfaceAlternate = Color.FromArgb(24, 29, 36),
            .ControlFace = Color.FromArgb(33, 38, 45),
            .ControlHover = Color.FromArgb(48, 54, 61),
            .ControlPressed = Color.FromArgb(64, 72, 82),
            .Border = Color.FromArgb(48, 54, 61),
            .TextPrimary = Color.FromArgb(240, 246, 252),
            .TextMuted = Color.FromArgb(139, 148, 158),
            .TextDisabled = Color.FromArgb(72, 79, 88),
            .Accent = Color.FromArgb(31, 111, 235),
            .AccentHover = Color.FromArgb(56, 139, 253),
            .AccentText = Color.FromArgb(255, 255, 255),
            .StatusDanger = Color.FromArgb(248, 81, 73),
            .StatusDangerHover = Color.FromArgb(218, 54, 51),
            .StatusDangerText = Color.FromArgb(255, 255, 255),
            .StatusWarning = Color.FromArgb(187, 128, 9),
            .StatusWarningHover = Color.FromArgb(210, 153, 34),
            .StatusWarningText = Color.FromArgb(255, 255, 255),
            .StatusSuccess = Color.FromArgb(46, 160, 67),
            .StatusInfo = Color.FromArgb(88, 166, 255),
            .ConsoleBackground = Color.FromArgb(13, 17, 23),
            .ConsoleText = Color.FromArgb(230, 237, 243)
        }
    End Sub

    Public Shared Function DetectWindowsDarkTheme() As Boolean
        Try
            Dim val = Registry.GetValue("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1)
            If val IsNot Nothing AndAlso TypeOf val Is Integer Then
                Return CInt(val) = 0
            End If
        Catch
        End Try
        Return False
    End Function

    Private Shared Sub EnsureSystemEventHook()
        If Not _isSubscribed Then
            Try
                AddHandler SystemEvents.UserPreferenceChanged, AddressOf OnUserPreferenceChanged
                _isSubscribed = True
            Catch
            End Try
        End If
    End Sub

    Private Shared Sub OnUserPreferenceChanged(sender As Object, e As UserPreferenceChangedEventArgs)
        If _mode = AppThemeMode.System AndAlso (e.Category = UserPreferenceCategory.General OrElse e.Category = UserPreferenceCategory.Color) Then
            RaiseEvent ThemeChanged(Nothing, EventArgs.Empty)
        End If
    End Sub

    ''' <summary>
    ''' Recursively styles a form and its child controls using the active palette.
    ''' </summary>
    Public Shared Sub ApplyTheme(targetForm As Form)
        Dim p = Palette
        targetForm.BackColor = p.WindowBackground
        targetForm.ForeColor = p.TextPrimary

        ApplyControlTheme(targetForm, p)
    End Sub

    Private Shared Sub ApplyControlTheme(parent As Control, p As ThemePalette)
        For Each ctrl As Control In parent.Controls
            If TypeOf ctrl Is Panel AndAlso Not (TypeOf ctrl Is FlowLayoutPanel) Then
                Dim pnl = CType(ctrl, Panel)
                If pnl.Name = "pnlBanner" Then
                    ' Banner sets its own dynamic status colors in RefreshAll
                ElseIf pnl.Name.StartsWith("pnlLeftHeader") OrElse pnl.Name.StartsWith("pnlWorkersHeader") OrElse pnl.Name.StartsWith("pnlPassesHeader") Then
                    pnl.BackColor = p.SurfaceSunken
                    pnl.ForeColor = p.TextPrimary
                ElseIf pnl.Name = "pnlTopActions" OrElse pnl.Name = "pnlBottom" OrElse pnl.Name = "pnlSteer" Then
                    pnl.BackColor = p.SurfaceRaised
                    pnl.ForeColor = p.TextPrimary
                ElseIf TypeOf ctrl Is TableLayoutPanel OrElse pnl.Name.StartsWith("tbl") OrElse pnl.Name = "pnlContent" Then
                    pnl.BackColor = p.WindowBackground
                    pnl.ForeColor = p.TextPrimary
                Else
                    pnl.BackColor = p.SurfaceRaised
                    pnl.ForeColor = p.TextPrimary
                End If
            ElseIf TypeOf ctrl Is FlowLayoutPanel Then
                If ctrl.Name = "pnlType" Then
                    ctrl.BackColor = p.WindowBackground
                    ctrl.ForeColor = p.TextPrimary
                ElseIf ctrl.Name = "pnlButtons" Then
                    ctrl.BackColor = Color.Transparent
                    ctrl.ForeColor = p.TextPrimary
                Else
                    ctrl.BackColor = p.SurfaceRaised
                    ctrl.ForeColor = p.TextPrimary
                End If
            ElseIf TypeOf ctrl Is SplitContainer Then
                Dim split = CType(ctrl, SplitContainer)
                split.BackColor = p.Border
                split.Panel1.BackColor = p.WindowBackground
                split.Panel2.BackColor = p.WindowBackground
            ElseIf TypeOf ctrl Is Splitter Then
                ctrl.BackColor = p.Border
            ElseIf TypeOf ctrl Is Button Then
                Dim btn = CType(ctrl, Button)
                ApplyButtonRank(btn, p)
            ElseIf TypeOf ctrl Is TextBox Then
                Dim txt = CType(ctrl, TextBox)
                If txt.Multiline AndAlso txt.ReadOnly AndAlso txt.Name.Contains("Console") Then
                    txt.BackColor = p.ConsoleBackground
                    txt.ForeColor = p.ConsoleText
                Else
                    txt.BackColor = If(IsDark, p.SurfaceSunken, p.WindowBackground)
                    txt.ForeColor = p.TextPrimary
                End If
            ElseIf TypeOf ctrl Is RichTextBox Then
                Dim rtb = CType(ctrl, RichTextBox)
                rtb.BackColor = p.ConsoleBackground
                rtb.ForeColor = p.ConsoleText
            ElseIf TypeOf ctrl Is ComboBox Then
                Dim cmb = CType(ctrl, ComboBox)
                cmb.BackColor = If(IsDark, p.SurfaceSunken, p.WindowBackground)
                cmb.ForeColor = p.TextPrimary
                cmb.FlatStyle = FlatStyle.Flat
            ElseIf TypeOf ctrl Is CheckBox OrElse TypeOf ctrl Is RadioButton Then
                ctrl.ForeColor = p.TextPrimary
            ElseIf TypeOf ctrl Is Label Then
                If ctrl.Name = "lblPqPath" OrElse ctrl.Name.StartsWith("lblSub") Then
                    ctrl.ForeColor = p.TextMuted
                ElseIf ctrl.Name = "lblStatus" OrElse ctrl.Name = "lblNextCandidate" Then
                    ' Banner labels manage their own text colors
                Else
                    ctrl.ForeColor = p.TextPrimary
                End If
            ElseIf TypeOf ctrl Is DataGridView Then
                Dim dgv = CType(ctrl, DataGridView)
                ApplyGridTheme(dgv, p)
            End If

            If ctrl.HasChildren Then
                ApplyControlTheme(ctrl, p)
            End If
        Next
    End Sub

    Private Shared Sub ApplyButtonRank(btn As Button, p As ThemePalette)
        btn.FlatStyle = FlatStyle.Flat
        btn.FlatAppearance.BorderSize = 1
        btn.FlatAppearance.BorderColor = p.Border

        ' Visual Rank mapping per BUTTONS contract
        If btn.Name = "btnStartLoop" OrElse btn.Name = "btnDraft" Then
            ' Primary Action
            btn.BackColor = p.Accent
            btn.ForeColor = p.AccentText
            btn.FlatAppearance.BorderColor = p.Accent
            btn.FlatAppearance.MouseOverBackColor = p.AccentHover
        ElseIf btn.Name = "btnKill" Then
            ' Destructive Action
            btn.BackColor = p.StatusDanger
            btn.ForeColor = p.StatusDangerText
            btn.FlatAppearance.BorderColor = p.StatusDanger
            btn.FlatAppearance.MouseOverBackColor = p.StatusDangerHover
        ElseIf btn.Name = "btnStop" Then
            ' Warning Action
            btn.BackColor = p.StatusWarning
            btn.ForeColor = p.StatusWarningText
            btn.FlatAppearance.BorderColor = p.StatusWarning
            btn.FlatAppearance.MouseOverBackColor = p.StatusWarningHover
        Else
            ' Ordinary / Secondary
            btn.BackColor = p.ControlFace
            btn.ForeColor = p.TextPrimary
            btn.FlatAppearance.MouseOverBackColor = p.ControlHover
            btn.FlatAppearance.MouseDownBackColor = p.ControlPressed
        End If
    End Sub

    Public Shared Sub ApplyGridTheme(dgv As DataGridView, p As ThemePalette)
        dgv.EnableHeadersVisualStyles = False
        dgv.BackgroundColor = p.WindowBackground
        dgv.GridColor = p.Border
        dgv.BorderStyle = BorderStyle.None

        ' Ordinary cell style
        dgv.DefaultCellStyle.BackColor = p.WindowBackground
        dgv.DefaultCellStyle.ForeColor = p.TextPrimary
        dgv.DefaultCellStyle.SelectionBackColor = p.SurfaceSelected
        dgv.DefaultCellStyle.SelectionForeColor = p.TextPrimary

        ' Alternate row cell style (surface.alternate)
        dgv.AlternatingRowsDefaultCellStyle.BackColor = p.SurfaceAlternate
        dgv.AlternatingRowsDefaultCellStyle.ForeColor = p.TextPrimary
        dgv.AlternatingRowsDefaultCellStyle.SelectionBackColor = p.SurfaceSelected
        dgv.AlternatingRowsDefaultCellStyle.SelectionForeColor = p.TextPrimary

        ' Column headers
        dgv.ColumnHeadersDefaultCellStyle.BackColor = p.SurfaceSunken
        dgv.ColumnHeadersDefaultCellStyle.ForeColor = p.TextPrimary
        dgv.ColumnHeadersDefaultCellStyle.SelectionBackColor = p.SurfaceSunken
        dgv.ColumnHeadersDefaultCellStyle.SelectionForeColor = p.TextPrimary
        dgv.ColumnHeadersBorderStyle = DataGridViewHeaderBorderStyle.Single
    End Sub
End Class
