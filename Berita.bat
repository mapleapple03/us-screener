@echo off
REM Klik dua kali file ini kalau HANYA ingin memperbarui berita (cepat, ~30 detik).
cd /d "%~dp0"

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Run-News.ps1"
