@echo off
rem  NOW - envia el archivo de la carrera en curso.
rem  Doble clic para abrir la ventana. La configuracion (consola y carpeta) se hace
rem  ahi mismo y queda guardada en settings.txt
cd /d "%~dp0"
rem  -STA: la ventana lo necesita. -WindowStyle Hidden: que no quede una ventana negra
rem  de mas detras de la ventana del programa.
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0now-console-agent.ps1"
