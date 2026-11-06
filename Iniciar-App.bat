@echo off
title Mesa de Ayuda - Desbloqueo de Usuarios
echo Iniciando servidor local en http://localhost:8080/ ...
start "" "http://localhost:8080/"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\server.ps1"
pause
