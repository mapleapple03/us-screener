<#
.SYNOPSIS
    Sekali jalan: membuat repositori GitHub dan menyalakan GitHub Pages,
    supaya dashboard bisa dibuka dari HP Android.

.DESCRIPTION
    Langkah yang dilakukan:
      1. Memastikan GitHub CLI (gh) terpasang dan Anda sudah login
      2. Menyiapkan repositori git lokal + .gitignore
      3. Membuat repositori di GitHub
      4. Mengunggah isi folder docs\
      5. Menyalakan GitHub Pages dari folder docs\ di branch utama

    Cukup dijalankan SATU KALI. Setelah itu, untuk memperbarui isi situsnya
    tinggal jalankan .\Publish-Web.ps1 -Push

    PERHATIAN: GitHub Pages gratis hanya melayani repositori PUBLIK. Isi
    dashboard - termasuk daftar saham pantauan Anda - bisa dilihat siapa pun
    yang tahu alamatnya. Kalau tidak mau, pakai .\Serve-Local.ps1 sebagai
    gantinya (hanya bisa diakses dari WiFi rumah Anda sendiri).

.PARAMETER RepoName
    Nama repositori di GitHub. Default: us-screener

.PARAMETER Private
    Buat repositori privat. Catatan: GitHub Pages TIDAK aktif untuk repositori
    privat kecuali akun Anda berlangganan GitHub Pro.

.EXAMPLE
    .\Setup-GitHub.ps1
    .\Setup-GitHub.ps1 -RepoName saham-as
