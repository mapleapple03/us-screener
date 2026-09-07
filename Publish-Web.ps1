<#
.SYNOPSIS
    Menyiapkan dan menerbitkan kedua dashboard ke GitHub Pages,
    supaya bisa dibuka dari HP Android maupun komputer lain.

.DESCRIPTION
    Menyalin dashboard terbaru ke folder docs\ (folder yang dibaca GitHub Pages),
    membuat ikon dan manifest agar bisa dipasang di layar utama ponsel seperti
    aplikasi biasa, lalu commit dan push ke GitHub.

    Autentikasi GitHub harus Anda lakukan sendiri lebih dulu (gh auth login).
    Skrip ini tidak pernah menyimpan atau meminta password/token.

    PERHATIAN: GitHub Pages gratis hanya bisa dari repositori PUBLIK. Artinya
    siapa pun yang tahu alamatnya bisa melihat isi dashboard Anda - termasuk
    daftar saham pantauan. Isinya memang hanya olahan data pasar yang sudah
    publik, tapi putuskan sendiri apakah Anda nyaman.

.PARAMETER Push
    Lakukan git commit + push. Tanpa ini, hanya menyiapkan folder docs\ saja.

.PARAMETER Message
    Pesan commit. Default memakai tanggal-jam pembaruan.

.EXAMPLE
    .\Publish-Web.ps1                 # siapkan docs\ saja, belum diunggah
    .\Publish-Web.ps1 -Push           # siapkan lalu unggah ke GitHub
#>
[CmdletBinding()]
param(
    [switch]$Push,
    [string]$Message = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$docs = Join-Path $root 'docs'

$srcScreener = Join-Path $root 'output\index.html'
$srcNews     = Join-Path $root 'output\berita.html'

if (-not (Test-Path $srcScreener)) {
    throw "Dashboard screener belum dibuat. Jalankan .\Run-Screener.ps1 dulu."
}
if (-not (Test-Path $docs)) { New-Item -ItemType Directory -Path $docs -Force | Out-Null }

Write-Host ''
Write-Host '  Menyiapkan folder docs\ untuk GitHub Pages...' -ForegroundColor Cyan
Write-Host ''

# --- 1. Salin kedua dashboard ---
Copy-Item $srcScreener (Join-Path $docs 'index.html') -Force
Write-Host '  [OK] index.html  (screener)' -ForegroundColor Green

if (Test-Path $srcNews) {
    Copy-Item $srcNews (Join-Path $docs 'berita.html') -Force
    Write-Host '  [OK] berita.html (berita + agenda)' -ForegroundColor Green
} else {
    Write-Host '  [--] berita.html belum ada. Jalankan .\Run-News.ps1 supaya' -ForegroundColor Yellow
    Write-Host '       tombol "Berita & Agenda" di dashboard tidak mati.' -ForegroundColor Yellow
}

# --- 2. Ikon aplikasi (dibuat sekali, dipakai untuk Add to Home Screen) ---
# Sengaja dibedakan dari ikon screener IDX - garis naik biru, bukan batang hijau -
# supaya dua aplikasi ini gampang dibedakan di layar utama HP.
function New-AppIcon([int]$Size, [string]$Path) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bg = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(11, 15, 22))
    $g.FillRectangle($bg, 0, 0, $Size, $Size)

    # Garis tren naik
    $pts = @(
        (New-Object System.Drawing.PointF([single]($Size * 0.16), [single]($Size * 0.72))),
        (New-Object System.Drawing.PointF([single]($Size * 0.38), [single]($Size * 0.52))),
        (New-Object System.Drawing.PointF([single]($Size * 0.56), [single]($Size * 0.62))),
        (New-Object System.Drawing.PointF([single]($Size * 0.84), [single]($Size * 0.26)))
    )
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(74, 163, 255)), ([single]($Size * 0.085))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawLines($pen, $pts)
    $pen.Dispose()

    # Titik hijau di ujung kanan atas
    $dot = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(46, 204, 113))
    $r = $Size * 0.10
    $g.FillEllipse($dot, [single]($Size * 0.84 - $r), [single]($Size * 0.26 - $r), [single]($r * 2), [single]($r * 2))
    $dot.Dispose()

    $g.Dispose()
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$madeIcon = $false
foreach ($sz in @(180, 192, 512)) {
    $p = Join-Path $docs "icon-$sz.png"
    if (-not (Test-Path $p)) { New-AppIcon -Size $sz -Path $p; $madeIcon = $true }
}
if ($madeIcon) { Write-Host '  [OK] ikon aplikasi dibuat' -ForegroundColor Green }

