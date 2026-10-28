Option Explicit On
Option Strict On

Public Module Program
    <STAThread>
    Public Sub Main()
        Application.SetHighDpiMode(HighDpiMode.SystemAware)
        Application.EnableVisualStyles()
        Application.SetCompatibleTextRenderingDefault(False)
        ' An exception in an event handler (an Async Sub included) is shown, not allowed to close the panel.
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException)
        AddHandler Application.ThreadException,
            Sub(s, e) MessageBox.Show(e.Exception.ToString(), "PQ Control Panel - unexpected error", MessageBoxButtons.OK, MessageBoxIcon.Error)
        Application.Run(New MainForm())
    End Sub
End Module
