Option Explicit On
Option Strict On

Imports System.Diagnostics
Imports System.Text.RegularExpressions

Public Class CliResult
    Public Property ExitCode As Integer
    Public Property Output As String = ""
    Public Property ErrorOutput As String = ""
    Public ReadOnly Property Success As Boolean
        Get
            Return ExitCode = 0
        End Get
    End Property

    ' stderr when there is any, else stdout: pq names its errors on stderr, spec-draft prints them with Write-Host.
    Public ReadOnly Property Message As String
        Get
            Return If(Not String.IsNullOrWhiteSpace(ErrorOutput), ErrorOutput, Output).Trim()
        End Get
    End Property
End Class

Public Class PqCli
    Private Shared _pqScriptPath As String = ""
    Private Shared _pwshExePath As String = ""
    Private Shared _specDraftScriptPath As String = ""

    ' The checkout this panel was built for; the published exe runs from a deploy folder outside it.
    Private Const FallbackPortfolioDir As String = "P:\WEB\sza-unified-rules\tools\harness\portfolio"

    Public Shared Property PqScriptPath As String
        Get
            If String.IsNullOrWhiteSpace(_pqScriptPath) OrElse Not File.Exists(_pqScriptPath) Then
                _pqScriptPath = ResolvePqScriptPath()
            End If
            Return _pqScriptPath
        End Get
        Set(value As String)
            _pqScriptPath = value
        End Set
    End Property

    Public Shared Property SpecDraftScriptPath As String
        Get
            If String.IsNullOrWhiteSpace(_specDraftScriptPath) OrElse Not File.Exists(_specDraftScriptPath) Then
                _specDraftScriptPath = Path.Combine(PortfolioDir, "spec-draft.ps1")
            End If
            Return _specDraftScriptPath
        End Get
        Set(value As String)
            _specDraftScriptPath = value
        End Set
    End Property

    Public Shared Property PwshExePath As String
        Get
            If String.IsNullOrWhiteSpace(_pwshExePath) OrElse Not File.Exists(_pwshExePath) Then
                _pwshExePath = ResolvePwshExe()
            End If
            Return _pwshExePath
        End Get
        Set(value As String)
            _pwshExePath = value
        End Set
    End Property

    Public Shared ReadOnly Property PortfolioDir As String
        Get
            Dim dir = Path.GetDirectoryName(PqScriptPath)
            Return If(String.IsNullOrEmpty(dir), FallbackPortfolioDir, dir)
        End Get
    End Property

    ' SZA_PQ_SCRIPT, then pq.ps1 beside the exe or in an ancestor checkout, then the fixed checkout path.
    Public Shared Function ResolvePqScriptPath() As String
        Dim env = Environment.GetEnvironmentVariable("SZA_PQ_SCRIPT")
        If Not String.IsNullOrWhiteSpace(env) AndAlso File.Exists(env) Then Return Path.GetFullPath(env)

        Dim dir = New DirectoryInfo(AppContext.BaseDirectory)
        While dir IsNot Nothing
            Dim candidate = Path.Combine(dir.FullName, "pq.ps1")
            If File.Exists(candidate) Then Return candidate
            candidate = Path.Combine(dir.FullName, "tools", "harness", "portfolio", "pq.ps1")
            If File.Exists(candidate) Then Return candidate
            dir = dir.Parent
        End While

        Return Path.Combine(FallbackPortfolioDir, "pq.ps1")
    End Function

    Public Shared Function ResolvePwshExe() As String
        Dim programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)
        Dim paths = {
            Path.Combine(programFiles, "PowerShell", "7", "pwsh.exe"),
            Path.Combine(programFiles, "PowerShell", "7-preview", "pwsh.exe")
        }
        For Each p In paths
            If File.Exists(p) Then Return p
        Next
        Return "pwsh.exe"
    End Function

    Public Shared Function GetGuidePath() As String
        Return Path.Combine(PortfolioDir, "README.md")
    End Function

    ' A visible terminal that stays open, for the verbs the owner watches (start) or that open an editor.
    ' Returns an error message, or Nothing when the window started.
    Public Shared Function LaunchInteractive(ParamArray arguments As String()) As String
        Dim script = PqScriptPath
        If Not File.Exists(script) Then Return $"pq.ps1 not found at {script}"

        Dim psi As New ProcessStartInfo With {
            .FileName = PwshExePath,
            .WorkingDirectory = Path.GetDirectoryName(script),
            .UseShellExecute = False
        }
        For Each a In {"-NoExit", "-NoProfile", "-File", script}
            psi.ArgumentList.Add(a)
        Next
        For Each a In arguments
            psi.ArgumentList.Add(a)
        Next
        Try
            Process.Start(psi)?.Dispose()
            Return Nothing
        Catch ex As Exception
            Return $"cannot start {PwshExePath}: {ex.Message}"
        End Try
    End Function

    ' The script runs inside -EncodedCommand so its console output can be switched to UTF-8 first: a redirected
    ' pwsh writes in the OEM code page (cp866 here), which turns every non-ASCII path and title into garbage.
    ' A bare -Name argument stays a parameter name; every other argument goes in single quotes, verbatim.
    Public Shared Function BuildEncodedCommand(scriptPath As String, arguments As IEnumerable(Of String)) As String
        Dim sb As New StringBuilder()
        sb.Append("[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); & ")
        sb.Append(Quote(scriptPath))
        For Each a In arguments
            sb.Append(" "c)
            sb.Append(If(Regex.IsMatch(a, "^-[A-Za-z]+$"), a, Quote(a)))
        Next
        sb.Append("; exit $LASTEXITCODE")
        Return Convert.ToBase64String(Encoding.Unicode.GetBytes(sb.ToString()))
    End Function

    Private Shared Function Quote(value As String) As String
        Return "'" & value.Replace("'", "''") & "'"
    End Function

    Public Shared Async Function RunScriptSilentAsync(scriptPath As String, ParamArray arguments As String()) As Task(Of CliResult)
        Dim res As New CliResult()
        If Not File.Exists(scriptPath) Then
            res.ExitCode = -1
            res.ErrorOutput = $"script not found: {scriptPath}"
            Return res
        End If

        Dim psi As New ProcessStartInfo With {
            .FileName = PwshExePath,
            .WorkingDirectory = Path.GetDirectoryName(scriptPath),
            .RedirectStandardInput = True,
            .RedirectStandardOutput = True,
            .RedirectStandardError = True,
            .UseShellExecute = False,
            .CreateNoWindow = True,
            .StandardOutputEncoding = New UTF8Encoding(False),
            .StandardErrorEncoding = New UTF8Encoding(False)
        }
        ' -OutputFormat Text: with -EncodedCommand and a redirected stderr pwsh otherwise wraps every error and every
        ' Write-Host line in CLIXML, and the status line shows only its "#< CLIXML" header.
        For Each a In {"-NoProfile", "-NonInteractive", "-OutputFormat", "Text", "-EncodedCommand", BuildEncodedCommand(scriptPath, arguments)}
            psi.ArgumentList.Add(a)
        Next

        Try
            Using proc = Process.Start(psi)
                If proc Is Nothing Then
                    res.ExitCode = -1
                    res.ErrorOutput = "Failed to start process."
                    Return res
                End If
                proc.StandardInput.Close()

                Dim outTask = proc.StandardOutput.ReadToEndAsync()
                Dim errTask = proc.StandardError.ReadToEndAsync()
                Await proc.WaitForExitAsync()

                res.ExitCode = proc.ExitCode
                res.Output = Await outTask
                res.ErrorOutput = Await errTask
            End Using
        Catch ex As Exception
            res.ExitCode = -1
            res.ErrorOutput = ex.Message
        End Try

        Return res
    End Function

    Public Shared Function RunSilentAsync(ParamArray arguments As String()) As Task(Of CliResult)
        Return RunScriptSilentAsync(PqScriptPath, arguments)
    End Function

    Public Shared Async Function DraftSpecAsync(projectKey As String, slug As String, textContent As String, complexity As String, pin As Boolean) As Task(Of CliResult)
        ' The owner's words go through a file: spec-draft keeps them byte for byte, so no BOM is added.
        Dim tempFile = Path.Combine(Path.GetTempPath(), $"pq_spec_{Guid.NewGuid():N}.txt")
        File.WriteAllText(tempFile, textContent, New UTF8Encoding(False))

        Dim args As New List(Of String) From {"-Project", projectKey, "-Slug", slug, "-TextFile", tempFile}
        If Not String.IsNullOrWhiteSpace(complexity) Then
            args.Add("-Complexity")
            args.Add(complexity)
        End If
        ' An urgent blocker (hotfix-) is pinned by spec-draft unless told otherwise; an unticked box is that word.
        If pin Then
            args.Add("-Pin")
        ElseIf slug.StartsWith("hotfix-", StringComparison.Ordinal) Then
            args.Add("-NoPin")
        End If

        Try
            Return Await RunScriptSilentAsync(SpecDraftScriptPath, args.ToArray())
        Finally
            Try
                File.Delete(tempFile)
            Catch
            End Try
        End Try
    End Function

    Public Shared Function OpenFileWithDefaultApp(path As String) As String
        If Not File.Exists(path) Then Return $"not found: {path}"
        Try
            Process.Start(New ProcessStartInfo With {.FileName = path, .UseShellExecute = True})?.Dispose()
            Return Nothing
        Catch ex As Exception
            Return ex.Message
        End Try
    End Function

    Public Shared Function OpenFolder(path As String) As String
        If Not Directory.Exists(path) Then Return $"not found: {path}"
        Try
            Dim psi As New ProcessStartInfo With {.FileName = "explorer.exe", .UseShellExecute = True}
            psi.ArgumentList.Add(path)
            Process.Start(psi)?.Dispose()
            Return Nothing
        Catch ex As Exception
            Return ex.Message
        End Try
    End Function

    Public Shared Function ResolveVsCodeExe() As String
        Dim env = Environment.GetEnvironmentVariable("SZA_VSCODE_EXE")
        If Not String.IsNullOrWhiteSpace(env) AndAlso File.Exists(env) Then Return Path.GetFullPath(env)

        Dim localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
        Dim programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)
        Dim programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86)

        Dim candidates = {
            Path.Combine(localAppData, "Programs", "Microsoft VS Code", "Code.exe"),
            Path.Combine(programFiles, "Microsoft VS Code", "Code.exe"),
            Path.Combine(programFilesX86, "Microsoft VS Code", "Code.exe"),
            Path.Combine(localAppData, "Programs", "Microsoft VS Code Insiders", "Code - Insiders.exe"),
            Path.Combine(programFiles, "Microsoft VS Code Insiders", "Code - Insiders.exe")
        }
        For Each c In candidates
            If File.Exists(c) Then Return c
        Next

        Dim pathEnv = Environment.GetEnvironmentVariable("PATH")
        If Not String.IsNullOrEmpty(pathEnv) Then
            For Each p In pathEnv.Split(";"c, StringSplitOptions.RemoveEmptyEntries)
                Try
                    Dim trimmed = p.Trim()
                    Dim codeExe = Path.Combine(trimmed, "Code.exe")
                    If File.Exists(codeExe) Then Return codeExe
                    Dim codeCmd = Path.Combine(trimmed, "code.cmd")
                    If File.Exists(codeCmd) Then
                        Dim parentDir = Path.GetDirectoryName(trimmed)
                        If Not String.IsNullOrEmpty(parentDir) Then
                            Dim parentExe = Path.Combine(parentDir, "Code.exe")
                            If File.Exists(parentExe) Then Return parentExe
                        End If
                        Return codeCmd
                    End If
                Catch
                End Try
            Next
        End If

        Return Nothing
    End Function

    Public Shared Function OpenVsCode(path As String) As String
        If Not Directory.Exists(path) Then Return $"not found: {path}"
        Dim exe = ResolveVsCodeExe()
        Try
            Dim psi As ProcessStartInfo
            If Not String.IsNullOrEmpty(exe) AndAlso File.Exists(exe) Then
                psi = New ProcessStartInfo With {
                    .FileName = exe,
                    .UseShellExecute = exe.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase),
                    .CreateNoWindow = True
                }
                psi.ArgumentList.Add(path)
            Else
                psi = New ProcessStartInfo With {
                    .FileName = "code",
                    .UseShellExecute = True
                }
                psi.ArgumentList.Add(path)
            End If
            Process.Start(psi)?.Dispose()
            Return Nothing
        Catch ex As Exception
            Return ex.Message
        End Try
    End Function
End Class