# --- 3. Manifest PWA ---
$manifest = @'
{
  "name": "Screener Saham AS",
  "short_name": "Saham AS",
  "description": "Screener dan berita saham Amerika Serikat: fundamental, teknikal, dan agenda laporan keuangan.",
  "start_url": "./index.html",
  "display": "standalone",
  "background_color": "#0b0f16",
  "theme_color": "#0b0f16",
  "orientation": "portrait-primary",
  "icons": [
    { "src": "icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" }
  ]
}
'@
[System.IO.File]::WriteAllText((Join-Path $docs 'manifest.json'), $manifest, (New-Object System.Text.UTF8Encoding $false))

# GitHub Pages jangan memproses file lewat Jekyll.
[System.IO.File]::WriteAllText((Join-Path $docs '.nojekyll'), '', (New-Object System.Text.UTF8Encoding $false))

$sz1 = [Math]::Round((Get-Item (Join-Path $docs 'index.html')).Length / 1KB, 0)
$sz2 = 0
if (Test-Path (Join-Path $docs 'berita.html')) {
    $sz2 = [Math]::Round((Get-Item (Join-Path $docs 'berita.html')).Length / 1KB, 0)
}
Write-Host ''
Write-Host "  Folder docs\ siap. Screener $sz1 KB, berita $sz2 KB." -ForegroundColor Green

# --- 4. Unggah ke GitHub ---
if (-not $Push) {
    Write-Host '  Jalankan dengan -Push untuk mengunggah ke GitHub.' -ForegroundColor DarkGray
    Write-Host ''
    return
}

Push-Location $root
# PENTING: git menulis peringatan biasa (mis. soal CRLF) ke stderr. Di PowerShell 5.1
# stderr dari program eksternal dibungkus jadi ErrorRecord, sehingga dengan
# ErrorActionPreference 'Stop' peringatan sepele pun membatalkan skrip. Karena itu
# di blok ini dipakai 'Continue' dan keberhasilan dinilai dari $LASTEXITCODE.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    if (-not (Test-Path (Join-Path $root '.git'))) {
        throw "Belum ada repositori git di sini. Jalankan .\Setup-GitHub.ps1 dulu."
    }
    $remote = ''
    try { $remote = (git remote get-url origin) } catch { }
    if ([string]::IsNullOrWhiteSpace($remote)) {
        throw "Remote 'origin' belum diatur. Jalankan .\Setup-GitHub.ps1 dulu."
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        $Message = "Perbarui dashboard " + (Get-Date -Format 'yyyy-MM-dd HH:mm')
    }

    git add docs 2>$null | Out-Null
    $status = git status --porcelain docs
    $branch = (git rev-parse --abbrev-ref HEAD).Trim()

    if ([string]::IsNullOrWhiteSpace($status)) {
        # Tidak ada perubahan baru - tapi bisa saja ada commit lama yang gagal
        # terunggah (mis. proses dihentikan setelah commit tapi sebelum push).
        # Push tetap dicoba; kalau sudah sinkron, git tidak melakukan apa-apa.
        git push origin $branch 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host '  Tidak ada perubahan baru; repositori sudah sinkron.' -ForegroundColor DarkGray
        } else {
            Write-Host '  Tidak ada perubahan baru, tapi push commit lama GAGAL.' -ForegroundColor Yellow
            Write-Host "  Coba manual: git push origin $branch" -ForegroundColor DarkGray
        }
        Write-Host ''
        return
    }

    git commit -m $Message 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git commit gagal." }
    git push origin $branch 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "git push gagal. Pastikan Anda sudah login ke GitHub (jalankan: gh auth login)."
    }

    Write-Host "  Terunggah ke GitHub (branch $branch)." -ForegroundColor Green
    $url = $remote -replace '\.git$', '' -replace '^git@github\.com:', 'https://github.com/'
    if ($url -match 'github\.com/([^/]+)/([^/]+)') {
        $site = "https://$($Matches[1]).github.io/$($Matches[2])/"
        Write-Host ''
        Write-Host "  Screener : $site" -ForegroundColor Cyan
        Write-Host "  Berita   : ${site}berita.html" -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Perubahan biasanya tampil di web dalam 1-2 menit.' -ForegroundColor DarkGray
    }
    Write-Host ''
}
finally {
    $ErrorActionPreference = $prevEAP
    Pop-Location
}
