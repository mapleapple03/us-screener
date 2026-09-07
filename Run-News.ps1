<#
.SYNOPSIS
    Berita Saham Amerika Serikat - dikelompokkan per tema, plus agenda laporan keuangan.

.DESCRIPTION
    Mengambil berita dari RSS publik (CNBC, Yahoo Finance, Google News), lalu:
      1. Mengelompokkannya per tema (suku bunga, inflasi, laporan keuangan, dll)
      2. Menambahkan penjelasan "apa artinya buat investor" untuk tiap tema
      3. Mengambil berita khusus untuk saham yang Anda pantau
      4. Menyusun agenda laporan keuangan dari hasil screener terakhir

    Hasil disimpan ke output\berita.html.

.PARAMETER Watchlist
    Daftar kode saham yang ingin diikuti beritanya. Kalau tidak diisi, dipakai
    isi data\watchlist.txt, atau kalau itu juga tidak ada, saham dengan sinyal
    beli terbaik dari hasil screener terakhir.

.PARAMETER TopN
    Berapa saham teratas dari screener yang diambil beritanya. Default 12.

.PARAMETER NoOpen
    Jangan buka dashboard otomatis setelah selesai.

.EXAMPLE
    .\Run-News.ps1
    .\Run-News.ps1 -Watchlist AAPL,NVDA,MSFT
#>
[CmdletBinding()]
param(
    [string[]]$Watchlist,
    [int]$TopN = 12,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $root 'lib\Config.ps1')
. (Join-Path $root 'lib\MarketData.ps1')
. (Join-Path $root 'lib\News.ps1')
. (Join-Path $root 'lib\NewsReport.ps1')

$startTime = Get-Date

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host '   BERITA SAHAM AMERIKA SERIKAT' -ForegroundColor Cyan
Write-Host '   Makro + Laporan Keuangan + Saham Pantauan' -ForegroundColor DarkGray
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host ''

