@echo off
rem Avvia l installatore di Chat Ollama senza blocchi dei criteri di esecuzione di PowerShell.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installa_chat_ollama.ps1"
if errorlevel 1 pause
