# Test reale su Windows: crea una stampante IP di prova, esporta, rimuove, importa, verifica. Richiede amministratore.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$t = [System.IO.File]::ReadAllText((Join-Path $root 'VMPrinter.Engine.psm1'), [System.Text.Encoding]::UTF8)
Import-Module (New-Module -Name 'VMPrinter.Engine' -ScriptBlock ([scriptblock]::Create($t))) -Force
Initialize-PmCallbacks -OnLog { param($l, $m) Write-Host "  [$l] $m" }
"PowerShell " + $PSVersionTable.PSVersion.ToString()
Start-Service Spooler -ErrorAction SilentlyContinue
$name = 'VMTEST Stampante IP'; $drv = 'Generic / Text Only'; $port = 'IP_10.99.99.99'
Add-PrinterDriver -Name $drv
Add-PrinterPort -Name $port -PrinterHostAddress '10.99.99.99' -PortNumber 9100
Add-Printer -Name $name -DriverName $drv -PortName $port
Set-Printer -Name $name -Location 'Ufficio test' -Comment 'creata dal test'
$out = Join-Path $env:TEMP ('prn_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$e = Export-PmPackage -Destination $out -PrinterNames @($name)
if ($e.Stampanti -ne 1) { throw "attese 1 stampante esportata, trovate $($e.Stampanti)" }
Get-ChildItem $e.Pacchetto -Recurse | ForEach-Object { "  file: " + $_.FullName.Substring($e.Pacchetto.Length) }
$m = Read-PmPackage -PackagePath $e.Pacchetto
if ([string]$m.Stampanti[0].IndirizzoIP -ne '10.99.99.99') { throw 'IP non esportato correttamente' }
Remove-Printer -Name $name; Remove-PrinterPort -Name $port
if (Get-Printer -Name $name -ErrorAction SilentlyContinue) { throw 'stampante non rimossa' }
$i = Import-PmPackage -PackagePath $e.Pacchetto
if ($i.Importate -ne 1 -or $i.Errori -ne 0) { throw "importazione: $($i.Importate) ok, $($i.Errori) errori" }
$p = Get-Printer -Name $name
if ($p.PortName -ne $port -or $p.DriverName -ne $drv -or $p.Location -ne 'Ufficio test') { throw 'stampante ricreata con dati diversi' }
if ((Get-PrinterPort -Name $port).PrinterHostAddress -ne '10.99.99.99') { throw 'porta ricreata con IP diverso' }
$i2 = Import-PmPackage -PackagePath $e.Pacchetto
if ($i2.Saltate -ne 1) { throw 'la seconda importazione doveva saltare la stampante gia'' presente' }
Remove-Printer -Name $name; Remove-PrinterPort -Name $port
'ROUND TRIP OK'
