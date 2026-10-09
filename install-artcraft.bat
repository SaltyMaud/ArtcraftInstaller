@echo off
title ArtCraft installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-artcraft.ps1" %*
if "%ERRORLEVEL%"=="7" exit
echo.
pause
