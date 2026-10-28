Option Explicit On
Option Strict On

Imports System.Text.Json.Serialization

''' <summary>
''' Represents persistent user interface layout state and preferences per APP-BEHAVIOUR Rule 9.
''' </summary>
Public Class UiStateData
    Public Property WindowX As Integer?
    Public Property WindowY As Integer?
    Public Property WindowWidth As Integer?
    Public Property WindowHeight As Integer?
    Public Property WindowMaximized As Boolean = False
    Public Property MainSplitterDistance As Integer?
    Public Property MonitorSplitterDistance As Integer?
    Public Property ConsoleHeight As Integer = 140
    Public Property ConsoleCollapsed As Boolean = False
    Public Property AutoRefresh As Boolean = True
    Public Property Theme As String = "System"
End Class

Public Class UiState
    Private Const FileName As String = "ui-state.json"

    Private Shared Function GetStatePath() As String
        Return Path.Combine(PortfolioState.PortfolioRoot, FileName)
    End Function

    Public Shared Function Load() As UiStateData
        Dim filePath = GetStatePath()
        If File.Exists(filePath) Then
            Try
                Dim json = File.ReadAllText(filePath, Encoding.UTF8)
                Dim data = JsonSerializer.Deserialize(Of UiStateData)(json)
                If data IsNot Nothing Then Return data
            Catch
            End Try
        End If
        Return New UiStateData()
    End Function

    Public Shared Sub Save(data As UiStateData)
        If data Is Nothing Then Return
        Try
            Dim filePath = GetStatePath()
            Dim dir = Path.GetDirectoryName(filePath)
            If Not String.IsNullOrEmpty(dir) AndAlso Not Directory.Exists(dir) Then
                Directory.CreateDirectory(dir)
            End If
            Dim options As New JsonSerializerOptions With {.WriteIndented = True}
            Dim json = JsonSerializer.Serialize(data, options)
            File.WriteAllText(filePath, json, Encoding.UTF8)
        Catch
        End Try
    End Sub

    ''' <summary>
    ''' Clamps saved bounds so the window is guaranteed to be visible on an existing screen.
    ''' </summary>
    Public Shared Sub ApplyBoundsSafely(targetForm As Form, data As UiStateData)
        If targetForm Is Nothing OrElse data Is Nothing Then Return

        If data.WindowWidth.HasValue AndAlso data.WindowHeight.HasValue AndAlso data.WindowX.HasValue AndAlso data.WindowY.HasValue Then
            Dim savedRect As New Rectangle(data.WindowX.Value, data.WindowY.Value, data.WindowWidth.Value, data.WindowHeight.Value)
            Dim isVisibleOnAnyScreen As Boolean = False

            For Each s In Screen.AllScreens
                Dim intersection = Rectangle.Intersect(s.WorkingArea, savedRect)
                ' At least 100x100 pixels must be inside a visible screen area
                If intersection.Width >= 100 AndAlso intersection.Height >= 100 Then
                    isVisibleOnAnyScreen = True
                    Exit For
                End If
            Next

            If isVisibleOnAnyScreen Then
                targetForm.StartPosition = FormStartPosition.Manual
                targetForm.Bounds = savedRect
            Else
                ' Center on primary screen if saved position is off-screen
                targetForm.StartPosition = FormStartPosition.CenterScreen
            End If
        End If

        If data.WindowMaximized Then
            targetForm.WindowState = FormWindowState.Maximized
        End If
    End Sub
End Class
