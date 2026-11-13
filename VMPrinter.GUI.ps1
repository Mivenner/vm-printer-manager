#Requires -Version 5.1
<# VM Printer Manager - interfaccia WPF. Richiede VMPrinter.Engine.psm1, GUI.xaml, logo.png nella stessa cartella. #>
[CmdletBinding()] param()
$script:Root = $PSScriptRoot
if (-not $script:Root) { try { $script:Root = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) } catch {} }
if (-not $script:Root) { $script:Root = [AppDomain]::CurrentDomain.BaseDirectory }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
function Show-FatalError([string]$Message, $Err) {
    $d = $Message; if ($Err) { $d += "`r`n" + $Err.InvocationInfo.PositionMessage + "`r`n" + $Err.ScriptStackTrace }
    foreach ($lp in (Join-Path $script:Root 'vmprn_error.log'), (Join-Path $env:TEMP 'vmprn_error.log')) { try { Add-Content -LiteralPath $lp -Value ("{0} {1}" -f (Get-Date -Format s), $d); break } catch {} }
    try { [System.Windows.MessageBox]::Show($Message, 'VM Printer Manager', 'OK', 'Error') | Out-Null } catch {}
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try { $exe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exe -match 'powershell(_ise)?\.exe$|pwsh\.exe$') { Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File', ('"' + $PSCommandPath + '"')) -Verb RunAs | Out-Null } else { Start-Process -FilePath $exe -Verb RunAs | Out-Null }
    } catch { Show-FatalError 'Sono necessari privilegi di amministratore.' }
    return
}
try {
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch {}
$EnginePath = Join-Path $script:Root 'VMPrinter.Engine.psm1'; $XamlPath = Join-Path $script:Root 'GUI.xaml'
foreach ($f in $EnginePath, $XamlPath) { if (-not (Test-Path -LiteralPath $f)) { Show-FatalError "File mancante: $f"; return } }
$EngineText = [System.IO.File]::ReadAllText($EnginePath, [System.Text.Encoding]::UTF8)
Import-Module (New-Module -Name 'VMPrinter.Engine' -ScriptBlock ([scriptblock]::Create($EngineText))) -Force
[xml]$xaml = Get-Content -LiteralPath $XamlPath -Raw -Encoding UTF8
$Window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}; $xaml.SelectNodes('//*[@Name]') | ForEach-Object { $ui[$_.Name] = $Window.FindName($_.Name) }
try { $logo = Join-Path $script:Root 'logo.png'; if (Test-Path -LiteralPath $logo) { $bmp = New-Object System.Windows.Media.Imaging.BitmapImage; $bmp.BeginInit(); $bmp.UriSource = New-Object System.Uri($logo); $bmp.CacheOption = 'OnLoad'; $bmp.EndInit(); $ui.imgLogo.Source = $bmp; $Window.Icon = $bmp } } catch {}
$ui.lblComputer.Text = $env:COMPUTERNAME
$ui.txtExportDest.Text = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Stampanti'
$script:LastFolder = $null

function Add-Log([string]$Line) { $ui.txtLog.AppendText($Line + "`r`n"); $ui.txtLog.ScrollToEnd() }
function New-Item-Check([string]$Tag, [string]$Text, [bool]$Checked) { $cb = New-Object System.Windows.Controls.CheckBox; $cb.Tag = $Tag; $cb.Content = $Text; $cb.IsChecked = $Checked; return $cb }
function Get-Checked($List) { $out = @(); foreach ($x in $List.Items) { if ($x.IsChecked) { $out += [string]$x.Tag } }; return $out }
function Set-All($List, [bool]$Value) { foreach ($x in $List.Items) { $x.IsChecked = $Value } }

