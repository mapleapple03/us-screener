<#
.SYNOPSIS
    Memperbarui daftar saham AS yang akan di-screen (data\universe.json).

.DESCRIPTION
    Mengambil daftar konstituen S&P 500 terbaru, lalu menambahkan saham
    Nasdaq-100 yang belum masuk S&P 500 dan sejumlah ETF populer.

    Cukup dijalankan sesekali (misal sebulan sekali). Daftar S&P 500 hanya
    berubah beberapa nama per tahun.

    Kalau pengambilan gagal (internet mati / sumber berubah), screener tetap
    jalan memakai daftar cadangan bawaan di lib\Universe.ps1.

.EXAMPLE
    .\Update-Universe.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $root 'lib\Universe.ps1')

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'

Write-Host ''
Write-Host '  Memperbarui daftar saham AS...' -ForegroundColor Cyan
Write-Host ''

$stocks = New-Object System.Collections.ArrayList
$seen   = @{}

function Add-Stock {
    param([string]$Code, [string]$Name, [string]$Sector, [string]$Group)
    $c = $Code.Trim().ToUpper()
    if ([string]::IsNullOrWhiteSpace($c)) { return }
    if ($seen.ContainsKey($c)) { return }
    $seen[$c] = $true
    [void]$stocks.Add([pscustomobject]@{
        Code = $c; Name = $Name; Sector = $Sector; Group = $Group
    })
}

# --- 1. S&P 500 dari daftar publik yang dipelihara komunitas ---
$sp500Url = 'https://raw.githubusercontent.com/datasets/s-and-p-500-companies/main/data/constituents.csv'
$gotSp500 = $false
Write-Host '  [1/3] Mengambil daftar S&P 500...' -NoNewline
try {
    $csv = Invoke-WebRequest -Uri $sp500Url -UseBasicParsing -TimeoutSec 40 -UserAgent $UA -ErrorAction Stop
    $rows = $csv.Content | ConvertFrom-Csv
    foreach ($r in $rows) {
        # Yahoo memakai tanda hubung, bukan titik: BRK.B -> BRK-B
        $code = "$($r.Symbol)".Replace('.', '-')
        Add-Stock -Code $code -Name $r.Security -Sector $r.'GICS Sector' -Group 'S&P 500'
    }
    if ($stocks.Count -gt 400) { $gotSp500 = $true }
} catch {
    # Ditangani di bawah.
}
if ($gotSp500) {
    Write-Host " OK ($($stocks.Count) saham)" -ForegroundColor Green
} else {
    Write-Host ' GAGAL' -ForegroundColor Yellow
    Write-Host '        Memakai daftar cadangan bawaan.' -ForegroundColor DarkGray
    foreach ($c in $Global:US_UNIVERSE_FALLBACK) { Add-Stock -Code $c -Name '' -Sector '' -Group 'Cadangan' }
}

# --- 2. Nasdaq-100 yang belum tercakup S&P 500 ---
# Umumnya perusahaan asing yang listing di AS (ADR) - tidak masuk S&P 500
# karena syaratnya harus perusahaan berdomisili AS.
Write-Host '  [2/3] Menambah Nasdaq-100 di luar S&P 500...' -NoNewline
$before = $stocks.Count
foreach ($c in $Global:US_NASDAQ_EXTRA) { Add-Stock -Code $c -Name '' -Sector '' -Group 'Nasdaq-100' }
Write-Host " OK (+$($stocks.Count - $before))" -ForegroundColor Green

# --- 3. ETF populer ---
Write-Host '  [3/3] Menambah ETF populer...' -NoNewline
$before = $stocks.Count
foreach ($e in $Global:US_ETF_LIST) { Add-Stock -Code $e.Code -Name $e.Name -Sector 'ETF' -Group 'ETF' }
Write-Host " OK (+$($stocks.Count - $before))" -ForegroundColor Green

# --- Simpan ---
$outDir = Join-Path $root 'data'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPath = Join-Path $outDir 'universe.json'

$payload = [pscustomobject]@{
    UpdatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    Count     = $stocks.Count
    Source    = $(if ($gotSp500) { 'S&P 500 (live) + Nasdaq-100 + ETF' } else { 'daftar cadangan + Nasdaq-100 + ETF' })
    Stocks    = $stocks
}
$payload | ConvertTo-Json -Depth 5 | Set-Content -Path $outPath -Encoding UTF8

Write-Host ''
Write-Host "  Selesai. $($stocks.Count) saham tersimpan di data\universe.json" -ForegroundColor Green
Write-Host ''
