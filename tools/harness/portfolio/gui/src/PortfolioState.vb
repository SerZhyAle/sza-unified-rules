Option Explicit On
Option Strict On

Imports System.Diagnostics
Imports System.Globalization
Imports System.Linq
Imports System.Text.Json
Imports System.Text.RegularExpressions

Public Class RepoInfo
    Public Property Key As String = ""
    Public Property Path As String = ""
    Public Property Enabled As Boolean = False
    Public Property Role As String = "product"
    Public Property PermissionMode As String = ""
    Public Property MaxWorkers As Integer = 1
    Public Property Concurrent As Boolean = False
    ' The project order (TASK-FLOW rule 41): rank ascending, equal ranks in array order.
    Public Property Rank As Long = 100
    Public Property Index As Integer
    ' The registry's own hold flag (TASK-FLOW rule 41), and a bare key under the queue file's hold heading.
    Public Property RegistryHold As Boolean = False
    Public Property QueueHold As Boolean = False
    ' Active rows of this repository in PORTFOLIO_QUEUE.md, '--' included.
    Public Property QueuedRows As Integer = 0
    ' Of those, the ticket rows the runner would take (PortfolioState.IsRunnable); 0 for a repository it does not
    ' work (disabled or held).
    Public Property RunnableRows As Integer = 0
    ' Ticket rows in a Block* status (BlockQuestions, BlockNeedUserTest, BlockByOtherTask, BlockExternal), active or held:
    ' open, and waiting on someone or something before the runner can move them.
    Public Property BlockedRows As Integer = 0

    Public ReadOnly Property IsHeld As Boolean
        Get
            Return RegistryHold OrElse QueueHold
        End Get
    End Property
End Class

Public Class WorkerInfo
    Public Property Slot As Integer
    Public Property Pid As Integer
    Public Property StartedAt As String = ""
    Public Property Repository As String = ""
    Public Property Ticket As String = ""
    Public Property Title As String = ""
    Public Property Since As String = ""
    Public Property Alive As Boolean
    Public Property Elapsed As String = ""
End Class

Public Class PassInfo
    Public Property Run As String = ""
    Public Property Pass As String = ""
    Public Property Repo As String = ""
    Public Property Id As String = ""
    Public Property Agent As String = ""
    Public Property Model As String = ""
    Public Property Complexity As String = ""
    Public Property StatusBefore As String = ""
    Public Property StatusAfter As String = ""
    Public Property Moved As Boolean
    Public Property Outcome As String = ""
    Public Property ExitCode As Integer
    Public Property Seconds As Double
    Public Property FinishedAt As String = ""
End Class

Public Class StopInfo
    Public Property Present As Boolean = False
    Public Property Level As String = ""
End Class

Public Class QueueRow
    ' A numbered heading's value; -1 before the first heading; Long.MaxValue under '--'.
    Public Property Package As Long
    Public Property Repo As String = ""
    ' Nothing for a head row ('<repo>' or '<repo>:*').
    Public Property Id As String
    Public Property Line As Integer
    Public Property Status As String = ""

    Public ReadOnly Property Target As String
        Get
            Return If(Id Is Nothing, Repo, $"{Repo}:{Id}")
        End Get
    End Property
End Class

Public Class QueueSnapshot
    Public Property Present As Boolean
    ' Active rows in effective order: packages ascending, then line order (Read-PqQueueFile).
    Public Property Rows As New List(Of QueueRow)()
    Public Property Held As New List(Of QueueRow)()
End Class

Public Class CandidateInfo
    Public Property Repo As String = ""
    Public Property Id As String
    Public Property Status As String = ""

    Public ReadOnly Property Target As String
        Get
            Return If(Id Is Nothing, Repo, $"{Repo}:{Id}")
        End Get
    End Property
End Class

