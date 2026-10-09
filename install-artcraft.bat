@echo off
title ArtCraft installer
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-artcraft.ps1" %*
exit %ERRORLEVEL%
