<#
.SYNOPSIS
    Menyiapkan screener di komputer BARU (laptop kedua) setelah repositori
    di-clone dari GitHub.

.DESCRIPTION
    Dijalankan sekali di komputer baru. Yang dikerjakan:

      1. Memeriksa git dan GitHub CLI
      2. Mengisi identitas git untuk repositori ini (kalau belum ada)
      3. Mengunduh daftar S&P 500 terbaru (data\universe.json tidak ikut di-clone
         karena termasuk berkas hasil, bukan berkas sumber)
      4. Menjalankan screener sekali supaya dashboard langsung ada isinya

    Setelah ini selesai, tinggal pasang jadwal otomatisnya:
        .\Install-Schedule.ps1        (lewat PowerShell "Run as administrator")

    JANGAN lupa mematikan jadwal di laptop LAMA, supaya keduanya tidak
    berebut mengunggah ke situs yang sama:
        .\Install-Schedule.ps1 -Remove

.PARAMETER SkipScan
    Lewati pemindaian awal (langkah 4). Berguna kalau Anda sedang buru-buru -
    pemindaian penuh butuh 20-35 menit.

.EXAMPLE
    .\Setup-Laptop.ps1
    .\Setup-Laptop.ps1 -SkipScan
#>
[CmdletBinding()]
param(
    [switch]$SkipScan
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host '   PENYIAPAN DI KOMPUTER BARU' -ForegroundColor Cyan
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host ''

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location $root
try {
    # --- 1. git ---
    Write-Host '  [1/4] Memeriksa git...' -NoNewline
    $gitOk = $false
    try { $null = & git --version 2>$null; $gitOk = ($LASTEXITCODE -eq 0) } catch { }
    if (-not $gitOk) {
        Write-Host ' TIDAK ADA' -ForegroundColor Red
        Write-Host ''
        Write-Host '  git belum terpasang. Pasang dulu:' -ForegroundColor Yellow
        Write-Host '     winget install Git.Git' -ForegroundColor Gray
        Write-Host '  Lalu tutup dan buka lagi PowerShell, ulangi skrip ini.' -ForegroundColor Yellow
        Write-Host ''
        return
    }
    Write-Host ' OK' -ForegroundColor Green

    # --- 2. Identitas git untuk repositori ini ---
    # Di komputer ini identitas git biasanya diatur PER-REPOSITORI, bukan global.
    # Kalau kosong, Publish-Web.ps1 akan gagal saat commit.
    Write-Host '  [2/4] Memeriksa identitas git...' -NoNewline
    $isRepo = Test-Path (Join-Path $root '.git')
    if (-not $isRepo) {
        Write-Host ' BUKAN REPOSITORI' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Folder ini bukan hasil clone dari GitHub, jadi tidak bisa mengunggah' -ForegroundColor Yellow
        Write-Host '  pembaruan ke situs. Screener tetap bisa dipakai secara lokal.' -ForegroundColor DarkGray
        Write-Host '  Untuk dapat versi yang bisa mengunggah, clone dulu:' -ForegroundColor DarkGray
        Write-Host '     git clone https://github.com/mapleapple03/us-screener.git' -ForegroundColor Gray
    }
    else {
        $uname = ''
        try { $uname = (git config user.name 2>$null) } catch { }
        if ([string]::IsNullOrWhiteSpace($uname)) {
            git config user.name  'siaha' 2>$null | Out-Null
            git config user.email 'siahaansammy71@gmail.com' 2>$null | Out-Null
            Write-Host ' DIISI (siaha)' -ForegroundColor Green
        } else {
            Write-Host " OK ($uname)" -ForegroundColor Green
        }

        # GitHub CLI hanya diperlukan kalau ingin mengunggah pembaruan.
        Write-Host '  ..... Memeriksa login GitHub...' -NoNewline
        $authOk = $false
        try { $null = & gh auth status 2>&1; $authOk = ($LASTEXITCODE -eq 0) } catch { }
        if ($authOk) {
            Write-Host ' OK' -ForegroundColor Green
        } else {
            Write-Host ' BELUM' -ForegroundColor Yellow
            Write-Host '        Supaya dashboard di HP ikut diperbarui dari komputer ini,' -ForegroundColor DarkGray
            Write-Host '        login dulu (sekali saja):  gh auth login' -ForegroundColor Gray
            Write-Host '        Tanpa itu, screener tetap jalan tapi hasilnya lokal saja.' -ForegroundColor DarkGray
        }
    }

    # --- 3. Daftar saham ---
    Write-Host '  [3/4] Mengunduh daftar S&P 500 terbaru...' -ForegroundColor Gray
    $ErrorActionPreference = 'Stop'
    try {
        & (Join-Path $root 'Update-Universe.ps1')
    } catch {
        Write-Host "  Gagal: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '  Screener tetap bisa jalan memakai daftar cadangan bawaan.' -ForegroundColor DarkGray
    }
    $ErrorActionPreference = 'Continue'

    # --- 4. Pemindaian pertama ---
    if ($SkipScan) {
        Write-Host '  [4/4] Pemindaian awal dilewati (-SkipScan).' -ForegroundColor DarkGray
    } else {
        Write-Host '  [4/4] Menjalankan screener pertama kali (20-35 menit)...' -ForegroundColor Gray
        Write-Host '        Biarkan jendela ini terbuka.' -ForegroundColor DarkGray
        Write-Host ''
        $ErrorActionPreference = 'Stop'
        try {
            & (Join-Path $root 'Run-Screener.ps1') -NoOpen
            & (Join-Path $root 'Run-News.ps1') -NoOpen
        } catch {
            Write-Host "  Gagal: $($_.Exception.Message)" -ForegroundColor Yellow
        }
        $ErrorActionPreference = 'Continue'
    }

    Write-Host ''
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host '   Langkah terakhir (dilakukan sendiri):' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '   1. Pasang jadwal otomatis DI KOMPUTER INI.' -ForegroundColor White
    Write-Host '      Buka PowerShell sebagai Administrator, lalu:' -ForegroundColor DarkGray
    Write-Host '         .\Install-Schedule.ps1' -ForegroundColor Gray
    Write-Host ''
    Write-Host '   2. MATIKAN jadwal di laptop LAMA.' -ForegroundColor White
    Write-Host '      Kalau dua komputer sama-sama aktif, keduanya berebut' -ForegroundColor DarkGray
    Write-Host '      mengunggah ke situs yang sama dan salah satu akan gagal.' -ForegroundColor DarkGray
    Write-Host '      Di laptop lama, jalankan:' -ForegroundColor DarkGray
    Write-Host '         .\Install-Schedule.ps1 -Remove' -ForegroundColor Gray
    Write-Host ''
    Write-Host '   Alamat dashboard tetap sama, tidak berubah:' -ForegroundColor DarkGray
    Write-Host '     https://mapleapple03.github.io/us-screener/' -ForegroundColor Cyan
    Write-Host ''
}
finally {
    $ErrorActionPreference = $prevEAP
    Pop-Location
}