#>
[CmdletBinding()]
param(
    [string]$RepoName = 'us-screener',
    [switch]$Private
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host '   PENYIAPAN GITHUB PAGES (sekali jalan)' -ForegroundColor Cyan
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host ''

# --- 1. Cek gh ---
Write-Host '  [1/5] Memeriksa GitHub CLI...' -NoNewline
$ghOk = $false
try { $null = & gh --version 2>$null; $ghOk = ($LASTEXITCODE -eq 0) } catch { }
if (-not $ghOk) {
    Write-Host ' TIDAK ADA' -ForegroundColor Red
    Write-Host ''
    Write-Host '  GitHub CLI belum terpasang. Pasang dulu lewat:' -ForegroundColor Yellow
    Write-Host '     winget install GitHub.cli' -ForegroundColor Gray
    Write-Host '  Lalu login:  gh auth login' -ForegroundColor Gray
    Write-Host ''
    return
}

$account = ''
$authOk = $false
try {
    $st = & gh auth status 2>&1 | Out-String
    $authOk = ($LASTEXITCODE -eq 0)
    if ($st -match 'account\s+(\S+)') { $account = $Matches[1] }
} catch { }
if (-not $authOk) {
    Write-Host ' BELUM LOGIN' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Jalankan dulu:  gh auth login' -ForegroundColor Yellow
    Write-Host ''
    return
}
Write-Host " OK (akun: $account)" -ForegroundColor Green

# --- 2. Repositori lokal ---
Write-Host '  [2/5] Menyiapkan repositori lokal...' -NoNewline
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
Push-Location $root
try {
    $gitignore = @'
# Hasil kerja yang dibuat ulang tiap kali screener jalan.
output/
data/universe.json
data/latest.json

# Berkas sementara Windows
Thumbs.db
desktop.ini
'@
    [System.IO.File]::WriteAllText((Join-Path $root '.gitignore'), $gitignore, (New-Object System.Text.UTF8Encoding $false))

    if (-not (Test-Path (Join-Path $root '.git'))) {
        git init 2>$null | Out-Null
        git branch -M main 2>$null | Out-Null
    }

    # Di komputer ini identitas git diatur PER-REPOSITORI, bukan global. Repositori
    # yang baru dibuat karena itu belum punya nama/email, dan `git commit` akan
    # gagal. Nilainya disalin dari repositori tetangga (idx-screener) kalau ada.
    $uname = ''
    try { $uname = (git config user.name 2>$null) } catch { }
    if ([string]::IsNullOrWhiteSpace($uname)) {
        $srcName = ''; $srcMail = ''
        $sibling = Join-Path (Split-Path -Parent $root) 'idx-screener'
        if (Test-Path (Join-Path $sibling '.git')) {
            try {
                $srcName = (git -C $sibling config user.name 2>$null)
                $srcMail = (git -C $sibling config user.email 2>$null)
            } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($srcName)) { $srcName = $account }
        if ([string]::IsNullOrWhiteSpace($srcMail)) { $srcMail = "$account@users.noreply.github.com" }
        git config user.name  "$srcName" 2>$null | Out-Null
        git config user.email "$srcMail" 2>$null | Out-Null
        Write-Host " OK (identitas git: $srcName <$srcMail>)" -ForegroundColor Green
    } else {
        Write-Host ' OK' -ForegroundColor Green
    }

    # --- 3. Siapkan docs\ ---
    Write-Host '  [3/5] Menyiapkan folder docs\...' -ForegroundColor Gray
    & (Join-Path $root 'Publish-Web.ps1')

    # --- 4. Buat repositori di GitHub ---
    Write-Host "  [4/5] Membuat repositori '$RepoName' di GitHub..." -NoNewline
    $exists = $false
    try { $null = & gh repo view "$account/$RepoName" 2>$null; $exists = ($LASTEXITCODE -eq 0) } catch { }

    if ($exists) {
        Write-Host ' SUDAH ADA' -ForegroundColor Yellow
        $remote = ''
        try { $remote = (git remote get-url origin 2>$null) } catch { }
        if ([string]::IsNullOrWhiteSpace($remote)) {
            git remote add origin "https://github.com/$account/$RepoName.git" 2>$null | Out-Null
        }
    } else {
        $vis = if ($Private) { '--private' } else { '--public' }
        git add -A 2>$null | Out-Null
        git commit -m 'Screener dan berita saham AS' 2>$null | Out-Null
        & gh repo create $RepoName $vis --source=. --remote=origin --push 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ' GAGAL' -ForegroundColor Red
            Write-Host '  Coba manual:  gh repo create ' -NoNewline -ForegroundColor Yellow
            Write-Host "$RepoName --public --source=. --remote=origin --push" -ForegroundColor Yellow
            return
        }
        Write-Host ' OK' -ForegroundColor Green
    }

    # Pastikan semua terunggah.
    git add -A 2>$null | Out-Null
    $status = git status --porcelain
    if (-not [string]::IsNullOrWhiteSpace($status)) {
        git commit -m 'Perbarui dashboard' 2>$null | Out-Null
    }
    git push -u origin main 2>$null | Out-Null

    # --- 5. Nyalakan GitHub Pages ---
    Write-Host '  [5/5] Menyalakan GitHub Pages (branch main, folder docs)...' -NoNewline
    $pagesOk = $false
    # Kalau Pages belum pernah aktif, endpointnya POST. Kalau sudah, PUT.
    & gh api -X POST "repos/$account/$RepoName/pages" -f "source[branch]=main" -f "source[path]=/docs" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $pagesOk = $true }
    else {
        & gh api -X PUT "repos/$account/$RepoName/pages" -f "source[branch]=main" -f "source[path]=/docs" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $pagesOk = $true }
    }

    if ($pagesOk) {
        Write-Host ' OK' -ForegroundColor Green
    } else {
        Write-Host ' PERLU MANUAL' -ForegroundColor Yellow
        Write-Host "     Buka https://github.com/$account/$RepoName/settings/pages" -ForegroundColor Gray
        Write-Host '     Source: Deploy from a branch -> Branch: main -> Folder: /docs -> Save' -ForegroundColor Gray
    }

    $site = "https://$account.github.io/$RepoName/"
    Write-Host ''
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host '   Selesai. Alamat situs Anda:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "   Screener : $site" -ForegroundColor White
    Write-Host "   Berita   : ${site}berita.html" -ForegroundColor White
    Write-Host ''
    Write-Host '   Situs baru biasanya aktif 1-3 menit setelah ini.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   Di HP Android: buka alamat itu di Chrome, lalu menu tiga titik' -ForegroundColor DarkGray
    Write-Host '   -> "Add to Home screen". Ikonnya akan muncul seperti aplikasi.' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host '   Untuk memperbarui isinya nanti:  .\Publish-Web.ps1 -Push' -ForegroundColor DarkGray
    Write-Host ''
}
finally {
    $ErrorActionPreference = $prevEAP
    Pop-Location
}
