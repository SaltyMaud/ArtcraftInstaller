@echo off
title ArtCraft updater
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-artcraft.ps1" -Update %*
exit %ERRORLEVEL%
