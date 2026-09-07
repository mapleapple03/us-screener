@echo off
REM Klik dua kali file ini untuk memperbarui screener DAN berita sekaligus.
cd /d "%~dp0"

echo.
echo   Memperbarui screener saham AS... (sekitar 30-40 menit)
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Run-Screener.ps1" -NoOpen

echo.
echo   Memperbarui berita... (sekitar 30 detik)
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Run-News.ps1" -NoOpen

echo.
echo   Selesai. Membuka dashboard...
start "" "%~dp0output\index.html"
start "" "%~dp0output\berita.html"

timeout /t 5 >nul
