<#
================================================================================
BEYOND COMPARE 5 (64-bit) - PROFESSIONAL DIFF & MERGE STUDIO
Version: 5.0.6 (build 30713) - Enterprise Offline Edition
100% Native Zero-Dependency Offline Execution
Matches Scooter Software Beyond Compare 5 Interface & Functionality 1:1
================================================================================
#>
param(
    [string]$Path1 = "",
    [string]$Path2 = "",
    [string]$Title1 = "",
    [string]$Title2 = "",
    [string]$LeftText = "",
    [string]$RightText = ""
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Auto-unblock files silently to prevent SmartScreen / permission blocks
try {
    $bcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $bcDir -or -not (Test-Path $bcDir)) { $bcDir = $PSScriptRoot }
    if (-not $bcDir -or -not (Test-Path $bcDir)) { $bcDir = "C:\Users\mandar.k\Nexus-Photo-Optimizer-Portable" }
    if ($bcDir -and (Test-Path $bcDir)) {
        Get-ChildItem -Path $bcDir -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
    }
} catch {}

$global:IsRunningAsAdmin = $false
try {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    $global:IsRunningAsAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {
    $global:IsRunningAsAdmin = $false
}
$script:AdminTag = if ($global:IsRunningAsAdmin) { " [Administrator]" } else { "" }

# Command line parameters handling
if ($Path1 -and (Test-Path $Path1 -PathType Leaf)) {
    try { $LeftText = [System.IO.File]::ReadAllText($Path1); if (-not $Title1) { $Title1 = $Path1 } } catch {}
}
if ($Path2 -and (Test-Path $Path2 -PathType Leaf)) {
    try { $RightText = [System.IO.File]::ReadAllText($Path2); if (-not $Title2) { $Title2 = $Path2 } } catch {}
}
if ($LeftText -and -not $leftText) { $leftText = $LeftText }
if ($RightText -and -not $rightText) { $rightText = $RightText }
if ($Title1 -and -not $leftTitle) { $leftTitle = $Title1 }
if ($Title2 -and -not $rightTitle) { $rightTitle = $Title2 }

$global:isBeyondCompareOpen = $false
if ($global:beyondCompareWin -and $global:beyondCompareWin.IsLoaded) {
    try {
        $global:beyondCompareWin.WindowState = [System.Windows.WindowState]::Normal
        $global:beyondCompareWin.Activate()
        $global:beyondCompareWin.Focus()
    } catch {}
    return
}
$global:isBeyondCompareOpen = $true

try {
    $win = New-Object System.Windows.Window
    $global:beyondCompareWin = $win
    $win.Title = "Home - Beyond Compare" + $script:AdminTag
    $win.Width = 1280
    $win.Height = 760
    $win.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    $win.Background = [System.Windows.Media.Brushes]::White
    $win.ResizeMode = [System.Windows.ResizeMode]::CanResizeWithGrip

    # Global Script State
    $script:ActiveSessionType = "HOME"
    $script:PreviousView = "HOME"
    $script:IsDarkMode = $false
    $script:IsWordWrap = $false
    $script:CurrentViewMode = "DIFFS"
    $script:RuleIgnoreCase = $false
    $script:RuleIgnoreLeadingWs = $false
    $script:RuleIgnoreTrailingWs = $false
    $script:RuleIgnoreAllWs = $false
    $script:RuleIgnoreBlankLines = $false
    $script:DtAll = $null
    $script:DtDiffs = $null
    $script:DtSame = $null
    $script:AllFolderItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    $script:AllTableItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    $script:AllHexItems = [System.Collections.Generic.List[PSCustomObject]]::new()
    $script:SearchMatches = [System.Collections.Generic.List[int]]::new()
    $script:SearchMatchIndex = -1
    $script:IsLeftDirty = $false
    $script:IsRightDirty = $false

    # Master Grid
    $masterGrid = New-Object System.Windows.Controls.Grid
    $win.Content = $masterGrid

    # View 1: Home View
    $viewHome = New-Object System.Windows.Controls.Grid
    $masterGrid.Children.Add($viewHome) | Out-Null

    # View 2: Text Compare View
    $viewText = New-Object System.Windows.Controls.Grid
    $viewText.Visibility = [System.Windows.Visibility]::Collapsed
    $masterGrid.Children.Add($viewText) | Out-Null

    # View 3: Folder Compare & Sync View
    $viewFolder = New-Object System.Windows.Controls.Grid
    $viewFolder.Visibility = [System.Windows.Visibility]::Collapsed
    $masterGrid.Children.Add($viewFolder) | Out-Null

    # View 4: Table Compare View
    $viewTable = New-Object System.Windows.Controls.Grid
    $viewTable.Visibility = [System.Windows.Visibility]::Collapsed
    $masterGrid.Children.Add($viewTable) | Out-Null

    # View 5: Hex / Binary Compare View
    $viewHex = New-Object System.Windows.Controls.Grid
    $viewHex.Visibility = [System.Windows.Visibility]::Collapsed
    $masterGrid.Children.Add($viewHex) | Out-Null
    # -------------------------------------------------------------
    # VIEW 1: HOME SCREEN (Screenshot 1)
    # -------------------------------------------------------------
    $vhRow0 = New-Object System.Windows.Controls.RowDefinition; $vhRow0.Height = [System.Windows.GridLength]::Auto
    $vhRow1 = New-Object System.Windows.Controls.RowDefinition; $vhRow1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vhRow2 = New-Object System.Windows.Controls.RowDefinition; $vhRow2.Height = [System.Windows.GridLength]::Auto
    $viewHome.RowDefinitions.Add($vhRow0); $viewHome.RowDefinitions.Add($vhRow1); $viewHome.RowDefinitions.Add($vhRow2)

    # Row 0: Home Menu Bar
    $vhMenuGrid = New-Object System.Windows.Controls.Grid
    $vhMenuGrid.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F6F7")
    $vhmc0 = New-Object System.Windows.Controls.ColumnDefinition; $vhmc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vhmc1 = New-Object System.Windows.Controls.ColumnDefinition; $vhmc1.Width = [System.Windows.GridLength]::Auto
    $vhMenuGrid.ColumnDefinitions.Add($vhmc0); $vhMenuGrid.ColumnDefinitions.Add($vhmc1)

    $vhMenu = New-Object System.Windows.Controls.Menu
    $vhMenu.Background = [System.Windows.Media.Brushes]::Transparent
    $vhMenu.Padding = New-Object System.Windows.Thickness(4,2,4,2)
    @("Session", "View", "Tools", "Help") | ForEach-Object {
        $m = New-Object System.Windows.Controls.MenuItem; $m.Header = "_$_"; $m.FontSize = 12
        $vhMenu.Items.Add($m) | Out-Null
    }
    [System.Windows.Controls.Grid]::SetColumn($vhMenu, 0)
    $vhMenuGrid.Children.Add($vhMenu) | Out-Null

    $vhLblNewVer = New-Object System.Windows.Controls.TextBlock
    $vhLblNewVer.Text = "New version available..."
    $vhLblNewVer.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0066CC")
    $vhLblNewVer.FontSize = 11; $vhLblNewVer.VerticalAlignment = "Center"; $vhLblNewVer.Margin = New-Object System.Windows.Thickness(0,0,12,0)
    $vhLblNewVer.Cursor = [System.Windows.Input.Cursors]::Hand
    [System.Windows.Controls.Grid]::SetColumn($vhLblNewVer, 1)
    $vhMenuGrid.Children.Add($vhLblNewVer) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($vhMenuGrid, 0)
    $viewHome.Children.Add($vhMenuGrid) | Out-Null

    # Row 1: Home Main Grid (Left Sidebar + Center Canvas)
    $vhMainGrid = New-Object System.Windows.Controls.Grid
    $vhcSidebar = New-Object System.Windows.Controls.ColumnDefinition; $vhcSidebar.Width = New-Object System.Windows.GridLength(240)
    $vhcSplitter = New-Object System.Windows.Controls.ColumnDefinition; $vhcSplitter.Width = [System.Windows.GridLength]::Auto
    $vhcCanvas = New-Object System.Windows.Controls.ColumnDefinition; $vhcCanvas.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vhMainGrid.ColumnDefinitions.Add($vhcSidebar); $vhMainGrid.ColumnDefinitions.Add($vhcSplitter); $vhMainGrid.ColumnDefinitions.Add($vhcCanvas)

    # --- Left Sidebar ---
    $vhSideBorder = New-Object System.Windows.Controls.Border
    $vhSideBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8F9FA")
    $vhSideBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D5DD")
    $vhSideBorder.BorderThickness = New-Object System.Windows.Thickness(0,1,1,0)

    $vhSideGrid = New-Object System.Windows.Controls.Grid
    $vhsRow0 = New-Object System.Windows.Controls.RowDefinition; $vhsRow0.Height = [System.Windows.GridLength]::Auto
    $vhsRow1 = New-Object System.Windows.Controls.RowDefinition; $vhsRow1.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vhsRow2 = New-Object System.Windows.Controls.RowDefinition; $vhsRow2.Height = [System.Windows.GridLength]::Auto
    $vhSideGrid.RowDefinitions.Add($vhsRow0); $vhSideGrid.RowDefinitions.Add($vhsRow1); $vhSideGrid.RowDefinitions.Add($vhsRow2)

    # Sessions Header
    $vhSideHeader = New-Object System.Windows.Controls.Border
    $vhSideHeader.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECEEF1")
    $vhSideHeader.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D5DD")
    $vhSideHeader.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1)
    $vhSideHeader.Padding = New-Object System.Windows.Thickness(8,5,8,5)
    $vhLblSideTitle = New-Object System.Windows.Controls.TextBlock; $vhLblSideTitle.Text = "Sessions"; $vhLblSideTitle.FontWeight = [System.Windows.FontWeights]::SemiBold; $vhLblSideTitle.FontSize = 11.5; $vhLblSideTitle.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
    $vhSideHeader.Child = $vhLblSideTitle
    [System.Windows.Controls.Grid]::SetRow($vhSideHeader, 0)
    $vhSideGrid.Children.Add($vhSideHeader) | Out-Null

    # Sessions TreeView
    $tvSessions = New-Object System.Windows.Controls.TreeView
    $tvSessions.BorderThickness = New-Object System.Windows.Thickness(0)
    $tvSessions.Background = [System.Windows.Media.Brushes]::Transparent
    $tvSessions.Padding = New-Object System.Windows.Thickness(4)

    $rootNode = New-Object System.Windows.Controls.TreeViewItem
    $rootNode.Header = "New"
    $rootNode.IsExpanded = $true
    $rootNode.FontSize = 11.5

    $sessionItemsList = @("Folder Compare", "Folder Merge", "Folder Sync", "Text Compare", "Text Merge", "Table Compare", "Hex Compare")
    $script:SessionTreeNodes = [System.Collections.Generic.List[object]]::new()
    foreach ($sItem in $sessionItemsList) {
        $item = New-Object System.Windows.Controls.TreeViewItem
        $item.Header = $sItem
        $item.Padding = New-Object System.Windows.Thickness(2)
        $rootNode.Items.Add($item) | Out-Null
        $script:SessionTreeNodes.Add($item)
    }
    $tvSessions.Items.Add($rootNode) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($tvSessions, 1)
    $vhSideGrid.Children.Add($tvSessions) | Out-Null

    # Sidebar Bottom Bar (+ and Search box)
    $vhSideBottom = New-Object System.Windows.Controls.Border
    $vhSideBottom.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECEEF1")
    $vhSideBottom.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D5DD")
    $vhSideBottom.BorderThickness = New-Object System.Windows.Thickness(0,1,0,0)
    $vhSideBottom.Padding = New-Object System.Windows.Thickness(4,3,4,3)

    $vhSbGrid = New-Object System.Windows.Controls.Grid
    $vhsbc0 = New-Object System.Windows.Controls.ColumnDefinition; $vhsbc0.Width = [System.Windows.GridLength]::Auto
    $vhsbc1 = New-Object System.Windows.Controls.ColumnDefinition; $vhsbc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vhSbGrid.ColumnDefinitions.Add($vhsbc0); $vhSbGrid.ColumnDefinitions.Add($vhsbc1)

    $btnAddSession = New-Object System.Windows.Controls.Button
    $btnAddSession.Content = " + "
    $btnAddSession.FontWeight = [System.Windows.FontWeights]::Bold
    $btnAddSession.FontSize = 11
    $btnAddSession.Padding = New-Object System.Windows.Thickness(4,1,4,1)
    $btnAddSession.Margin = New-Object System.Windows.Thickness(0,0,4,0)
    $btnAddSession.Cursor = [System.Windows.Input.Cursors]::Hand
    $btnAddSession.ToolTip = "Create New Session"
    [System.Windows.Controls.Grid]::SetColumn($btnAddSession, 0)
    $vhSbGrid.Children.Add($btnAddSession) | Out-Null

    $txtSearchSessions = New-Object System.Windows.Controls.TextBox
    $txtSearchSessions.FontSize = 11
    $txtSearchSessions.Padding = New-Object System.Windows.Thickness(4,2,4,2)
    $txtSearchSessions.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C0C8D0")
    $txtSearchSessions.ToolTip = "Filter sessions"
    [System.Windows.Controls.Grid]::SetColumn($txtSearchSessions, 1)
    $vhSbGrid.Children.Add($txtSearchSessions) | Out-Null

    $vhSideBottom.Child = $vhSbGrid
    [System.Windows.Controls.Grid]::SetRow($vhSideBottom, 2)
    $vhSideGrid.Children.Add($vhSideBottom) | Out-Null

    $vhSideBorder.Child = $vhSideGrid
    [System.Windows.Controls.Grid]::SetColumn($vhSideBorder, 0)
    $vhMainGrid.Children.Add($vhSideBorder) | Out-Null

    # Splitter
    $vhSplitter = New-Object System.Windows.Controls.GridSplitter
    $vhSplitter.Width = 4
    $vhSplitter.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0")
    $vhSplitter.HorizontalAlignment = "Right"
    [System.Windows.Controls.Grid]::SetColumn($vhSplitter, 0)
    $vhMainGrid.Children.Add($vhSplitter) | Out-Null

    # --- Center Canvas ---
    $vhCanvasBorder = New-Object System.Windows.Controls.Border
    $vhCanvasBorder.Background = [System.Windows.Media.Brushes]::White
    $vhCanvasBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D5DD")
    $vhCanvasBorder.BorderThickness = New-Object System.Windows.Thickness(0,1,0,0)
    $vhCanvasBorder.AllowDrop = $true

    $vhCanvasGrid = New-Object System.Windows.Controls.Grid
    $vhcgRow0 = New-Object System.Windows.Controls.RowDefinition; $vhcgRow0.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vhCanvasGrid.RowDefinitions.Add($vhcgRow0)

    # Central Launcher Container
    $vhCenterStack = New-Object System.Windows.Controls.StackPanel
    $vhCenterStack.VerticalAlignment = "Center"
    $vhCenterStack.HorizontalAlignment = "Center"
    $vhCenterStack.Margin = New-Object System.Windows.Thickness(0,0,0,30)

    # Prompt Text
    $lblPrompt1 = New-Object System.Windows.Controls.TextBlock; $lblPrompt1.Text = "Drag folders or files here"; $lblPrompt1.FontSize = 12; $lblPrompt1.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#475569"); $lblPrompt1.HorizontalAlignment = "Center"
    $lblPrompt2 = New-Object System.Windows.Controls.TextBlock; $lblPrompt2.Text = "or click a session icon to begin:"; $lblPrompt2.FontSize = 12; $lblPrompt2.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#475569"); $lblPrompt2.HorizontalAlignment = "Center"; $lblPrompt2.Margin = New-Object System.Windows.Thickness(0,2,0,20)
    $vhCenterStack.Children.Add($lblPrompt1) | Out-Null
    $vhCenterStack.Children.Add($lblPrompt2) | Out-Null

    # Session Icon Buttons Container
    $vhIconRow = New-Object System.Windows.Controls.WrapPanel
    $vhIconRow.HorizontalAlignment = "Center"
    $vhIconRow.MaxWidth = 720

    $MakeHomeSessionIcon = {
        param($title, $iconType)
        $card = New-Object System.Windows.Controls.Button
        $card.Background = [System.Windows.Media.Brushes]::Transparent
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.BorderBrush = [System.Windows.Media.Brushes]::Transparent
        $card.Margin = New-Object System.Windows.Thickness(8,4,8,4)
        $card.Padding = New-Object System.Windows.Thickness(8,8,8,6)
        $card.Cursor = [System.Windows.Input.Cursors]::Hand
        $card.ToolTip = "Start a new $title session"

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.HorizontalAlignment = "Center"
        $sp.Width = 86

        $c = New-Object System.Windows.Controls.Canvas
        $c.Width = 56; $c.Height = 52
        $c.HorizontalAlignment = "Center"

        if ($iconType -like "Folder*") {
            $fTab = New-Object System.Windows.Shapes.Path; $fTab.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B"); $fTab.Data = [System.Windows.Media.Geometry]::Parse("M 6,10 L 22,10 L 26,14 L 50,14 L 50,44 L 6,44 Z"); $c.Children.Add($fTab) | Out-Null
            $fBody = New-Object System.Windows.Shapes.Path; $fBody.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FBBF24"); $fBody.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97706"); $fBody.StrokeThickness = 1; $fBody.Data = [System.Windows.Media.Geometry]::Parse("M 4,16 L 52,16 L 48,46 L 8,46 Z"); $c.Children.Add($fBody) | Out-Null
            if ($iconType -eq "FolderMerge") {
                $doc = New-Object System.Windows.Shapes.Rectangle; $doc.Width = 18; $doc.Height = 22; $doc.Fill = [System.Windows.Media.Brushes]::White; $doc.Stroke = [System.Windows.Media.Brushes]::Gray; $doc.StrokeThickness = 1; [System.Windows.Controls.Canvas]::SetLeft($doc, 19); [System.Windows.Controls.Canvas]::SetTop($doc, 20); $c.Children.Add($doc) | Out-Null
            } elseif ($iconType -eq "FolderSync") {
                $badge = New-Object System.Windows.Shapes.Ellipse; $badge.Width = 20; $badge.Height = 20; $badge.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#8B5CF6"); [System.Windows.Controls.Canvas]::SetLeft($badge, 18); [System.Windows.Controls.Canvas]::SetTop($badge, 22); $c.Children.Add($badge) | Out-Null
                $syncTxt = New-Object System.Windows.Controls.TextBlock; $syncTxt.Text = "<>"; $syncTxt.FontSize = 10; $syncTxt.FontWeight = [System.Windows.FontWeights]::Bold; $syncTxt.Foreground = [System.Windows.Media.Brushes]::White; [System.Windows.Controls.Canvas]::SetLeft($syncTxt, 21); [System.Windows.Controls.Canvas]::SetTop($syncTxt, 24); $c.Children.Add($syncTxt) | Out-Null
            }
        } elseif ($iconType -like "Table*") {
            $tbl = New-Object System.Windows.Shapes.Rectangle; $tbl.Width = 44; $tbl.Height = 38; $tbl.Fill = [System.Windows.Media.Brushes]::White; $tbl.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7"); $tbl.StrokeThickness = 1.5; [System.Windows.Controls.Canvas]::SetLeft($tbl, 6); [System.Windows.Controls.Canvas]::SetTop($tbl, 7); $c.Children.Add($tbl) | Out-Null
            $tHdr = New-Object System.Windows.Shapes.Rectangle; $tHdr.Width = 44; $tHdr.Height = 10; $tHdr.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#BAE6FD"); [System.Windows.Controls.Canvas]::SetLeft($tHdr, 6); [System.Windows.Controls.Canvas]::SetTop($tHdr, 7); $c.Children.Add($tHdr) | Out-Null
            $tG1 = New-Object System.Windows.Shapes.Line; $tG1.X1 = 20; $tG1.X2 = 20; $tG1.Y1 = 7; $tG1.Y2 = 45; $tG1.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7"); $c.Children.Add($tG1) | Out-Null
            $tG2 = New-Object System.Windows.Shapes.Line; $tG2.X1 = 36; $tG2.X2 = 36; $tG2.Y1 = 7; $tG2.Y2 = 45; $tG2.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7"); $c.Children.Add($tG2) | Out-Null
            $tG3 = New-Object System.Windows.Shapes.Line; $tG3.X1 = 6; $tG3.X2 = 50; $tG3.Y1 = 25; $tG3.Y2 = 25; $tG3.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7"); $c.Children.Add($tG3) | Out-Null
        } elseif ($iconType -like "Hex*") {
            $hexBox = New-Object System.Windows.Shapes.Rectangle; $hexBox.Width = 44; $hexBox.Height = 38; $hexBox.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0F172A"); $hexBox.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#475569"); $hexBox.StrokeThickness = 1.5; [System.Windows.Controls.Canvas]::SetLeft($hexBox, 6); [System.Windows.Controls.Canvas]::SetTop($hexBox, 7); $c.Children.Add($hexBox) | Out-Null
            $hexT = New-Object System.Windows.Controls.TextBlock; $hexT.Text = "0100`nFF7A"; $hexT.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $hexT.FontSize = 10; $hexT.FontWeight = [System.Windows.FontWeights]::Bold; $hexT.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4ADE80"); [System.Windows.Controls.Canvas]::SetLeft($hexT, 12); [System.Windows.Controls.Canvas]::SetTop($hexT, 11); $c.Children.Add($hexT) | Out-Null
        } else {
            $doc1 = New-Object System.Windows.Shapes.Path; $doc1.Fill = [System.Windows.Media.Brushes]::White; $doc1.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B"); $doc1.StrokeThickness = 1.2; $doc1.Data = [System.Windows.Media.Geometry]::Parse("M 10,6 L 36,6 L 46,16 L 46,46 L 10,46 Z"); $c.Children.Add($doc1) | Out-Null
            $corner = New-Object System.Windows.Shapes.Path; $corner.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0"); $corner.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B"); $corner.StrokeThickness = 1; $corner.Data = [System.Windows.Media.Geometry]::Parse("M 36,6 L 36,16 L 46,16 Z"); $c.Children.Add($corner) | Out-Null
            for ($lineY = 22; $lineY -le 38; $lineY += 5) {
                $ln = New-Object System.Windows.Shapes.Line; $ln.X1 = 16; $ln.X2 = 40; $ln.Y1 = $lineY; $ln.Y2 = $lineY; $ln.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#94A3B8"); $ln.StrokeThickness = 1.5; $c.Children.Add($ln) | Out-Null
            }
            if ($iconType -eq "TextMerge") {
                $badge = New-Object System.Windows.Shapes.Ellipse; $badge.Width = 18; $badge.Height = 18; $badge.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7"); [System.Windows.Controls.Canvas]::SetLeft($badge, 26); [System.Windows.Controls.Canvas]::SetTop($badge, 26); $c.Children.Add($badge) | Out-Null
                $mTxt = New-Object System.Windows.Controls.TextBlock; $mTxt.Text = "M"; $mTxt.FontSize = 10; $mTxt.FontWeight = [System.Windows.FontWeights]::Bold; $mTxt.Foreground = [System.Windows.Media.Brushes]::White; [System.Windows.Controls.Canvas]::SetLeft($mTxt, 31); [System.Windows.Controls.Canvas]::SetTop($mTxt, 28); $c.Children.Add($mTxt) | Out-Null
            }
        }
        $sp.Children.Add($c) | Out-Null
        $tx = New-Object System.Windows.Controls.TextBlock; $tx.Text = $title; $tx.FontSize = 11; $tx.HorizontalAlignment = "Center"; $tx.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B"); $tx.Margin = New-Object System.Windows.Thickness(0,6,0,0); $sp.Children.Add($tx) | Out-Null
        $card.Content = $sp
        return $card
    }

    $btnFC = &$MakeHomeSessionIcon "Folder Compare" "FolderCompare"
    $btnFM = &$MakeHomeSessionIcon "Folder Merge" "FolderMerge"
    $btnFS = &$MakeHomeSessionIcon "Folder Sync" "FolderSync"
    $btnTC = &$MakeHomeSessionIcon "Text Compare" "TextCompare"
    $btnTM = &$MakeHomeSessionIcon "Text Merge" "TextMerge"
    $btnTabC = &$MakeHomeSessionIcon "Table Compare" "TableCompare"
    $btnHC = &$MakeHomeSessionIcon "Hex Compare" "HexCompare"

    $vhIconRow.Children.Add($btnFC) | Out-Null
    $vhIconRow.Children.Add($btnFM) | Out-Null
    $vhIconRow.Children.Add($btnFS) | Out-Null
    $vhIconRow.Children.Add($btnTC) | Out-Null
    $vhIconRow.Children.Add($btnTM) | Out-Null
    $vhIconRow.Children.Add($btnTabC) | Out-Null
    $vhIconRow.Children.Add($btnHC) | Out-Null

    # Right chevron button
    $btnMore = New-Object System.Windows.Controls.Button; $btnMore.Content = " > "; $btnMore.FontSize = 18; $btnMore.FontWeight = [System.Windows.FontWeights]::Bold; $btnMore.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B"); $btnMore.Background = [System.Windows.Media.Brushes]::Transparent; $btnMore.BorderThickness = New-Object System.Windows.Thickness(0); $btnMore.VerticalAlignment = "Center"; $btnMore.Margin = New-Object System.Windows.Thickness(12,0,0,0); $btnMore.Cursor = [System.Windows.Input.Cursors]::Hand
    $vhIconRow.Children.Add($btnMore) | Out-Null

    $vhCenterStack.Children.Add($vhIconRow) | Out-Null
    $vhCanvasGrid.Children.Add($vhCenterStack) | Out-Null

    # Bottom-Right Scooter Software Seal of Quality Badge
    $sealBadge = New-Object System.Windows.Controls.Border; $sealBadge.Width = 64; $sealBadge.Height = 64; $sealBadge.CornerRadius = New-Object System.Windows.CornerRadius(32); $sealBadge.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#582E1E"); $sealBadge.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D97706"); $sealBadge.BorderThickness = New-Object System.Windows.Thickness(2); $sealBadge.HorizontalAlignment = "Right"; $sealBadge.VerticalAlignment = "Bottom"; $sealBadge.Margin = New-Object System.Windows.Thickness(0,0,24,24)
    $sealTxt = New-Object System.Windows.Controls.TextBlock; $sealTxt.Text = "SCOOTER`nSOFTWARE`nSEAL"; $sealTxt.FontSize = 8.5; $sealTxt.FontWeight = [System.Windows.FontWeights]::Bold; $sealTxt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEF3C7"); $sealTxt.TextAlignment = "Center"; $sealTxt.VerticalAlignment = "Center"
    $sealBadge.Child = $sealTxt
    $vhCanvasGrid.Children.Add($sealBadge) | Out-Null

    $vhCanvasBorder.Child = $vhCanvasGrid
    [System.Windows.Controls.Grid]::SetColumn($vhCanvasBorder, 2)
    $vhMainGrid.Children.Add($vhCanvasBorder) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($vhMainGrid, 1)
    $viewHome.Children.Add($vhMainGrid) | Out-Null

    # Row 2: Authentic Red Footer Banner
    $redFooter = New-Object System.Windows.Controls.Border; $redFooter.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#990000"); $redFooter.Padding = New-Object System.Windows.Thickness(16,10,16,10)
    [System.Windows.Controls.Grid]::SetRow($redFooter, 2)

    $rfGrid = New-Object System.Windows.Controls.Grid
    for ($c=0; $c -lt 5; $c++) { $col = New-Object System.Windows.Controls.ColumnDefinition; $col.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $rfGrid.ColumnDefinitions.Add($col) }
    $colClose = New-Object System.Windows.Controls.ColumnDefinition; $colClose.Width = [System.Windows.GridLength]::Auto; $rfGrid.ColumnDefinitions.Add($colClose)

    $MakeHomeFooterCol = {
        param($title, $bodyText, $colIdx)
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = New-Object System.Windows.Thickness(0,0,12,0)
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $title; $t.FontSize = 10; $t.FontWeight = [System.Windows.FontWeights]::Bold; $t.Foreground = [System.Windows.Media.Brushes]::White; $t.Margin = New-Object System.Windows.Thickness(0,0,0,3); $sp.Children.Add($t) | Out-Null
        $b = New-Object System.Windows.Controls.TextBlock; $b.Text = $bodyText; $b.FontSize = 9.5; $b.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FCA5A5"); $b.TextWrapping = [System.Windows.TextWrapping]::Wrap; $sp.Children.Add($b) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($sp, $colIdx)
        return $sp
    }
    $rfGrid.Children.Add((&$MakeHomeFooterCol "KNOWLEDGE BASE" "Search documentation and tutorials." 0)) | Out-Null
    $rfGrid.Children.Add((&$MakeHomeFooterCol "SUPPORT FORUMS" "Visit our online forums for technical support." 1)) | Out-Null
    $rfGrid.Children.Add((&$MakeHomeFooterCol "SCREENCASTS" "Watch our online videos for tips on Beyond Compare." 2)) | Out-Null
    $rfGrid.Children.Add((&$MakeHomeFooterCol "REGISTER" "Running full version. License active." 3)) | Out-Null
    $rfGrid.Children.Add((&$MakeHomeFooterCol "VERSION 5 (BUILD 30713)" "Latest high-performance edition installed." 4)) | Out-Null

    $btnCloseBanner = New-Object System.Windows.Controls.Button; $btnCloseBanner.Content = " X "; $btnCloseBanner.FontSize = 10; $btnCloseBanner.FontWeight = [System.Windows.FontWeights]::Bold; $btnCloseBanner.Foreground = [System.Windows.Media.Brushes]::White; $btnCloseBanner.Background = [System.Windows.Media.Brushes]::Transparent; $btnCloseBanner.BorderThickness = New-Object System.Windows.Thickness(0); $btnCloseBanner.Cursor = [System.Windows.Input.Cursors]::Hand; $btnCloseBanner.VerticalAlignment = "Top"
    [System.Windows.Controls.Grid]::SetColumn($btnCloseBanner, 5)
    $btnCloseBanner.Add_Click({ $redFooter.Visibility = [System.Windows.Visibility]::Collapsed })
    $rfGrid.Children.Add($btnCloseBanner) | Out-Null

    $redFooter.Child = $rfGrid
    $viewHome.Children.Add($redFooter) | Out-Null
    # -------------------------------------------------------------
    # VIEW 2: TEXT COMPARE SCREEN (Screenshot 2)
    # -------------------------------------------------------------
    $vtRow0 = New-Object System.Windows.Controls.RowDefinition; $vtRow0.Height = [System.Windows.GridLength]::Auto
    $vtRow1 = New-Object System.Windows.Controls.RowDefinition; $vtRow1.Height = [System.Windows.GridLength]::Auto
    $vtRow2 = New-Object System.Windows.Controls.RowDefinition; $vtRow2.Height = [System.Windows.GridLength]::Auto
    $vtRow3 = New-Object System.Windows.Controls.RowDefinition; $vtRow3.Height = [System.Windows.GridLength]::Auto
    $vtRow4 = New-Object System.Windows.Controls.RowDefinition; $vtRow4.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vtRow5 = New-Object System.Windows.Controls.RowDefinition; $vtRow5.Height = [System.Windows.GridLength]::Auto
    $vtRow6 = New-Object System.Windows.Controls.RowDefinition; $vtRow6.Height = [System.Windows.GridLength]::Auto
    $viewText.RowDefinitions.Add($vtRow0); $viewText.RowDefinitions.Add($vtRow1); $viewText.RowDefinitions.Add($vtRow2)
    $viewText.RowDefinitions.Add($vtRow3); $viewText.RowDefinitions.Add($vtRow4); $viewText.RowDefinitions.Add($vtRow5)
    $viewText.RowDefinitions.Add($vtRow6)

    # 0. Menu Bar
    $vtMenuGrid = New-Object System.Windows.Controls.Grid
    $vtMenuGrid.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F6F7")
    $vtmc0 = New-Object System.Windows.Controls.ColumnDefinition; $vtmc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vtmc1 = New-Object System.Windows.Controls.ColumnDefinition; $vtmc1.Width = [System.Windows.GridLength]::Auto
    $vtMenuGrid.ColumnDefinitions.Add($vtmc0); $vtMenuGrid.ColumnDefinitions.Add($vtmc1)

    $vtMenu = New-Object System.Windows.Controls.Menu
    $vtMenu.Background = [System.Windows.Media.Brushes]::Transparent
    $vtMenu.Padding = New-Object System.Windows.Thickness(4,2,4,2)

    $mSession = New-Object System.Windows.Controls.MenuItem; $mSession.Header = "_Session"; $mSession.FontSize = 12
    $mFile    = New-Object System.Windows.Controls.MenuItem; $mFile.Header    = "_File";    $mFile.FontSize = 12
    $mEdit    = New-Object System.Windows.Controls.MenuItem; $mEdit.Header    = "_Edit";    $mEdit.FontSize = 12
    $mSearch  = New-Object System.Windows.Controls.MenuItem; $mSearch.Header  = "_Search";  $mSearch.FontSize = 12
    $mView    = New-Object System.Windows.Controls.MenuItem; $mView.Header    = "_View";    $mView.FontSize = 12
    $mTools   = New-Object System.Windows.Controls.MenuItem; $mTools.Header   = "_Tools";   $mTools.FontSize = 12
    $mHelp    = New-Object System.Windows.Controls.MenuItem; $mHelp.Header    = "_Help";    $mHelp.FontSize = 12

    $vtMenu.Items.Add($mSession) | Out-Null
    $vtMenu.Items.Add($mFile) | Out-Null
    $vtMenu.Items.Add($mEdit) | Out-Null
    $vtMenu.Items.Add($mSearch) | Out-Null
    $vtMenu.Items.Add($mView) | Out-Null
    $vtMenu.Items.Add($mTools) | Out-Null
    $vtMenu.Items.Add($mHelp) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($vtMenu, 0)
    $vtMenuGrid.Children.Add($vtMenu) | Out-Null

    $vtLblNewVer = New-Object System.Windows.Controls.TextBlock; $vtLblNewVer.Text = "New version available..."; $vtLblNewVer.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0066CC"); $vtLblNewVer.FontSize = 11; $vtLblNewVer.VerticalAlignment = "Center"; $vtLblNewVer.Margin = New-Object System.Windows.Thickness(0,0,12,0); $vtLblNewVer.Cursor = [System.Windows.Input.Cursors]::Hand
    [System.Windows.Controls.Grid]::SetColumn($vtLblNewVer, 1)
    $vtMenuGrid.Children.Add($vtLblNewVer) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($vtMenuGrid, 0)
    $viewText.Children.Add($vtMenuGrid) | Out-Null

    # 1. Iconic Beyond Compare Toolbar (Matches Screenshot 2)
    $toolBorder = New-Object System.Windows.Controls.Border
    $toolBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8")
    $toolBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D0D0")
    $toolBorder.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1)
    $toolBorder.Padding = New-Object System.Windows.Thickness(4,3,4,3)
    [System.Windows.Controls.Grid]::SetRow($toolBorder, 1)

    $toolWrap = New-Object System.Windows.Controls.WrapPanel

    $MakeToolBtn = {
        param($text, $iconText, $iconColor, $tooltip)
        $b = New-Object System.Windows.Controls.Button
        $b.Margin = New-Object System.Windows.Thickness(1,0,1,0)
        $b.Padding = New-Object System.Windows.Thickness(6,2,6,2)
        $b.Background = [System.Windows.Media.Brushes]::Transparent
        $b.BorderThickness = New-Object System.Windows.Thickness(0)
        $b.Cursor = [System.Windows.Input.Cursors]::Hand
        if ($tooltip) { $b.ToolTip = $tooltip }

        $sp = New-Object System.Windows.Controls.StackPanel; $sp.HorizontalAlignment = "Center"
        $ic = New-Object System.Windows.Controls.TextBlock; $ic.Text = $iconText; $ic.FontWeight = [System.Windows.FontWeights]::Bold; $ic.FontSize = 12.5; $ic.HorizontalAlignment = "Center"; $ic.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($iconColor)
        $sp.Children.Add($ic) | Out-Null
        $tx = New-Object System.Windows.Controls.TextBlock; $tx.Text = $text; $tx.FontSize = 10; $tx.HorizontalAlignment = "Center"; $tx.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
        $sp.Children.Add($tx) | Out-Null
        $b.Content = $sp
        return $b
    }

    $MakeToolSep = {
        $sep = New-Object System.Windows.Controls.Border; $sep.Width = 1; $sep.Height = 28; $sep.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C5C8CD"); $sep.Margin = New-Object System.Windows.Thickness(3,2,3,2)
        return $sep
    }

    # Group 1: Home & Sessions
    $btnHome = &$MakeToolBtn "Home" "[H]" "#2563EB" "Return to Beyond Compare Home Screen"
    $btnSessions = &$MakeToolBtn "Sessions" "[S]" "#D97706" "Session Manager & Settings"
    $toolWrap.Children.Add($btnHome) | Out-Null
    $toolWrap.Children.Add($btnSessions) | Out-Null
    $toolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    # Group 2: All, Diffs, Same, Context, Minor
    $btnAll     = &$MakeToolBtn "All" "*" "#1E293B" "Show all lines"
    $btnDiffs   = &$MakeToolBtn "Diffs" "!=" "#DC2626" "Show differences only (Red highlight)"
    $btnSame    = &$MakeToolBtn "Same" "=" "#16A34A" "Show identical lines only"
    $btnContext = &$MakeToolBtn "Context" "[::]" "#2563EB" "Show differences with 3 lines of context"
    $btnMinor   = &$MakeToolBtn "Minor" "~" "#7C3AED" "Toggle minor differences (whitespace/case)"
    $toolWrap.Children.Add($btnAll) | Out-Null
    $toolWrap.Children.Add($btnDiffs) | Out-Null
    $toolWrap.Children.Add($btnSame) | Out-Null
    $toolWrap.Children.Add($btnContext) | Out-Null
    $toolWrap.Children.Add($btnMinor) | Out-Null
    $toolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    # Group 3: Rules & Format
    $btnRules  = &$MakeToolBtn "Rules" "[R]" "#D97706" "Configure comparison rules (Ignore Case, Whitespace, etc.)"
    $btnFormat = &$MakeToolBtn "Format" "[F]" "#0891B2" "Syntax format & encoding settings"
    $toolWrap.Children.Add($btnRules) | Out-Null
    $toolWrap.Children.Add($btnFormat) | Out-Null
    $toolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    # Group 4: Copy & Edit
    $btnCopy = &$MakeToolBtn "Copy" "[C]" "#2563EB" "Copy differences to clipboard"
    $btnEdit = &$MakeToolBtn "Edit" "[E]" "#16A34A" "Toggle live dual-text editing mode"
    $toolWrap.Children.Add($btnCopy) | Out-Null
    $toolWrap.Children.Add($btnEdit) | Out-Null
    $toolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    # Group 5: Save Left & Save Right
    $btnSaveL = &$MakeToolBtn "Save L" "[Save]" "#2563EB" "Save Left File to disk (Ctrl+S)"
    $btnSaveR = &$MakeToolBtn "Save R" "[Save]" "#2563EB" "Save Right File to disk (Ctrl+Shift+S)"
    $toolWrap.Children.Add($btnSaveL) | Out-Null
    $toolWrap.Children.Add($btnSaveR) | Out-Null
    $toolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    # Group 6: Next Section & Prev Section
    $btnNext = &$MakeToolBtn "Next Section" "v" "#DC2626" "Jump to next red difference section"
    $btnPrev = &$MakeToolBtn "Prev Section" "^" "#DC2626" "Jump to previous red difference section"
    $toolWrap.Children.Add($btnNext) | Out-Null
    $toolWrap.Children.Add($btnPrev) | Out-Null
    $toolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    # Group 7: Swap, Reload, & Report
    $btnSwap   = &$MakeToolBtn "Swap" "<->" "#4F46E5" "Swap Left and Right comparison sides"
    $btnReload = &$MakeToolBtn "Reload" "@" "#16A34A" "Reload files and re-compare (F5)"
    $btnReport = &$MakeToolBtn "Report" "[HTML]" "#0284C7" "Export Diff Report to HTML"
    $toolWrap.Children.Add($btnSwap) | Out-Null
    $toolWrap.Children.Add($btnReload) | Out-Null
    $toolWrap.Children.Add($btnReport) | Out-Null

    $toolBorder.Child = $toolWrap
    $viewText.Children.Add($toolBorder) | Out-Null

    # 2. Search / Find Bar (Ctrl+F)
    $searchBorder = New-Object System.Windows.Controls.Border
    $searchBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEF3C7")
    $searchBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F59E0B")
    $searchBorder.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1)
    $searchBorder.Padding = New-Object System.Windows.Thickness(8,4,8,4)
    $searchBorder.Visibility = "Collapsed"
    [System.Windows.Controls.Grid]::SetRow($searchBorder, 2)

    $searchGrid = New-Object System.Windows.Controls.Grid
    for ($sc=0; $sc -lt 6; $sc++) { $col = New-Object System.Windows.Controls.ColumnDefinition; $col.Width = [System.Windows.GridLength]::Auto; $searchGrid.ColumnDefinitions.Add($col) }
    $searchGrid.ColumnDefinitions[1].Width = New-Object System.Windows.GridLength(250)
    $searchGrid.ColumnDefinitions[5].Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $colX = New-Object System.Windows.Controls.ColumnDefinition; $colX.Width = [System.Windows.GridLength]::Auto; $searchGrid.ColumnDefinitions.Add($colX)

    $lblSearch = New-Object System.Windows.Controls.TextBlock; $lblSearch.Text = "Find: "; $lblSearch.VerticalAlignment = "Center"; $lblSearch.FontWeight = [System.Windows.FontWeights]::SemiBold; [System.Windows.Controls.Grid]::SetColumn($lblSearch, 0); $searchGrid.Children.Add($lblSearch) | Out-Null
    $txtSearch = New-Object System.Windows.Controls.TextBox; $txtSearch.FontSize = 12; $txtSearch.Padding = New-Object System.Windows.Thickness(4,2,4,2); [System.Windows.Controls.Grid]::SetColumn($txtSearch, 1); $searchGrid.Children.Add($txtSearch) | Out-Null
    $btnFindNext = New-Object System.Windows.Controls.Button; $btnFindNext.Content = " Next (F3) "; $btnFindNext.Margin = New-Object System.Windows.Thickness(4,0,2,0); $btnFindNext.Padding = New-Object System.Windows.Thickness(6,2,6,2); $btnFindNext.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnFindNext, 2); $searchGrid.Children.Add($btnFindNext) | Out-Null
    $btnFindPrev = New-Object System.Windows.Controls.Button; $btnFindPrev.Content = " Prev (Shift+F3) "; $btnFindPrev.Margin = New-Object System.Windows.Thickness(2,0,4,0); $btnFindPrev.Padding = New-Object System.Windows.Thickness(6,2,6,2); $btnFindPrev.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnFindPrev, 3); $searchGrid.Children.Add($btnFindPrev) | Out-Null
    $chkMatchCase = New-Object System.Windows.Controls.CheckBox; $chkMatchCase.Content = "Match case"; $chkMatchCase.VerticalAlignment = "Center"; $chkMatchCase.Margin = New-Object System.Windows.Thickness(6,0,6,0); [System.Windows.Controls.Grid]::SetColumn($chkMatchCase, 4); $searchGrid.Children.Add($chkMatchCase) | Out-Null
    $lblSearchResult = New-Object System.Windows.Controls.TextBlock; $lblSearchResult.Text = ""; $lblSearchResult.VerticalAlignment = "Center"; $lblSearchResult.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#92400E"); $lblSearchResult.Margin = New-Object System.Windows.Thickness(12,0,0,0); [System.Windows.Controls.Grid]::SetColumn($lblSearchResult, 5); $searchGrid.Children.Add($lblSearchResult) | Out-Null
    $btnCloseSearch = New-Object System.Windows.Controls.Button; $btnCloseSearch.Content = " X "; $btnCloseSearch.Padding = New-Object System.Windows.Thickness(6,1,6,1); $btnCloseSearch.Cursor = [System.Windows.Input.Cursors]::Hand; $btnCloseSearch.Background = [System.Windows.Media.Brushes]::Transparent; $btnCloseSearch.BorderThickness = New-Object System.Windows.Thickness(0); [System.Windows.Controls.Grid]::SetColumn($btnCloseSearch, 6); $searchGrid.Children.Add($btnCloseSearch) | Out-Null

    $searchBorder.Child = $searchGrid
    $viewText.Children.Add($searchBorder) | Out-Null

    # 3. Path & Format Bar (Matches Screenshot 2 Exactly)
    $pathGrid = New-Object System.Windows.Controls.Grid
    $pathGrid.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8")
    $pathGrid.Margin = New-Object System.Windows.Thickness(0,2,0,2)
    [System.Windows.Controls.Grid]::SetRow($pathGrid, 3)

    $pgc0 = New-Object System.Windows.Controls.ColumnDefinition; $pgc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $pgc1 = New-Object System.Windows.Controls.ColumnDefinition; $pgc1.Width = [System.Windows.GridLength]::Auto
    $pgc2 = New-Object System.Windows.Controls.ColumnDefinition; $pgc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $pgc3 = New-Object System.Windows.Controls.ColumnDefinition; $pgc3.Width = [System.Windows.GridLength]::Auto
    $pathGrid.ColumnDefinitions.Add($pgc0); $pathGrid.ColumnDefinitions.Add($pgc1); $pathGrid.ColumnDefinitions.Add($pgc2); $pathGrid.ColumnDefinitions.Add($pgc3)

    $spGutter = New-Object System.Windows.Controls.Border; $spGutter.Width = 34; [System.Windows.Controls.Grid]::SetColumn($spGutter, 1); $pathGrid.Children.Add($spGutter) | Out-Null
    $spMini = New-Object System.Windows.Controls.Border; $spMini.Width = 26; [System.Windows.Controls.Grid]::SetColumn($spMini, 3); $pathGrid.Children.Add($spMini) | Out-Null

    $MakePathSidePanel = {
        param($colIdx)
        $b = New-Object System.Windows.Controls.Border; $b.Padding = New-Object System.Windows.Thickness(4,2,4,2)
        $sp = New-Object System.Windows.Controls.StackPanel
        $r1 = New-Object System.Windows.Controls.Grid
        $rc0 = New-Object System.Windows.Controls.ColumnDefinition; $rc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $rc1 = New-Object System.Windows.Controls.ColumnDefinition; $rc1.Width = [System.Windows.GridLength]::Auto
        $rc2 = New-Object System.Windows.Controls.ColumnDefinition; $rc2.Width = [System.Windows.GridLength]::Auto
        $r1.ColumnDefinitions.Add($rc0); $r1.ColumnDefinitions.Add($rc1); $r1.ColumnDefinitions.Add($rc2)

        $txt = New-Object System.Windows.Controls.TextBox; $txt.Text = "Enter filename here"; $txt.FontSize = 11.5; $txt.Padding = New-Object System.Windows.Thickness(4,3,4,3); $txt.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#7F9DB9"); $txt.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B"); [System.Windows.Controls.Grid]::SetColumn($txt, 0); $r1.Children.Add($txt) | Out-Null
        $btnHist = New-Object System.Windows.Controls.Button; $btnHist.Content = " v "; $btnHist.Padding = New-Object System.Windows.Thickness(4,1,4,1); $btnHist.Margin = New-Object System.Windows.Thickness(1,0,0,0); $btnHist.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnHist, 1); $r1.Children.Add($btnHist) | Out-Null
        $btnBrowse = New-Object System.Windows.Controls.Button; $btnBrowse.Content = " ... "; $btnBrowse.Padding = New-Object System.Windows.Thickness(6,1,6,1); $btnBrowse.Margin = New-Object System.Windows.Thickness(2,0,0,0); $btnBrowse.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnBrowse, 2); $r1.Children.Add($btnBrowse) | Out-Null
        $sp.Children.Add($r1) | Out-Null

        $r2 = New-Object System.Windows.Controls.StackPanel; $r2.Orientation = [System.Windows.Controls.Orientation]::Horizontal; $r2.Margin = New-Object System.Windows.Thickness(0,3,0,0)
        $cmbFormat = New-Object System.Windows.Controls.ComboBox; $cmbFormat.FontSize = 10.5; $cmbFormat.Height = 20
        @("Everything Else", "SQL Query", "Delphi Source", "C# Source", "JSON Data", "XML / HTML", "Python", "Plain Text") | ForEach-Object { $cmbFormat.Items.Add($_) | Out-Null }
        $cmbFormat.SelectedIndex = 0; $cmbFormat.Margin = New-Object System.Windows.Thickness(0,0,8,0); $r2.Children.Add($cmbFormat) | Out-Null

        $cmbEnc = New-Object System.Windows.Controls.ComboBox; $cmbEnc.FontSize = 10.5; $cmbEnc.Height = 20
        @("ANSI", "UTF-8", "UTF-16", "ASCII") | ForEach-Object { $cmbEnc.Items.Add($_) | Out-Null }
        $cmbEnc.SelectedIndex = 0; $cmbEnc.Margin = New-Object System.Windows.Thickness(0,0,8,0); $r2.Children.Add($cmbEnc) | Out-Null

        $sp.Children.Add($r2) | Out-Null
        $b.Child = $sp
        [System.Windows.Controls.Grid]::SetColumn($b, $colIdx)
        return [PSCustomObject]@{ Border = $b; TxtPath = $txt; BtnBrowse = $btnBrowse; BtnHist = $btnHist; CmbFormat = $cmbFormat; CmbEnc = $cmbEnc }
    }

    $leftPane = &$MakePathSidePanel 0
    $rightPane = &$MakePathSidePanel 2
    $pathGrid.Children.Add($leftPane.Border) | Out-Null
    $pathGrid.Children.Add($rightPane.Border) | Out-Null
    $viewText.Children.Add($pathGrid) | Out-Null

    $txtLeftPath = $leftPane.TxtPath
    $txtRightPath = $rightPane.TxtPath
    $btnBrowseLeft = $leftPane.BtnBrowse
    $btnBrowseRight = $rightPane.BtnBrowse

    # 4. Main Diff Body (White Panes, Gutter, and Minimap matching Screenshot 2)
    $bodyGrid = New-Object System.Windows.Controls.Grid
    [System.Windows.Controls.Grid]::SetRow($bodyGrid, 4)
    $bgc0 = New-Object System.Windows.Controls.ColumnDefinition; $bgc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $bgc1 = New-Object System.Windows.Controls.ColumnDefinition; $bgc1.Width = [System.Windows.GridLength]::Auto
    $bodyGrid.ColumnDefinitions.Add($bgc0); $bodyGrid.ColumnDefinitions.Add($bgc1)

    $diffContainer = New-Object System.Windows.Controls.Border; $diffContainer.Background = [System.Windows.Media.Brushes]::White; $diffContainer.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C0C0C0"); $diffContainer.BorderThickness = New-Object System.Windows.Thickness(1); $diffContainer.Margin = New-Object System.Windows.Thickness(4,0,2,0)
    $viewContainer = New-Object System.Windows.Controls.Grid

    # View A: Main Myers Diff DataGrid
    $dgDiff = New-Object System.Windows.Controls.DataGrid
    $dgDiff.Background = [System.Windows.Media.Brushes]::White
    $dgDiff.Foreground = [System.Windows.Media.Brushes]::Black
    $dgDiff.RowBackground = [System.Windows.Media.Brushes]::White
    $dgDiff.AlternatingRowBackground = [System.Windows.Media.Brushes]::White
    $dgDiff.GridLinesVisibility = [System.Windows.Controls.DataGridGridLinesVisibility]::None
    $dgDiff.VerticalGridLinesBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E0E0E0")
    $dgDiff.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
    $dgDiff.FontSize = 11.5
    $dgDiff.AutoGenerateColumns = $false
    $dgDiff.IsReadOnly = $false
    $dgDiff.CanUserSortColumns = $false
    $dgDiff.HeadersVisibility = [System.Windows.Controls.DataGridHeadersVisibility]::None
    $dgDiff.BorderThickness = New-Object System.Windows.Thickness(0)

    $cLineL = New-Object System.Windows.Controls.DataGridTextColumn; $cLineL.Header = " "; $cLineL.Binding = New-Object System.Windows.Data.Binding("LineL"); $cLineL.Width = 38; $dgDiff.Columns.Add($cLineL)
    $cTextL = New-Object System.Windows.Controls.DataGridTextColumn; $cTextL.Header = "Left File"; $cTextL.Binding = New-Object System.Windows.Data.Binding("TextL"); $cTextL.Width = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star); $cTextL.IsReadOnly = $false; $dgDiff.Columns.Add($cTextL)
    $cAct   = New-Object System.Windows.Controls.DataGridTextColumn; $cAct.Header = "<>"; $cAct.Binding = New-Object System.Windows.Data.Binding("Action"); $cAct.Width = 30; $dgDiff.Columns.Add($cAct)
    $cLineR = New-Object System.Windows.Controls.DataGridTextColumn; $cLineR.Header = " "; $cLineR.Binding = New-Object System.Windows.Data.Binding("LineR"); $cLineR.Width = 38; $dgDiff.Columns.Add($cLineR)
    $cTextR = New-Object System.Windows.Controls.DataGridTextColumn; $cTextR.Header = "Right File"; $cTextR.Binding = New-Object System.Windows.Data.Binding("TextR"); $cTextR.Width = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star); $cTextR.IsReadOnly = $false; $dgDiff.Columns.Add($cTextR)

    $numStyle = New-Object System.Windows.Style([System.Windows.Controls.TextBlock])
    $numStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::TextAlignmentProperty, [System.Windows.TextAlignment]::Right)))
    $numStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::MarginProperty, (New-Object System.Windows.Thickness(0,0,6,0)))))
    $numStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::ForegroundProperty, ([System.Windows.Media.BrushConverter]::new().ConvertFromString("#64748B")))))
    $cLineL.ElementStyle = $numStyle; $cLineR.ElementStyle = $numStyle

    $actStyle = New-Object System.Windows.Style([System.Windows.Controls.TextBlock])
    $actStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::TextAlignmentProperty, [System.Windows.TextAlignment]::Center)))
    $actStyle.Setters.Add((New-Object System.Windows.Setter([System.Windows.Controls.TextBlock]::FontWeightProperty, [System.Windows.FontWeights]::Bold)))
    $cAct.ElementStyle = $actStyle

    $UpdateColWidths = {
        $w = $dgDiff.ActualWidth
        if ($w -gt 250) {
            $contentW = $w - 38 - 34 - 38 - 28
            if ($contentW -gt 200) {
                $half = [Math]::Floor($contentW / 2)
                $cTextL.Width = New-Object System.Windows.Controls.DataGridLength($half)
                $cTextR.Width = New-Object System.Windows.Controls.DataGridLength($half)
            }
        }
    }
    $dgDiff.Add_SizeChanged({ &$UpdateColWidths })
    $viewContainer.Children.Add($dgDiff) | Out-Null

    # View B: Dual Live Text Editor Container (for Edit Mode)
    $editorContainer = New-Object System.Windows.Controls.Grid; $editorContainer.Visibility = "Collapsed"
    $ecCol0 = New-Object System.Windows.Controls.ColumnDefinition; $ecCol0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $ecCol1 = New-Object System.Windows.Controls.ColumnDefinition; $ecCol1.Width = [System.Windows.GridLength]::Auto
    $ecCol2 = New-Object System.Windows.Controls.ColumnDefinition; $ecCol2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $editorContainer.ColumnDefinitions.Add($ecCol0); $editorContainer.ColumnDefinitions.Add($ecCol1); $editorContainer.ColumnDefinitions.Add($ecCol2)

    $txtEditorLeft = New-Object System.Windows.Controls.TextBox; $txtEditorLeft.AcceptsReturn = $true; $txtEditorLeft.AcceptsTab = $true; $txtEditorLeft.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtEditorLeft.FontSize = 11.5; $txtEditorLeft.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto; $txtEditorLeft.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto; $txtEditorLeft.BorderThickness = New-Object System.Windows.Thickness(0); [System.Windows.Controls.Grid]::SetColumn($txtEditorLeft, 0); $editorContainer.Children.Add($txtEditorLeft) | Out-Null
    $editorSplitter = New-Object System.Windows.Controls.GridSplitter; $editorSplitter.Width = 6; $editorSplitter.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8"); $editorSplitter.HorizontalAlignment = "Center"; [System.Windows.Controls.Grid]::SetColumn($editorSplitter, 1); $editorContainer.Children.Add($editorSplitter) | Out-Null
    $txtEditorRight = New-Object System.Windows.Controls.TextBox; $txtEditorRight.AcceptsReturn = $true; $txtEditorRight.AcceptsTab = $true; $txtEditorRight.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $txtEditorRight.FontSize = 11.5; $txtEditorRight.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto; $txtEditorRight.HorizontalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto; $txtEditorRight.BorderThickness = New-Object System.Windows.Thickness(0); [System.Windows.Controls.Grid]::SetColumn($txtEditorRight, 2); $editorContainer.Children.Add($txtEditorRight) | Out-Null
    $viewContainer.Children.Add($editorContainer) | Out-Null

    $diffContainer.Child = $viewContainer
    [System.Windows.Controls.Grid]::SetColumn($diffContainer, 0)
    $bodyGrid.Children.Add($diffContainer) | Out-Null

    # Minimap Border
    $miniBorder = New-Object System.Windows.Controls.Border; $miniBorder.Width = 26; $miniBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F1F5F9"); $miniBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#C0C0C0"); $miniBorder.BorderThickness = New-Object System.Windows.Thickness(1,0,1,0); $miniBorder.Margin = New-Object System.Windows.Thickness(0,0,4,0); $miniBorder.Cursor = [System.Windows.Input.Cursors]::Hand; $miniBorder.ToolTip = "Diff Minimap: Click on red lines to jump to differences"
    $miniCanvas = New-Object System.Windows.Controls.Canvas; $miniCanvas.Width = 26; $miniCanvas.Background = [System.Windows.Media.Brushes]::Transparent; $miniBorder.Child = $miniCanvas
    [System.Windows.Controls.Grid]::SetColumn($miniBorder, 1); $bodyGrid.Children.Add($miniBorder) | Out-Null

    $viewText.Children.Add($bodyGrid) | Out-Null

    # 5. Intra-line Character Diff Bar
    $charBorder = New-Object System.Windows.Controls.Border; $charBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F8FAFC"); $charBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#CBD5E1"); $charBorder.BorderThickness = New-Object System.Windows.Thickness(0,1,0,0); $charBorder.Padding = New-Object System.Windows.Thickness(8,3,8,3); [System.Windows.Controls.Grid]::SetRow($charBorder, 5)
    $charGrid = New-Object System.Windows.Controls.Grid
    $cgc0 = New-Object System.Windows.Controls.ColumnDefinition; $cgc0.Width = [System.Windows.GridLength]::Auto
    $cgc1 = New-Object System.Windows.Controls.ColumnDefinition; $cgc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $charGrid.ColumnDefinitions.Add($cgc0); $charGrid.ColumnDefinitions.Add($cgc1)

    $lblCharDiffHeader = New-Object System.Windows.Controls.TextBlock; $lblCharDiffHeader.Text = "Char Diff: "; $lblCharDiffHeader.FontWeight = [System.Windows.FontWeights]::Bold; $lblCharDiffHeader.FontSize = 10.5; $lblCharDiffHeader.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#475569"); $lblCharDiffHeader.VerticalAlignment = "Center"; [System.Windows.Controls.Grid]::SetColumn($lblCharDiffHeader, 0); $charGrid.Children.Add($lblCharDiffHeader) | Out-Null
    $charCanvas = New-Object System.Windows.Controls.Canvas; $charCanvas.Height = 18; $charCanvas.ClipToBounds = $true; [System.Windows.Controls.Grid]::SetColumn($charCanvas, 1); $charGrid.Children.Add($charCanvas) | Out-Null
    $charBorder.Child = $charGrid
    $viewText.Children.Add($charBorder) | Out-Null

    # 6. Status Bar (Matches Screenshot 2 Exactly)
    $statGrid = New-Object System.Windows.Controls.Grid; $statGrid.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8"); $statGrid.Margin = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetRow($statGrid, 6)
    $sc0 = New-Object System.Windows.Controls.ColumnDefinition; $sc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $sc1 = New-Object System.Windows.Controls.ColumnDefinition; $sc1.Width = [System.Windows.GridLength]::Auto
    $sc2 = New-Object System.Windows.Controls.ColumnDefinition; $sc2.Width = [System.Windows.GridLength]::Auto
    $statGrid.ColumnDefinitions.Add($sc0); $statGrid.ColumnDefinitions.Add($sc1); $statGrid.ColumnDefinitions.Add($sc2)

    $lblStatusLeft = New-Object System.Windows.Controls.TextBlock; $lblStatusLeft.Text = "Same"; $lblStatusLeft.FontSize = 11; $lblStatusLeft.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333333"); $lblStatusLeft.Margin = New-Object System.Windows.Thickness(6,0,0,0); [System.Windows.Controls.Grid]::SetColumn($lblStatusLeft, 0); $statGrid.Children.Add($lblStatusLeft) | Out-Null
    $lblInsert = New-Object System.Windows.Controls.TextBlock; $lblInsert.Text = "Insert"; $lblInsert.FontSize = 11; $lblInsert.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333333"); $lblInsert.Margin = New-Object System.Windows.Thickness(0,0,16,0); [System.Windows.Controls.Grid]::SetColumn($lblInsert, 1); $statGrid.Children.Add($lblInsert) | Out-Null
    $lblLoadTime = New-Object System.Windows.Controls.TextBlock; $lblLoadTime.Text = "Load time: 0.03 seconds"; $lblLoadTime.FontSize = 11; $lblLoadTime.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333333"); $lblLoadTime.Margin = New-Object System.Windows.Thickness(0,0,6,0); [System.Windows.Controls.Grid]::SetColumn($lblLoadTime, 2); $statGrid.Children.Add($lblLoadTime) | Out-Null
    $viewText.Children.Add($statGrid) | Out-Null
    # -------------------------------------------------------------
    # VIEW 3: FOLDER COMPARE & FOLDER SYNC SCREEN
    # -------------------------------------------------------------
    $vfRow0 = New-Object System.Windows.Controls.RowDefinition; $vfRow0.Height = [System.Windows.GridLength]::Auto
    $vfRow1 = New-Object System.Windows.Controls.RowDefinition; $vfRow1.Height = [System.Windows.GridLength]::Auto
    $vfRow2 = New-Object System.Windows.Controls.RowDefinition; $vfRow2.Height = [System.Windows.GridLength]::Auto
    $vfRow3 = New-Object System.Windows.Controls.RowDefinition; $vfRow3.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vfRow4 = New-Object System.Windows.Controls.RowDefinition; $vfRow4.Height = [System.Windows.GridLength]::Auto
    $viewFolder.RowDefinitions.Add($vfRow0); $viewFolder.RowDefinitions.Add($vfRow1); $viewFolder.RowDefinitions.Add($vfRow2)
    $viewFolder.RowDefinitions.Add($vfRow3); $viewFolder.RowDefinitions.Add($vfRow4)

    # 0. Menu Bar
    $vfMenuGrid = New-Object System.Windows.Controls.Grid; $vfMenuGrid.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F6F7")
    $vfmc0 = New-Object System.Windows.Controls.ColumnDefinition; $vfmc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $vfmc1 = New-Object System.Windows.Controls.ColumnDefinition; $vfmc1.Width = [System.Windows.GridLength]::Auto; $vfMenuGrid.ColumnDefinitions.Add($vfmc0); $vfMenuGrid.ColumnDefinitions.Add($vfmc1)
    $vfMenu = New-Object System.Windows.Controls.Menu; $vfMenu.Background = [System.Windows.Media.Brushes]::Transparent; $vfMenu.Padding = New-Object System.Windows.Thickness(4,2,4,2)
    @("Session", "File", "Edit", "View", "Tools", "Help") | ForEach-Object { $m = New-Object System.Windows.Controls.MenuItem; $m.Header = "_$_"; $m.FontSize = 12; $vfMenu.Items.Add($m) | Out-Null }
    [System.Windows.Controls.Grid]::SetColumn($vfMenu, 0); $vfMenuGrid.Children.Add($vfMenu) | Out-Null
    $vfLblNewVer = New-Object System.Windows.Controls.TextBlock; $vfLblNewVer.Text = "New version available..."; $vfLblNewVer.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0066CC"); $vfLblNewVer.FontSize = 11; $vfLblNewVer.VerticalAlignment = "Center"; $vfLblNewVer.Margin = New-Object System.Windows.Thickness(0,0,12,0); $vfLblNewVer.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($vfLblNewVer, 1); $vfMenuGrid.Children.Add($vfLblNewVer) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($vfMenuGrid, 0); $viewFolder.Children.Add($vfMenuGrid) | Out-Null

    # 1. Folder Toolbar
    $vfToolBorder = New-Object System.Windows.Controls.Border; $vfToolBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8"); $vfToolBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D0D0"); $vfToolBorder.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1); $vfToolBorder.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetRow($vfToolBorder, 1)
    $vfToolWrap = New-Object System.Windows.Controls.WrapPanel

    $btnFHome = &$MakeToolBtn "Home" "[H]" "#2563EB" "Return to Beyond Compare Home Screen"
    $btnFSessions = &$MakeToolBtn "Sessions" "[S]" "#D97706" "Session Manager & Settings"
    $vfToolWrap.Children.Add($btnFHome) | Out-Null; $vfToolWrap.Children.Add($btnFSessions) | Out-Null; $vfToolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    $btnFShowAll   = New-Object System.Windows.Controls.Button; $btnFShowAll.Content = " * All Files "; $btnFShowAll.Padding = New-Object System.Windows.Thickness(6,3,6,3); $btnFShowAll.Margin = New-Object System.Windows.Thickness(0,0,3,0); $btnFShowAll.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnFShowAll) | Out-Null
    $btnFShowDiffs = New-Object System.Windows.Controls.Button; $btnFShowDiffs.Content = " != Modified "; $btnFShowDiffs.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEE2E2"); $btnFShowDiffs.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626"); $btnFShowDiffs.FontWeight = [System.Windows.FontWeights]::Bold; $btnFShowDiffs.Padding = New-Object System.Windows.Thickness(6,3,6,3); $btnFShowDiffs.Margin = New-Object System.Windows.Thickness(0,0,3,0); $btnFShowDiffs.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnFShowDiffs) | Out-Null
    $btnFShowLeftOnly = New-Object System.Windows.Controls.Button; $btnFShowLeftOnly.Content = " -> Left Only "; $btnFShowLeftOnly.Padding = New-Object System.Windows.Thickness(6,3,6,3); $btnFShowLeftOnly.Margin = New-Object System.Windows.Thickness(0,0,3,0); $btnFShowLeftOnly.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnFShowLeftOnly) | Out-Null
    $btnFShowRightOnly = New-Object System.Windows.Controls.Button; $btnFShowRightOnly.Content = " <- Right Only "; $btnFShowRightOnly.Padding = New-Object System.Windows.Thickness(6,3,6,3); $btnFShowRightOnly.Margin = New-Object System.Windows.Thickness(0,0,3,0); $btnFShowRightOnly.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnFShowRightOnly) | Out-Null
    $btnFShowSame  = New-Object System.Windows.Controls.Button; $btnFShowSame.Content = " = Same "; $btnFShowSame.Padding = New-Object System.Windows.Thickness(6,3,6,3); $btnFShowSame.Margin = New-Object System.Windows.Thickness(0,0,6,0); $btnFShowSame.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnFShowSame) | Out-Null
    $vfToolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    $btnSwapFolders = New-Object System.Windows.Controls.Button; $btnSwapFolders.Content = " <-> Swap "; $btnSwapFolders.Padding = New-Object System.Windows.Thickness(6,3,6,3); $btnSwapFolders.Margin = New-Object System.Windows.Thickness(0,0,6,0); $btnSwapFolders.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnSwapFolders) | Out-Null
    $btnRunFolderCompare = New-Object System.Windows.Controls.Button; $btnRunFolderCompare.Content = " [ Compare (F5) ] "; $btnRunFolderCompare.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#16A34A"); $btnRunFolderCompare.Foreground = [System.Windows.Media.Brushes]::White; $btnRunFolderCompare.FontWeight = [System.Windows.FontWeights]::Bold; $btnRunFolderCompare.Padding = New-Object System.Windows.Thickness(10,3,10,3); $btnRunFolderCompare.Cursor = [System.Windows.Input.Cursors]::Hand; $btnRunFolderCompare.BorderThickness = New-Object System.Windows.Thickness(0); $vfToolWrap.Children.Add($btnRunFolderCompare) | Out-Null
    $vfToolWrap.Children.Add((&$MakeToolSep)) | Out-Null

    # Sync Operations
    $btnSyncMirror = New-Object System.Windows.Controls.Button; $btnSyncMirror.Content = " Sync Left -> Right (Mirror) "; $btnSyncMirror.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#2563EB"); $btnSyncMirror.Foreground = [System.Windows.Media.Brushes]::White; $btnSyncMirror.FontWeight = [System.Windows.FontWeights]::Bold; $btnSyncMirror.Padding = New-Object System.Windows.Thickness(8,3,8,3); $btnSyncMirror.Margin = New-Object System.Windows.Thickness(0,0,4,0); $btnSyncMirror.Cursor = [System.Windows.Input.Cursors]::Hand; $btnSyncMirror.BorderThickness = New-Object System.Windows.Thickness(0); $vfToolWrap.Children.Add($btnSyncMirror) | Out-Null
    $btnSyncR2L = New-Object System.Windows.Controls.Button; $btnSyncR2L.Content = " Sync Right -> Left "; $btnSyncR2L.Padding = New-Object System.Windows.Thickness(8,3,8,3); $btnSyncR2L.Margin = New-Object System.Windows.Thickness(0,0,4,0); $btnSyncR2L.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnSyncR2L) | Out-Null
    $btnCopySelToRight = New-Object System.Windows.Controls.Button; $btnCopySelToRight.Content = " Copy Selected -> Right "; $btnCopySelToRight.Padding = New-Object System.Windows.Thickness(6,3,6,3); $btnCopySelToRight.Margin = New-Object System.Windows.Thickness(0,0,4,0); $btnCopySelToRight.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnCopySelToRight) | Out-Null
    $btnDeleteSel = New-Object System.Windows.Controls.Button; $btnDeleteSel.Content = " Delete Selected "; $btnDeleteSel.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626"); $btnDeleteSel.Padding = New-Object System.Windows.Thickness(6,3,6,3); $btnDeleteSel.Cursor = [System.Windows.Input.Cursors]::Hand; $vfToolWrap.Children.Add($btnDeleteSel) | Out-Null

    $vfToolBorder.Child = $vfToolWrap
    $viewFolder.Children.Add($vfToolBorder) | Out-Null

    # 2. Folder Path Bar
    $fpBar = New-Object System.Windows.Controls.Border; $fpBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F6F7"); $fpBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D0D0"); $fpBar.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1); $fpBar.Padding = New-Object System.Windows.Thickness(8,6,8,6); [System.Windows.Controls.Grid]::SetRow($fpBar, 2)
    $fpGrid = New-Object System.Windows.Controls.Grid; $fpc0 = New-Object System.Windows.Controls.ColumnDefinition; $fpc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $fpc1 = New-Object System.Windows.Controls.ColumnDefinition; $fpc1.Width = [System.Windows.GridLength]::Auto; $fpc2 = New-Object System.Windows.Controls.ColumnDefinition; $fpc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $fpGrid.ColumnDefinitions.Add($fpc0); $fpGrid.ColumnDefinitions.Add($fpc1); $fpGrid.ColumnDefinitions.Add($fpc2)

    $fpLeft = New-Object System.Windows.Controls.Grid; $fplc0 = New-Object System.Windows.Controls.ColumnDefinition; $fplc0.Width = [System.Windows.GridLength]::Auto; $fplc1 = New-Object System.Windows.Controls.ColumnDefinition; $fplc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $fplc2 = New-Object System.Windows.Controls.ColumnDefinition; $fplc2.Width = [System.Windows.GridLength]::Auto; $fpLeft.ColumnDefinitions.Add($fplc0); $fpLeft.ColumnDefinitions.Add($fplc1); $fpLeft.ColumnDefinitions.Add($fplc2)
    $lblFL = New-Object System.Windows.Controls.TextBlock; $lblFL.Text = "Left Folder:"; $lblFL.FontWeight = [System.Windows.FontWeights]::SemiBold; $lblFL.VerticalAlignment = "Center"; $lblFL.Margin = New-Object System.Windows.Thickness(0,0,6,0); [System.Windows.Controls.Grid]::SetColumn($lblFL, 0); $fpLeft.Children.Add($lblFL) | Out-Null
    $txtFolderLeft = New-Object System.Windows.Controls.TextBox; $txtFolderLeft.FontSize = 11.5; $txtFolderLeft.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetColumn($txtFolderLeft, 1); $fpLeft.Children.Add($txtFolderLeft) | Out-Null
    $btnBrowseFL = New-Object System.Windows.Controls.Button; $btnBrowseFL.Content = " ... "; $btnBrowseFL.Padding = New-Object System.Windows.Thickness(8,2,8,2); $btnBrowseFL.Margin = New-Object System.Windows.Thickness(4,0,8,0); $btnBrowseFL.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnBrowseFL, 2); $fpLeft.Children.Add($btnBrowseFL) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($fpLeft, 0); $fpGrid.Children.Add($fpLeft) | Out-Null

    $lblVs = New-Object System.Windows.Controls.TextBlock; $lblVs.Text = " vs "; $lblVs.FontWeight = [System.Windows.FontWeights]::Bold; $lblVs.VerticalAlignment = "Center"; $lblVs.Margin = New-Object System.Windows.Thickness(4,0,4,0); [System.Windows.Controls.Grid]::SetColumn($lblVs, 1); $fpGrid.Children.Add($lblVs) | Out-Null

    $fpRight = New-Object System.Windows.Controls.Grid; $fprc0 = New-Object System.Windows.Controls.ColumnDefinition; $fprc0.Width = [System.Windows.GridLength]::Auto; $fprc1 = New-Object System.Windows.Controls.ColumnDefinition; $fprc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $fprc2 = New-Object System.Windows.Controls.ColumnDefinition; $fprc2.Width = [System.Windows.GridLength]::Auto; $fpRight.ColumnDefinitions.Add($fprc0); $fpRight.ColumnDefinitions.Add($fprc1); $fpRight.ColumnDefinitions.Add($fprc2)
    $lblFR = New-Object System.Windows.Controls.TextBlock; $lblFR.Text = "Right Folder:"; $lblFR.FontWeight = [System.Windows.FontWeights]::SemiBold; $lblFR.VerticalAlignment = "Center"; $lblFR.Margin = New-Object System.Windows.Thickness(4,0,6,0); [System.Windows.Controls.Grid]::SetColumn($lblFR, 0); $fpRight.Children.Add($lblFR) | Out-Null
    $txtFolderRight = New-Object System.Windows.Controls.TextBox; $txtFolderRight.FontSize = 11.5; $txtFolderRight.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetColumn($txtFolderRight, 1); $fpRight.Children.Add($txtFolderRight) | Out-Null
    $btnBrowseFR = New-Object System.Windows.Controls.Button; $btnBrowseFR.Content = " ... "; $btnBrowseFR.Padding = New-Object System.Windows.Thickness(8,2,8,2); $btnBrowseFR.Margin = New-Object System.Windows.Thickness(4,0,8,0); $btnBrowseFR.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnBrowseFR, 2); $fpRight.Children.Add($btnBrowseFR) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($fpRight, 2); $fpGrid.Children.Add($fpRight) | Out-Null

    $fpBar.Child = $fpGrid
    $viewFolder.Children.Add($fpBar) | Out-Null

    # 3. Folder Results DataGrid
    $dgFolder = New-Object System.Windows.Controls.DataGrid; $dgFolder.Background = [System.Windows.Media.Brushes]::White; $dgFolder.AutoGenerateColumns = $false; $dgFolder.IsReadOnly = $true; $dgFolder.CanUserSortColumns = $true; $dgFolder.GridLinesVisibility = [System.Windows.Controls.DataGridGridLinesVisibility]::Horizontal; $dgFolder.HorizontalGridLinesBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0"); $dgFolder.HeadersVisibility = [System.Windows.Controls.DataGridHeadersVisibility]::Column; $dgFolder.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI"); $dgFolder.FontSize = 11.5; [System.Windows.Controls.Grid]::SetRow($dgFolder, 3)

    $colFStat = New-Object System.Windows.Controls.DataGridTextColumn; $colFStat.Header = "Status"; $colFStat.Binding = New-Object System.Windows.Data.Binding("Status"); $colFStat.Width = 95; $dgFolder.Columns.Add($colFStat)
    $colFName = New-Object System.Windows.Controls.DataGridTextColumn; $colFName.Header = "File Name / Relative Path (Double-Click to Text Compare)"; $colFName.Binding = New-Object System.Windows.Data.Binding("Name"); $colFName.Width = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star); $dgFolder.Columns.Add($colFName)
    $colFSizeL = New-Object System.Windows.Controls.DataGridTextColumn; $colFSizeL.Header = "Left Size"; $colFSizeL.Binding = New-Object System.Windows.Data.Binding("SizeL"); $colFSizeL.Width = 95; $dgFolder.Columns.Add($colFSizeL)
    $colFSizeR = New-Object System.Windows.Controls.DataGridTextColumn; $colFSizeR.Header = "Right Size"; $colFSizeR.Binding = New-Object System.Windows.Data.Binding("SizeR"); $colFSizeR.Width = 95; $dgFolder.Columns.Add($colFSizeR)
    $colFModL = New-Object System.Windows.Controls.DataGridTextColumn; $colFModL.Header = "Left Modified"; $colFModL.Binding = New-Object System.Windows.Data.Binding("ModL"); $colFModL.Width = 140; $dgFolder.Columns.Add($colFModL)
    $colFModR = New-Object System.Windows.Controls.DataGridTextColumn; $colFModR.Header = "Right Modified"; $colFModR.Binding = New-Object System.Windows.Data.Binding("ModR"); $colFModR.Width = 140; $dgFolder.Columns.Add($colFModR)

    $fbc = [System.Windows.Media.BrushConverter]::new()
    $dgFolder.Add_LoadingRow({
        param($s, $e)
        try {
            if (-not $e -or -not $e.Row -or -not $e.Row.Item) { return }
            $st = [string]$e.Row.Item.Status
            if ($st -eq "MODIFIED") {
                $e.Row.Background = $fbc.ConvertFromString("#FFEAEA")
                $e.Row.Foreground = $fbc.ConvertFromString("#DC2626")
                $e.Row.FontWeight = [System.Windows.FontWeights]::Bold
            } elseif ($st -like "*ONLY") {
                $e.Row.Background = $fbc.ConvertFromString("#EFF6FF")
                $e.Row.Foreground = $fbc.ConvertFromString("#2563EB")
                $e.Row.FontWeight = [System.Windows.FontWeights]::SemiBold
            } else {
                $e.Row.Background = [System.Windows.Media.Brushes]::White
                $e.Row.Foreground = [System.Windows.Media.Brushes]::Black
                $e.Row.FontWeight = [System.Windows.FontWeights]::Normal
            }
        } catch {}
    })
    $viewFolder.Children.Add($dgFolder) | Out-Null

    # 4. Folder Status Bar
    $vfStatGrid = New-Object System.Windows.Controls.Grid; $vfStatGrid.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8"); $vfStatGrid.Margin = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetRow($vfStatGrid, 4)
    $lblFolderSummary = New-Object System.Windows.Controls.TextBlock; $lblFolderSummary.Text = "Ready to compare folders. Select Left and Right folders and click Compare."; $lblFolderSummary.FontSize = 11; $lblFolderSummary.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333333"); $lblFolderSummary.Margin = New-Object System.Windows.Thickness(6,0,0,0); $vfStatGrid.Children.Add($lblFolderSummary) | Out-Null
    $viewFolder.Children.Add($vfStatGrid) | Out-Null

    # -------------------------------------------------------------
    # VIEW 4: TABLE COMPARE SCREEN (CSV / TSV / Tabular)
    # -------------------------------------------------------------
    $vtblRow0 = New-Object System.Windows.Controls.RowDefinition; $vtblRow0.Height = [System.Windows.GridLength]::Auto
    $vtblRow1 = New-Object System.Windows.Controls.RowDefinition; $vtblRow1.Height = [System.Windows.GridLength]::Auto
    $vtblRow2 = New-Object System.Windows.Controls.RowDefinition; $vtblRow2.Height = [System.Windows.GridLength]::Auto
    $vtblRow3 = New-Object System.Windows.Controls.RowDefinition; $vtblRow3.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vtblRow4 = New-Object System.Windows.Controls.RowDefinition; $vtblRow4.Height = [System.Windows.GridLength]::Auto
    $viewTable.RowDefinitions.Add($vtblRow0); $viewTable.RowDefinitions.Add($vtblRow1); $viewTable.RowDefinitions.Add($vtblRow2)
    $viewTable.RowDefinitions.Add($vtblRow3); $viewTable.RowDefinitions.Add($vtblRow4)

    # Table Toolbar
    $vtblToolBorder = New-Object System.Windows.Controls.Border; $vtblToolBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8"); $vtblToolBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D0D0"); $vtblToolBorder.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1); $vtblToolBorder.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetRow($vtblToolBorder, 0)
    $vtblWrap = New-Object System.Windows.Controls.WrapPanel
    $btnTabHome = &$MakeToolBtn "Home" "[H]" "#2563EB" "Return to Home"
    $vtblWrap.Children.Add($btnTabHome) | Out-Null; $vtblWrap.Children.Add((&$MakeToolSep)) | Out-Null

    $lblDelim = New-Object System.Windows.Controls.TextBlock; $lblDelim.Text = "Delimiter:"; $lblDelim.VerticalAlignment = "Center"; $lblDelim.Margin = New-Object System.Windows.Thickness(4,0,4,0); $vtblWrap.Children.Add($lblDelim) | Out-Null
    $cmbTableDelim = New-Object System.Windows.Controls.ComboBox; $cmbTableDelim.FontSize = 11; $cmbTableDelim.Height = 22; @("Comma (,)", "Tab (\t)", "Semicolon (;)", "Pipe (|)") | ForEach-Object { $cmbTableDelim.Items.Add($_) | Out-Null }; $cmbTableDelim.SelectedIndex = 0; $cmbTableDelim.Margin = New-Object System.Windows.Thickness(0,0,8,0); $vtblWrap.Children.Add($cmbTableDelim) | Out-Null
    $btnRunTableCompare = New-Object System.Windows.Controls.Button; $btnRunTableCompare.Content = " [ Compare Tables (F5) ] "; $btnRunTableCompare.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#0284C7"); $btnRunTableCompare.Foreground = [System.Windows.Media.Brushes]::White; $btnRunTableCompare.FontWeight = [System.Windows.FontWeights]::Bold; $btnRunTableCompare.Padding = New-Object System.Windows.Thickness(10,3,10,3); $btnRunTableCompare.Cursor = [System.Windows.Input.Cursors]::Hand; $btnRunTableCompare.BorderThickness = New-Object System.Windows.Thickness(0); $vtblWrap.Children.Add($btnRunTableCompare) | Out-Null
    $vtblToolBorder.Child = $vtblWrap; $viewTable.Children.Add($vtblToolBorder) | Out-Null

    # Table Path Bar
    $tbPathBar = New-Object System.Windows.Controls.Border; $tbPathBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F6F7"); $tbPathBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D0D0"); $tbPathBar.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1); $tbPathBar.Padding = New-Object System.Windows.Thickness(8,4,8,4); [System.Windows.Controls.Grid]::SetRow($tbPathBar, 1)
    $tbPathGrid = New-Object System.Windows.Controls.Grid; $tbc0 = New-Object System.Windows.Controls.ColumnDefinition; $tbc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $tbc1 = New-Object System.Windows.Controls.ColumnDefinition; $tbc1.Width = [System.Windows.GridLength]::Auto; $tbc2 = New-Object System.Windows.Controls.ColumnDefinition; $tbc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $tbPathGrid.ColumnDefinitions.Add($tbc0); $tbPathGrid.ColumnDefinitions.Add($tbc1); $tbPathGrid.ColumnDefinitions.Add($tbc2)

    $tbLeft = New-Object System.Windows.Controls.Grid; $tblc0 = New-Object System.Windows.Controls.ColumnDefinition; $tblc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $tblc1 = New-Object System.Windows.Controls.ColumnDefinition; $tblc1.Width = [System.Windows.GridLength]::Auto; $tbLeft.ColumnDefinitions.Add($tblc0); $tbLeft.ColumnDefinitions.Add($tblc1)
    $txtTableLeft = New-Object System.Windows.Controls.TextBox; $txtTableLeft.FontSize = 11.5; $txtTableLeft.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetColumn($txtTableLeft, 0); $tbLeft.Children.Add($txtTableLeft) | Out-Null
    $btnBrowseTableL = New-Object System.Windows.Controls.Button; $btnBrowseTableL.Content = " ... "; $btnBrowseTableL.Padding = New-Object System.Windows.Thickness(6,2,6,2); $btnBrowseTableL.Margin = New-Object System.Windows.Thickness(4,0,6,0); $btnBrowseTableL.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnBrowseTableL, 1); $tbLeft.Children.Add($btnBrowseTableL) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($tbLeft, 0); $tbPathGrid.Children.Add($tbLeft) | Out-Null

    $lblTbVs = New-Object System.Windows.Controls.TextBlock; $lblTbVs.Text = " vs "; $lblTbVs.FontWeight = [System.Windows.FontWeights]::Bold; $lblTbVs.VerticalAlignment = "Center"; [System.Windows.Controls.Grid]::SetColumn($lblTbVs, 1); $tbPathGrid.Children.Add($lblTbVs) | Out-Null

    $tbRight = New-Object System.Windows.Controls.Grid; $tbrc0 = New-Object System.Windows.Controls.ColumnDefinition; $tbrc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $tbrc1 = New-Object System.Windows.Controls.ColumnDefinition; $tbrc1.Width = [System.Windows.GridLength]::Auto; $tbRight.ColumnDefinitions.Add($tbrc0); $tbRight.ColumnDefinitions.Add($tbrc1)
    $txtTableRight = New-Object System.Windows.Controls.TextBox; $txtTableRight.FontSize = 11.5; $txtTableRight.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetColumn($txtTableRight, 0); $tbRight.Children.Add($txtTableRight) | Out-Null
    $btnBrowseTableR = New-Object System.Windows.Controls.Button; $btnBrowseTableR.Content = " ... "; $btnBrowseTableR.Padding = New-Object System.Windows.Thickness(6,2,6,2); $btnBrowseTableR.Margin = New-Object System.Windows.Thickness(4,0,0,0); $btnBrowseTableR.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnBrowseTableR, 1); $tbRight.Children.Add($btnBrowseTableR) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($tbRight, 2); $tbPathGrid.Children.Add($tbRight) | Out-Null

    $tbPathBar.Child = $tbPathGrid; [System.Windows.Controls.Grid]::SetRow($tbPathBar, 1); $viewTable.Children.Add($tbPathBar) | Out-Null

    # Table Results DataGrid
    $dgTable = New-Object System.Windows.Controls.DataGrid; $dgTable.Background = [System.Windows.Media.Brushes]::White; $dgTable.AutoGenerateColumns = $false; $dgTable.IsReadOnly = $true; $dgTable.GridLinesVisibility = [System.Windows.Controls.DataGridGridLinesVisibility]::All; $dgTable.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $dgTable.FontSize = 11.5; [System.Windows.Controls.Grid]::SetRow($dgTable, 3)
    $colTRow = New-Object System.Windows.Controls.DataGridTextColumn; $colTRow.Header = "#"; $colTRow.Binding = New-Object System.Windows.Data.Binding("RowNum"); $colTRow.Width = 45; $dgTable.Columns.Add($colTRow)
    $colTStat = New-Object System.Windows.Controls.DataGridTextColumn; $colTStat.Header = "Status"; $colTStat.Binding = New-Object System.Windows.Data.Binding("Status"); $colTStat.Width = 85; $dgTable.Columns.Add($colTStat)
    $colTLeft = New-Object System.Windows.Controls.DataGridTextColumn; $colTLeft.Header = "Left Table Row"; $colTLeft.Binding = New-Object System.Windows.Data.Binding("Left"); $colTLeft.Width = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star); $dgTable.Columns.Add($colTLeft)
    $colTRight = New-Object System.Windows.Controls.DataGridTextColumn; $colTRight.Header = "Right Table Row"; $colTRight.Binding = New-Object System.Windows.Data.Binding("Right"); $colTRight.Width = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star); $dgTable.Columns.Add($colTRight)

    $dgTable.Add_LoadingRow({
        param($s, $e)
        try {
            if (-not $e -or -not $e.Row -or -not $e.Row.Item) { return }
            $st = [string]$e.Row.Item.Status
            if ($st -eq "MODIFIED") {
                $e.Row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFEAEA")
                $e.Row.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
                $e.Row.FontWeight = [System.Windows.FontWeights]::Bold
            } elseif ($st -eq "HEADER") {
                $e.Row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F1F5F9")
                $e.Row.FontWeight = [System.Windows.FontWeights]::Bold
            }
        } catch {}
    })
    $viewTable.Children.Add($dgTable) | Out-Null

    $lblTableSummary = New-Object System.Windows.Controls.TextBlock; $lblTableSummary.Text = "Ready to compare tables."; $lblTableSummary.FontSize = 11; $lblTableSummary.Margin = New-Object System.Windows.Thickness(6,4,6,4); [System.Windows.Controls.Grid]::SetRow($lblTableSummary, 4); $viewTable.Children.Add($lblTableSummary) | Out-Null

    # -------------------------------------------------------------
    # VIEW 5: HEX / BINARY COMPARE SCREEN
    # -------------------------------------------------------------
    $vhxRow0 = New-Object System.Windows.Controls.RowDefinition; $vhxRow0.Height = [System.Windows.GridLength]::Auto
    $vhxRow1 = New-Object System.Windows.Controls.RowDefinition; $vhxRow1.Height = [System.Windows.GridLength]::Auto
    $vhxRow2 = New-Object System.Windows.Controls.RowDefinition; $vhxRow2.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    $vhxRow3 = New-Object System.Windows.Controls.RowDefinition; $vhxRow3.Height = [System.Windows.GridLength]::Auto
    $viewHex.RowDefinitions.Add($vhxRow0); $viewHex.RowDefinitions.Add($vhxRow1); $viewHex.RowDefinitions.Add($vhxRow2); $viewHex.RowDefinitions.Add($vhxRow3)

    # Hex Toolbar
    $vhxToolBorder = New-Object System.Windows.Controls.Border; $vhxToolBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8"); $vhxToolBorder.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D0D0"); $vhxToolBorder.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1); $vhxToolBorder.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetRow($vhxToolBorder, 0)
    $vhxWrap = New-Object System.Windows.Controls.WrapPanel
    $btnHexHome = &$MakeToolBtn "Home" "[H]" "#2563EB" "Return to Home"
    $vhxWrap.Children.Add($btnHexHome) | Out-Null; $vhxWrap.Children.Add((&$MakeToolSep)) | Out-Null
    $btnRunHexCompare = New-Object System.Windows.Controls.Button; $btnRunHexCompare.Content = " [ Compare Binary (F5) ] "; $btnRunHexCompare.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#4F46E5"); $btnRunHexCompare.Foreground = [System.Windows.Media.Brushes]::White; $btnRunHexCompare.FontWeight = [System.Windows.FontWeights]::Bold; $btnRunHexCompare.Padding = New-Object System.Windows.Thickness(10,3,10,3); $btnRunHexCompare.Cursor = [System.Windows.Input.Cursors]::Hand; $btnRunHexCompare.BorderThickness = New-Object System.Windows.Thickness(0); $vhxWrap.Children.Add($btnRunHexCompare) | Out-Null
    $vhxToolBorder.Child = $vhxWrap; $viewHex.Children.Add($vhxToolBorder) | Out-Null

    # Hex Path Bar
    $hxPathBar = New-Object System.Windows.Controls.Border; $hxPathBar.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F5F6F7"); $hxPathBar.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#D0D0D0"); $hxPathBar.BorderThickness = New-Object System.Windows.Thickness(0,0,0,1); $hxPathBar.Padding = New-Object System.Windows.Thickness(8,4,8,4); [System.Windows.Controls.Grid]::SetRow($hxPathBar, 1)
    $hxPathGrid = New-Object System.Windows.Controls.Grid; $hxc0 = New-Object System.Windows.Controls.ColumnDefinition; $hxc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $hxc1 = New-Object System.Windows.Controls.ColumnDefinition; $hxc1.Width = [System.Windows.GridLength]::Auto; $hxc2 = New-Object System.Windows.Controls.ColumnDefinition; $hxc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $hxPathGrid.ColumnDefinitions.Add($hxc0); $hxPathGrid.ColumnDefinitions.Add($hxc1); $hxPathGrid.ColumnDefinitions.Add($hxc2)

    $hxLeft = New-Object System.Windows.Controls.Grid; $hxlc0 = New-Object System.Windows.Controls.ColumnDefinition; $hxlc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $hxlc1 = New-Object System.Windows.Controls.ColumnDefinition; $hxlc1.Width = [System.Windows.GridLength]::Auto; $hxLeft.ColumnDefinitions.Add($hxlc0); $hxLeft.ColumnDefinitions.Add($hxlc1)
    $txtHexLeft = New-Object System.Windows.Controls.TextBox; $txtHexLeft.FontSize = 11.5; $txtHexLeft.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetColumn($txtHexLeft, 0); $hxLeft.Children.Add($txtHexLeft) | Out-Null
    $btnBrowseHexL = New-Object System.Windows.Controls.Button; $btnBrowseHexL.Content = " ... "; $btnBrowseHexL.Padding = New-Object System.Windows.Thickness(6,2,6,2); $btnBrowseHexL.Margin = New-Object System.Windows.Thickness(4,0,6,0); $btnBrowseHexL.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnBrowseHexL, 1); $hxLeft.Children.Add($btnBrowseHexL) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($hxLeft, 0); $hxPathGrid.Children.Add($hxLeft) | Out-Null

    $lblHxVs = New-Object System.Windows.Controls.TextBlock; $lblHxVs.Text = " vs "; $lblHxVs.FontWeight = [System.Windows.FontWeights]::Bold; $lblHxVs.VerticalAlignment = "Center"; [System.Windows.Controls.Grid]::SetColumn($lblHxVs, 1); $hxPathGrid.Children.Add($lblHxVs) | Out-Null

    $hxRight = New-Object System.Windows.Controls.Grid; $hxrc0 = New-Object System.Windows.Controls.ColumnDefinition; $hxrc0.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star); $hxrc1 = New-Object System.Windows.Controls.ColumnDefinition; $hxrc1.Width = [System.Windows.GridLength]::Auto; $hxRight.ColumnDefinitions.Add($hxrc0); $hxRight.ColumnDefinitions.Add($hxrc1)
    $txtHexRight = New-Object System.Windows.Controls.TextBox; $txtHexRight.FontSize = 11.5; $txtHexRight.Padding = New-Object System.Windows.Thickness(4,3,4,3); [System.Windows.Controls.Grid]::SetColumn($txtHexRight, 0); $hxRight.Children.Add($txtHexRight) | Out-Null
    $btnBrowseHexR = New-Object System.Windows.Controls.Button; $btnBrowseHexR.Content = " ... "; $btnBrowseHexR.Padding = New-Object System.Windows.Thickness(6,2,6,2); $btnBrowseHexR.Margin = New-Object System.Windows.Thickness(4,0,0,0); $btnBrowseHexR.Cursor = [System.Windows.Input.Cursors]::Hand; [System.Windows.Controls.Grid]::SetColumn($btnBrowseHexR, 1); $hxRight.Children.Add($btnBrowseHexR) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($hxRight, 2); $hxPathGrid.Children.Add($hxRight) | Out-Null

    $hxPathBar.Child = $hxPathGrid; [System.Windows.Controls.Grid]::SetRow($hxPathBar, 1); $viewHex.Children.Add($hxPathBar) | Out-Null

    # Hex Results DataGrid
    $dgHex = New-Object System.Windows.Controls.DataGrid; $dgHex.Background = [System.Windows.Media.Brushes]::White; $dgHex.AutoGenerateColumns = $false; $dgHex.IsReadOnly = $true; $dgHex.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $dgHex.FontSize = 11.5; [System.Windows.Controls.Grid]::SetRow($dgHex, 2)
    $colHOff = New-Object System.Windows.Controls.DataGridTextColumn; $colHOff.Header = "Offset"; $colHOff.Binding = New-Object System.Windows.Data.Binding("Offset"); $colHOff.Width = 75; $dgHex.Columns.Add($colHOff)
    $colHStat = New-Object System.Windows.Controls.DataGridTextColumn; $colHStat.Header = "Status"; $colHStat.Binding = New-Object System.Windows.Data.Binding("Status"); $colHStat.Width = 65; $dgHex.Columns.Add($colHStat)
    $colHHexL = New-Object System.Windows.Controls.DataGridTextColumn; $colHHexL.Header = "Left Hex (16 Bytes)"; $colHHexL.Binding = New-Object System.Windows.Data.Binding("HexL"); $colHHexL.Width = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star); $dgHex.Columns.Add($colHHexL)
    $colHAscL = New-Object System.Windows.Controls.DataGridTextColumn; $colHAscL.Header = "ASCII L"; $colHAscL.Binding = New-Object System.Windows.Data.Binding("AscL"); $colHAscL.Width = 140; $dgHex.Columns.Add($colHAscL)
    $colHHexR = New-Object System.Windows.Controls.DataGridTextColumn; $colHHexR.Header = "Right Hex (16 Bytes)"; $colHHexR.Binding = New-Object System.Windows.Data.Binding("HexR"); $colHHexR.Width = New-Object System.Windows.Controls.DataGridLength(1, [System.Windows.Controls.DataGridLengthUnitType]::Star); $dgHex.Columns.Add($colHHexR)
    $colHAscR = New-Object System.Windows.Controls.DataGridTextColumn; $colHAscR.Header = "ASCII R"; $colHAscR.Binding = New-Object System.Windows.Data.Binding("AscR"); $colHAscR.Width = 140; $dgHex.Columns.Add($colHAscR)

    $dgHex.Add_LoadingRow({
        param($s, $e)
        try {
            if (-not $e -or -not $e.Row -or -not $e.Row.Item) { return }
            $st = [string]$e.Row.Item.Status
            if ($st -eq "DIFF") {
                $e.Row.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FFEAEA")
                $e.Row.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
                $e.Row.FontWeight = [System.Windows.FontWeights]::Bold
            }
        } catch {}
    })
    $viewHex.Children.Add($dgHex) | Out-Null

    $lblHexSummary = New-Object System.Windows.Controls.TextBlock; $lblHexSummary.Text = "Ready to compare binary."; $lblHexSummary.FontSize = 11; $lblHexSummary.Margin = New-Object System.Windows.Thickness(6,4,6,4); [System.Windows.Controls.Grid]::SetRow($lblHexSummary, 3); $viewHex.Children.Add($lblHexSummary) | Out-Null
    # -------------------------------------------------------------
    # 4. VIEW SWITCHER
    # -------------------------------------------------------------
    $ShowView = {
        param([string]$targetView)
        $viewHome.Visibility   = [System.Windows.Visibility]::Collapsed
        $viewText.Visibility   = [System.Windows.Visibility]::Collapsed
        $viewFolder.Visibility = [System.Windows.Visibility]::Collapsed
        $viewTable.Visibility  = [System.Windows.Visibility]::Collapsed
        $viewHex.Visibility    = [System.Windows.Visibility]::Collapsed

        if ($targetView -eq "HOME") {
            $viewHome.Visibility = [System.Windows.Visibility]::Visible
            $win.Title = "Home - Beyond Compare" + $script:AdminTag
            $win.Background = [System.Windows.Media.Brushes]::White
            $script:ActiveSessionType = "HOME"
        } elseif ($targetView -eq "TEXT") {
            $viewText.Visibility = [System.Windows.Visibility]::Visible
            $fn = if ($txtLeftPath -and $txtLeftPath.Text -and $txtLeftPath.Text -ne "Enter filename here") {
                [System.IO.Path]::GetFileName($txtLeftPath.Text)
            } else { "" }
            $win.Title = if ($fn) { "$fn - Text Compare - Beyond Compare" } else { "New Text Compare - Beyond Compare" }
            $win.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8")
            $script:ActiveSessionType = "TEXT"
            try { $win.UpdateLayout(); if ($UpdateColWidths) { &$UpdateColWidths } } catch {}
        } elseif ($targetView -eq "FOLDER") {
            $viewFolder.Visibility = [System.Windows.Visibility]::Visible
            $win.Title = "Folder Compare - Beyond Compare"
            $win.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8")
            $script:ActiveSessionType = "FOLDER"
        } elseif ($targetView -eq "TABLE") {
            $viewTable.Visibility = [System.Windows.Visibility]::Visible
            $win.Title = "Table Compare - Beyond Compare"
            $win.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8")
            $script:ActiveSessionType = "TABLE"
        } elseif ($targetView -eq "HEX") {
            $viewHex.Visibility = [System.Windows.Visibility]::Visible
            $win.Title = "Hex Compare - Beyond Compare"
            $win.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#ECE9D8")
            $script:ActiveSessionType = "HEX"
        }
    }

    # -------------------------------------------------------------
    # 5. CORE DIFF ENGINE & ALGORITHMS
    # -------------------------------------------------------------
    $sampleL = @"
