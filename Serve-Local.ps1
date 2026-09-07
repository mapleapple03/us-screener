<#
.SYNOPSIS
    Menyajikan dashboard lewat WiFi rumah, supaya bisa dibuka dari HP Android
    TANPA mengunggah apa pun ke internet.

.DESCRIPTION
    Menjalankan server web kecil di komputer ini. Selama komputer menyala dan
    HP Anda tersambung ke WiFi yang sama, dashboard bisa dibuka dari HP.

    Tidak ada data yang keluar dari rumah Anda. Bandingkan dengan
    .\Publish-Web.ps1 yang menaruh dashboard di internet (bisa dibuka dari mana
    saja, tapi juga bisa dilihat orang lain yang tahu alamatnya).

    Tekan Ctrl+C untuk menghentikan server.

    CATATAN: agar bisa diakses dari HP (bukan cuma dari komputer ini), skrip
    perlu dijalankan lewat PowerShell "Run as administrator". Kalau tidak,
    server tetap jalan tapi hanya bisa dibuka di komputer ini sendiri.

.PARAMETER Port
    Nomor port. Default 8080.

.EXAMPLE
    .\Serve-Local.ps1
    .\Serve-Local.ps1 -Port 9000
#>
[CmdletBinding()]
param(
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$web  = Join-Path $root 'output'

if (-not (Test-Path (Join-Path $web 'index.html'))) {
    throw "Dashboard belum dibuat. Jalankan .\Run-Screener.ps1 dulu."
}

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Cari alamat IP komputer ini di jaringan lokal.
$ip = $null
try {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object {
            $_.IPAddress -notlike '127.*' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.PrefixOrigin -ne 'WellKnown'
        } |
        Sort-Object -Property InterfaceMetric |
        Select-Object -First 1).IPAddress
} catch { }

$listener = New-Object System.Net.HttpListener
$prefix = if ($isAdmin) { "http://+:$Port/" } else { "http://localhost:$Port/" }
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
}
catch {
    Write-Host ''
    Write-Host "  Gagal membuka port $Port." -ForegroundColor Red
    Write-Host "  Kemungkinan port sedang dipakai program lain. Coba: .\Serve-Local.ps1 -Port 9000" -ForegroundColor Yellow
    Write-Host ''
    return
}

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host '   SERVER LOKAL AKTIF' -ForegroundColor Cyan
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host ''
Write-Host "   Di komputer ini : http://localhost:$Port/" -ForegroundColor White

if ($isAdmin -and $ip) {
    Write-Host "   Di HP Android   : http://${ip}:$Port/" -ForegroundColor Green
    Write-Host ''
    Write-Host '   Pastikan HP tersambung ke WiFi yang sama dengan komputer ini.' -ForegroundColor DarkGray
    Write-Host '   Kalau HP tidak bisa membuka, izinkan port ini di Windows Firewall:' -ForegroundColor DarkGray
    Write-Host "     netsh advfirewall firewall add rule name=`"Saham AS $Port`" dir=in action=allow protocol=TCP localport=$Port" -ForegroundColor DarkGray
} else {
    Write-Host ''
    Write-Host '   HANYA bisa dibuka di komputer ini.' -ForegroundColor Yellow
    Write-Host '   Supaya bisa dibuka dari HP, tutup jendela ini lalu jalankan ulang' -ForegroundColor Yellow
    Write-Host '   lewat PowerShell yang di-klik-kanan "Run as administrator".' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '   Tekan Ctrl+C untuk menghentikan server.' -ForegroundColor DarkGray
Write-Host ''

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.txt'  = 'text/plain; charset=utf-8'
    '.md'   = 'text/plain; charset=utf-8'
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response

        try {
            $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }

            # Jangan biarkan permintaan keluar dari folder output\.
            $full = [System.IO.Path]::GetFullPath((Join-Path $web $rel))
            $base = [System.IO.Path]::GetFullPath($web)

            if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $full -PathType Leaf)) {
                $res.StatusCode = 404
                $buf = [System.Text.Encoding]::UTF8.GetBytes('Tidak ditemukan.')
                $res.OutputStream.Write($buf, 0, $buf.Length)
            }
            else {
                $ext = [System.IO.Path]::GetExtension($full).ToLower()
                $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
                # Jangan simpan di cache - isinya berubah tiap kali screener jalan.
                $res.Headers.Add('Cache-Control', 'no-store')
                $bytes = [System.IO.File]::ReadAllBytes($full)
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host ("   {0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $rel) -ForegroundColor DarkGray
            }
        }
        catch {
            try { $res.StatusCode = 500 } catch { }
        }
        finally {
            try { $res.OutputStream.Close() } catch { }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
    Write-Host ''
    Write-Host '   Server dihentikan.' -ForegroundColor DarkGray
    Write-Host ''
}
