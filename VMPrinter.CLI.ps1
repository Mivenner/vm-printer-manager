#Requires -Version 5.1
<#
.SYNOPSIS  VM Printer Manager da riga di comando.
.EXAMPLE   .\VMPrinter.CLI.ps1 -Action List
.EXAMPLE   .\VMPrinter.CLI.ps1 -Action Export -Path D:\Backup
.EXAMPLE   .\VMPrinter.CLI.ps1 -Action Import -Path D:\Backup\Stampanti_PC01_20261113-1600 [-Overwrite] [-AllUsers] [-Printers "HP Ufficio","Kyocera"]
.EXAMPLE   .\VMPrinter.CLI.ps1 -Action Repair
.NOTES     Uscita: 0 ok, 2 importazione con errori, 1 errore fatale.
#>
[CmdletBinding()] param([Parameter(Mandatory)][ValidateSet('List','Export','Import','Repair')][string]$Action, [string]$Path, [string[]]$Printers, [switch]$Overwrite, [switch]$AllUsers, [switch]$NoDrivers, [switch]$NoSettings, [switch]$NoPrintBrm)
$root = $PSScriptRoot; if (-not $root) { $root = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$t = [System.IO.File]::ReadAllText((Join-Path $root 'VMPrinter.Engine.psm1'), [System.Text.Encoding]::UTF8)
Import-Module (New-Module -Name 'VMPrinter.Engine' -ScriptBlock ([scriptblock]::Create($t))) -Force
$colors = @{ INFO = 'Gray'; OK = 'Green'; WARN = 'Yellow'; ERROR = 'Red'; STEP = 'Cyan' }
Initialize-PmCallbacks -OnLog { param($l, $m) Write-Host ('[' + $l + '] ' + $m) -ForegroundColor $colors[$l] } -OnProgress { param($p, $s) }
try {
    switch ($Action) {
        'List'   { Get-PmPrinters | Format-Table Nome, Tipo, Driver, Porta, IndirizzoIP, Predefinita, Stato -AutoSize; exit 0 }
        'Export' { if (-not $Path) { throw 'Serve -Path (cartella di destinazione).' }; New-Item -ItemType Directory -Path $Path -Force | Out-Null; $r = Export-PmPackage -Destination $Path -PrinterNames $Printers -IncludeDrivers (-not $NoDrivers) -IncludeSettings (-not $NoSettings) -IncludePrintBrm (-not $NoPrintBrm); Write-Host ('Pacchetto: ' + $r.Pacchetto) -ForegroundColor Cyan; exit 0 }
        'Import' { if (-not $Path) { throw 'Serve -Path (cartella del pacchetto).' }; $r = Import-PmPackage -PackagePath $Path -PrinterNames $Printers -Overwrite $Overwrite.IsPresent -SharedForAllUsers $AllUsers.IsPresent -RestoreSettings (-not $NoSettings); if ($r.Errori -gt 0) { exit 2 } else { exit 0 } }
        'Repair' { [void](Repair-PmSpooler); exit 0 }
    }
} catch { Write-Host ('ERRORE: ' + $_.Exception.Message) -ForegroundColor Red; Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray; exit 1 }