function Load-Printers {
    $ui.lstPrinters.Items.Clear()
    try {
        $all = @(Get-PmPrinters)
        foreach ($p in $all) {
            $txt = $p.Nome + '   [' + $p.Tipo + ']   ' + $p.Driver + '   -   ' + $p.Porta
            if ($p.IndirizzoIP) { $txt += ' (' + $p.IndirizzoIP + ')' }
            if ($p.Predefinita) { $txt += '   * predefinita' }
            if ($p.Stato -and $p.Stato -ne 'Normal') { $txt += '   - stato: ' + $p.Stato }
            [void]$ui.lstPrinters.Items.Add((New-Item-Check $p.Nome $txt $true))
        }
        $ui.lblCount.Text = 'Stampanti installate: ' + $all.Count + ' (escluse le virtuali: PDF, XPS, Fax, OneNote)'
        $ui.lblDefault.Text = 'Predefinita: ' + (Get-PmDefaultPrinter)
    } catch { Add-Log ('[ERROR] Lettura stampanti: ' + $_.Exception.Message) }
}
function Load-Package([string]$Path) {
    $ui.lstImport.Items.Clear(); $ui.btnImport.IsEnabled = $false
    try {
        $m = Read-PmPackage -PackagePath $Path
        foreach ($p in @($m.Stampanti)) {
            $txt = [string]$p.Nome + '   [' + [string]$p.Tipo + ']   ' + [string]$p.Driver
            if ($p.IndirizzoIP) { $txt += ' (' + [string]$p.IndirizzoIP + ')' }
            if ($p.PacchettoDriver) { $txt += '   - driver incluso' } elseif ([string]$p.Tipo -ne 'Condivisa') { $txt += '   - driver di Windows' }
            if (Get-Printer -Name ([string]$p.Nome) -ErrorAction SilentlyContinue) { $txt += '   (gia'' presente su questo PC)' }
            [void]$ui.lstImport.Items.Add((New-Item-Check ([string]$p.Nome) $txt $true))
        }
        $ui.lblPkgInfo.Text = 'Origine: ' + [string]$m.Computer + '  -  creato: ' + [string]$m.Creato + '  -  ' + @($m.Stampanti).Count + ' stampanti  -  predefinita: ' + [string]$m.Predefinita
        $ui.btnImport.IsEnabled = $true
    } catch { $ui.lblPkgInfo.Text = 'Pacchetto non valido: ' + $_.Exception.Message }
}

$script:Sync = [hashtable]::Synchronized(@{ Log = (New-Object System.Collections.Concurrent.ConcurrentQueue[string]); Percent = 0.0; Status = ''; Done = $false; Error = $null; Result = $null; Mode = '' })
$Timer = New-Object System.Windows.Threading.DispatcherTimer; $Timer.Interval = [TimeSpan]::FromMilliseconds(250)
$Timer.Add_Tick({
    $line = $null
    while ($script:Sync.Log.TryDequeue([ref]$line)) { Add-Log $line }
    $ui.progressBar.Value = [double]$script:Sync.Percent; $ui.lblStatus.Text = [string]$script:Sync.Status
    if ($script:Sync.Done) {
        $Timer.Stop(); $ui.btnExport.IsEnabled = $true; $ui.btnImport.IsEnabled = ($ui.lstImport.Items.Count -gt 0); $ui.btnRepair.IsEnabled = $true
        if ($script:Sync.Error) { $ui.lblStatus.Text = 'Errore: ' + $script:Sync.Error; return }
        $r = $script:Sync.Result
        if ($script:Sync.Mode -eq 'Export') { $script:LastFolder = [string]$r.Pacchetto; $ui.btnOpenFolder.IsEnabled = $true; $ui.lblStatus.Text = 'Esportate ' + $r.Stampanti + ' stampanti in ' + $r.Pacchetto }
        elseif ($script:Sync.Mode -eq 'Import') { $ui.lblStatus.Text = 'Importate ' + $r.Importate + ', saltate ' + $r.Saltate + ', errori ' + $r.Errori; Load-Printers; Load-Package $ui.txtImportPkg.Text.Trim() }
        else { $ui.lblStatus.Text = 'Spooler riavviato.'; Load-Printers }
    }
})
function Start-Work([string]$Mode, [hashtable]$Opts) {
    $ui.btnExport.IsEnabled = $false; $ui.btnImport.IsEnabled = $false; $ui.btnRepair.IsEnabled = $false
    $script:Sync.Done = $false; $script:Sync.Error = $null; $script:Sync.Result = $null; $script:Sync.Percent = 0; $script:Sync.Mode = $Mode
    $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
    $rs.SessionStateProxy.SetVariable('Sync', $script:Sync); $rs.SessionStateProxy.SetVariable('EngineText', $EngineText); $rs.SessionStateProxy.SetVariable('Mode', $Mode); $rs.SessionStateProxy.SetVariable('Opts', $Opts)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    [void]$ps.AddScript({
        try {
            Import-Module (New-Module -Name 'VMPrinter.Engine' -ScriptBlock ([scriptblock]::Create($EngineText))) -Force
            Initialize-PmCallbacks -OnLog { param($l, $m) $Sync.Log.Enqueue(((Get-Date -Format 'HH:mm:ss') + ' [' + $l + '] ' + $m)) } -OnProgress { param($p, $s) $Sync.Percent = $p; $Sync.Status = $s }
            if ($Mode -eq 'Export') { $Sync.Result = Export-PmPackage -Destination $Opts.Dest -PrinterNames $Opts.Names -IncludeDrivers $Opts.Drivers -IncludeSettings $Opts.Settings -IncludePrintBrm $Opts.Brm }
            elseif ($Mode -eq 'Import') { $Sync.Result = Import-PmPackage -PackagePath $Opts.Pkg -PrinterNames $Opts.Names -Overwrite $Opts.Overwrite -RestoreSettings $Opts.Settings -RestoreDefault $Opts.Default -SharedForAllUsers $Opts.AllUsers }
            else { $Sync.Result = Repair-PmSpooler }
        } catch {
            $Sync.Error = $_.Exception.Message
            $Sync.Log.Enqueue('[ERROR] ' + $_.Exception.Message); $Sync.Log.Enqueue('[ERROR] ' + ($_.InvocationInfo.PositionMessage -replace "`r?`n", ' | ')); $Sync.Log.Enqueue('[ERROR] ' + ($_.ScriptStackTrace -replace "`r?`n", ' | '))
        } finally { $Sync.Done = $true }
    })
    [void]$ps.BeginInvoke(); $Timer.Start()
}
function Pick-Folder([string]$Initial) { $d = New-Object System.Windows.Forms.FolderBrowserDialog; if ($Initial -and (Test-Path -LiteralPath $Initial)) { $d.SelectedPath = $Initial }; if ($d.ShowDialog() -eq 'OK') { return $d.SelectedPath }; return $null }