' Read-only views of the portfolio root. Every read shares the file for writing and deletion: the runner appends to
' runs.jsonl and replaces worker-*.json and PORTFOLIO_QUEUE.md by rename, and a reader that locks them out would
' make the runner's own write fail.
Public Class PortfolioState
    Public Const Unscheduled As Long = Long.MaxValue

    Public Shared ReadOnly Property PortfolioRoot As String
        Get
            Dim env = Environment.GetEnvironmentVariable("SZA_PORTFOLIO_ROOT")
            If Not String.IsNullOrWhiteSpace(env) Then Return env
            Return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".sza", "portfolio")
        End Get
    End Property

    Public Shared Function GetReposJsonPath() As String
        Return Path.Combine(PortfolioRoot, "repos.json")
    End Function

    ' paths.portfolioQueue in the registry overrides the default, as in pq.ps1 Get-PqQueuePath.
    Public Shared Function GetPortfolioQueuePath() As String
        Try
            Using doc = ReadJson(GetReposJsonPath())
                If doc IsNot Nothing Then
                    Dim paths As JsonElement
                    If doc.RootElement.ValueKind = JsonValueKind.Object AndAlso doc.RootElement.TryGetProperty("paths", paths) Then
                        Dim over = Str(paths, "portfolioQueue")
                        If Not String.IsNullOrWhiteSpace(over) Then
                            Return If(Path.IsPathFullyQualified(over), over, Path.GetFullPath(Path.Combine(PortfolioRoot, over)))
                        End If
                    End If
                End If
            End Using
        Catch
        End Try
        Return Path.Combine(PortfolioRoot, "PORTFOLIO_QUEUE.md")
    End Function

    ''' <summary>
    ''' Resolves the ticket queue file for a repository (defaulting to PLAN/RELEASE_QUEUE.md or reading .sza-profile.json paths.releaseQueue).
    ''' </summary>
    Public Shared Function GetTicketQueuePath(repo As RepoInfo) As String
        If repo Is Nothing OrElse String.IsNullOrWhiteSpace(repo.Path) Then Return ""
        Dim repoPath = repo.Path
        Dim profileFile = Path.Combine(repoPath, ".sza-profile.json")
        If File.Exists(profileFile) Then
            Try
                Using doc = ReadJson(profileFile)
                    If doc IsNot Nothing Then
                        Dim paths As JsonElement
                        If doc.RootElement.ValueKind = JsonValueKind.Object AndAlso doc.RootElement.TryGetProperty("paths", paths) Then
                            Dim customRel = Str(paths, "releaseQueue")
                            If Not String.IsNullOrWhiteSpace(customRel) Then
                                Dim full = If(Path.IsPathFullyQualified(customRel), customRel, Path.Combine(repoPath, customRel))
                                If File.Exists(full) Then Return full
                            End If
                        End If
                    End If
                End Using
            Catch
            End Try
        End If

        Dim candidates = {
            "PLAN\RELEASE_QUEUE.md",
            "PLAN\release-queue.md",
            "DEV\plan\RELEASE_QUEUE.md",
            "docs\specifications\RELEASE_QUEUE.md",
            "PLAN\INDEX.md",
            "PLAN\spec-catalog.jsonl",
            "PLAN\README.md",
            "tasks\README.md",
            "tasks\INDEX.md"
        }
        For Each cand In candidates
            Dim full = Path.Combine(repoPath, cand)
            If File.Exists(full) Then Return full
        Next

        Return Path.Combine(repoPath, "PLAN\RELEASE_QUEUE.md")
    End Function

    ' ---- shared readers ----

    Private Shared Function OpenShared(path As String) As FileStream
        Return New FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite Or FileShare.Delete)
    End Function

    Public Shared Function ReadAllTextShared(path As String) As String
        Using fs = OpenShared(path), sr As New StreamReader(fs, Encoding.UTF8, True)
            Return sr.ReadToEnd()
        End Using
    End Function

    ' The last maxBytes of a file, split into lines; the first, possibly partial, line is dropped when cut.
    Private Shared Function ReadTailLines(path As String, maxBytes As Integer) As String()
        Using fs = OpenShared(path)
            Dim start = Math.Max(0L, fs.Length - maxBytes)
            fs.Seek(start, SeekOrigin.Begin)
            Using sr As New StreamReader(fs, Encoding.UTF8, start = 0)
                Dim lines = sr.ReadToEnd().Split({vbCrLf, vbLf}, StringSplitOptions.None)
                If start > 0 AndAlso lines.Length > 0 Then lines = lines.Skip(1).ToArray()
                Return lines
            End Using
        End Using
    End Function

    Private Shared Function ReadJson(path As String) As JsonDocument
        If Not File.Exists(path) Then Return Nothing
        Return JsonDocument.Parse(ReadAllTextShared(path))
    End Function

    ' Tolerant property reads: a missing key or a JSON null gives the default instead of throwing.
    Private Shared Function Str(e As JsonElement, name As String) As String
        Dim v As JsonElement
        If e.ValueKind <> JsonValueKind.Object OrElse Not e.TryGetProperty(name, v) Then Return ""
        Select Case v.ValueKind
            Case JsonValueKind.String : Return v.GetString()
            Case JsonValueKind.Null, JsonValueKind.Undefined : Return ""
            Case Else : Return v.GetRawText()
        End Select
    End Function

    Private Shared Function Bool(e As JsonElement, name As String, def As Boolean) As Boolean
        Dim v As JsonElement
        If e.ValueKind <> JsonValueKind.Object OrElse Not e.TryGetProperty(name, v) Then Return def
        If v.ValueKind = JsonValueKind.True Then Return True
        If v.ValueKind = JsonValueKind.False Then Return False
        Return def
    End Function

    Private Shared Function Num(e As JsonElement, name As String, def As Double) As Double
        Dim v As JsonElement
        If e.ValueKind <> JsonValueKind.Object OrElse Not e.TryGetProperty(name, v) Then Return def
        Dim d As Double
        If v.ValueKind = JsonValueKind.Number AndAlso v.TryGetDouble(d) Then Return d
        Return def
    End Function

    ' ---- STOP ----

    ' STOP is JSON written by 'pq stop': { level: pass|kill, by, at, reason }.
    Public Shared Function GetStopInfo() As StopInfo
        Dim info As New StopInfo()
        Dim stopFile = Path.Combine(PortfolioRoot, "STOP")
        If Not File.Exists(stopFile) Then Return info
        info.Present = True
        info.Level = "pass"
        Try
            Using doc = ReadJson(stopFile)
                If doc IsNot Nothing Then
                    Dim level = Str(doc.RootElement, "level")
                    If Not String.IsNullOrWhiteSpace(level) Then info.Level = level
                End If
            End Using
        Catch
        End Try
        Return info
    End Function

    ' ---- PORTFOLIO_QUEUE.md (the grammar of lib/queue-file.ps1 Get-PqQueueLine) ----

    Private Shared ReadOnly RowPattern As New Regex("^(?<repo>[a-z][a-z0-9-]*)(?::(?<id>\*|[^\s:#_]+)(?:_[^\s#]*)?)?$")
    Private Shared ReadOnly HeaderPattern As New Regex("^ticket\s+changed\s+status$")
    ' The columns the sync writes after the token: 'yy-MM-dd HH:mm  <status>'.
    ' The status word after the optional changed date and time ('26-10-29 01:37  Approved', '26-10-29  Approved',
    ' 'Approved (owner order..)'); the rest of the line is a note.
    Private Shared ReadOnly StatusPattern As New Regex("^(?:\d{2}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?\s+)?(?<status>In Progress|[A-Za-z]+)")

    ' The statuses the picker offers on their own (spec-next-preflight.ps1 $eligibleStatuses), less BlockByOtherTask,
    ' which it offers only once the blocker is closed - in a night's queue almost never. A row with no status column
    ' is counted: the ledger, not the file, decides it.
    Private Shared ReadOnly RunnableStatuses As New HashSet(Of String)(
        {"Draft", "Approved", "Tactical", "In Progress", "Implemented", "Partial", "Broken"}, StringComparer.Ordinal)

    ' A ticket row the runner would take, judged from the queue file alone; pq dry-run asks the pickers for the exact plan.
    Public Shared Function IsRunnable(row As QueueRow) As Boolean
        Return row.Id IsNot Nothing AndAlso (String.IsNullOrEmpty(row.Status) OrElse RunnableStatuses.Contains(row.Status))
    End Function

    Public Shared Function ReadQueue() As QueueSnapshot
        Dim snap As New QueueSnapshot()
        Dim qPath = GetPortfolioQueuePath()
        If Not File.Exists(qPath) Then Return snap
        snap.Present = True

        Dim text As String
        Try
            text = ReadAllTextShared(qPath)
        Catch
            Return snap
        End Try

        Dim package As Long = -1
        Dim inHold = False
        Dim lineNo = 0
        Dim seenActive As New HashSet(Of String)(StringComparer.Ordinal)
        Dim seenHeld As New HashSet(Of String)(StringComparer.Ordinal)
        For Each line In text.Split({vbCrLf, vbLf}, StringSplitOptions.None)
            lineNo += 1
            Dim hashAt = line.IndexOf("#"c)
            Dim body = If(hashAt >= 0, line.Substring(0, hashAt), line).Trim()
            If body.Length = 0 Then Continue For
            If Regex.IsMatch(body, "^\d+$") Then
                If Not Long.TryParse(body, package) OrElse package >= Unscheduled Then package = Unscheduled - 1
                inHold = False
                Continue For
            End If
            If body = "--" Then
                package = Unscheduled
                inHold = False
                Continue For
            End If
            If body.Equals("hold", StringComparison.OrdinalIgnoreCase) Then
                inHold = True
                Continue For
            End If
            If HeaderPattern.IsMatch(body) Then Continue For

            Dim parts = Regex.Split(body, "\s+", RegexOptions.None)
            Dim m = RowPattern.Match(parts(0))
            If Not m.Success Then Continue For
            Dim idGroup = m.Groups("id")
            Dim row As New QueueRow With {
                .Package = package,
                .Repo = m.Groups("repo").Value,
                .Id = If(idGroup.Success AndAlso idGroup.Value <> "*", idGroup.Value, Nothing),
                .Line = lineNo
            }
            If parts.Length > 1 Then
                Dim sm = StatusPattern.Match(String.Join(" ", parts.Skip(1)))
                If sm.Success Then row.Status = sm.Groups("status").Value
            End If

            If Not If(inHold, seenHeld, seenActive).Add(row.Target) Then Continue For
            If inHold Then snap.Held.Add(row) Else snap.Rows.Add(row)
        Next

        snap.Rows = snap.Rows.OrderBy(Function(r) r.Package).ThenBy(Function(r) r.Line).ToList()
        Return snap
    End Function

    ' ---- registry ----

    Public Shared Function GetRepos(Optional queue As QueueSnapshot = Nothing) As List(Of RepoInfo)
        Dim list As New List(Of RepoInfo)()
        If queue Is Nothing Then queue = ReadQueue()

        Dim heldKeys As New HashSet(Of String)(queue.Held.Where(Function(r) r.Id Is Nothing).Select(Function(r) r.Repo), StringComparer.Ordinal)
        Dim counts = queue.Rows.Concat(queue.Held.Where(Function(r) r.Id IsNot Nothing)).GroupBy(Function(r) r.Repo).ToDictionary(Function(g) g.Key, Function(g) g.Count(), StringComparer.Ordinal)
        Dim heldTickets As New HashSet(Of String)(queue.Held.Where(Function(r) r.Id IsNot Nothing).Select(Function(r) r.Target), StringComparer.Ordinal)
        Dim blocked = queue.Rows.Concat(queue.Held).Where(Function(r) r.Id IsNot Nothing AndAlso r.Status IsNot Nothing AndAlso r.Status.StartsWith("Block", StringComparison.Ordinal)).GroupBy(Function(r) r.Repo).ToDictionary(Function(g) g.Key, Function(g) g.Count(), StringComparer.Ordinal)
        Dim runnable = queue.Rows.Where(Function(r) IsRunnable(r) AndAlso Not heldTickets.Contains(r.Target)).GroupBy(Function(r) r.Repo).ToDictionary(Function(g) g.Key, Function(g) g.Count(), StringComparer.Ordinal)

        Try
            Using doc = ReadJson(GetReposJsonPath())
                If doc Is Nothing Then Return list
                Dim repos As JsonElement
                If doc.RootElement.ValueKind <> JsonValueKind.Object OrElse Not doc.RootElement.TryGetProperty("repos", repos) _
                    OrElse repos.ValueKind <> JsonValueKind.Array Then Return list
                ' permissionMode may be inherited from the registry (pq.ps1 help).
                Dim defaultMode = Str(doc.RootElement, "permissionMode")
                For Each item In repos.EnumerateArray()
                    Dim r As New RepoInfo With {
                        .Key = Str(item, "key"),
                        .Path = Str(item, "path"),
                        .Enabled = Bool(item, "enabled", False),
                        .Role = Str(item, "role"),
                        .PermissionMode = Str(item, "permissionMode"),
                        .MaxWorkers = CInt(Num(item, "maxWorkers", 1)),
                        .Concurrent = Bool(item, "concurrent", False),
                        .RegistryHold = Bool(item, "hold", False),
                        .Rank = CLng(Num(item, "rank", 100)),
                        .Index = list.Count
                    }
                    If String.IsNullOrWhiteSpace(r.PermissionMode) AndAlso Not String.IsNullOrWhiteSpace(defaultMode) Then
                        r.PermissionMode = $"{defaultMode} (registry)"
                    End If
                    r.QueueHold = heldKeys.Contains(r.Key)
                    Dim n As Integer
                    If counts.TryGetValue(r.Key, n) Then r.QueuedRows = n
                    If r.Enabled AndAlso Not r.IsHeld AndAlso runnable.TryGetValue(r.Key, n) Then r.RunnableRows = n
                    If blocked.TryGetValue(r.Key, n) Then r.BlockedRows = n
                    list.Add(r)
                Next
            End Using
        Catch
        End Try

        ' In project order, as pq rank prints it.
        Return list.OrderBy(Function(r) r.Rank).ThenBy(Function(r) r.Index).ToList()
    End Function

    ' The first active, scheduled row of an enabled repository that nothing holds. pq ranks with the repositories'
    ' own pickers as well (pq dry-run, pq status), which takes far too long for a refresh timer; this is the
    ' queue file's own answer and usually the same one.
    Public Shared Function GetQueueTop(queue As QueueSnapshot, repos As List(Of RepoInfo)) As CandidateInfo
        Dim byKey = repos.Where(Function(r) r.Key <> "").GroupBy(Function(r) r.Key).ToDictionary(Function(g) g.Key, Function(g) g.First(), StringComparer.Ordinal)
        Dim heldTickets As New HashSet(Of String)(queue.Held.Where(Function(r) r.Id IsNot Nothing).Select(Function(r) r.Target), StringComparer.Ordinal)
        For Each row In queue.Rows
            If row.Package = Unscheduled Then Exit For
            Dim repo As RepoInfo = Nothing
            If Not byKey.TryGetValue(row.Repo, repo) OrElse Not repo.Enabled OrElse repo.IsHeld Then Continue For
            If row.Id IsNot Nothing AndAlso heldTickets.Contains(row.Target) Then Continue For
            If row.Id IsNot Nothing AndAlso Not IsRunnable(row) Then Continue For
            Return New CandidateInfo With {.Repo = row.Repo, .Id = row.Id, .Status = row.Status}
        Next
        Return Nothing
    End Function

    ' ---- run/worker-<k>.json ----

    Public Shared Function GetActiveWorkers() As List(Of WorkerInfo)
        Dim list As New List(Of WorkerInfo)()
        Dim runDir = Path.Combine(PortfolioRoot, "run")
        If Not Directory.Exists(runDir) Then Return list

        For Each file In Directory.GetFiles(runDir, "worker-*.json")
            Dim match = Regex.Match(Path.GetFileName(file), "^worker-(\d+)\.json$")
            If Not match.Success Then Continue For
            Try
                Using doc = ReadJson(file)
                    If doc Is Nothing Then Continue For
                    Dim root = doc.RootElement
                    Dim w As New WorkerInfo With {
                        .Slot = Integer.Parse(match.Groups(1).Value, CultureInfo.InvariantCulture),
                        .Pid = CInt(Num(root, "pid", 0)),
                        .StartedAt = Str(root, "startedAt"),
                        .Repository = Str(root, "repository"),
                        .Ticket = Str(root, "ticket"),
                        .Title = Str(root, "title"),
                        .Since = Str(root, "since")
                    }
                    w.Alive = IsStateOwnerAlive(w.Pid, w.StartedAt)

                    Dim since As DateTimeOffset
                    If DateTimeOffset.TryParse(w.Since, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, since) Then
                        Dim elapsed = DateTimeOffset.UtcNow - since
                        If elapsed.Ticks >= 0 Then w.Elapsed = $"{Math.Floor(elapsed.TotalMinutes):00}m {elapsed.Seconds:00}s"
                    End If
                    list.Add(w)
                End Using
            Catch
            End Try
        Next

        list.Sort(Function(a, b) a.Slot.CompareTo(b.Slot))
        Return list
    End Function

    ' lib/loop.ps1 Test-PqStateOwner: the pid is alive AND its start time matches, so a reused pid is not a worker.
    Private Shared Function IsStateOwnerAlive(pid As Integer, startedAt As String) As Boolean
        If pid <= 0 Then Return False
        Try
            Using p = Process.GetProcessById(pid)
                If p.HasExited Then Return False
                If String.IsNullOrWhiteSpace(startedAt) Then Return True
                Return p.StartTime.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture) = startedAt
            End Using
        Catch
            Return False
        End Try
    End Function

    ' ---- runs.jsonl ----

    Public Shared Function GetRecentPasses(Optional count As Integer = 30) As List(Of PassInfo)
        Dim list As New List(Of PassInfo)()
        Dim runsFile = Path.Combine(PortfolioRoot, "runs.jsonl")
        If Not File.Exists(runsFile) Then Return list

        Dim lines As String()
        Try
            ' A row is well under 1 KB; 256 KB holds far more than any count the panel asks for.
            lines = ReadTailLines(runsFile, 256 * 1024)
        Catch
            Return list
        End Try

        For i = lines.Length - 1 To 0 Step -1
            If list.Count >= count Then Exit For
            Dim line = lines(i).Trim()
            If line.Length = 0 Then Continue For
            Try
                Using doc = JsonDocument.Parse(line)
                    Dim r = doc.RootElement
                    list.Add(New PassInfo With {
                        .Run = Str(r, "run"),
                        .Pass = Str(r, "pass"),
                        .Repo = Str(r, "repo"),
                        .Id = Str(r, "id"),
                        .Agent = Str(r, "agent"),
                        .Model = Str(r, "model"),
                        .Complexity = Str(r, "complexity"),
                        .StatusBefore = Str(r, "statusBefore"),
                        .StatusAfter = Str(r, "statusAfter"),
                        .Moved = Bool(r, "moved", False),
                        .Outcome = Str(r, "outcome"),
                        .ExitCode = CInt(Num(r, "exitCode", -1)),
                        .Seconds = Num(r, "seconds", 0),
                        .FinishedAt = Str(r, "finishedAt")
                    })
                End Using
            Catch
            End Try
        Next

        Return list
    End Function
End Class
