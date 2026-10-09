@echo off
set SCRIPT=%~dp0SAP_Logon_Repair_GUI.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
