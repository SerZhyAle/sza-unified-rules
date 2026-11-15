Option Explicit On
Option Strict On

''' <summary>
''' Specification draft capture dialog per APP-BEHAVIOUR, BUTTONS, and APP-STYLE.
''' </summary>
Public Class FormNewSpec
    Inherits Form

    Private cmbProject As ComboBox
    Private rdoFeature As RadioButton
    Private rdoBug As RadioButton
    Private rdoHotfix As RadioButton
    Private txtSlug As TextBox
    Private cmbComplexity As ComboBox
    Private chkPin As CheckBox
    Private txtDescription As TextBox
    Private btnDraft As Button
    Private btnCancel As Button
    Private lblStatus As Label
    Private lstAttachments As ListBox
    Private btnAddFile As Button
    Private btnPasteImage As Button
    Private btnRemoveAttachment As Button

    Private _defaultProjectKey As String = ""
    Private _pinTickedByType As Boolean = False
    Private _capturing As Boolean = False
    ' Pasted images live here until the dialog closes; spec-draft copies them into the ticket before it returns.
    Private ReadOnly _pasteDir As String = Path.Combine(Path.GetTempPath(), $"pq_attach_{Guid.NewGuid():N}")

    ' What spec-draft printed, for the main window's console.
    Public Property ResultText As String = ""

    Public Sub New(Optional defaultProjectKey As String = "")
        _defaultProjectKey = defaultProjectKey
        InitializeComponent()
    End Sub

    Private Sub InitializeComponent()
        ' The caption is short on purpose: a long one is cut by the window buttons (APP-BEHAVIOUR rule 2).
        Me.Text = "New Specification (/spec-draft)"
        Me.AutoScaleDimensions = New SizeF(7.0F, 15.0F)
        Me.AutoScaleMode = AutoScaleMode.Font
        Me.ClientSize = New Size(780, 720)
        ' Narrower than this the Type row (three radio buttons on one line) no longer fits.
        Me.MinimumSize = New Size(760, 660)
        Me.StartPosition = FormStartPosition.CenterParent
        Me.Font = New Font("Segoe UI", 9.0F)
        Me.SuspendLayout()

        ' --- Bottom Panel (Status & Buttons, docked bottom) ---
        Dim pnlBottom As New Panel With {
            .Name = "pnlBottom",
            .Dock = DockStyle.Bottom,
            .Height = 84,
            .Padding = New Padding(20, 4, 20, 10)
        }

        lblStatus = New Label With {
            .Name = "lblStatus",
            .Dock = DockStyle.Top,
            .Height = 26,
            .TextAlign = ContentAlignment.MiddleLeft,
            .Font = New Font("Segoe UI", 9.0F)
        }

        Dim pnlButtons As New FlowLayoutPanel With {
            .Name = "pnlButtons",
            .Dock = DockStyle.Bottom,
            .Height = 42,
            .FlowDirection = FlowDirection.RightToLeft,
            .WrapContents = False,
            .Margin = Padding.Empty,
            .Padding = Padding.Empty
        }

        ' BUTTONS section 3: width is the caption plus padding (never a fixed or equal width), height 32.
        btnCancel = New Button With {
            .Name = "btnCancel",
            .Text = "Cancel",
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .MinimumSize = New Size(0, 32),
            .Padding = New Padding(12, 0, 12, 0),
            .Margin = New Padding(0, 2, 8, 0),
            .AccessibleName = "Cancel Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnCancel.Click, Sub() Me.DialogResult = DialogResult.Cancel

        btnDraft = New Button With {
            .Name = "btnDraft",
            .Text = "📝 &Create Specification",
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .MinimumSize = New Size(0, 32),
            .Padding = New Padding(12, 0, 12, 0),
            .Margin = New Padding(0, 2, 0, 0),
            .Font = New Font("Segoe UI", 9.5F, FontStyle.Bold),
            .AccessibleName = "Create Specification Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnDraft.Click, AddressOf BtnDraft_Click

        ' The strip fills from the right, so the first control sits rightmost: Create first, then Cancel to its
        ' left - reading order Cancel, then the affirmative action (BUTTONS section 4 rule 4).
        pnlButtons.Controls.AddRange({btnDraft, btnCancel})
        pnlBottom.Controls.AddRange({pnlButtons, lblStatus})

        ' --- Top Controls: a caption column and one shared editor column (WINDOWS-UI section 4). No editor is sized as a
        '     percentage of a spanned row, so nothing is cut or wrapped away at any DPI (APP-BEHAVIOUR rule 2) ---
        Dim tblTop As New TableLayoutPanel With {
            .Name = "tblTop",
            .Dock = DockStyle.Top,
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .Padding = New Padding(20, 16, 20, 6),
            .ColumnCount = 2,
            .RowCount = 6
        }
        tblTop.SuspendLayout()

        tblTop.ColumnStyles.Add(New ColumnStyle(SizeType.AutoSize))
        tblTop.ColumnStyles.Add(New ColumnStyle(SizeType.Percent, 100.0F))

        For i = 0 To 5
            tblTop.RowStyles.Add(New RowStyle(SizeType.AutoSize))
        Next

        ' An editor fills the editor column up to this width and stays left-aligned beyond it; the longest
        ' complexity item is about 200 px, so nothing in a dropdown is cut.
        Dim editorMax As New Size(360, 0)

        ' Row 0: Target Project
        Dim lblProj As New Label With {
            .Name = "lblProj",
            .Text = "Target &Project:",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(0, 0, 16, 8)
        }
        cmbProject = New ComboBox With {
            .Name = "cmbProject",
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .Anchor = AnchorStyles.Left Or AnchorStyles.Right,
            .MaximumSize = editorMax,
            .Margin = New Padding(0, 0, 0, 8),
            .AccessibleName = "Target Project Dropdown"
        }

        ' Row 1: Complexity
        Dim lblComp As New Label With {
            .Name = "lblComp",
            .Text = "&Complexity:",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(0, 0, 16, 8)
        }
        cmbComplexity = New ComboBox With {
            .Name = "cmbComplexity",
            .DropDownStyle = ComboBoxStyle.DropDownList,
            .Anchor = AnchorStyles.Left Or AnchorStyles.Right,
            .MaximumSize = editorMax,
            .Margin = New Padding(0, 0, 0, 8),
            .AccessibleName = "Complexity Dropdown"
        }
        cmbComplexity.Items.AddRange({
            "medium - not assessed at capture",
            "light - simple fix or small chore",
            "hard - complex task or deep defect"
        })
        cmbComplexity.SelectedIndex = 0

        tblTop.Controls.Add(lblProj, 0, 0)
        tblTop.Controls.Add(cmbProject, 1, 0)
        tblTop.Controls.Add(lblComp, 0, 1)
        tblTop.Controls.Add(cmbComplexity, 1, 1)

        ' Row 2: Type / prefix. The three radio buttons stay on one line (WrapContents off); a wrapped third
        ' button dropped under the caption column and read as a separate field.
        Dim lblType As New Label With {
            .Name = "lblType",
            .Text = "Type:",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(0, 0, 16, 8)
        }
        Dim pnlType As New FlowLayoutPanel With {
            .Name = "pnlType",
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .Anchor = AnchorStyles.Left,
            .WrapContents = False,
            .FlowDirection = FlowDirection.LeftToRight,
            .Margin = New Padding(0, 0, 0, 8)
        }
        rdoFeature = New RadioButton With {
            .Name = "rdoFeature",
            .Text = "&Feature / Task",
            .AutoSize = True,
            .Checked = True,
            .Margin = New Padding(0, 0, 20, 0)
        }
        AddHandler rdoFeature.CheckedChanged, AddressOf RdoType_CheckedChanged

        rdoBug = New RadioButton With {
            .Name = "rdoBug",
            .Text = "&Bug / Defect (bugfix-)",
            .AutoSize = True,
            .Margin = New Padding(0, 0, 20, 0)
        }
        AddHandler rdoBug.CheckedChanged, AddressOf RdoType_CheckedChanged

        rdoHotfix = New RadioButton With {
            .Name = "rdoHotfix",
            .Text = "&Urgent Blocker (hotfix-)",
            .AutoSize = True,
            .Margin = New Padding(0, 0, 0, 0)
        }
        AddHandler rdoHotfix.CheckedChanged, AddressOf RdoType_CheckedChanged

        pnlType.Controls.AddRange({rdoFeature, rdoBug, rdoHotfix})
        tblTop.Controls.Add(lblType, 0, 2)
        tblTop.Controls.Add(pnlType, 1, 2)

        ' Row 3: Ticket Slug
        Dim lblSlug As New Label With {
            .Name = "lblSlug",
            .Text = "Ticket &Slug (optional):",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(0, 0, 16, 8)
        }
        txtSlug = New TextBox With {
            .Name = "txtSlug",
            .Anchor = AnchorStyles.Left Or AnchorStyles.Right,
            .MaximumSize = editorMax,
            .Font = New Font("Consolas", 9.5F),
            .Margin = New Padding(0, 0, 0, 8),
            .AccessibleName = "Ticket Slug Input"
        }
        tblTop.Controls.Add(lblSlug, 0, 3)
        tblTop.Controls.Add(txtSlug, 1, 3)

        ' Row 4: Pin, under the slug it belongs to
        chkPin = New CheckBox With {
            .Name = "chkPin",
            .Text = "Pin to &top of queue (-Pin)",
            .AutoSize = True,
            .Anchor = AnchorStyles.Left,
            .Margin = New Padding(0, 0, 0, 8),
            .AccessibleName = "Pin to top checkbox"
        }
        tblTop.Controls.Add(chkPin, 1, 4)

        ' Row 5: Description header
        Dim lblDesc As New Label With {
            .Name = "lblDesc",
            .Text = "&Task or Problem Description (in your own words; spec-draft will turn this into an aligned spec):",
            .AutoSize = True,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold),
            .Margin = New Padding(0, 4, 0, 4)
        }
        tblTop.Controls.Add(lblDesc, 0, 5)
        tblTop.SetColumnSpan(lblDesc, 2)

        tblTop.ResumeLayout(False)
        tblTop.PerformLayout()

        ' --- Center Content: Task Description Multiline Editor ---
        Dim pnlContent As New Panel With {
            .Name = "pnlContent",
            .Dock = DockStyle.Fill,
            .Padding = New Padding(20, 0, 20, 0)
        }
        txtDescription = New TextBox With {
            .Name = "txtDescription",
            .Dock = DockStyle.Fill,
            .Multiline = True,
            .AcceptsReturn = True,
            .ScrollBars = ScrollBars.Vertical,
            .Font = New Font("Segoe UI", 9.5F),
            .AccessibleName = "Task Description Text"
        }
        pnlContent.Controls.Add(txtDescription)

        ' --- Attachments: files and pasted screenshots, copied into the ticket folder by spec-draft ---
        ' The panel is tall enough for its caption, a list of several rows and one row of command buttons; the buttons
        ' flow horizontally at their content width and wrap whole when the window is narrow (BUTTONS section 4).
        Dim pnlAttach As New Panel With {
            .Name = "pnlAttach",
            .Dock = DockStyle.Bottom,
            .Height = 168,
            .Padding = New Padding(20, 8, 20, 4)
        }
        Dim lblAttach As New Label With {
            .Name = "lblAttach",
            .Text = "&Attachments (screenshots, logs):",
            .Dock = DockStyle.Top,
            .Height = 24,
            .TextAlign = ContentAlignment.MiddleLeft,
            .Font = New Font("Segoe UI", 9.0F, FontStyle.Bold)
        }
        Dim pnlAttachButtons As New FlowLayoutPanel With {
            .Name = "pnlAttachButtons",
            .Dock = DockStyle.Bottom,
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .FlowDirection = FlowDirection.LeftToRight,
            .WrapContents = True,
            .Padding = Padding.Empty
        }
        btnAddFile = New Button With {
            .Name = "btnAddFile",
            .Text = "Add &File..",
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .MinimumSize = New Size(0, 32),
            .Padding = New Padding(12, 0, 12, 0),
            .Margin = New Padding(0, 8, 8, 0),
            .AccessibleName = "Add File Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnAddFile.Click, AddressOf BtnAddFile_Click
        btnPasteImage = New Button With {
            .Name = "btnPasteImage",
            .Text = "Paste &Image",
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .MinimumSize = New Size(0, 32),
            .Padding = New Padding(12, 0, 12, 0),
            .Margin = New Padding(0, 8, 8, 0),
            .AccessibleName = "Paste Image Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnPasteImage.Click, AddressOf BtnPasteImage_Click
        btnRemoveAttachment = New Button With {
            .Name = "btnRemoveAttachment",
            .Text = "&Remove",
            .AutoSize = True,
            .AutoSizeMode = AutoSizeMode.GrowAndShrink,
            .MinimumSize = New Size(0, 32),
            .Padding = New Padding(12, 0, 12, 0),
            .Margin = New Padding(0, 8, 0, 0),
            .AccessibleName = "Remove Attachment Button",
            .AccessibleRole = AccessibleRole.PushButton
        }
        AddHandler btnRemoveAttachment.Click, AddressOf BtnRemoveAttachment_Click
        pnlAttachButtons.Controls.AddRange({btnAddFile, btnPasteImage, btnRemoveAttachment})
        lstAttachments = New ListBox With {
            .Name = "lstAttachments",
            .Dock = DockStyle.Fill,
            .BorderStyle = BorderStyle.FixedSingle,
            .SelectionMode = SelectionMode.MultiExtended,
            .HorizontalScrollbar = True,
            .IntegralHeight = False,
            .AccessibleName = "Attachments List"
        }
        ' Docking runs from the last control added to the first: caption (top), buttons (bottom), then the list fills.
        pnlAttach.Controls.Add(lstAttachments)
        pnlAttach.Controls.Add(pnlAttachButtons)
        pnlAttach.Controls.Add(lblAttach)

        ' Container assembly in correct docking z-order
        Me.Controls.Add(pnlContent)
        Me.Controls.Add(pnlAttach)
        Me.Controls.Add(tblTop)
        Me.Controls.Add(pnlBottom)
        pnlContent.BringToFront()

        ' APP-BEHAVIOUR Rule 1
        Me.AcceptButton = btnDraft
        Me.CancelButton = btnCancel

        ' Tab order follows reading order, and each caption sits right before its editor so that its mnemonic
        ' (Alt+letter) lands there; Cancel comes before Create, as they read.
        tblTop.TabIndex = 0
        lblProj.TabIndex = 0
        cmbProject.TabIndex = 1
        lblComp.TabIndex = 2
        cmbComplexity.TabIndex = 3
        lblType.TabIndex = 4
        pnlType.TabIndex = 5
        rdoFeature.TabIndex = 0
        rdoBug.TabIndex = 1
        rdoHotfix.TabIndex = 2
        lblSlug.TabIndex = 6
        txtSlug.TabIndex = 7
        chkPin.TabIndex = 8
        lblDesc.TabIndex = 9
        pnlContent.TabIndex = 1
        txtDescription.TabIndex = 0
        pnlAttach.TabIndex = 2
        lblAttach.TabIndex = 0
        lstAttachments.TabIndex = 1
        pnlAttachButtons.TabIndex = 2
        btnAddFile.TabIndex = 0
        btnPasteImage.TabIndex = 1
        btnRemoveAttachment.TabIndex = 2
        pnlBottom.TabIndex = 3
        lblStatus.TabIndex = 0
        pnlButtons.TabIndex = 1
        btnCancel.TabIndex = 0
        btnDraft.TabIndex = 1

        Me.ResumeLayout(False)
        Me.PerformLayout()
    End Sub

    Protected Overrides Sub OnLoad(e As EventArgs)
        MyBase.OnLoad(e)
        LoadProjects()
        ApplyDialogTheme()
        AddHandler ThemeService.ThemeChanged, Sub() ApplyDialogTheme()

        ' When the project is already chosen (the dialog opens on the selected repository) the cursor starts where
        ' the typing starts, in the description; otherwise it starts at the project dropdown.
        If Not String.IsNullOrWhiteSpace(_defaultProjectKey) AndAlso cmbProject.SelectedIndex >= 0 Then
            Me.ActiveControl = txtDescription
        End If
    End Sub

    ' ThemeService has no list-box branch (a CheckedListBox on another form would change with it), so the attachments
    ' list takes the same field colours the text boxes get; left alone it stays white on the dark theme.
    Private Sub ApplyDialogTheme()
        ThemeService.ApplyTheme(Me)
        Dim p = ThemeService.Palette
        lstAttachments.BackColor = If(ThemeService.IsDark, p.SurfaceSunken, p.WindowBackground)
        lstAttachments.ForeColor = p.TextPrimary
    End Sub

    Private Sub LoadProjects()
        cmbProject.Items.Clear()
        Dim repos = PortfolioState.GetRepos()
        Dim selIdx = -1

        For i = 0 To repos.Count - 1
            Dim r = repos(i)
            cmbProject.Items.Add(r.Key)
            If Not String.IsNullOrWhiteSpace(_defaultProjectKey) AndAlso r.Key.Equals(_defaultProjectKey, StringComparison.OrdinalIgnoreCase) Then
                selIdx = i
            End If
        Next

        If selIdx >= 0 Then
            cmbProject.SelectedIndex = selIdx
        ElseIf cmbProject.Items.Count > 0 Then
            cmbProject.SelectedIndex = 0
        End If
    End Sub

    Private Sub RdoType_CheckedChanged(sender As Object, e As EventArgs)
        Dim current = txtSlug.Text.Trim()
        Dim baseSlug = current
        For Each prefix In {"bugfix-", "hotfix-"}
            If baseSlug.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) Then
                baseSlug = baseSlug.Substring(prefix.Length)
            End If
        Next

        If rdoBug.Checked Then
            txtSlug.Text = "bugfix-" & baseSlug
        ElseIf rdoHotfix.Checked Then
            txtSlug.Text = "hotfix-" & baseSlug
        Else
            txtSlug.Text = baseSlug
        End If

        ' An urgent blocker goes first in the queue: the type ticks the pin box, and leaving the type takes back only
        ' a tick the type made.
        If rdoHotfix.Checked AndAlso Not chkPin.Checked Then
            chkPin.Checked = True
            _pinTickedByType = True
        ElseIf Not rdoHotfix.Checked AndAlso _pinTickedByType Then
            chkPin.Checked = False
            _pinTickedByType = False
        End If
    End Sub

    Private Async Sub BtnDraft_Click(sender As Object, e As EventArgs)
        Dim projKey = cmbProject.SelectedItem?.ToString()
        Dim slug = txtSlug.Text.Trim()
        Dim desc = txtDescription.Text.Trim()
        Dim comp = cmbComplexity.SelectedItem?.ToString()
        Dim pin = chkPin.Checked

        If String.IsNullOrWhiteSpace(projKey) Then
            SetStatus("Please select a target repository project.", isError:=True)
            Return
        End If

        ' An empty slug or the bare type prefix is fine: spec-draft names the ticket from the description.
        If String.IsNullOrWhiteSpace(desc) Then
            SetStatus("Please provide a description of the task or defect.", isError:=True)
            txtDescription.Focus()
            Return
        End If

        Dim compToken = "medium"
        If comp.StartsWith("light") Then
            compToken = "light"
        ElseIf comp.StartsWith("hard") Then
            compToken = "hard"
        End If

        btnDraft.Enabled = False
        btnCancel.Enabled = False
        SetStatus("Generating ticket specification via spec-draft.ps1..", isError:=False)

        Dim attachments As New List(Of String)
        For Each item In lstAttachments.Items
            attachments.Add(item.ToString())
        Next

        _capturing = True
        Dim res As CliResult = Nothing
        Try
            res = Await PqCli.DraftSpecAsync(projKey, slug, desc, compToken, pin, attachments)
        Finally
            _capturing = False
        End Try
        If res.Success Then
            ResultText = res.Output.Trim()
            Me.DialogResult = DialogResult.OK
        Else
            SetStatus(res.Message, isError:=True)
            btnDraft.Enabled = True
            btnCancel.Enabled = True
        End If
    End Sub

    Private Sub BtnAddFile_Click(sender As Object, e As EventArgs)
        Using dlg As New OpenFileDialog With {
            .Title = "Attach files to the specification",
            .Multiselect = True,
            .CheckFileExists = True
        }
            If dlg.ShowDialog(Me) <> DialogResult.OK Then Return
            For Each f In dlg.FileNames
                AddAttachment(f)
            Next
        End Using
    End Sub

    ' The clipboard holds either a picture (a screenshot) or files copied in Explorer; both become attachments.
    Private Sub BtnPasteImage_Click(sender As Object, e As EventArgs)
        Try
            If Clipboard.ContainsImage() Then
                Using img = Clipboard.GetImage()
                    If img Is Nothing Then
                        SetStatus("The clipboard image could not be read. Copy the screenshot again.", isError:=True)
                        Return
                    End If
                    Directory.CreateDirectory(_pasteDir)
                    Dim baseName = $"screenshot-{Date.Now:yyyyMMdd-HHmmss}"
                    Dim target = Path.Combine(_pasteDir, baseName & ".png")
                    Dim n = 2
                    While File.Exists(target)
                        target = Path.Combine(_pasteDir, $"{baseName}-{n}.png")
                        n += 1
                    End While
                    img.Save(target, Imaging.ImageFormat.Png)
                    AddAttachment(target)
                End Using
            ElseIf Clipboard.ContainsFileDropList() Then
                For Each f In Clipboard.GetFileDropList()
                    If f IsNot Nothing Then AddAttachment(f)
                Next
            Else
                SetStatus("The clipboard has no image or file. Take a screenshot (Win+Shift+S) and press Paste Image again.", isError:=True)
            End If
        Catch ex As Exception
            SetStatus($"The clipboard could not be read: {ex.Message}", isError:=True)
        End Try
    End Sub

    Private Sub BtnRemoveAttachment_Click(sender As Object, e As EventArgs)
        Dim selected As New List(Of Object)
        For Each item In lstAttachments.SelectedItems
            selected.Add(item)
        Next
        For Each item In selected
            lstAttachments.Items.Remove(item)
        Next
    End Sub

    Private Sub AddAttachment(filePath As String)
        If filePath.Contains(";"c) Then
            SetStatus($"A file name with ';' cannot be attached: {Path.GetFileName(filePath)}. Rename it and add it again.", isError:=True)
            Return
        End If
        If Not File.Exists(filePath) Then
            SetStatus($"Only files can be attached: {filePath}", isError:=True)
            Return
        End If
        For Each item In lstAttachments.Items
            If String.Equals(item.ToString(), filePath, StringComparison.OrdinalIgnoreCase) Then Return
        Next
        lstAttachments.Items.Add(filePath)
    End Sub

    ' The pasted images must outlive the capture that copies them, so the window stays open while it runs.
    Protected Overrides Sub OnFormClosing(e As FormClosingEventArgs)
        If _capturing Then
            e.Cancel = True
            SetStatus("The specification is being created. Wait for it to finish.", isError:=False)
        End If
        MyBase.OnFormClosing(e)
    End Sub

    ' Completion and cancellation both close the dialog; the pasted images go with it.
    Protected Overrides Sub OnFormClosed(e As FormClosedEventArgs)
        MyBase.OnFormClosed(e)
        Try
            If Directory.Exists(_pasteDir) Then Directory.Delete(_pasteDir, recursive:=True)
        Catch ex As IOException
            Diagnostics.Debug.WriteLine($"FormNewSpec: could not remove {_pasteDir}: {ex.Message}")
        Catch ex As UnauthorizedAccessException
            Diagnostics.Debug.WriteLine($"FormNewSpec: could not remove {_pasteDir}: {ex.Message}")
        End Try
    End Sub

    Private Sub SetStatus(msg As String, isError As Boolean)
        lblStatus.Text = msg
        lblStatus.ForeColor = If(isError, ThemeService.Palette.StatusDanger, ThemeService.Palette.Accent)
    End Sub
End Class
