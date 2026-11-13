@echo off
rem Esempio: Avvia-CLI.cmd -Action Export -Path D:\Backup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VMPrinter.CLI.ps1" %*
