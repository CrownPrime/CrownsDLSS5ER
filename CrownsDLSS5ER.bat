@echo off
rem conhost --headless: no console window at all. Windows Terminal ignores -WindowStyle Hidden and would leave an
rem empty PowerShell window open behind the manager.
start "" conhost.exe --headless powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CrownsDLSSManager.ps1"