$ui.btnRefresh.Add_Click({ Load-Printers })
$ui.btnAll.Add_Click({ Set-All $ui.lstPrinters $true })
$ui.btnNone.Add_Click({ Set-All $ui.lstPrinters $false })
$ui.btnExportBrowse.Add_Click({ $f = Pick-Folder $ui.txtExportDest.Text; if ($f) { $ui.txtExportDest.Text = $f } })
$ui.btnExport.Add_Click({
    $names = @(Get-Checked $ui.lstPrinters); $dest = $ui.txtExportDest.Text.Trim()
    if ($names.Count -eq 0) { [System.Windows.MessageBox]::Show('Seleziona almeno una stampante.', 'VM Printer Manager') | Out-Null; return }
    if (-not $dest) { [System.Windows.MessageBox]::Show('Indica la cartella di destinazione.', 'VM Printer Manager') | Out-Null; return }
    try { New-Item -ItemType Directory -Path $dest -Force | Out-Null } catch { [System.Windows.MessageBox]::Show('Cartella non creabile: ' + $dest, 'VM Printer Manager') | Out-Null; return }
    Start-Work 'Export' @{ Dest = $dest; Names = $names; Drivers = [bool]$ui.chkDrivers.IsChecked; Settings = [bool]$ui.chkSettings.IsChecked; Brm = [bool]$ui.chkBrm.IsChecked }
})
$ui.btnRepair.Add_Click({ if ([System.Windows.MessageBox]::Show('Riavviare lo spooler e svuotare la coda di stampa? I lavori in attesa verranno eliminati.', 'VM Printer Manager', 'YesNo', 'Question') -eq 'Yes') { Start-Work 'Repair' @{} } })
$ui.btnImportBrowse.Add_Click({ $f = Pick-Folder $ui.txtImportPkg.Text; if ($f) { $ui.txtImportPkg.Text = $f; Load-Package $f } })
$ui.txtImportPkg.Add_LostFocus({ $t = $ui.txtImportPkg.Text.Trim(); if ($t) { Load-Package $t } })
$ui.btnImport.Add_Click({
    $names = @(Get-Checked $ui.lstImport)
    if ($names.Count -eq 0) { [System.Windows.MessageBox]::Show('Seleziona almeno una stampante.', 'VM Printer Manager') | Out-Null; return }
    if ([System.Windows.MessageBox]::Show(('Importare ' + $names.Count + ' stampanti su questo PC?'), 'Conferma', 'YesNo', 'Question') -ne 'Yes') { return }
    Start-Work 'Import' @{ Pkg = $ui.txtImportPkg.Text.Trim(); Names = $names; Overwrite = [bool]$ui.chkOverwrite.IsChecked; Settings = [bool]$ui.chkImpSettings.IsChecked; Default = [bool]$ui.chkImpDefault.IsChecked; AllUsers = [bool]$ui.chkAllUsers.IsChecked }
})
$ui.btnOpenFolder.Add_Click({ if ($script:LastFolder) { Start-Process explorer.exe -ArgumentList ('"' + $script:LastFolder + '"') } })
Load-Printers
[void]$Window.ShowDialog()
} catch { Show-FatalError ("Errore: " + $_.Exception.Message) $_ }
