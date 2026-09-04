@echo off
chcp 65001 >nul
title HEIC -> JPEG Donusturucu
cd /d "%~dp0"

if not exist "%~dp0HEIC_Donustur.ps1" (
    echo HATA: HEIC_Donustur.ps1 bulunamadi. Bu .bat dosyasi ile ayni klasorde olmali.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0HEIC_Donustur.ps1"