$mkt = Get-UsMarketStatus
Write-Host "  $($mkt.State)  |  New York $($mkt.EtTime)  |  WIB $($mkt.WibTime)" -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------------------
# 1. Tentukan daftar saham pantauan
# ---------------------------------------------------------------------------
$screener = $null
$screenerPath = Join-Path $root 'data\latest.json'
if (Test-Path $screenerPath) {
    try { $screener = Get-Content $screenerPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
}

$wlSource = ''
$codes = @()

if ($Watchlist -and $Watchlist.Count -gt 0) {
    $codes = @($Watchlist | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
    $wlSource = 'daftar dari perintah'
}
else {
    $wlPath = Join-Path $root 'data\watchlist.txt'
    if (Test-Path $wlPath) {
        $lines = Get-Content $wlPath -Encoding UTF8 |
            ForEach-Object { ($_ -split '#')[0].Trim().ToUpper() } |
            Where-Object { $_ -match '^[A-Z][A-Z0-9\-\.]*$' }
        if (@($lines).Count -gt 0) {
            $codes = @($lines | Select-Object -Unique)
            $wlSource = 'data\watchlist.txt'
        }
    }
    if ($codes.Count -eq 0 -and $null -ne $screener) {
        $picks = @($screener.Stocks |
            Where-Object { $_.signal -in @('STRONG BUY', 'BUY', 'AKUMULASI') } |
            Sort-Object -Property combined -Descending |
            Select-Object -First $TopN)
        $codes = @($picks | ForEach-Object { $_.code })
        $wlSource = "$($codes.Count) sinyal beli terbaik dari screener"
    }
    if ($codes.Count -eq 0) {
        $codes = @('AAPL','MSFT','NVDA','GOOGL','AMZN','META','TSLA','SPY')
        $wlSource = 'daftar bawaan'
    }
}

Write-Host "  Saham pantauan ($wlSource):" -ForegroundColor DarkGray
Write-Host "  $($codes -join ', ')" -ForegroundColor Gray
Write-Host ''

# ---------------------------------------------------------------------------
# 2. Ambil berita
# ---------------------------------------------------------------------------
Write-Host '  [1/3] Mengambil berita makro & pasar...' -NoNewline
$macro = Get-MacroNews -PerFeed 18
Write-Host " OK ($($macro.Count) berita)" -ForegroundColor Green

Write-Host '  [2/3] Mengambil berita laporan keuangan...' -NoNewline
$earnNews = Get-EarningsNews -Max 20
Write-Host " OK ($($earnNews.Count) berita)" -ForegroundColor Green

Write-Host '  [3/3] Mengambil berita per saham pantauan...' -NoNewline
$tickerNews = New-Object System.Collections.ArrayList
foreach ($c in $codes) {
    $items = Get-TickerNews -Symbol $c -Max 6
    foreach ($it in $items) { [void]$tickerNews.Add($it) }
}
Write-Host " OK ($($tickerNews.Count) berita)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. Olah: kelompokkan per tema, tebak nada, buang yang kembar
# ---------------------------------------------------------------------------
$all = New-Object System.Collections.ArrayList
foreach ($x in $macro)      { [void]$all.Add($x) }
foreach ($x in $earnNews)   { [void]$all.Add($x) }
foreach ($x in $tickerNews) { [void]$all.Add($x) }

$all = Remove-DuplicateNews -Items $all

$prepared = New-Object System.Collections.ArrayList
foreach ($it in $all) {
    $cat = Get-NewsCategory -Title $it.Title -Summary $it.Summary
    [void]$prepared.Add([pscustomobject]@{
        title     = $it.Title
        link      = $it.Link
        summary   = $it.Summary
        source    = $it.Source
        scope     = $it.Scope
        category  = $cat
        tone      = Get-NewsTone -Title $it.Title
        ticker    = $(if ($it.PSObject.Properties.Name -contains 'Ticker') { $it.Ticker } else { $null })
        published = $(if ($null -ne $it.Published) { $it.Published.ToString('yyyy-MM-ddTHH:mm:ss') } else { $null })
        sortKey   = $(if ($null -ne $it.Published) { $it.Published } else { [DateTime]::MinValue })
    })
}

# --- Kelompokkan per tema ---
# Urutannya sengaja dipatok, bukan berdasarkan jumlah berita: tema yang paling
# menggerakkan pasar ditaruh di atas, dan keranjang sisa "Lainnya" selalu di bawah.
$catOrder = @(
    'Pasar Umum', 'Suku Bunga & The Fed', 'Inflasi & Data Ekonomi', 'Laporan Keuangan',
    'Analis & Rating', 'Teknologi & AI', 'Energi & Komoditas', 'Kripto & Bitcoin',
    'Merger & Akuisisi', 'Dividen & Buyback', 'Regulasi & Hukum', 'Geopolitik',
    'Properti & Perumahan', 'Perusahaan & Bisnis', 'Lainnya'
)
$categories = New-Object System.Collections.ArrayList
$grouped = $prepared | Group-Object -Property category | Sort-Object -Property @{
    Expression = {
        $idx = $catOrder.IndexOf($_.Name)
        if ($idx -lt 0) { 900 } else { $idx }
    }
}
foreach ($g in $grouped) {
    $items = @($g.Group | Sort-Object -Property sortKey -Descending |
        Select-Object title, link, summary, source, scope, category, tone, ticker, published)
    [void]$categories.Add([pscustomobject]@{
        name  = $g.Name
        why   = Get-NewsExplainer -Category $g.Name
        count = $items.Count
        items = $items
    })
}

# --- Kelompokkan berita per saham pantauan ---
$byTicker = New-Object System.Collections.ArrayList
foreach ($c in $codes) {
    $items = @($prepared | Where-Object { $_.ticker -eq $c } |
        Sort-Object -Property sortKey -Descending |
        Select-Object title, link, summary, source, scope, category, tone, ticker, published)
    if ($items.Count -eq 0) { continue }

    $info = $null
    if ($null -ne $screener) { $info = $screener.Stocks | Where-Object { $_.code -eq $c } | Select-Object -First 1 }

    [void]$byTicker.Add([pscustomobject]@{
        code   = $c
        name   = $(if ($null -ne $info) { $info.name } else { $null })
        signal = $(if ($null -ne $info) { $info.signal } else { $null })
        chg1d  = $(if ($null -ne $info) { $info.chg1d } else { $null })
        items  = $items
    })
}

# ---------------------------------------------------------------------------
# 4. Agenda laporan keuangan (dari hasil screener terakhir)
# ---------------------------------------------------------------------------
$agenda = New-Object System.Collections.ArrayList
if ($null -ne $screener) {
    $upcoming = @($screener.Stocks |
        Where-Object { $_.earningsDate -and $null -ne $_.earningsIn -and $_.earningsIn -ge 0 -and $_.earningsIn -le 30 } |
        Sort-Object -Property earningsIn)
    foreach ($s in $upcoming) {
        [void]$agenda.Add([pscustomobject]@{
            code   = $s.code
            name   = $s.name
            date   = $s.earningsDate
            days   = $s.earningsIn
            signal = $s.signal
            chg1d  = $s.chg1d
        })
    }
}

# ---------------------------------------------------------------------------
# 5. Bangun dashboard
# ---------------------------------------------------------------------------
$meta = [pscustomobject]@{
    GeneratedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    MarketState     = $mkt.State
    MarketOpen      = ($mkt.State -like '*SEDANG BUKA*')
    OpenWib         = $mkt.OpenWib
    CloseWib        = $mkt.CloseWib
    TotalNews       = $prepared.Count
    WatchlistSource = $wlSource
    Watchlist       = ($codes -join ', ')
    HasScreener     = ($null -ne $screener)
}

$outPath = Join-Path $root 'output\berita.html'
New-NewsReport -Categories $categories -Tickers $byTicker -Earnings $agenda -OutPath $outPath -Meta $meta

# ---------------------------------------------------------------------------
# Ringkasan
# ---------------------------------------------------------------------------
$elapsed = (Get-Date) - $startTime
Write-Host ''
Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkCyan
Write-Host "   Selesai dalam $([int]$elapsed.TotalSeconds) detik" -ForegroundColor Cyan
Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkCyan
Write-Host "   Total berita (setelah buang kembar) : $($prepared.Count)" -ForegroundColor Gray
Write-Host "   Tema                                 : $($categories.Count)" -ForegroundColor Gray
Write-Host "   Saham pantauan dengan berita         : $($byTicker.Count)" -ForegroundColor Gray
Write-Host "   Agenda laporan keuangan (30 hari)    : $($agenda.Count)" -ForegroundColor Gray
Write-Host ''
foreach ($c in ($categories | Select-Object -First 8)) {
    Write-Host ("   {0,-26} {1,3} berita" -f $c.name, $c.count) -ForegroundColor DarkGray
}
if ($agenda.Count -eq 0 -and $null -eq $screener) {
    Write-Host ''
    Write-Host '   Catatan: jalankan Run-Screener.ps1 dulu supaya agenda laporan' -ForegroundColor Yellow
    Write-Host '   keuangan dan sinyal per saham ikut tampil.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host "   Dashboard: $outPath" -ForegroundColor Cyan
Write-Host ''

if (-not $NoOpen) { Start-Process $outPath }
