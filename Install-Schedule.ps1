<#
.SYNOPSIS
    Memasang jadwal otomatis harian untuk screener dan berita saham AS.

.DESCRIPTION
    Membuat dua tugas di Windows Task Scheduler:

      "Screener Saham AS"  - jalan tiap hari kerja pukul 06.30 WIB
      "Berita Saham AS"    - jalan tiap hari kerja pukul 06.45 WIB dan 19.00 WIB

    Kenapa pagi hari? Bursa AS tutup pukul 03.00-04.00 WIB (tergantung musim
    panas/dingin di sana). Jadi jam 06.30 WIB data penutupan semalam sudah
    lengkap dan siap dibaca sebelum Anda mulai beraktivitas.

    Jadwal berita yang kedua (19.00 WIB) berguna untuk melihat berita menjelang
    bursa AS buka malam harinya.

    Tugas hanya berjalan kalau komputer menyala. Kalau komputer sedang mati,
    Windows akan menjalankannya begitu komputer dinyalakan kembali.

.PARAMETER ScreenerTime
    Jam screener berjalan, format HH:mm. Default 06:30.

.PARAMETER NewsTime
    Jam berita pagi berjalan, format HH:mm. Default 06:45.

.PARAMETER NewsTime2
    Jam berita sore berjalan, format HH:mm. Default 19:00. Isi kosong untuk melewati.

.PARAMETER Remove
    Hapus kedua jadwal, jangan pasang.

.EXAMPLE
    .\Install-Schedule.ps1
    .\Install-Schedule.ps1 -ScreenerTime 05:30 -NewsTime 05:45
    .\Install-Schedule.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$ScreenerTime = '06:30',
    [string]$NewsTime     = '06:45',
    [string]$NewsTime2    = '19:00',
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

# --- Cek hak administrator ---
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

# --- Validasi format jam ---
function Test-TimeFormat {
    param([string]$T)
    return ($T -match '^([01]?\d|2[0-3]):[0-5]\d$')
}
foreach ($pair in @(@{N='ScreenerTime';V=$ScreenerTime}, @{N='NewsTime';V=$NewsTime})) {
    if (-not (Test-TimeFormat $pair.V)) {
        Write-Host "  Format jam -$($pair.N) salah: '$($pair.V)'. Pakai format HH:mm, misal 06:30." -ForegroundColor Red
        Write-Host ''
        return
    }
}
$useNews2 = (-not [string]::IsNullOrWhiteSpace($NewsTime2))
if ($useNews2 -and -not (Test-TimeFormat $NewsTime2)) {
    Write-Host "  Format jam -NewsTime2 salah: '$NewsTime2'. Pakai format HH:mm." -ForegroundColor Red
    Write-Host ''
    return
}

$days = @('Monday','Tuesday','Wednesday','Thursday','Friday')

try {
    Remove-TaskIfExists -Name $taskScreener | Out-Null
    Remove-TaskIfExists -Name $taskNews     | Out-Null

    # Kalau komputer sempat mati saat jadwalnya lewat, jalankan begitu menyala.
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -DontStopIfGoingOnBatteries `
        -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 2)

    # --- Screener ---
    $actS = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$root\Run-Screener.ps1`" -NoOpen" `
        -WorkingDirectory $root
    $trgS = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $ScreenerTime
    Register-ScheduledTask -TaskName $taskScreener -Action $actS -Trigger $trgS `
        -Settings $settings -Description 'Memperbarui screener saham AS setiap pagi.' | Out-Null
    Write-Host "  [OK] '$taskScreener' -> tiap Senin-Jumat pukul $ScreenerTime WIB" -ForegroundColor Green

    # --- Berita ---
    $actN = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$root\Run-News.ps1`" -NoOpen" `
        -WorkingDirectory $root
    $trgN = @(New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $NewsTime)
    if ($useNews2) { $trgN += New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $NewsTime2 }
    Register-ScheduledTask -TaskName $taskNews -Action $actN -Trigger $trgN `
        -Settings $settings -Description 'Memperbarui berita saham AS.' | Out-Null
    $jam = $NewsTime
    if ($useNews2) { $jam = "$NewsTime dan $NewsTime2" }
    Write-Host "  [OK] '$taskNews' -> tiap Senin-Jumat pukul $jam WIB" -ForegroundColor Green
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
Write-Host '  sudah lengkap. Dashboard tinggal dibuka dari folder output\.' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  Untuk mematikan jadwal:  .\Install-Schedule.ps1 -Remove' -ForegroundColor DarkGray
Write-Host ''
