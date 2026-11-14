<!-- header -->
<p align="center"><img src="logo.png" width="96" alt="vm technology"></p>
<h1 align="center">VM Printer Manager</h1>
<p align="center">Controlla, esporta e importa le stampanti installate su Windows: driver, porte IP, impostazioni e predefinita.</p>
<p align="center">
  <a href="https://github.com/Mivenner/vm-printer-manager/actions/workflows/build.yml"><img src="https://github.com/Mivenner/vm-printer-manager/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4" alt="Windows 10 | 11">
  <img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE" alt="PowerShell 5.1 | 7">
</p>

**Download dell'ultima build:** [File singolo .cmd](https://github.com/Mivenner/vm-printer-manager/releases/latest/download/VMPrinterManager_Portable.cmd) · [Zip portable](https://github.com/Mivenner/vm-printer-manager/releases/latest/download/VMPrinterManager_Portable.zip) · [Installer](https://github.com/Mivenner/vm-printer-manager/releases/latest/download/VMPrinterManager_Setup.exe)

Altri strumenti vm technology: [Migration Suite](https://github.com/Mivenner/vm-migration-suite) · [Health Check](https://github.com/Mivenner/vm-health-check) · [Setup Suite](https://github.com/Mivenner/vm-setup-suite) · [Printer Manager](https://github.com/Mivenner/vm-printer-manager)

---

Controlla le stampanti installate su un PC Windows 10/11 e le **esporta/importa** su un altro PC: driver, porte TCP/IP, impostazioni di stampa, connessioni condivise e stampante predefinita. Funziona anche su Windows Home, dove lo strumento Microsoft "Migrazione stampanti" (PrintBrm) non c'e'.

- GUI: `VMPrinterManager.exe`, `Avvia-GUI.cmd` oppure il portatile a file singolo `VMPrinterManager_Portable.cmd`.
- CLI: `Avvia-CLI.cmd -Action List | Export -Path <cartella> | Import -Path <pacchetto> [-Overwrite] [-AllUsers] | Repair`.

## Pacchetto `Stampanti_<PC>_<data>\`
`printers.json` (elenco completo) - `stampanti.csv` (apribile in Excel) - `Drivers\` (pacchetti driver dal driver store) - `Settings\*.dat` (impostazioni di ogni stampante, `printui /Ss`) - `PrintBrm.printerExport` (formato standard Microsoft, solo dove PrintBrm e' presente) - `export.log` / `import_<PC>.log`.

## Cosa viene ricreato
| Tipo | Importazione |
|------|--------------|
| IP (TCP/IP RAW o LPR) | driver, porta, stampante, posizione/commento, condivisione, impostazioni |
| Condivisa da server (`\\server\stampante`) | connessione per l'utente corrente oppure per tutti gli utenti (`/ga`) |
| USB / WSD | solo driver: Windows aggiunge la stampante al collegamento o al rilevamento in rete |
| Virtuali (PDF, XPS, Fax, OneNote) | ignorate |

Le stampanti gia' presenti vengono lasciate invariate, salvo l'opzione "Sostituisci". "Ripara spooler" riavvia il servizio e svuota la coda.
