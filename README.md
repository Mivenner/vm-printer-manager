# VM Printer Manager 1.0

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
