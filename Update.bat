@echo off
REM Klik dua kali file ini untuk memperbarui screener DAN berita sekaligus,
REM lalu mengunggah hasilnya ke situs supaya bisa dibuka dari HP.
REM
REM Kalau TIDAK ingin mengunggah ke internet, hapus bagian [3/3] di bawah.
cd /d "%~dp0"

echo.
echo   [1/3] Memperbarui screener saham AS... (sekitar 20-35 menit)
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Run-Screener.ps1" -NoOpen

echo.
echo   [2/3] Memperbarui berita... (sekitar 30 detik)
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Run-News.ps1" -NoOpen

echo.
echo   [3/3] Mengunggah ke situs (supaya HP ikut ter-update)...
echo.
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0Publish-Web.ps1" -Push

echo.
echo   Selesai. Membuka dashboard...
start "" "%~dp0output\index.html"
start "" "%~dp0output\berita.html"

timeout /t 5 >nul