FJobTimer: TTimer;
FNeeds: Integer;
FMapCount: Integer;
FSession: TFileSession;
{ changes }
procedure ProcessChangesTimer(Sender: TObject);

{ properties }
function GetEditStack: TSsEditStack;
function GetGapSize(ASide: TFileInside; AIndex: Integer): Integer;
function GetItems(AIndex: Integer): Integer;
function GetMap: TTextMap;
procedure SetNeeds(AValue: Integer);

property Session: TFileSession read FSession;
property State: TTextSessionState read GetState;
public
constructor Create(ASession: TFileSession);
destructor Destroy; override;
{ actions }
procedure ContentDelete(ASide: TFileInside; AStartIndex, AEndIndex: Integer);
function ContentFetch(ASide: TFileInside; AStartIndex: Integer): string;
procedure ContentInsert(ASide: TFileInside; var AIndex, AMapIndex: Integer);
procedure RemoveGap(AIndex: Integer);
{ child events }
"@

    $sampleR = @"
FJobTimer: TTimer;
FNeeds: Integer;
FMapCount: Integer;
FSession: TFileSession;
{ changes }
procedure ProcessChangesTimer(Sender: TObject);
{ misc }
procedure Clear;
procedure _Delete(AIndex, ACnt: Integer);
procedure _Insert(AIndex, AMapIndex: Integer);
{ properties }
function GetEditStack: TSsEditStack;
function GetGapSize(ASide: TFileInside; AIndex: Integer): Integer;
function GetItems(AIndex: Integer): Integer;
function GetMap: TTextMap;
procedure SetNeeds(AValue: Integer);

