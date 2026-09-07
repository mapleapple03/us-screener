<#
.SYNOPSIS
    Memasang jadwal otomatis harian untuk screener, berita, dan unggah ke situs.

.DESCRIPTION
    Membuat dua tugas di Windows Task Scheduler:

      "Screener Saham AS"  - tiap hari kerja pukul 06.30 WIB
                             screener -> berita -> unggah ke situs (berurutan)

      "Berita Saham AS"    - tiap hari kerja pukul 19.00 WIB
                             berita -> unggah ke situs

    Kenapa pagi hari? Bursa AS tutup pukul 03.00-04.00 WIB (tergantung musim
    panas/dingin di sana). Jadi jam 06.30 WIB data penutupan semalam sudah
    lengkap dan siap dibaca sebelum Anda mulai beraktivitas.

    Kenapa berita ikut di rangkaian pagi, bukan tugas terpisah? Karena screener
    butuh 20-35 menit. Kalau berita dijadwalkan terpisah beberapa menit setelah
    screener mulai, ia akan membaca hasil screener KEMARIN yang belum tertimpa.
    Dijadikan satu rangkaian, urutannya dijamin benar.

    Jadwal sore (19.00) berguna untuk melihat berita menjelang bursa AS buka.

    Tugas hanya berjalan kalau komputer menyala. Kalau komputer sedang mati,
    Windows menjalankannya begitu komputer dinyalakan kembali.

.PARAMETER ScreenerTime
    Jam rangkaian pagi berjalan, format HH:mm. Default 06:30.

.PARAMETER NewsTime
    Jam pembaruan berita sore, format HH:mm. Default 19:00.
    Isi string kosong ('') untuk melewati jadwal sore.

.PARAMETER NoPublish
    Jangan ikut mengunggah ke GitHub Pages. Dashboard tetap diperbarui di
    komputer, tapi versi yang di HP tidak ikut segar.

.PARAMETER Remove
    Hapus kedua jadwal, jangan pasang.

.EXAMPLE
    .\Install-Schedule.ps1
    .\Install-Schedule.ps1 -ScreenerTime 05:30 -NewsTime 20:00
    .\Install-Schedule.ps1 -NoPublish
    .\Install-Schedule.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$ScreenerTime = '06:30',
    [string]$NewsTime     = '19:00',
    [switch]$NoPublish,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

$taskScreener = 'Screener Saham AS'
$taskNews     = 'Berita Saham AS'

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host '   JADWAL OTOMATIS HARIAN' -ForegroundColor Cyan
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host ''

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Remove-TaskIfExists {
    param([string]$Name)
    $t = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($null -ne $t) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
        Write-Host "  Jadwal lama '$Name' dihapus." -ForegroundColor DarkGray
        return $true
    }
    return $false
}

if ($Remove) {
    $a = Remove-TaskIfExists -Name $taskScreener
    $b = Remove-TaskIfExists -Name $taskNews
    if ($a -or $b) { Write-Host '  Jadwal otomatis sudah dimatikan.' -ForegroundColor Green }
    else { Write-Host '  Tidak ada jadwal yang terpasang.' -ForegroundColor Yellow }
    Write-Host ''
    return
}

function Test-TimeFormat {
    param([string]$T)
    return ($T -match '^([01]?\d|2[0-3]):[0-5]\d$')
}
if (-not (Test-TimeFormat $ScreenerTime)) {
    Write-Host "  Format jam -ScreenerTime salah: '$ScreenerTime'. Pakai HH:mm, misal 06:30." -ForegroundColor Red
    Write-Host ''
    return
}
$useNews = (-not [string]::IsNullOrWhiteSpace($NewsTime))
if ($useNews -and -not (Test-TimeFormat $NewsTime)) {
    Write-Host "  Format jam -NewsTime salah: '$NewsTime'. Pakai HH:mm, misal 19:00." -ForegroundColor Red
    Write-Host ''
    return
}

$days = @('Monday','Tuesday','Wednesday','Thursday','Friday')

# Pembantu: satu langkah = satu skrip PowerShell.
function New-Step {
    param([string]$Script, [string]$Extra = '')
    return New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$root\$Script`" $Extra".Trim() `
        -WorkingDirectory $root
}

try {
    Remove-TaskIfExists -Name $taskScreener | Out-Null
    Remove-TaskIfExists -Name $taskNews     | Out-Null

    # Kalau komputer sempat mati saat jadwalnya lewat, jalankan begitu menyala.
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -DontStopIfGoingOnBatteries `
        -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    # --- Rangkaian pagi: screener -> berita -> unggah ---
    # Task Scheduler menjalankan daftar action secara BERURUTAN, menunggu tiap
    # langkah selesai. Itu yang dipakai untuk menjamin urutannya benar.
    $actS = @(
        (New-Step -Script 'Run-Screener.ps1' -Extra '-NoOpen'),
        (New-Step -Script 'Run-News.ps1'     -Extra '-NoOpen')
    )
    if (-not $NoPublish) { $actS += (New-Step -Script 'Publish-Web.ps1' -Extra '-Push') }

    $trgS = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $ScreenerTime
    Register-ScheduledTask -TaskName $taskScreener -Action $actS -Trigger $trgS `
        -Settings $settings -Description 'Screener + berita + unggah, tiap pagi.' | Out-Null

    $langkah = 'screener -> berita'
    if (-not $NoPublish) { $langkah += ' -> unggah ke situs' }
    Write-Host "  [OK] '$taskScreener'" -ForegroundColor Green
    Write-Host "       Senin-Jumat $ScreenerTime WIB  ($langkah)" -ForegroundColor DarkGray

    # --- Pembaruan berita sore ---
    if ($useNews) {
        $actN = @( (New-Step -Script 'Run-News.ps1' -Extra '-NoOpen') )
        if (-not $NoPublish) { $actN += (New-Step -Script 'Publish-Web.ps1' -Extra '-Push') }

        $trgN = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $NewsTime
        Register-ScheduledTask -TaskName $taskNews -Action $actN -Trigger $trgN `
            -Settings $settings -Description 'Memperbarui berita saham AS.' | Out-Null

        $langkah2 = 'berita'
        if (-not $NoPublish) { $langkah2 += ' -> unggah ke situs' }
        Write-Host "  [OK] '$taskNews'" -ForegroundColor Green
        Write-Host "       Senin-Jumat $NewsTime WIB  ($langkah2)" -ForegroundColor DarkGray
    }
}
catch {
    Write-Host ''
    Write-Host "  GAGAL memasang jadwal: $($_.Exception.Message)" -ForegroundColor Red
    if (-not $isAdmin) {
        Write-Host ''
        Write-Host '  Kemungkinan besar karena PowerShell tidak dijalankan sebagai Administrator.' -ForegroundColor Yellow
        Write-Host '  Klik kanan PowerShell -> "Run as administrator", lalu ulangi perintah ini.' -ForegroundColor Yellow
    }
    Write-Host ''
    return
}

Write-Host ''
Write-Host '  Bursa AS tutup pukul 03.00-04.00 WIB, jadi jam segini data semalam' -ForegroundColor DarkGray
Write-Host '  sudah lengkap.' -ForegroundColor DarkGray
if (-not $NoPublish) {
    Write-Host '  Dashboard di HP ikut diperbarui otomatis setelah tiap jadwal.' -ForegroundColor DarkGray
}
Write-Host ''
Write-Host '  Untuk mematikan jadwal:  .\Install-Schedule.ps1 -Remove' -ForegroundColor DarkGray
Write-Host ''
