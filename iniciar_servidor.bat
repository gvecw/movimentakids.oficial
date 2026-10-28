@echo off
title Servidor Local Funcional Kids
cd /d "%~dp0"
echo Iniciando servidor local na porta 8080...
start http://localhost:8080
powershell -NoProfile -ExecutionPolicy Bypass -File server.ps1 -Port 8080
pause