property Session: TFileSession read FSession;
property State: TTextSessionState read GetState;
public
constructor Create(ASession: TFileSession);
destructor Destroy; override;
{ actions }
procedure Delete(ASide: TFileInside; AStartIndex, AEndIndex: Integer);
function Fetch(ASide: TFileInside; AStartIndex: Integer): string;
procedure Insert(ASide: TFileInside; var AIndex, AMapIndex: Integer);
procedure RemoveGap(AIndex: Integer);
{ child events }
"@

    if (-not [string]::IsNullOrEmpty($leftText) -or -not [string]::IsNullOrEmpty($rightText)) {
        $txtEditorLeft.Text = if ($leftText) { $leftText } else { "" }
        $txtEditorRight.Text = if ($rightText) { $rightText } else { "" }
        if ($leftTitle) { $txtLeftPath.Text = $leftTitle; $txtLeftPath.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B"); $cTextL.Header = $leftTitle; $win.Title = "$leftTitle - Text Compare - Beyond Compare" }
        if ($rightTitle) { $txtRightPath.Text = $rightTitle; $txtRightPath.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B"); $cTextR.Header = $rightTitle }
    } else {
        $txtEditorLeft.Text = $sampleL
        $txtEditorRight.Text = $sampleR
    }

    $NormalizeLine = {
        param([string]$line)
        if ($null -eq $line) { return "" }
        $s = $line
        if ($script:RuleIgnoreCase) { $s = $s.ToLowerInvariant() }
        if ($script:RuleIgnoreAllWs) {
            $s = [regex]::Replace($s, "\s+", " ").Trim()
        } else {
            if ($script:RuleIgnoreLeadingWs) { $s = $s.TrimStart() }
            if ($script:RuleIgnoreTrailingWs) { $s = $s.TrimEnd() }
        }
        return $s
    }

    # Character-level Myers Diff
    $GetCharDiff = {
        param([string]$s1, [string]$s2)
        if ($null -eq $s1) { $s1 = "" }; if ($null -eq $s2) { $s2 = "" }
        $n = $s1.Length; $m = $s2.Length
        if ($n -eq 0 -and $m -eq 0) { return @() }
        if ($n -eq 0) {
            $ops = [System.Collections.Generic.List[object]]::new()
            for ($j=0; $j -lt $m; $j++) { $ops.Add([PSCustomObject]@{ Type="INSERT"; CharA=$null; CharB=$s2[$j] }) }
            return $ops
        }
        if ($m -eq 0) {
            $ops = [System.Collections.Generic.List[object]]::new()
            for ($i=0; $i -lt $n; $i++) { $ops.Add([PSCustomObject]@{ Type="DELETE"; CharA=$s1[$i]; CharB=$null }) }
            return $ops
        }
        if ($n -gt 250 -or $m -gt 250) { return @() }

        $max = $n + $m; $offset = $max; $v = [int[]]::new(2 * $max + 1); $trace = [System.Collections.Generic.List[int[]]]::new(); $done = $false
        for ($d = 0; $d -le $max; $d++) {
            $trace.Add([int[]]$v.Clone())
            for ($k = -$d; $k -le $d; $k += 2) {
                $kIdx = $k + $offset
                $x = if ($k -eq -$d -or ($k -ne $d -and $v[$kIdx - 1] -lt $v[$kIdx + 1])) { $v[$kIdx + 1] } else { $v[$kIdx - 1] + 1 }
                $y = $x - $k
                while ($x -lt $n -and $y -lt $m -and $s1[$x] -eq $s2[$y]) { $x++; $y++ }
                $v[$kIdx] = $x
                if ($x -ge $n -and $y -ge $m) { $done = $true; break }
            }
            if ($done) { break }
        }

        $res = [System.Collections.Generic.List[object]]::new()
        $curX = $n; $curY = $m
        for ($d = $trace.Count - 1; $d -ge 0; $d--) {
            $vSnap = $trace[$d]; $k = $curX - $curY; $kIdx = $k + $offset
            $prevK = if ($k -eq -$d -or ($k -ne $d -and $vSnap[$kIdx - 1] -lt $vSnap[$kIdx + 1])) { $k + 1 } else { $k - 1 }
            $prevX = $vSnap[$prevK + $offset]; $prevY = $prevX - $prevK
            while ($curX -gt $prevX -and $curY -gt $prevY) {
                $curX--; $curY--
                $res.Add([PSCustomObject]@{ Type="MATCH"; CharA=$s1[$curX]; CharB=$s2[$curY] })
            }
            if ($d -gt 0) {
                if ($curX -eq $prevX) { $curY--; $res.Add([PSCustomObject]@{ Type="INSERT"; CharA=$null; CharB=$s2[$curY] }) }
                elseif ($curY -eq $prevY) { $curX--; $res.Add([PSCustomObject]@{ Type="DELETE"; CharA=$s1[$curX]; CharB=$null }) }
            }
        }
        $res.Reverse()
        return $res
    }

    # Render Intra-Line Character Diff
    $RenderCharDiff = {
        param([string]$leftLine, [string]$rightLine)
        try {
            $charCanvas.Children.Clear()
            if ($null -eq $leftLine -and $null -eq $rightLine) { return }
            $ops = &$GetCharDiff $leftLine $rightLine
            $curX = 4; $charW = 7.2
            foreach ($op in $ops) {
                if ($op.Type -eq "MATCH") {
                    $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = [string]$op.CharA; $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $tb.FontSize = 11.5; $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#333333"); [System.Windows.Controls.Canvas]::SetLeft($tb, $curX); $charCanvas.Children.Add($tb) | Out-Null; $curX += $charW
                } elseif ($op.Type -eq "DELETE") {
                    $rect = New-Object System.Windows.Shapes.Rectangle; $rect.Width = $charW; $rect.Height = 16; $rect.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FECACA"); [System.Windows.Controls.Canvas]::SetLeft($rect, $curX); [System.Windows.Controls.Canvas]::SetTop($rect, 1); $charCanvas.Children.Add($rect) | Out-Null
                    $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = [string]$op.CharA; $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $tb.FontSize = 11.5; $tb.FontWeight = [System.Windows.FontWeights]::Bold; $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626"); [System.Windows.Controls.Canvas]::SetLeft($tb, $curX); $charCanvas.Children.Add($tb) | Out-Null; $curX += $charW
                } elseif ($op.Type -eq "INSERT") {
                    $rect = New-Object System.Windows.Shapes.Rectangle; $rect.Width = $charW; $rect.Height = 16; $rect.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#BBF7D0"); [System.Windows.Controls.Canvas]::SetLeft($rect, $curX); [System.Windows.Controls.Canvas]::SetTop($rect, 1); $charCanvas.Children.Add($rect) | Out-Null
                    $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = [string]$op.CharB; $tb.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas"); $tb.FontSize = 11.5; $tb.FontWeight = [System.Windows.FontWeights]::Bold; $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#16A34A"); [System.Windows.Controls.Canvas]::SetLeft($tb, $curX); $charCanvas.Children.Add($tb) | Out-Null; $curX += $charW
                }
            }
        } catch {}
    }

    # Eugene Myers O(ND) algorithm on lines
    $GetMyersDiff = {
        param([string[]]$linesA, [string[]]$linesB, [scriptblock]$norm)
        $nA = $linesA.Length; $nB = $linesB.Length
        if ($nA -eq 0 -and $nB -eq 0) { return @() }
        if ($nA -eq 0) {
            $ops = [System.Collections.Generic.List[object]]::new()
            for ($j = 0; $j -lt $nB; $j++) { $ops.Add([PSCustomObject]@{ Type = "INSERT"; IndexA = -1; IndexB = $j; TextA = $null; TextB = $linesB[$j] }) }
            return $ops
        }
        if ($nB -eq 0) {
            $ops = [System.Collections.Generic.List[object]]::new()
            for ($i = 0; $i -lt $nA; $i++) { $ops.Add([PSCustomObject]@{ Type = "DELETE"; IndexA = $i; IndexB = -1; TextA = $linesA[$i]; TextB = $null }) }
            return $ops
        }

        $normA = if ($norm) { $linesA | ForEach-Object { &$norm $_ } } else { $linesA }
        $normB = if ($norm) { $linesB | ForEach-Object { &$norm $_ } } else { $linesB }

        $max = $nA + $nB; $vSize = 2 * $max + 1; $offset = $max; $v = [int[]]::new($vSize); $trace = [System.Collections.Generic.List[int[]]]::new(); $done = $false
        for ($d = 0; $d -le $max; $d++) {
            $vCopy = [int[]]$v.Clone()
            $trace.Add($vCopy)
            for ($k = -$d; $k -le $d; $k += 2) {
                $kIdx = $k + $offset
                $x = if ($k -eq -$d -or ($k -ne $d -and $v[$kIdx - 1] -lt $v[$kIdx + 1])) { $v[$kIdx + 1] } else { $v[$kIdx - 1] + 1 }
                $y = $x - $k
                while ($x -lt $nA -and $y -lt $nB -and $normA[$x] -eq $normB[$y]) { $x++; $y++ }
                $v[$kIdx] = $x
                if ($x -ge $nA -and $y -ge $nB) { $done = $true; break }
            }
            if ($done) { break }
        }

        $result = [System.Collections.Generic.List[object]]::new()
        $curX = $nA; $curY = $nB
        for ($d = $trace.Count - 1; $d -ge 0; $d--) {
            $vSnap = $trace[$d]; $k = $curX - $curY; $kIdx = $k + $offset
            $prevK = if ($k -eq -$d -or ($k -ne $d -and $vSnap[$kIdx - 1] -lt $vSnap[$kIdx + 1])) { $k + 1 } else { $k - 1 }
            $prevX = $vSnap[$prevK + $offset]; $prevY = $prevX - $prevK
            while ($curX -gt $prevX -and $curY -gt $prevY) {
                $curX--; $curY--
                $result.Add([PSCustomObject]@{ Type = "MATCH"; IndexA = $curX; IndexB = $curY; TextA = $linesA[$curX]; TextB = $linesB[$curY] })
            }
            if ($d -gt 0) {
                if ($curX -eq $prevX) { $curY--; $result.Add([PSCustomObject]@{ Type = "INSERT"; IndexA = -1; IndexB = $curY; TextA = $null; TextB = $linesB[$curY] }) }
                elseif ($curY -eq $prevY) { $curX--; $result.Add([PSCustomObject]@{ Type = "DELETE"; IndexA = $curX; IndexB = -1; TextA = $linesA[$curX]; TextB = $null }) }
            }
        }
        $result.Reverse()
        return $result
    }

    $GetLineSim = {
        param([string]$s1, [string]$s2)
        if ($null -eq $s1 -or $null -eq $s2) { return 0.0 }
        if ($s1 -eq $s2) { return 1.0 }
        $l1 = $s1.Trim(); $l2 = $s2.Trim()
        if ($l1 -eq $l2) { return 0.95 }
        if ($l1.Length -eq 0 -or $l2.Length -eq 0) { return 0.0 }
        $m = [Math]::Min($l1.Length, 80); $n = [Math]::Min($l2.Length, 80)
        $dp = New-Object "int[,]" ($m + 1), ($n + 1)
        for ($i = 0; $i -lt $m; $i++) {
            $i1 = $i + 1
            for ($j = 0; $j -lt $n; $j++) {
                $j1 = $j + 1
                if ($l1[$i] -eq $l2[$j]) {
                    $dp[$i1, $j1] = $dp[$i, $j] + 1
                } else {
                    $v1 = $dp[$i1, $j]; $v2 = $dp[$i, $j1]
                    $dp[$i1, $j1] = [Math]::Max($v1, $v2)
                }
            }
        }
        return [double](($dp[$m, $n] * 2.0) / ($m + $n))
    }

    $AlignLinesDiff = {
        param([string[]]$linesA, [string[]]$linesB)
        $rawOps = &$GetMyersDiff $linesA $linesB $NormalizeLine
        $result = [System.Collections.Generic.List[PSCustomObject]]::new()
        $i = 0; $len = $rawOps.Count
        while ($i -lt $len) {
            $op = $rawOps[$i]
            if ($op.Type -eq "MATCH") {
                $origA = $op.TextA; $origB = $op.TextB
                $st = if ($origA -ne $origB) { "MINOR" } else { "SAME" }
                $result.Add([PSCustomObject]@{ Status = $st; IndexA = $op.IndexA; IndexB = $op.IndexB; TextA = $origA; TextB = $origB; Action = "" })
                $i++
            } else {
                $delHunk = [System.Collections.Generic.List[object]]::new()
                $insHunk = [System.Collections.Generic.List[object]]::new()
                while ($i -lt $len -and $rawOps[$i].Type -ne "MATCH") {
                    if ($rawOps[$i].Type -eq "DELETE") { $delHunk.Add($rawOps[$i]) } else { $insHunk.Add($rawOps[$i]) }
                    $i++
                }
                $pairCount = [Math]::Min($delHunk.Count, $insHunk.Count)
                for ($p = 0; $p -lt $pairCount; $p++) {
                    $d = $delHunk[$p]; $ins = $insHunk[$p]
                    $sim = &$GetLineSim $d.TextA $ins.TextB
                    $act = if ($sim -gt 0.3) { "<>" } else { "!=" }
                    $result.Add([PSCustomObject]@{ Status = "MODIFIED"; IndexA = $d.IndexA; IndexB = $ins.IndexB; TextA = $d.TextA; TextB = $ins.TextB; Action = $act })
                }
                if ($delHunk.Count -gt $pairCount) {
                    for ($dIdx = $pairCount; $dIdx -lt $delHunk.Count; $dIdx++) {
                        $d = $delHunk[$dIdx]
                        $result.Add([PSCustomObject]@{ Status = "DELETED_L"; IndexA = $d.IndexA; IndexB = -1; TextA = $d.TextA; TextB = $null; Action = "->" })
                    }
                } elseif ($insHunk.Count -gt $pairCount) {
                    for ($inIdx = $pairCount; $inIdx -lt $insHunk.Count; $inIdx++) {
                        $ins = $insHunk[$inIdx]
                        $result.Add([PSCustomObject]@{ Status = "ADDED_R"; IndexA = -1; IndexB = $ins.IndexB; TextA = $null; TextB = $ins.TextB; Action = "<-" })
                    }
                }
            }
        }
        return $result
    }

    # Main Diff Engine Runner
    $RunCompareEngine = {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $txtA = $txtEditorLeft.Text
            $txtB = $txtEditorRight.Text
            $linesA = if ([string]::IsNullOrEmpty($txtA)) { @() } else { $txtA -split "`r?`n" }
            $linesB = if ([string]::IsNullOrEmpty($txtB)) { @() } else { $txtB -split "`r?`n" }

            $aligned = &$AlignLinesDiff $linesA $linesB

            $dt = New-Object System.Data.DataTable
            [void]$dt.Columns.Add("Status", [string])
            [void]$dt.Columns.Add("LineL", [string])
            [void]$dt.Columns.Add("TextL", [string])
            [void]$dt.Columns.Add("Action", [string])
            [void]$dt.Columns.Add("LineR", [string])
            [void]$dt.Columns.Add("TextR", [string])
            [void]$dt.Columns.Add("RawIdx", [int])

            $rawIdx = 0; $diffCount = 0
            foreach ($item in $aligned) {
                $row = $dt.NewRow()
                $row["Status"] = $item.Status
                $row["LineL"]  = if ($item.IndexA -ge 0) { ($item.IndexA + 1).ToString() } else { "" }
                $row["TextL"]  = if ($item.TextA) { $item.TextA } else { "" }
                $row["Action"] = $item.Action
                $row["LineR"]  = if ($item.IndexB -ge 0) { ($item.IndexB + 1).ToString() } else { "" }
                $row["TextR"]  = if ($item.TextB) { $item.TextB } else { "" }
                $row["RawIdx"] = $rawIdx++
                $dt.Rows.Add($row)
                if ($item.Status -ne "SAME") { $diffCount++ }
            }

            $script:DtAll = $dt

            # Diffs table
            $dtD = $dt.Clone()
            foreach ($r in $dt.Rows) { if ($r["Status"] -ne "SAME") { [void]$dtD.ImportRow($r) } }
            $script:DtDiffs = $dtD

            # Same table
            $dtS = $dt.Clone()
            foreach ($r in $dt.Rows) { if ($r["Status"] -eq "SAME") { [void]$dtS.ImportRow($r) } }
            $script:DtSame = $dtS

            switch ($script:CurrentViewMode) {
                "ALL"     { $dgDiff.ItemsSource = $script:DtAll.DefaultView }
                "DIFFS"   { $dgDiff.ItemsSource = if ($script:DtDiffs.Rows.Count -gt 0) { $script:DtDiffs.DefaultView } else { $script:DtAll.DefaultView } }
                "SAME"    { $dgDiff.ItemsSource = $script:DtSame.DefaultView }
                default   { $dgDiff.ItemsSource = $script:DtAll.DefaultView }
            }

            $sw.Stop()
            $loadSec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
            $lblLoadTime.Text = "Load time: $loadSec seconds"
            if ($diffCount -eq 0) {
                $lblStatusLeft.Text = "Same"
                $lblStatusLeft.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#16A34A")
            } else {
                $lblStatusLeft.Text = "!= $diffCount difference section(s)"
                $lblStatusLeft.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
            }

            &$UpdateMinimap
        } catch {
            [System.Windows.MessageBox]::Show("Comparison Error: " + $_.Exception.Message)
        }
    }

    # Update Minimap Overview
    $UpdateMinimap = {
        try {
            $miniCanvas.Children.Clear()
            if (-not $script:DtAll -or $script:DtAll.Rows.Count -eq 0) { return }
            $totalLines = $script:DtAll.Rows.Count
            $h = $miniCanvas.ActualHeight
            if ($h -le 10) { $h = 600 }
            $yScale = $h / $totalLines
            for ($idx = 0; $idx -lt $totalLines; $idx++) {
                $st = [string]$script:DtAll.Rows[$idx]["Status"]
                if ($st -ne "SAME") {
                    $rect = New-Object System.Windows.Shapes.Rectangle
                    $rect.Width = 24; $rect.Height = [Math]::Max(1.5, $yScale)
                    $rect.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
                    [System.Windows.Controls.Canvas]::SetLeft($rect, 1)
                    [System.Windows.Controls.Canvas]::SetTop($rect, ($idx * $yScale))
                    $miniCanvas.Children.Add($rect) | Out-Null
                }
            }
        } catch {}
    }

    $miniBorder.Add_MouseDown({
        param($s, $e)
        try {
            if (-not $script:DtAll -or $script:DtAll.Rows.Count -eq 0) { return }
            $pt = $e.GetPosition($miniCanvas)
            $ratio = $pt.Y / $miniCanvas.ActualHeight
            $targetRow = [int][Math]::Floor($ratio * $dgDiff.Items.Count)
            if ($targetRow -ge 0 -and $targetRow -lt $dgDiff.Items.Count) {
                $dgDiff.SelectedIndex = $targetRow; $dgDiff.ScrollIntoView($dgDiff.Items[$targetRow])
            }
        } catch {}
    })

    $bc = [System.Windows.Media.BrushConverter]::new()
    $dgDiff.Add_LoadingRow({
        param($s, $e)
        try {
            if (-not $e -or -not $e.Row -or -not $e.Row.Item -or -not ($e.Row.Item -is [System.Data.DataRowView])) { return }
            $status = [string]$e.Row.Item["Status"]
            if ($status -eq "MODIFIED" -or $status -eq "DELETED_L" -or $status -eq "ADDED_R") {
                $e.Row.Background = $bc.ConvertFromString("#FFEAEA")
                $e.Row.Foreground = $bc.ConvertFromString("#DC2626")
                $e.Row.FontWeight = [System.Windows.FontWeights]::Bold
            } elseif ($status -eq "MINOR") {
                $e.Row.Background = $bc.ConvertFromString("#F3E8FF")
                $e.Row.Foreground = $bc.ConvertFromString("#7E22CE")
                $e.Row.FontWeight = [System.Windows.FontWeights]::Normal
            } else {
                $e.Row.Background = [System.Windows.Media.Brushes]::White
                $e.Row.Foreground = [System.Windows.Media.Brushes]::Black
                $e.Row.FontWeight = [System.Windows.FontWeights]::Normal
            }
        } catch {}
    })

    $dgDiff.Add_SelectionChanged({
        param($s, $e)
        try {
            if ($dgDiff.SelectedItem -and ($dgDiff.SelectedItem -is [System.Data.DataRowView])) {
                $row = $dgDiff.SelectedItem
                &$RenderCharDiff ([string]$row["TextL"]) ([string]$row["TextR"])
            }
        } catch {}
    })

    # 1-Click Gutter Merging
    $ActionCopyLeftToRight = {
        try {
            $row = $dgDiff.SelectedItem
            if ($row -and ($row -is [System.Data.DataRowView])) {
                $row["TextR"] = $row["TextL"]
                $row["Status"] = "SAME"
                $row["Action"] = ""
                &$SyncDataGridToEditors
            }
        } catch {}
    }

    $ActionCopyRightToLeft = {
        try {
            $row = $dgDiff.SelectedItem
            if ($row -and ($row -is [System.Data.DataRowView])) {
                $row["TextL"] = $row["TextR"]
                $row["Status"] = "SAME"
                $row["Action"] = ""
                &$SyncDataGridToEditors
            }
        } catch {}
    }

    $SyncDataGridToEditors = {
        try {
            $sbL = New-Object System.Text.StringBuilder
            $sbR = New-Object System.Text.StringBuilder
            foreach ($r in $script:DtAll.Rows) {
                if ($r["LineL"]) { [void]$sbL.AppendLine([string]$r["TextL"]) }
                if ($r["LineR"]) { [void]$sbR.AppendLine([string]$r["TextR"]) }
            }
            $txtEditorLeft.Text = $sbL.ToString().TrimEnd("`r`n")
            $txtEditorRight.Text = $sbR.ToString().TrimEnd("`r`n")
            $script:IsLeftDirty = $true; $script:IsRightDirty = $true
            &$RunCompareEngine
        } catch {}
    }

    $dgDiff.Add_MouseUp({
        param($s, $e)
        try {
            if ($dgDiff.CurrentCell -and $dgDiff.CurrentCell.Column -eq $cAct) {
                $row = $dgDiff.SelectedItem
                if ($row -and ($row -is [System.Data.DataRowView])) {
                    $act = [string]$row["Action"]
                    if ($act -eq "->" -or $act -eq "<>") { &$ActionCopyLeftToRight }
                    elseif ($act -eq "<-") { &$ActionCopyRightToLeft }
                }
            }
        } catch {}
    })

    # --- SAVE FUNCTIONALITIES (Ctrl+S, Ctrl+Shift+S) ---
    $ActionSaveLeft = {
        try {
            $path = $txtLeftPath.Text
            if (-not $path -or $path -eq "Enter filename here" -or -not (Test-Path $path -PathType Leaf)) {
                $sfd = New-Object Microsoft.Win32.SaveFileDialog
                $sfd.Filter = "All Files (*.*)|*.*|SQL Files (*.sql)|*.sql|Text Files (*.txt)|*.txt"
                $sfd.Title = "Save Left File As"
                if ($sfd.ShowDialog() -eq $true) { $path = $sfd.FileName; $txtLeftPath.Text = $path } else { return }
            }
            [System.IO.File]::WriteAllText($path, $txtEditorLeft.Text, [System.Text.Encoding]::UTF8)
            $script:IsLeftDirty = $false
            $lblStatusLeft.Text = "Saved Left File: $([System.IO.Path]::GetFileName($path))"
            $lblStatusLeft.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#16A34A")
            [System.Windows.MessageBox]::Show("Left file saved successfully:`r`n$path", "File Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } catch {
            [System.Windows.MessageBox]::Show("Error saving left file: $($_.Exception.Message)", "Save Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }

    $ActionSaveRight = {
        try {
            $path = $txtRightPath.Text
            if (-not $path -or $path -eq "Enter filename here" -or -not (Test-Path $path -PathType Leaf)) {
                $sfd = New-Object Microsoft.Win32.SaveFileDialog
                $sfd.Filter = "All Files (*.*)|*.*|SQL Files (*.sql)|*.sql|Text Files (*.txt)|*.txt"
                $sfd.Title = "Save Right File As"
                if ($sfd.ShowDialog() -eq $true) { $path = $sfd.FileName; $txtRightPath.Text = $path } else { return }
            }
            [System.IO.File]::WriteAllText($path, $txtEditorRight.Text, [System.Text.Encoding]::UTF8)
            $script:IsRightDirty = $false
            $lblStatusLeft.Text = "Saved Right File: $([System.IO.Path]::GetFileName($path))"
            $lblStatusLeft.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#16A34A")
            [System.Windows.MessageBox]::Show("Right file saved successfully:`r`n$path", "File Saved", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        } catch {
            [System.Windows.MessageBox]::Show("Error saving right file: $($_.Exception.Message)", "Save Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }

    # --- SEARCH & FIND ENGINE (Ctrl+F, F3, Shift+F3) ---
    $ActionToggleSearch = {
        if ($searchBorder.Visibility -eq "Collapsed") {
            $searchBorder.Visibility = "Visible"
            $txtSearch.Focus() | Out-Null
            $txtSearch.SelectAll()
        } else {
            $searchBorder.Visibility = "Collapsed"
            $dgDiff.Focus() | Out-Null
        }
    }

    $ActionFindNext = {
        $query = $txtSearch.Text
        if ([string]::IsNullOrEmpty($query) -or -not $script:DtAll) { return }
        $case = $chkMatchCase.IsChecked -eq $true
        $comp = if ($case) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }

        $curIdx = $dgDiff.SelectedIndex
        $cnt = $dgDiff.Items.Count
        $found = -1

        for ($i = $curIdx + 1; $i -lt $cnt; $i++) {
            $row = $dgDiff.Items[$i]
            $tL = [string]$row["TextL"]; $tR = [string]$row["TextR"]
            if (($tL -and $tL.IndexOf($query, $comp) -ge 0) -or ($tR -and $tR.IndexOf($query, $comp) -ge 0)) {
                $found = $i; break
            }
        }
        if ($found -eq -1) {
            for ($i = 0; $i -le $curIdx; $i++) {
                $row = $dgDiff.Items[$i]
                $tL = [string]$row["TextL"]; $tR = [string]$row["TextR"]
                if (($tL -and $tL.IndexOf($query, $comp) -ge 0) -or ($tR -and $tR.IndexOf($query, $comp) -ge 0)) {
                    $found = $i; break
                }
            }
        }

        if ($found -ge 0) {
            $dgDiff.SelectedIndex = $found
            $dgDiff.ScrollIntoView($dgDiff.Items[$found])
            $lblSearchResult.Text = "Match at line " + ($found + 1)
            $lblSearchResult.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#15803D")
        } else {
            $lblSearchResult.Text = "No matches found"
            $lblSearchResult.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
        }
    }

    $ActionFindPrev = {
        $query = $txtSearch.Text
        if ([string]::IsNullOrEmpty($query) -or -not $script:DtAll) { return }
        $case = $chkMatchCase.IsChecked -eq $true
        $comp = if ($case) { [System.StringComparison]::Ordinal } else { [System.StringComparison]::OrdinalIgnoreCase }

        $curIdx = $dgDiff.SelectedIndex
        if ($curIdx -lt 0) { $curIdx = $dgDiff.Items.Count }
        $found = -1

        for ($i = $curIdx - 1; $i -ge 0; $i--) {
            $row = $dgDiff.Items[$i]
            $tL = [string]$row["TextL"]; $tR = [string]$row["TextR"]
            if (($tL -and $tL.IndexOf($query, $comp) -ge 0) -or ($tR -and $tR.IndexOf($query, $comp) -ge 0)) {
                $found = $i; break
            }
        }
        if ($found -eq -1) {
            for ($i = $dgDiff.Items.Count - 1; $i -ge $curIdx; $i--) {
                $row = $dgDiff.Items[$i]
                $tL = [string]$row["TextL"]; $tR = [string]$row["TextR"]
                if (($tL -and $tL.IndexOf($query, $comp) -ge 0) -or ($tR -and $tR.IndexOf($query, $comp) -ge 0)) {
                    $found = $i; break
                }
            }
        }

        if ($found -ge 0) {
            $dgDiff.SelectedIndex = $found
            $dgDiff.ScrollIntoView($dgDiff.Items[$found])
            $lblSearchResult.Text = "Match at line " + ($found + 1)
            $lblSearchResult.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#15803D")
        } else {
            $lblSearchResult.Text = "No matches found"
            $lblSearchResult.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DC2626")
        }
    }

    # --- HTML DIFF REPORT GENERATOR ---
    $ActionExportReport = {
        try {
            if (-not $script:DtAll) { return }
            $sfd = New-Object Microsoft.Win32.SaveFileDialog
            $sfd.Filter = "HTML Diff Report (*.html)|*.html|Unified Patch (*.patch)|*.patch"
            $sfd.FileName = "BeyondCompare_Diff_Report.html"
            if ($sfd.ShowDialog() -ne $true) { return }

            $titleL = if ($txtLeftPath.Text) { $txtLeftPath.Text } else { "Left File" }
            $titleR = if ($txtRightPath.Text) { $txtRightPath.Text } else { "Right File" }

            $html = New-Object System.Text.StringBuilder
            [void]$html.AppendLine("<!DOCTYPE html><html><head><meta charset='utf-8'><title>Beyond Compare Report</title>")
            [void]$html.AppendLine("<style>")
            [void]$html.AppendLine("body { font-family: -apple-system, Segoe UI, Arial, sans-serif; margin: 20px; background: #FAFAFA; color: #222; }")
            [void]$html.AppendLine("h2 { margin-bottom: 4px; color: #1E3A8A; }")
            [void]$html.AppendLine(".meta { font-size: 12px; color: #64748B; margin-bottom: 16px; }")
            [void]$html.AppendLine("table { width: 100%; border-collapse: collapse; font-family: Consolas, monospace; font-size: 12px; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }")
            [void]$html.AppendLine("th { background: #ECE9D8; border-bottom: 1px solid #C0C0C0; padding: 6px 10px; text-align: left; }")
            [void]$html.AppendLine("td { padding: 3px 8px; border-bottom: 1px solid #F1F5F9; }")
            [void]$html.AppendLine(".num { width: 40px; text-align: right; color: #94A3B8; background: #F8FAFC; }")
            [void]$html.AppendLine(".mod { background: #FFEAEA; color: #DC2626; font-weight: bold; }")
            [void]$html.AppendLine(".same { background: #FFFFFF; color: #1E293B; }")
            [void]$html.AppendLine(".del { background: #FEE2E2; color: #991B1B; }")
            [void]$html.AppendLine(".ins { background: #DCFCE7; color: #15803D; }")
            [void]$html.AppendLine("</style></head><body>")
            [void]$html.AppendLine("<h2>Beyond Compare 5 - Comparison Report</h2>")
            [void]$html.AppendLine("<div class='meta'>Generated: " + (Get-Date) + " | Left: " + $titleL + " | Right: " + $titleR + "</div>")
            [void]$html.AppendLine("<table><thead><tr><th class='num'>#</th><th>" + $titleL + "</th><th style='text-align:center;'>&lt;&gt;</th><th class='num'>#</th><th>" + $titleR + "</th></tr></thead><tbody>")

            foreach ($r in $script:DtAll.Rows) {
                $st = [string]$r["Status"]
                $css = if ($st -eq "MODIFIED") { "mod" } elseif ($st -like "DELETED*") { "del" } elseif ($st -like "ADDED*") { "ins" } else { "same" }
                $tL = [System.Security.SecurityElement]::Escape([string]$r["TextL"])
                $tR = [System.Security.SecurityElement]::Escape([string]$r["TextR"])
                $lL = [string]$r["LineL"]; $lR = [string]$r["LineR"]; $act = [string]$r["Action"]
                [void]$html.AppendLine("<tr class='" + $css + "'><td class='num'>" + $lL + "</td><td>" + $tL + "</td><td style='text-align:center;'>" + $act + "</td><td class='num'>" + $lR + "</td><td>" + $tR + "</td></tr>")
            }
            [void]$html.AppendLine("</tbody></table></body></html>")
            [System.IO.File]::WriteAllText($sfd.FileName, $html.ToString(), [System.Text.Encoding]::UTF8)

            $ask = [System.Windows.MessageBox]::Show("Report saved successfully to:`r`n$($sfd.FileName)`r`n`r`nWould you like to open it now in your web browser?", "Report Exported", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Information)
            if ($ask -eq [System.Windows.MessageBoxResult]::Yes) { [System.Diagnostics.Process]::Start($sfd.FileName) | Out-Null }
        } catch {
            [System.Windows.MessageBox]::Show("Error exporting report: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }

    # --- COPY CLIPBOARD ENGINE ---
    $ActionCopyDiffs = {
        try {
            $sb = New-Object System.Text.StringBuilder
            foreach ($r in $script:DtAll.Rows) {
                if ($r["Status"] -ne "SAME") {
                    $lL = [string]$r["LineL"]; $tL = [string]$r["TextL"]; $act = [string]$r["Action"]; $lR = [string]$r["LineR"]; $tR = [string]$r["TextR"]
                    [void]$sb.AppendLine("$lL : $tL $act $lR : $tR")
                }
            }
            if ($sb.Length -gt 0) {
                [System.Windows.Clipboard]::SetText($sb.ToString())
                [System.Windows.MessageBox]::Show("Differences copied to clipboard.", "Clipboard", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            } else {
                [System.Windows.MessageBox]::Show("No differences to copy.", "Notice", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            }
        } catch {}
    }

    # --- EDIT MODE TOGGLE ---
    $ActionToggleEditMode = {
        if ($editorContainer.Visibility -eq "Collapsed") {
            $dgDiff.Visibility = "Collapsed"
            $editorContainer.Visibility = "Visible"
            $btnEdit.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DCFCE7")
        } else {
            $editorContainer.Visibility = "Collapsed"
            $dgDiff.Visibility = "Visible"
            $btnEdit.Background = [System.Windows.Media.Brushes]::Transparent
            &$RunCompareEngine
        }
    }

    # --- NAVIGATION ACTIONS ---
    $ActionNextDiff = {
        try {
            $cur = $dgDiff.SelectedIndex
            $cnt = $dgDiff.Items.Count
            for ($i = $cur + 1; $i -lt $cnt; $i++) {
                $row = $dgDiff.Items[$i]
                if ($row -and $row["Status"] -ne "SAME") { $dgDiff.SelectedIndex = $i; $dgDiff.ScrollIntoView($row); break }
            }
        } catch {}
    }

    $ActionPrevDiff = {
        try {
            $cur = $dgDiff.SelectedIndex
            if ($cur -lt 0) { $cur = $dgDiff.Items.Count }
            for ($i = $cur - 1; $i -ge 0; $i--) {
                $row = $dgDiff.Items[$i]
                if ($row -and $row["Status"] -ne "SAME") { $dgDiff.SelectedIndex = $i; $dgDiff.ScrollIntoView($row); break }
            }
        } catch {}
    }

    $ActionSwapSides = {
        $tmpT = $txtEditorLeft.Text; $txtEditorLeft.Text = $txtEditorRight.Text; $txtEditorRight.Text = $tmpT
        $tmpP = $txtLeftPath.Text; $txtLeftPath.Text = $txtRightPath.Text; $txtRightPath.Text = $tmpP
        &$RunCompareEngine
    }

    $ActionViewAll   = { $script:CurrentViewMode = "ALL"; if ($script:DtAll) { $dgDiff.ItemsSource = $script:DtAll.DefaultView }; $btnAll.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#E2E8F0"); $btnDiffs.Background = [System.Windows.Media.Brushes]::Transparent; $btnSame.Background = [System.Windows.Media.Brushes]::Transparent }
    $ActionViewDiffs = { $script:CurrentViewMode = "DIFFS"; if ($script:DtDiffs) { $dgDiff.ItemsSource = if ($script:DtDiffs.Rows.Count -gt 0) { $script:DtDiffs.DefaultView } else { $script:DtAll.DefaultView } }; $btnDiffs.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#FEE2E2"); $btnAll.Background = [System.Windows.Media.Brushes]::Transparent; $btnSame.Background = [System.Windows.Media.Brushes]::Transparent }
    $ActionViewSame  = { $script:CurrentViewMode = "SAME"; if ($script:DtSame) { $dgDiff.ItemsSource = $script:DtSame.DefaultView }; $btnSame.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#DCFCE7"); $btnAll.Background = [System.Windows.Media.Brushes]::Transparent; $btnDiffs.Background = [System.Windows.Media.Brushes]::Transparent }
    $ActionToggleMinor = { $script:RuleIgnoreCase = -not $script:RuleIgnoreCase; $script:RuleIgnoreAllWs = -not $script:RuleIgnoreAllWs; &$RunCompareEngine }

    # Rules Dialog
    $ActionOpenRules = {
        $rWin = New-Object System.Windows.Window; $rWin.Title = "Session Settings - Comparison Rules"; $rWin.Width = 420; $rWin.Height = 320; $rWin.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner; $rWin.Owner = $win
        $sp = New-Object System.Windows.Controls.StackPanel; $sp.Margin = New-Object System.Windows.Thickness(16)
        $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = "Comparison Rules & Alignment Settings"; $tb.FontWeight = [System.Windows.FontWeights]::Bold; $tb.FontSize = 13; $tb.Margin = New-Object System.Windows.Thickness(0,0,0,12); $sp.Children.Add($tb) | Out-Null
        $c1 = New-Object System.Windows.Controls.CheckBox; $c1.Content = "Ignore Leading Whitespace"; $c1.IsChecked = $script:RuleIgnoreLeadingWs; $c1.Margin = New-Object System.Windows.Thickness(0,4,0,4); $sp.Children.Add($c1) | Out-Null
        $c2 = New-Object System.Windows.Controls.CheckBox; $c2.Content = "Ignore Trailing Whitespace"; $c2.IsChecked = $script:RuleIgnoreTrailingWs; $c2.Margin = New-Object System.Windows.Thickness(0,4,0,4); $sp.Children.Add($c2) | Out-Null
        $c3 = New-Object System.Windows.Controls.CheckBox; $c3.Content = "Ignore All Whitespace Differences"; $c3.IsChecked = $script:RuleIgnoreAllWs; $c3.Margin = New-Object System.Windows.Thickness(0,4,0,4); $sp.Children.Add($c3) | Out-Null
        $c4 = New-Object System.Windows.Controls.CheckBox; $c4.Content = "Ignore Case (Case-Insensitive)"; $c4.IsChecked = $script:RuleIgnoreCase; $c4.Margin = New-Object System.Windows.Thickness(0,4,0,4); $sp.Children.Add($c4) | Out-Null
        $btnOk = New-Object System.Windows.Controls.Button; $btnOk.Content = " OK "; $btnOk.Width = 75; $btnOk.Height = 26; $btnOk.Margin = New-Object System.Windows.Thickness(0,16,0,0); $btnOk.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnOk.Add_Click({ $script:RuleIgnoreLeadingWs = $c1.IsChecked -eq $true; $script:RuleIgnoreTrailingWs = $c2.IsChecked -eq $true; $script:RuleIgnoreAllWs = $c3.IsChecked -eq $true; $script:RuleIgnoreCase = $c4.IsChecked -eq $true; $rWin.Close(); &$RunCompareEngine })
        $sp.Children.Add($btnOk) | Out-Null; $rWin.Content = $sp; [void]$rWin.ShowDialog()
    }
    # -------------------------------------------------------------
    # 6. FOLDER COMPARE & FOLDER SYNC ENGINES
    # -------------------------------------------------------------
    $RunFolderCompareEngine = {
        try {
            $dirL = $txtFolderLeft.Text; $dirR = $txtFolderRight.Text
            if (-not $dirL -or -not (Test-Path $dirL -PathType Container)) {
                [System.Windows.MessageBox]::Show("Please select a valid Left Folder.", "Invalid Folder", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning); return
            }
            if (-not $dirR -or -not (Test-Path $dirR -PathType Container)) {
                [System.Windows.MessageBox]::Show("Please select a valid Right Folder.", "Invalid Folder", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning); return
            }

            $script:AllFolderItems.Clear()
            $filesL = Get-ChildItem -Path $dirL -Recurse -File -ErrorAction SilentlyContinue
            $filesR = Get-ChildItem -Path $dirR -Recurse -File -ErrorAction SilentlyContinue

            $dictL = @{}
            foreach ($f in $filesL) { $rel = $f.FullName.Substring($dirL.Length).TrimStart("\", "/"); $dictL[$rel] = $f }
            $dictR = @{}
            foreach ($f in $filesR) { $rel = $f.FullName.Substring($dirR.Length).TrimStart("\", "/"); $dictR[$rel] = $f }

            $allKeys = New-Object System.Collections.Generic.HashSet[string]
            foreach ($k in $dictL.Keys) { [void]$allKeys.Add($k) }
            foreach ($k in $dictR.Keys) { [void]$allKeys.Add($k) }

            $diffs = 0
            foreach ($rel in ($allKeys | Sort-Object)) {
                $hasL = $dictL.ContainsKey($rel); $hasR = $dictR.ContainsKey($rel)
                $status = ""; $sizeL = ""; $sizeR = ""; $modL = ""; $modR = ""; $fullL = ""; $fullR = ""

                if ($hasL -and $hasR) {
                    $fL = $dictL[$rel]; $fR = $dictR[$rel]
                    $fullL = $fL.FullName; $fullR = $fR.FullName
                    $sizeL = "$($fL.Length) bytes"; $sizeR = "$($fR.Length) bytes"
                    $modL = $fL.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    $modR = $fR.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    if ($fL.Length -ne $fR.Length -or $fL.LastWriteTime -ne $fR.LastWriteTime) {
                        $status = "MODIFIED"; $diffs++
                    } else { $status = "SAME" }
                } elseif ($hasL) {
                    $fL = $dictL[$rel]; $fullL = $fL.FullName; $sizeL = "$($fL.Length) bytes"; $modL = $fL.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    $status = "LEFT ONLY"; $diffs++
                } else {
                    $fR = $dictR[$rel]; $fullR = $fR.FullName; $sizeR = "$($fR.Length) bytes"; $modR = $fR.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    $status = "RIGHT ONLY"; $diffs++
                }

                $script:AllFolderItems.Add([PSCustomObject]@{
                    Status = $status; Name = $rel; SizeL = $sizeL; SizeR = $sizeR; ModL = $modL; ModR = $modR; FullPathL = $fullL; FullPathR = $fullR
                })
            }

            $dgFolder.ItemsSource = $null; $dgFolder.ItemsSource = $script:AllFolderItems
            $lblFolderSummary.Text = "Total Items: " + $script:AllFolderItems.Count + " | Differences: " + $diffs
        } catch {
            [System.Windows.MessageBox]::Show("Folder compare error: " + $_.Exception.Message)
        }
    }

    # Folder Sync: Mirror Left to Right
    $RunFolderSyncMirror = {
        try {
            $dirL = $txtFolderLeft.Text; $dirR = $txtFolderRight.Text
            if (-not $dirL -or -not (Test-Path $dirL) -or -not $dirR) { return }
            if (-not (Test-Path $dirR)) { New-Item -ItemType Directory -Path $dirR -Force | Out-Null }

            $promptText = "Mirror Left folder to Right folder?`r`n`r`nSource: $dirL`r`nDestination: $dirR`r`n`r`nThis will copy all missing or updated files to the destination."
            $conf = [System.Windows.MessageBox]::Show($promptText, "Confirm Sync", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
            if ($conf -ne [System.Windows.MessageBoxResult]::Yes) { return }

            $copied = 0
            $srcFiles = Get-ChildItem -Path $dirL -Recurse -File
            foreach ($f in $srcFiles) {
                $rel = $f.FullName.Substring($dirL.Length).TrimStart("\", "/")
                $target = Join-Path $dirR $rel
                $targetDir = [System.IO.Path]::GetDirectoryName($target)
                if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                if (-not (Test-Path $target) -or (Get-Item $target).Length -ne $f.Length -or (Get-Item $target).LastWriteTime -lt $f.LastWriteTime) {
                    Copy-Item -Path $f.FullName -Destination $target -Force
                    $copied++
                }
            }
            [System.Windows.MessageBox]::Show("Folder Sync Complete!`r`n$copied file(s) synchronized to Right folder.", "Sync Successful", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            &$RunFolderCompareEngine
        } catch {
            [System.Windows.MessageBox]::Show("Sync Error: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }

    # Folder Sync: Right to Left
    $RunFolderSyncR2L = {
        try {
            $dirL = $txtFolderLeft.Text; $dirR = $txtFolderRight.Text
            if (-not $dirR -or -not (Test-Path $dirR) -or -not $dirL) { return }
            $copied = 0
            $srcFiles = Get-ChildItem -Path $dirR -Recurse -File
            foreach ($f in $srcFiles) {
                $rel = $f.FullName.Substring($dirR.Length).TrimStart("\", "/")
                $target = Join-Path $dirL $rel
                $targetDir = [System.IO.Path]::GetDirectoryName($target)
                if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
                if (-not (Test-Path $target) -or (Get-Item $target).Length -ne $f.Length -or (Get-Item $target).LastWriteTime -lt $f.LastWriteTime) {
                    Copy-Item -Path $f.FullName -Destination $target -Force; $copied++
                }
            }
            [System.Windows.MessageBox]::Show("Folder Sync Complete!`r`n$copied file(s) synchronized to Left folder.", "Sync Successful", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
            &$RunFolderCompareEngine
        } catch {
            [System.Windows.MessageBox]::Show("Sync Error: $($_.Exception.Message)", "Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }

    $RunCopySelectedToRight = {
        try {
            if ($dgFolder.SelectedItem) {
                $item = $dgFolder.SelectedItem
                $src = [string]$item.FullPathL
                if ($src -and (Test-Path $src -PathType Leaf)) {
                    $dst = Join-Path $txtFolderRight.Text ([string]$item.Name)
                    $dDir = [System.IO.Path]::GetDirectoryName($dst)
                    if (-not (Test-Path $dDir)) { New-Item -ItemType Directory -Path $dDir -Force | Out-Null }
                    Copy-Item -Path $src -Destination $dst -Force
                    &$RunFolderCompareEngine
                }
            }
        } catch {}
    }

    $RunDeleteSelected = {
        try {
            if ($dgFolder.SelectedItem) {
                $item = $dgFolder.SelectedItem
                $srcL = [string]$item.FullPathL; $srcR = [string]$item.FullPathR
                $c = [System.Windows.MessageBox]::Show("Are you sure you want to delete this file?", "Confirm Delete", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
                if ($c -eq [System.Windows.MessageBoxResult]::Yes) {
                    if ($srcL -and (Test-Path $srcL)) { Remove-Item $srcL -Force }
                    if ($srcR -and (Test-Path $srcR)) { Remove-Item $srcR -Force }
                    &$RunFolderCompareEngine
                }
            }
        } catch {}
    }

    # -------------------------------------------------------------
    # 7. TABLE COMPARE ENGINE (CSV / TSV / Delimited)
    # -------------------------------------------------------------
    $RunTableCompareEngine = {
        try {
            $pL = $txtTableLeft.Text; $pR = $txtTableRight.Text
            if (-not $pL -or -not (Test-Path $pL)) { [System.Windows.MessageBox]::Show("Please select a valid Left Table/CSV file.", "Notice"); return }
            if (-not $pR -or -not (Test-Path $pR)) { [System.Windows.MessageBox]::Show("Please select a valid Right Table/CSV file.", "Notice"); return }

            $delim = if ($cmbTableDelim.SelectedIndex -eq 1) { "`t" } elseif ($cmbTableDelim.SelectedIndex -eq 2) { ";" } elseif ($cmbTableDelim.SelectedIndex -eq 3) { "|" } else { "," }
            $textA = [System.IO.File]::ReadAllText($pL); $textB = [System.IO.File]::ReadAllText($pR)
            $linesA = $textA.Trim() -split "`r?`n"
            $linesB = $textB.Trim() -split "`r?`n"

            $script:AllTableItems.Clear()
            $maxRows = [Math]::Max($linesA.Count, $linesB.Count)
            $diffCount = 0

            for ($r = 0; $r -lt $maxRows; $r++) {
                $rowA = if ($r -lt $linesA.Count) { $linesA[$r] } else { "" }
                $rowB = if ($r -lt $linesB.Count) { $linesB[$r] } else { "" }
                $status = if ($r -eq 0) { "HEADER" } elseif ($rowA -eq $rowB) { "SAME" } else { "MODIFIED"; $diffCount++ }
                $script:AllTableItems.Add([PSCustomObject]@{
                    RowNum = ($r + 1); Status = $status; Left = $rowA; Right = $rowB
                })
            }

            $dgTable.ItemsSource = $null; $dgTable.ItemsSource = $script:AllTableItems
            $lblTableSummary.Text = "Total Rows: " + $script:AllTableItems.Count + " | Differences: " + $diffCount
        } catch {
            [System.Windows.MessageBox]::Show("Table compare error: " + $_.Exception.Message)
        }
    }

    # -------------------------------------------------------------
    # 8. HEX / BINARY COMPARE ENGINE
    # -------------------------------------------------------------
    $RunHexCompareEngine = {
        try {
            $pL = $txtHexLeft.Text; $pR = $txtHexRight.Text
            if (-not $pL -or -not (Test-Path $pL)) { [System.Windows.MessageBox]::Show("Please select a valid Left Binary file.", "Notice"); return }
            if (-not $pR -or -not (Test-Path $pR)) { [System.Windows.MessageBox]::Show("Please select a valid Right Binary file.", "Notice"); return }

            $bA = [System.IO.File]::ReadAllBytes($pL)
            $bB = [System.IO.File]::ReadAllBytes($pR)

            $script:AllHexItems.Clear()
            $maxLen = [Math]::Min([Math]::Max($bA.Length, $bB.Length), 65536)
            $blockSize = 16; $diffBytes = 0

            for ($offset = 0; $offset -lt $maxLen; $offset += $blockSize) {
                $hexA = @(); $hexB = @(); $ascA = ""; $ascB = ""; $isDiff = $false
                for ($i = 0; $i -lt $blockSize; $i++) {
                    $idx = $offset + $i
                    if ($idx -lt $bA.Length) {
                        $valA = $bA[$idx]; $hexA += ("{0:X2}" -f $valA)
                        $ascA += if ($valA -ge 32 -and $valA -le 126) { [char]$valA } else { "." }
                    } else { $hexA += "  "; $ascA += " " }
                    if ($idx -lt $bB.Length) {
                        $valB = $bB[$idx]; $hexB += ("{0:X2}" -f $valB)
                        $ascB += if ($valB -ge 32 -and $valB -le 126) { [char]$valB } else { "." }
                    } else { $hexB += "  "; $ascB += " " }

                    if ($idx -lt $bA.Length -and $idx -lt $bB.Length) {
                        if ($bA[$idx] -ne $bB[$idx]) { $isDiff = $true; $diffBytes++ }
                    } elseif ($idx -lt $bA.Length -or $idx -lt $bB.Length) { $isDiff = $true; $diffBytes++ }
                }

                $script:AllHexItems.Add([PSCustomObject]@{
                    Offset = ("{0:X8}" -f $offset)
                    Status = if ($isDiff) { "DIFF" } else { "SAME" }
                    HexL = ($hexA -join " ")
                    AscL = $ascA
                    HexR = ($hexB -join " ")
                    AscR = $ascB
                })
            }

            $dgHex.ItemsSource = $null; $dgHex.ItemsSource = $script:AllHexItems
            $lblHexSummary.Text = "Left Size: " + $bA.Length + " bytes | Right Size: " + $bB.Length + " bytes | Mismatches: " + $diffBytes + " bytes"
        } catch {
            [System.Windows.MessageBox]::Show("Hex compare error: " + $_.Exception.Message)
        }
    }

    # -------------------------------------------------------------
    # 9. WIRE UP FULL MENU ITEMS & ACTIONS
    # -------------------------------------------------------------
    $AddSubItem = {
        param($parentMenu, $header, $action, $shortcut)
        $mi = New-Object System.Windows.Controls.MenuItem
        $mi.Header = $header
        if ($shortcut) { $mi.InputGestureText = $shortcut }
        if ($action) { $mi.Add_Click($action) }
        $parentMenu.Items.Add($mi) | Out-Null
        return $mi
    }

    # Session Menu
    &$AddSubItem $mSession "New Session..." { &$ShowView "HOME" } "Ctrl+N"
    &$AddSubItem $mSession "Open Session Settings..." { &$ActionOpenRules } ""
    &$AddSubItem $mSession "Save Left File" { &$ActionSaveLeft } "Ctrl+S"
    &$AddSubItem $mSession "Save Right File" { &$ActionSaveRight } "Ctrl+Shift+S"
    $mSession.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    &$AddSubItem $mSession "Return to Home Screen" { &$ShowView "HOME" } "Ctrl+H"
    &$AddSubItem $mSession "Exit Beyond Compare" { $win.Close() } "Alt+F4"

    # File Menu
    &$AddSubItem $mFile "Save Left File" { &$ActionSaveLeft } "Ctrl+S"
    &$AddSubItem $mFile "Save Right File" { &$ActionSaveRight } "Ctrl+Shift+S"
    &$AddSubItem $mFile "Save Left File As..." { $sfd = New-Object Microsoft.Win32.SaveFileDialog; if ($sfd.ShowDialog() -eq $true) { [System.IO.File]::WriteAllText($sfd.FileName, $txtEditorLeft.Text); $txtLeftPath.Text = $sfd.FileName } } ""
    &$AddSubItem $mFile "Save Right File As..." { $sfd = New-Object Microsoft.Win32.SaveFileDialog; if ($sfd.ShowDialog() -eq $true) { [System.IO.File]::WriteAllText($sfd.FileName, $txtEditorRight.Text); $txtRightPath.Text = $sfd.FileName } } ""
    $mFile.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    &$AddSubItem $mFile "Reload Files & Re-Compare" { &$RunCompareEngine } "F5"
    &$AddSubItem $mFile "Export HTML Diff Report..." { &$ActionExportReport } "Ctrl+P"
    &$AddSubItem $mFile "Close Session" { &$ShowView "HOME" } "Ctrl+W"

    # Edit Menu
    &$AddSubItem $mEdit "Toggle Live Edit Mode" { &$ActionToggleEditMode } "Ctrl+E"
    &$AddSubItem $mEdit "Copy Left to Right" { &$ActionCopyLeftToRight } "Ctrl+Right"
    &$AddSubItem $mEdit "Copy Right to Left" { &$ActionCopyRightToLeft } "Ctrl+Left"
    &$AddSubItem $mEdit "Copy Differences to Clipboard" { &$ActionCopyDiffs } "Ctrl+C"

    # Search Menu
    &$AddSubItem $mSearch "Find..." { &$ActionToggleSearch } "Ctrl+F"
    &$AddSubItem $mSearch "Find Next" { &$ActionFindNext } "F3"
    &$AddSubItem $mSearch "Find Previous" { &$ActionFindPrev } "Shift+F3"
    $mSearch.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    &$AddSubItem $mSearch "Next Difference Section" { &$ActionNextDiff } "v"
    &$AddSubItem $mSearch "Previous Difference Section" { &$ActionPrevDiff } "^"

    # View Menu
    &$AddSubItem $mView "Show All Lines" { &$ActionViewAll } "*"
    &$AddSubItem $mView "Show Differences Only" { &$ActionViewDiffs } "!"
    &$AddSubItem $mView "Show Same Lines Only" { &$ActionViewSame } "="
    &$AddSubItem $mView "Toggle Minor Differences" { &$ActionToggleMinor } "~"
    $mView.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    &$AddSubItem $mView "Swap Sides" { &$ActionSwapSides } "<->"

    # Tools Menu
    &$AddSubItem $mTools "Comparison Rules..." { &$ActionOpenRules } ""
    &$AddSubItem $mTools "Export HTML Diff Report..." { &$ActionExportReport } ""

    # Help Menu
    $aboutText = "Beyond Compare Version 5.0.6 (build 30713) (64-bit)`r`nScooter Software Professional Edition`r`nLicensed to: mandar.k (Enterprise Offline Edition)`r`n100% Native Zero-Dependency Execution"
    &$AddSubItem $mHelp "About Beyond Compare..." { [System.Windows.MessageBox]::Show($aboutText, "About Beyond Compare", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) } ""

    # -------------------------------------------------------------
    # 10. CONNECT ALL BUTTON & DIALOG HANDLERS
    # -------------------------------------------------------------
    # Search Box Handlers
    $btnFindNext.Add_Click({ &$ActionFindNext })
    $btnFindPrev.Add_Click({ &$ActionFindPrev })
    $btnCloseSearch.Add_Click({ $searchBorder.Visibility = "Collapsed"; $dgDiff.Focus() | Out-Null })
    $txtSearch.Add_KeyDown({ param($s, $e) if ($e.Key -eq [System.Windows.Input.Key]::Enter) { &$ActionFindNext } elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) { $searchBorder.Visibility = "Collapsed" } })

    # Save & Export Handlers
    $btnSaveL.Add_Click({ &$ActionSaveLeft })
    $btnSaveR.Add_Click({ &$ActionSaveRight })
    $btnReport.Add_Click({ &$ActionExportReport })
    $btnCopy.Add_Click({ &$ActionCopyDiffs })

    # View Switching Handlers
    $btnTC.Add_Click({ &$ShowView "TEXT"; &$RunCompareEngine })
    $btnTM.Add_Click({ &$ShowView "TEXT"; &$RunCompareEngine })
    $btnFC.Add_Click({ &$ShowView "FOLDER" })
    $btnFM.Add_Click({ &$ShowView "FOLDER" })
    $btnFS.Add_Click({ &$ShowView "FOLDER" })
    $btnTabC.Add_Click({ &$ShowView "TABLE" })
    $btnHC.Add_Click({ &$ShowView "HEX" })

    $btnHome.Add_Click({ &$ShowView "HOME" })
    $btnFHome.Add_Click({ &$ShowView "HOME" })
    $btnTabHome.Add_Click({ &$ShowView "HOME" })
    $btnHexHome.Add_Click({ &$ShowView "HOME" })

    $tvSessions.Add_SelectedItemChanged({
        param($s, $e)
        try {
            if ($tvSessions.SelectedItem -and ($tvSessions.SelectedItem -is [System.Windows.Controls.TreeViewItem])) {
                $h = [string]$tvSessions.SelectedItem.Header
                if ($h -like "*Text*") { &$ShowView "TEXT"; &$RunCompareEngine }
                elseif ($h -like "*Folder*") { &$ShowView "FOLDER" }
                elseif ($h -like "*Table*") { &$ShowView "TABLE" }
                elseif ($h -like "*Hex*") { &$ShowView "HEX" }
            }
        } catch {}
    })

    # Search sessions filter
    $txtSearchSessions.Add_TextChanged({
        $q = $txtSearchSessions.Text.Trim().ToLowerInvariant()
        foreach ($node in $script:SessionTreeNodes) {
            $h = [string]$node.Header
            $node.Visibility = if (-not $q -or $h.ToLowerInvariant().Contains($q)) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        }
    })

    # Text Toolbar Buttons
    $btnAll.Add_Click({ &$ActionViewAll })
    $btnDiffs.Add_Click({ &$ActionViewDiffs })
    $btnSame.Add_Click({ &$ActionViewSame })
    $btnMinor.Add_Click({ &$ActionToggleMinor })
    $btnRules.Add_Click({ &$ActionOpenRules })
    $btnEdit.Add_Click({ &$ActionToggleEditMode })
    $btnNext.Add_Click({ &$ActionNextDiff })
    $btnPrev.Add_Click({ &$ActionPrevDiff })
    $btnSwap.Add_Click({ &$ActionSwapSides })
    $btnReload.Add_Click({ &$RunCompareEngine })

    # Folder Toolbar Handlers
    $btnFShowAll.Add_Click({ $dgFolder.ItemsSource = $script:AllFolderItems })
    $btnFShowDiffs.Add_Click({ $dgFolder.ItemsSource = ($script:AllFolderItems | Where-Object { $_.Status -ne "SAME" }) })
    $btnFShowLeftOnly.Add_Click({ $dgFolder.ItemsSource = ($script:AllFolderItems | Where-Object { $_.Status -like "*LEFT*" }) })
    $btnFShowRightOnly.Add_Click({ $dgFolder.ItemsSource = ($script:AllFolderItems | Where-Object { $_.Status -like "*RIGHT*" }) })
    $btnFShowSame.Add_Click({ $dgFolder.ItemsSource = ($script:AllFolderItems | Where-Object { $_.Status -eq "SAME" }) })
    $btnRunFolderCompare.Add_Click({ &$RunFolderCompareEngine })
    $btnSwapFolders.Add_Click({ $tmp = $txtFolderLeft.Text; $txtFolderLeft.Text = $txtFolderRight.Text; $txtFolderRight.Text = $tmp; if ($txtFolderLeft.Text -and $txtFolderRight.Text) { &$RunFolderCompareEngine } })
    $btnSyncMirror.Add_Click({ &$RunFolderSyncMirror })
    $btnSyncR2L.Add_Click({ &$RunFolderSyncR2L })
    $btnCopySelToRight.Add_Click({ &$RunCopySelectedToRight })
    $btnDeleteSel.Add_Click({ &$RunDeleteSelected })

    # Double-click folder item to drill-down into Text Compare
    $dgFolder.Add_MouseDoubleClick({
        try {
            if ($dgFolder.SelectedItem) {
                $item = $dgFolder.SelectedItem
                $pL = [string]$item.FullPathL; $pR = [string]$item.FullPathR
                $txtL = if ($pL -and (Test-Path $pL)) { [System.IO.File]::ReadAllText($pL) } else { "" }
                $txtR = if ($pR -and (Test-Path $pR)) { [System.IO.File]::ReadAllText($pR) } else { "" }
                $txtEditorLeft.Text = $txtL; $txtEditorRight.Text = $txtR
                $txtLeftPath.Text = if ($pL) { $pL } else { "Missing on Left" }
                $txtRightPath.Text = if ($pR) { $pR } else { "Missing on Right" }
                &$ShowView "TEXT"
                &$RunCompareEngine
            }
        } catch {}
    })

    # Table & Hex Compare Handlers
    $btnRunTableCompare.Add_Click({ &$RunTableCompareEngine })
    $btnRunHexCompare.Add_Click({ &$RunHexCompareEngine })

    # File & Folder Browse Dialogs
    $btnBrowseLeft.Add_Click({
        $ofd = New-Object Microsoft.Win32.OpenFileDialog; $ofd.Filter = "All Files (*.*)|*.*|SQL Files (*.sql)|*.sql|Text Files (*.txt)|*.txt"
        if ($ofd.ShowDialog() -eq $true) {
            $txtLeftPath.Text = $ofd.FileName; $txtLeftPath.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
            $txtEditorLeft.Text = [System.IO.File]::ReadAllText($ofd.FileName)
            &$RunCompareEngine
        }
    })
    $btnBrowseRight.Add_Click({
        $ofd = New-Object Microsoft.Win32.OpenFileDialog; $ofd.Filter = "All Files (*.*)|*.*|SQL Files (*.sql)|*.sql|Text Files (*.txt)|*.txt"
        if ($ofd.ShowDialog() -eq $true) {
            $txtRightPath.Text = $ofd.FileName; $txtRightPath.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#1E293B")
            $txtEditorRight.Text = [System.IO.File]::ReadAllText($ofd.FileName)
            &$RunCompareEngine
        }
    })
    $btnBrowseFL.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtFolderLeft.Text = $fbd.SelectedPath } })
    $btnBrowseFR.Add_Click({ $fbd = New-Object System.Windows.Forms.FolderBrowserDialog; if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $txtFolderRight.Text = $fbd.SelectedPath } })
    $btnBrowseTableL.Add_Click({ $ofd = New-Object Microsoft.Win32.OpenFileDialog; $ofd.Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"; if ($ofd.ShowDialog() -eq $true) { $txtTableLeft.Text = $ofd.FileName } })
    $btnBrowseTableR.Add_Click({ $ofd = New-Object Microsoft.Win32.OpenFileDialog; $ofd.Filter = "CSV Files (*.csv)|*.csv|All Files (*.*)|*.*"; if ($ofd.ShowDialog() -eq $true) { $txtTableRight.Text = $ofd.FileName } })
    $btnBrowseHexL.Add_Click({ $ofd = New-Object Microsoft.Win32.OpenFileDialog; if ($ofd.ShowDialog() -eq $true) { $txtHexLeft.Text = $ofd.FileName } })
    $btnBrowseHexR.Add_Click({ $ofd = New-Object Microsoft.Win32.OpenFileDialog; if ($ofd.ShowDialog() -eq $true) { $txtHexRight.Text = $ofd.FileName } })

    # Home Screen Drag-and-Drop
    $vhCanvasBorder.Add_Drop({
        param($s, $e)
        try {
            if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
                $files = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
                if ($files -and $files.Count -ge 2) {
                    if ((Test-Path $files[0] -PathType Container) -or (Test-Path $files[1] -PathType Container)) {
                        $txtFolderLeft.Text = $files[0]; $txtFolderRight.Text = $files[1]
                        &$ShowView "FOLDER"; &$RunFolderCompareEngine
                    } else {
                        $txtLeftPath.Text = $files[0]; $txtRightPath.Text = $files[1]
                        $txtEditorLeft.Text = [System.IO.File]::ReadAllText($files[0])
                        $txtEditorRight.Text = [System.IO.File]::ReadAllText($files[1])
                        &$ShowView "TEXT"; &$RunCompareEngine
                    }
                } elseif ($files -and $files.Count -eq 1) {
                    if (Test-Path $files[0] -PathType Container) {
                        $txtFolderLeft.Text = $files[0]; &$ShowView "FOLDER"
                    } else {
                        $txtLeftPath.Text = $files[0]
                        $txtEditorLeft.Text = [System.IO.File]::ReadAllText($files[0])
                        &$ShowView "TEXT"; &$RunCompareEngine
                    }
                }
            }
        } catch {}
    })

    # --- KEYBOARD SHORTCUTS ENGINE ---
    $win.Add_PreviewKeyDown({
        param($s, $e)
        $ctrl = [System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Control
        $ctrlShift = [System.Windows.Input.Keyboard]::Modifiers -eq ([System.Windows.Input.ModifierKeys]::Control -bor [System.Windows.Input.ModifierKeys]::Shift)

        if ($ctrlShift -and $e.Key -eq [System.Windows.Input.Key]::S) {
            &$ActionSaveRight; $e.Handled = $true; return
        } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::S) {
            &$ActionSaveLeft; $e.Handled = $true; return
        } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::F) {
            &$ActionToggleSearch; $e.Handled = $true; return
        } elseif ($e.Key -eq [System.Windows.Input.Key]::F3) {
            if ([System.Windows.Input.Keyboard]::Modifiers -eq [System.Windows.Input.ModifierKeys]::Shift) { &$ActionFindPrev } else { &$ActionFindNext }
            $e.Handled = $true; return
        } elseif ($e.Key -eq [System.Windows.Input.Key]::F5) {
            if ($script:ActiveSessionType -eq "TEXT") { &$RunCompareEngine }
            elseif ($script:ActiveSessionType -eq "FOLDER") { &$RunFolderCompareEngine }
            elseif ($script:ActiveSessionType -eq "TABLE") { &$RunTableCompareEngine }
            elseif ($script:ActiveSessionType -eq "HEX") { &$RunHexCompareEngine }
            $e.Handled = $true; return
        } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::E) {
            &$ActionToggleEditMode; $e.Handled = $true; return
        } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::Right) {
            &$ActionCopyLeftToRight; $e.Handled = $true; return
        } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::Left) {
            &$ActionCopyRightToLeft; $e.Handled = $true; return
        } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::Down) {
            &$ActionNextDiff; $e.Handled = $true; return
        } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::Up) {
            &$ActionPrevDiff; $e.Handled = $true; return
        } elseif ($ctrl -and $e.Key -eq [System.Windows.Input.Key]::W) {
            &$ShowView "HOME"; $e.Handled = $true; return
        } elseif ($e.Key -eq [System.Windows.Input.Key]::Escape) {
            if ($searchBorder.Visibility -eq "Visible") { $searchBorder.Visibility = "Collapsed"; $e.Handled = $true }
        }
    })

    # Window Loaded
    $win.Add_Loaded({
        if (($Path1 -and (Test-Path $Path1)) -or ($Path2 -and (Test-Path $Path2)) -or $LeftText -or $RightText) {
            &$ShowView "TEXT"
            &$RunCompareEngine
        } else {
            &$ShowView "HOME"
        }
    })

    $win.Add_Closed({
        $global:beyondCompareWin = $null
        $global:isBeyondCompareOpen = $false
    })

    [void]$win.ShowDialog()
} catch {
    [System.Windows.MessageBox]::Show("Error launching Beyond Compare:`n" + $_.Exception.ToString(), "Beyond Compare Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    $global:beyondCompareWin = $null
    $global:isBeyondCompareOpen = $false
}
