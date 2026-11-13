#Requires -Version 5.1
<#
.SYNOPSIS  VM Printer Manager - Motore v1.0: inventario, esportazione e importazione delle stampanti installate.
.DESCRIPTION
    Esporta in una cartella-pacchetto: elenco stampanti (locali/IP/WSD/USB e condivise dell'utente), porte TCP/IP,
    pacchetti driver (pnputil /export-driver), impostazioni di ogni stampante (printui /Ss: formato carta, vassoi,
    fronte-retro, preferenze), stampante predefinita e, dove disponibile (Windows Pro), anche il file standard
    Microsoft .printerExport creato da PrintBrm. L'importazione ricrea driver, porte, stampanti, impostazioni,
    connessioni condivise e predefinita. Funziona anche su Windows Home (non dipende da PrintBrm).
.NOTES     (c) vm technology - uso interno. Richiede privilegi di amministratore.
#>
Set-StrictMode -Version 2.0
$script:Version = '1.0.0'
$script:LogCallback = $null; $script:ProgCallback = $null; $script:LogFile = $null
$script:Virtual = '^(Microsoft Print to PDF|Microsoft XPS Document Writer|Fax|OneNote.*|Send To OneNote.*|Invia a OneNote.*|Adobe PDF|Foxit.*PDF.*|PDF24|CutePDF.*|Bullzip.*|AnyDesk Printer|TeamViewer.*)$'

function Initialize-PmCallbacks { param([scriptblock]$OnLog, [scriptblock]$OnProgress) $script:LogCallback = $OnLog; $script:ProgCallback = $OnProgress }
function Write-PmLog {
    param([string]$Message, [ValidateSet('INFO','OK','WARN','ERROR','STEP')][string]$Level = 'INFO')
    if ($script:LogFile) { try { Add-Content -LiteralPath $script:LogFile -Value ("{0} [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message) -Encoding UTF8 } catch {} }
    if ($script:LogCallback) { try { & $script:LogCallback $Level $Message } catch {} }
}
function Write-PmProgress { param([double]$Percent, [string]$Status) if ($script:ProgCallback) { try { & $script:ProgCallback $Percent $Status } catch {} } }
function Test-PmAdmin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Get-PmValue { param($Obj, [string]$Name, $Default = $null) if ($null -ne $Obj -and $Obj.PSObject.Properties[$Name] -and $null -ne $Obj.$Name) { return $Obj.$Name }; return $Default }
function Get-PmSafeName { param([string]$Name) return (($Name -replace '[\\/:*?"<>|]', '_').Trim()) }

function Get-PmDefaultPrinter {
    try { $d = Get-CimInstance Win32_Printer -Filter 'Default=True' -ErrorAction Stop | Select-Object -First 1; if ($d) { return [string]$d.Name } } catch {}
    return ''
}

function Get-PmPrinters {
    <# Inventario: una riga per stampante. Tipo = IP | WSD | USB | Condivisa | Locale | Virtuale #>
    [CmdletBinding()] param([switch]$IncludeVirtual)
    $def = Get-PmDefaultPrinter
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($p in @(Get-Printer -ErrorAction Stop)) {
        $name = [string]$p.Name; $portName = [string]$p.PortName
        $isVirtual = ($name -match $script:Virtual) -or ($portName -match '^(PORTPROMPT:|nul:|SHRFAX:|XPSPort:|FILE:)')
        if ($isVirtual -and -not $IncludeVirtual) { continue }
        $ip = ''; $portNum = 0; $proto = ''; $queue = ''; $snmp = $false
        if ([string]$p.Type -ne 'Connection') {
            try {
                $port = Get-PrinterPort -Name $portName -ErrorAction Stop
                $ip = [string](Get-PmValue $port 'PrinterHostAddress' '')
                $portNum = [int](Get-PmValue $port 'PortNumber' 0)
                $proto = [string](Get-PmValue $port 'Protocol' '')
                $queue = [string](Get-PmValue $port 'LprQueueName' '')
                $snmp = [bool](Get-PmValue $port 'SNMPEnabled' $false)
            } catch {}
        }
        $tipo = 'Locale'
        if ($isVirtual) { $tipo = 'Virtuale' } elseif ([string]$p.Type -eq 'Connection') { $tipo = 'Condivisa' } elseif ($ip) { $tipo = 'IP' } elseif ($portName -like 'WSD*') { $tipo = 'WSD' } elseif ($portName -like 'USB*') { $tipo = 'USB' }
        $item = New-Object psobject
        $item | Add-Member NoteProperty Nome $name
        $item | Add-Member NoteProperty Tipo $tipo
        $item | Add-Member NoteProperty Driver ([string]$p.DriverName)
        $item | Add-Member NoteProperty Porta $portName
        $item | Add-Member NoteProperty IndirizzoIP $ip
        $item | Add-Member NoteProperty NumeroPorta $portNum
        $item | Add-Member NoteProperty Protocollo $proto
        $item | Add-Member NoteProperty CodaLpr $queue
        $item | Add-Member NoteProperty Snmp $snmp
        $item | Add-Member NoteProperty Condivisa ([bool]$p.Shared)
        $item | Add-Member NoteProperty NomeCondivisione ([string]$p.ShareName)
        $item | Add-Member NoteProperty Posizione ([string]$p.Location)
        $item | Add-Member NoteProperty Commento ([string]$p.Comment)
        $item | Add-Member NoteProperty Stato ([string]$p.PrinterStatus)
        $item | Add-Member NoteProperty Predefinita ($name -eq $def)
        $item | Add-Member NoteProperty PacchettoDriver ''
        $item | Add-Member NoteProperty FileImpostazioni ''
        $list.Add($item)
    }
    return $list.ToArray()
}

function Export-PmDriver {
    <# Esporta nel pacchetto il driver di una stampante. Ritorna il nome della sottocartella o '' (driver di sistema / non esportabile). #>
    param([string]$DriverName, [string]$DriversFolder, [hashtable]$Cache)
    if ($Cache.ContainsKey($DriverName)) { return $Cache[$DriverName] }
    $result = ''
    try {
        $drv = Get-PrinterDriver -Name $DriverName -ErrorAction Stop | Select-Object -First 1
        $inf = [string]$drv.InfPath
        if ($inf -and (Test-Path -LiteralPath $inf)) {
            $folder = Split-Path -Parent $inf
            if ($folder -like '*\DriverStore\FileRepository\*') {
                $leaf = Split-Path -Leaf $folder
                $isInbox = ($leaf -like 'ntprint.inf*') -or ($leaf -like 'prnms*') -or ($leaf -like 'prnge001*')
                if (-not $isInbox) {
                    $dest = Join-Path $DriversFolder $leaf
                    if (-not (Test-Path -LiteralPath $dest)) { Copy-Item -LiteralPath $folder -Destination $dest -Recurse -Force }
                    $result = $leaf
                }
            }
        }
    } catch { Write-PmLog -Level WARN -Message ("Driver '{0}' non esportato: {1}" -f $DriverName, $_.Exception.Message) }
    $Cache[$DriverName] = $result
    return $result
}

function Export-PmPackage {
    <# Crea <Destination>\Stampanti_<PC>_<data>\ con printers.json, Drivers\, Settings\, (PrintBrm.printerExport), export.log. Ritorna oggetto riepilogo. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Destination, [string[]]$PrinterNames, [bool]$IncludeDrivers = $true, [bool]$IncludeSettings = $true, [bool]$IncludePrintBrm = $true)
    if (-not (Test-PmAdmin)) { throw 'Servono privilegi di amministratore.' }
    $pkg = Join-Path $Destination ('Stampanti_{0}_{1}' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
    $drvDir = Join-Path $pkg 'Drivers'; $setDir = Join-Path $pkg 'Settings'
    foreach ($d in $pkg, $drvDir, $setDir) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $script:LogFile = Join-Path $pkg 'export.log'
    Write-PmLog -Level STEP -Message "=== ESPORTAZIONE stampanti di $env:COMPUTERNAME -> $pkg ==="
    $all = @(Get-PmPrinters)
    $sel = @($all | Where-Object { -not $PrinterNames -or $PrinterNames -contains $_.Nome })
    $cache = @{}; $i = 0
    foreach ($p in $sel) {
        $i++; Write-PmProgress -Percent (($i - 1) / [math]::Max(1, $sel.Count) * 90) -Status ("Esporto {0}/{1}: {2}" -f $i, $sel.Count, $p.Nome)
        if ($IncludeDrivers -and $p.Tipo -ne 'Condivisa') { $p.PacchettoDriver = Export-PmDriver -DriverName $p.Driver -DriversFolder $drvDir -Cache $cache }
        if ($IncludeSettings) {
            $file = (Get-PmSafeName $p.Nome) + '.dat'
            try {
                $proc = Start-Process rundll32.exe -ArgumentList ('printui.dll,PrintUIEntry /Ss /q /n "{0}" /a "{1}"' -f $p.Nome, (Join-Path $setDir $file)) -Wait -PassThru -WindowStyle Hidden
                if (Test-Path -LiteralPath (Join-Path $setDir $file)) { $p.FileImpostazioni = $file }
            } catch {}
        }
        Write-PmLog -Level OK -Message ("{0} [{1}] driver '{2}' porta {3}{4}{5}{6}" -f $p.Nome, $p.Tipo, $p.Driver, $p.Porta, $(if ($p.IndirizzoIP) { ' (' + $p.IndirizzoIP + ')' } else { '' }), $(if ($p.PacchettoDriver) { ' - driver esportato' } elseif ($p.Tipo -ne 'Condivisa') { ' - driver di Windows' } else { '' }), $(if ($p.FileImpostazioni) { ' - impostazioni salvate' } else { '' }))
    }
    $brm = ''
    if ($IncludePrintBrm) {
        $exe = Join-Path $env:SystemRoot 'System32\spool\tools\PrintBrm.exe'
        if (Test-Path -LiteralPath $exe) {
            Write-PmProgress -Percent 92 -Status 'PrintBrm: creazione file .printerExport standard Microsoft...'
            try {
                $f = Join-Path $pkg 'PrintBrm.printerExport'
                $proc = Start-Process $exe -ArgumentList ('-b -f "{0}" -o force' -f $f) -Wait -PassThru -WindowStyle Hidden
                if ((Test-Path -LiteralPath $f) -and $proc.ExitCode -eq 0) { $brm = 'PrintBrm.printerExport'; Write-PmLog -Level OK -Message 'Creato anche PrintBrm.printerExport (importabile con lo strumento Microsoft "Migrazione stampanti").' }
                else { Write-PmLog -Level WARN -Message "PrintBrm ha restituito codice $($proc.ExitCode): file standard non creato (il pacchetto resta completo)." }
            } catch { Write-PmLog -Level WARN -Message "PrintBrm: $($_.Exception.Message)" }
        } else { Write-PmLog 'PrintBrm non presente (Windows Home): uso solo il formato del pacchetto.' }
    }
    $manifest = New-Object psobject
    $manifest | Add-Member NoteProperty Magic 'VMPRN'
    $manifest | Add-Member NoteProperty Versione $script:Version
    $manifest | Add-Member NoteProperty Computer $env:COMPUTERNAME
    $manifest | Add-Member NoteProperty Utente ($env:USERDOMAIN + '\' + $env:USERNAME)
    $manifest | Add-Member NoteProperty Creato (Get-Date).ToString('s')
    $manifest | Add-Member NoteProperty Predefinita (Get-PmDefaultPrinter)
    $manifest | Add-Member NoteProperty PrintBrm $brm
    $manifest | Add-Member NoteProperty Stampanti $sel
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $pkg 'printers.json') -Encoding UTF8
    $sel | Select-Object Nome, Tipo, Driver, Porta, IndirizzoIP, Condivisa, Posizione, Predefinita | Export-Csv -LiteralPath (Join-Path $pkg 'stampanti.csv') -NoTypeInformation -Delimiter ';' -Encoding UTF8
    Write-PmProgress -Percent 100 -Status 'Esportazione completata'
    Write-PmLog -Level STEP -Message ("=== COMPLETATO: {0} stampanti, {1} pacchetti driver. Pacchetto: {2} ===" -f $sel.Count, @(Get-ChildItem -LiteralPath $drvDir -Directory).Count, $pkg)
    $out = New-Object psobject
    $out | Add-Member NoteProperty Pacchetto $pkg
    $out | Add-Member NoteProperty Stampanti $sel.Count
    $out | Add-Member NoteProperty Log $script:LogFile
    return $out
}

function Read-PmPackage {
    param([Parameter(Mandatory)][string]$PackagePath)
    $f = Join-Path $PackagePath 'printers.json'
    if (-not (Test-Path -LiteralPath $f)) { throw "printers.json non trovato in ${PackagePath}: non e' un pacchetto VM Printer Manager." }
    $m = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$m.Magic -ne 'VMPRN') { throw 'Formato pacchetto non riconosciuto.' }
    return $m
}

function Import-PmPackage {
    <#
    .PARAMETER PrinterNames     Sottoinsieme da importare (default tutte).
    .PARAMETER Overwrite        Se la stampante esiste gia': $true la ricrea, $false la lascia.
    .PARAMETER SharedForAllUsers  Connessioni condivise per tutti gli utenti del PC (printui /ga) invece che solo per l'utente corrente.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackagePath, [string[]]$PrinterNames, [bool]$Overwrite = $false, [bool]$RestoreSettings = $true, [bool]$RestoreDefault = $true, [bool]$SharedForAllUsers = $false)
    if (-not (Test-PmAdmin)) { throw 'Servono privilegi di amministratore.' }
    $m = Read-PmPackage -PackagePath $PackagePath
    $script:LogFile = Join-Path $PackagePath ('import_{0}.log' -f $env:COMPUTERNAME)
    Write-PmLog -Level STEP -Message "=== IMPORTAZIONE da $PackagePath (origine: $($m.Computer), $($m.Creato)) su $env:COMPUTERNAME ==="
    $sel = @($m.Stampanti | Where-Object { -not $PrinterNames -or $PrinterNames -contains $_.Nome })
    $ok = 0; $skip = 0; $fail = 0; $i = 0; $installed = @{}
    foreach ($p in $sel) {
        $i++; $name = [string]$p.Nome
        Write-PmProgress -Percent (($i - 1) / [math]::Max(1, $sel.Count) * 95) -Status ("Importo {0}/{1}: {2}" -f $i, $sel.Count, $name)
        try {
            if ([string]$p.Tipo -eq 'Condivisa') {
                $flag = '/in'; if ($SharedForAllUsers) { $flag = '/ga' }
                Start-Process rundll32.exe -ArgumentList ('printui.dll,PrintUIEntry {0} /q /n "{1}"' -f $flag, $name) -Wait -WindowStyle Hidden
                Write-PmLog -Level OK -Message ("{0}: connessione condivisa aggiunta ({1})." -f $name, $(if ($SharedForAllUsers) { 'tutti gli utenti, attiva al prossimo accesso' } else { 'utente corrente' }))
                $ok++; continue
            }
            $exists = Get-Printer -Name $name -ErrorAction SilentlyContinue
            if ($exists -and -not $Overwrite) { Write-PmLog "${name}: gia' presente, lasciata invariata."; $skip++; continue }
            # 1. driver
            $drv = [string]$p.Driver; $pk = [string](Get-PmValue $p 'PacchettoDriver' '')
            if (-not (Get-PrinterDriver -Name $drv -ErrorAction SilentlyContinue)) {
                if ($pk -and -not $installed.ContainsKey($pk)) {
                    $inf = Get-ChildItem -LiteralPath (Join-Path (Join-Path $PackagePath 'Drivers') $pk) -Filter *.inf -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($inf) { $o = & pnputil.exe /add-driver "$($inf.FullName)" /install 2>&1; $installed[$pk] = $true; Write-PmLog ("Driver {0}: pnputil codice {1}" -f $pk, $LASTEXITCODE) }
                }
                try { Add-PrinterDriver -Name $drv -ErrorAction Stop } catch { throw ("driver '{0}' non disponibile su questo PC ({1}). Installare il driver del produttore e ripetere l'importazione." -f $drv, $_.Exception.Message) }
            }
            # 2. porta
            $portName = [string]$p.Porta; $tipo = [string]$p.Tipo
            if ($tipo -eq 'IP') {
                if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
                    $ip = [string]$p.IndirizzoIP; $num = [int](Get-PmValue $p 'NumeroPorta' 9100); if ($num -le 0) { $num = 9100 }
                    if ([string](Get-PmValue $p 'Protocollo' '') -match 'LPR|2' -and [string](Get-PmValue $p 'CodaLpr' '')) { Add-PrinterPort -Name $portName -LprHostAddress $ip -LprQueueName ([string]$p.CodaLpr) -ErrorAction Stop }
                    else { Add-PrinterPort -Name $portName -PrinterHostAddress $ip -PortNumber $num -ErrorAction Stop }
                }
            } elseif ($tipo -eq 'USB' -or $tipo -eq 'WSD') {
                Write-PmLog -Level INFO -Message ("{0}: stampante {1} - driver installato; verra' aggiunta da Windows al collegamento/rilevamento in rete." -f $name, $tipo); $skip++; continue
            } elseif (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
                throw "porta '$portName' non presente su questo PC e non ricreabile automaticamente."
            }
            # 3. stampante
            if ($exists) { Remove-Printer -Name $name -ErrorAction Stop }
            Add-Printer -Name $name -DriverName $drv -PortName $portName -ErrorAction Stop
            $loc = [string](Get-PmValue $p 'Posizione' ''); $com = [string](Get-PmValue $p 'Commento' '')
            if ($loc -or $com) { Set-Printer -Name $name -Location $loc -Comment $com -ErrorAction SilentlyContinue }
            if ([bool](Get-PmValue $p 'Condivisa' $false) -and [string](Get-PmValue $p 'NomeCondivisione' '')) { Set-Printer -Name $name -Shared $true -ShareName ([string]$p.NomeCondivisione) -ErrorAction SilentlyContinue }
            # 4. impostazioni
            $sf = [string](Get-PmValue $p 'FileImpostazioni' '')
            if ($RestoreSettings -and $sf) {
                $full = Join-Path (Join-Path $PackagePath 'Settings') $sf
                if (Test-Path -LiteralPath $full) { Start-Process rundll32.exe -ArgumentList ('printui.dll,PrintUIEntry /Sr /q /n "{0}" /a "{1}" d u g 8' -f $name, $full) -Wait -WindowStyle Hidden }
            }
            Write-PmLog -Level OK -Message ("{0}: creata (driver '{1}', porta {2})." -f $name, $drv, $portName)
            $ok++
        } catch { $fail++; Write-PmLog -Level ERROR -Message ("{0}: {1}" -f $name, $_.Exception.Message) }
    }
    $def = [string](Get-PmValue $m 'Predefinita' '')
    if ($RestoreDefault -and $def -and (-not $PrinterNames -or $PrinterNames -contains $def)) {
        try { Start-Process rundll32.exe -ArgumentList ('printui.dll,PrintUIEntry /y /q /n "{0}"' -f $def) -Wait -WindowStyle Hidden; Write-PmLog -Level OK -Message "Stampante predefinita: $def" } catch {}
    }
    Write-PmProgress -Percent 100 -Status 'Importazione completata'
    Write-PmLog -Level STEP -Message ("=== COMPLETATO: {0} importate, {1} saltate, {2} errori ===" -f $ok, $skip, $fail)
    $out = New-Object psobject
    $out | Add-Member NoteProperty Importate $ok
    $out | Add-Member NoteProperty Saltate $skip
    $out | Add-Member NoteProperty Errori $fail
    $out | Add-Member NoteProperty Log $script:LogFile
    return $out
}

function Repair-PmSpooler {
    <# Ferma lo spooler, svuota la coda (file .SHD/.SPL) e lo riavvia. #>
    if (-not (Test-PmAdmin)) { throw 'Servono privilegi di amministratore.' }
    Stop-Service Spooler -Force -ErrorAction SilentlyContinue
    $n = 0
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'System32\spool\PRINTERS') -File -ErrorAction SilentlyContinue) { try { Remove-Item -LiteralPath $f.FullName -Force; $n++ } catch {} }
    Start-Service Spooler
    Write-PmLog -Level OK -Message "Spooler riavviato, $n file di coda rimossi."
    return $n
}

function Remove-PmPrinter {
    param([Parameter(Mandatory)][string]$Name)
    Remove-Printer -Name $Name -ErrorAction Stop
    Write-PmLog -Level OK -Message "Stampante '$Name' rimossa."
}

Export-ModuleMember -Function *-Pm*
