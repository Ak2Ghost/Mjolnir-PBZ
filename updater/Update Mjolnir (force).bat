@echo off
title Mjolnir updater
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update_mjolnir.ps1" -Force
