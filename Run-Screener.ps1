<#
.SYNOPSIS
    Screener Saham Amerika Serikat - analisa fundamental + teknikal otomatis.

.DESCRIPTION
    Mengambil data harga & fundamental untuk seluruh saham di data\universe.json
    (S&P 500 + Nasdaq-100 + ETF populer), menghitung skor teknikal dan
    fundamental, menentukan gaya trading yang cocok (Day Trade / Swing Trade /
    Investasi), lalu menyusun rencana entry, stop loss, dan take profit.

    Hasil disimpan ke data\latest.json dan dashboard output\index.html.

.PARAMETER Limit
    Batasi jumlah saham yang di-scan (untuk uji coba cepat).

.PARAMETER MinScore
    Skor gabungan minimum agar saham masuk dashboard. Default 0 (tampilkan semua).

.PARAMETER NoOpen
    Jangan buka dashboard otomatis setelah selesai.

.EXAMPLE
    .\Run-Screener.ps1
    .\Run-Screener.ps1 -Limit 25 -NoOpen
#>
[CmdletBinding()]
param(
    [int]$Limit = 0,
    [double]$MinScore = 0,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $root 'lib\Config.ps1')
. (Join-Path $root 'lib\Universe.ps1')
. (Join-Path $root 'lib\MarketData.ps1')
. (Join-Path $root 'lib\Indicators.ps1')
. (Join-Path $root 'lib\Analysis.ps1')
. (Join-Path $root 'lib\Report.ps1')

$startTime = Get-Date

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host '   SCREENER SAHAM AMERIKA SERIKAT' -ForegroundColor Cyan
Write-Host '   Analisa Fundamental + Teknikal' -ForegroundColor DarkGray
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host ''

# --- Siapkan sesi data ---
Write-Host '  Menyiapkan koneksi data pasar...' -NoNewline
$ok = Initialize-YahooSession
if ($ok) { Write-Host ' OK' -ForegroundColor Green }
else {
    Write-Host ' SEBAGIAN' -ForegroundColor Yellow
    Write-Host '  Data harga tetap bisa diambil, tapi data fundamental mungkin kosong.' -ForegroundColor DarkGray
}

# --- Status bursa & kurs ---
$mkt = Get-UsMarketStatus
Write-Host "  $($mkt.State)  |  New York $($mkt.EtTime)  |  WIB $($mkt.WibTime)" -ForegroundColor DarkGray
Write-Host "  Jam bursa dalam WIB: $($mkt.OpenWib) - $($mkt.CloseWib)" -ForegroundColor DarkGray

Write-Host '  Mengambil kurs USD/IDR...' -NoNewline
$usdIdr = Get-UsdIdrRate
Write-Host (" Rp {0:N0}" -f $usdIdr) -ForegroundColor Green

# --- Benchmark S&P 500 untuk kekuatan relatif ---
Write-Host "  Mengambil data $($Global:US_BENCHMARK_NAME)..." -NoNewline
$bench = Get-PriceHistory -Symbol $Global:US_BENCHMARK -Range '1y'
$benchChg3m = $null
if ($null -ne $bench -and $bench.Count -gt 65) {
    $bc = $bench.Close
    $benchChg3m = 100.0 * ($bc[$bc.Count - 1] - $bc[$bc.Count - 64]) / $bc[$bc.Count - 64]
    Write-Host (" OK ({0:+0.0;-0.0}% dalam 3 bulan)" -f $benchChg3m) -ForegroundColor Green
} else {
    Write-Host ' GAGAL (kekuatan relatif dilewati)' -ForegroundColor Yellow
}

# --- Daftar saham ---
$universe = Get-UsUniverse -Root $root
if ($Limit -gt 0 -and $Limit -lt $universe.Count) { $universe = $universe[0..($Limit - 1)] }
$total = $universe.Count

Write-Host ''
Write-Host "  Sumber daftar: $($Global:US_UNIVERSE_SOURCE)" -ForegroundColor DarkGray
Write-Host "  Memindai $total saham. Perkiraan waktu: $([Math]::Ceiling($total * 2.2 / 60)) menit." -ForegroundColor DarkGray
Write-Host ''

$results = New-Object System.Collections.ArrayList
$failed  = New-Object System.Collections.ArrayList
$i = 0
$sessionProgress = $mkt.Progress

foreach ($u in $universe) {
    $i++
    $code = $u.Code
    Write-Progress -Activity 'Memindai saham AS' -Status "$code  ($i dari $total)" `
        -PercentComplete ([int](100 * $i / $total))

    try {
        # --- 1. Data harga ---
        $hist = Get-PriceHistory -Symbol $code -Range '2y'
        if ($null -eq $hist) { [void]$failed.Add($code); continue }

        $n   = $hist.Count
        $C   = $hist.Close; $H = $hist.High; $L = $hist.Low; $V = $hist.Volume
        $px  = $C[$n - 1]
        if ($px -le 0) { [void]$failed.Add($code); continue }

        $limitedData = ($n -lt 200)

        # --- 2. Indikator teknikal ---
        $ema20  = Get-LastValid (Get-EMA -Data $C -Period 20)
        $ema50  = Get-LastValid (Get-EMA -Data $C -Period 50)
        $ema200 = Get-LastValid (Get-EMA -Data $C -Period 200)
        $rsi    = Get-LastValid (Get-RSI -Close $C -Period 14)
        $atr    = Get-LastValid (Get-ATR -High $H -Low $L -Close $C -Period 14)

        $macd     = Get-MACD -Close $C
        $macdV    = Get-LastValid $macd.MACD
        $macdSig  = Get-LastValid $macd.Signal
        $macdHist = Get-LastValid $macd.Histogram
        $macdHistPrev = Get-LastValid $macd.Histogram -Back 1

        $adxObj = Get-ADX -High $H -Low $L -Close $C -Period 14
        $adx    = Get-LastValid $adxObj.ADX
        $pDI    = Get-LastValid $adxObj.PlusDI
        $mDI    = Get-LastValid $adxObj.MinusDI

        $bb = Get-Bollinger -Close $C -Period 20 -Mult 2.0
        $bbUp = Get-LastValid $bb.Upper; $bbLo = Get-LastValid $bb.Lower
        $bbPos = $null
        if ($null -ne $bbUp -and $null -ne $bbLo -and ($bbUp - $bbLo) -gt 0) {
            $bbPos = ($px - $bbLo) / ($bbUp - $bbLo)
        }

        $profile = Get-VolumeProfile -High $H -Low $L -Volume $V -Lookback 120 -Bins 60
        $sr = Get-SupportResistance -High $H -Low $L -Price $px -Lookback 120 -Wing 3 -Profile $profile
        $swingLow = Get-SwingLow -Low $L -Lookback 10

        $high52w = Get-Highest -Data $C -Lookback 252
        $low52w  = Get-Lowest  -Data $C -Lookback 252
        $pctFrom52wHigh = $null
        if ($null -ne $high52w -and $high52w -gt 0) { $pctFrom52wHigh = 100.0 * ($high52w - $px) / $high52w }

        # --- 3. Volume & likuiditas (dalam dolar) ---
        # Kalau bar terakhir adalah hari ini dan bursa masih berjalan, volumenya
        # belum penuh. Disetarakan dulu supaya tidak salah dibaca sebagai sepi.
        $volToday = $V[$n - 1]
        if ((Test-BarIsToday -UnixTs $hist.Timestamp[$n - 1]) -and $sessionProgress -gt 0.05 -and $sessionProgress -lt 1) {
            $volToday = $volToday / $sessionProgress
        }
        $volSum = 0.0; $valSum = 0.0; $cnt = 0
        for ($k = [Math]::Max(0, $n - 21); $k -lt ($n - 1); $k++) {
            $volSum += $V[$k]; $valSum += $V[$k] * $C[$k]; $cnt++
        }
        $avgVol = if ($cnt -gt 0) { $volSum / $cnt } else { $null }
        $avgValue = if ($cnt -gt 0) { $valSum / $cnt } else { $null }
        $volRatio = if ($null -ne $avgVol -and $avgVol -gt 0) { $volToday / $avgVol } else { $null }

        $atrPct = if ($null -ne $atr -and $px -gt 0) { 100.0 * $atr / $px } else { $null }
        $todayRangePct = if ($px -gt 0) { 100.0 * ($H[$n - 1] - $L[$n - 1]) / $px } else { $null }

        # --- 4. Perubahan harga ---
        function ChgPct($back) {
            if ($n -le $back) { return $null }
            $old = $C[$n - 1 - $back]
            if ($old -le 0) { return $null }
            return 100.0 * ($px - $old) / $old
        }
        $chg1d = ChgPct 1
        $chg5d = ChgPct 5
        $chg1m = ChgPct 21
        $chg3m = ChgPct 63

        $relStrength = $null
        if ($null -ne $chg3m -and $null -ne $benchChg3m) { $relStrength = $chg3m - $benchChg3m }

        # --- 5. Fundamental ---
        $isEtf = ($u.Group -eq 'ETF')
        $f = Get-Fundamentals -Symbol $code
        if ($null -eq $f) {
            $f = [pscustomobject]@{
                Name = $u.Name; Sector = $u.Sector; PER = $null; PBV = $null; PEG = $null
                ROE = $null; ROA = $null; NetMargin = $null; DER = $null; CurrentRatio = $null
                RevGrowth = $null; EarnGrowth = $null; DivYield = $null; MarketCap = $null
                FreeCashflow = $null; Beta = $null; TargetMean = $null; RecommendKey = $null
                NumAnalysts = $null; EarningsDate = $null; EarningsIn = $null; Industry = $null
                ForwardPER = $null
            }
        }
        $sector = $f.Sector
        if ([string]::IsNullOrWhiteSpace($sector)) { $sector = $u.Sector }
        if ($isEtf) { $sector = 'ETF' }

        $name = $f.Name
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $u.Name }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $hist.Name }

        # --- 6. Skoring ---
        $T = [pscustomobject]@{
            Price = $px; EMA20 = $ema20; EMA50 = $ema50; EMA200 = $ema200
            RSI = $rsi; ATR = $atr; ATRPct = $atrPct
            MACD = $macdV; MACDSignal = $macdSig; MACDHist = $macdHist; MACDHistPrev = $macdHistPrev
            ADX = $adx; PlusDI = $pDI; MinusDI = $mDI
            BBPos = $bbPos; VolRatio = $volRatio; AvgValue = $avgValue
            ExtensionPct = $(if ($null -ne $ema20 -and $ema20 -gt 0) { 100.0 * ($px - $ema20) / $ema20 } else { $null })
            PctFrom52wHigh = $pctFrom52wHigh; High52w = $high52w; Low52w = $low52w
            RelStrength = $relStrength; DivYield = $f.DivYield
            Support = $sr.Support; Resistance = $sr.Resistance; Resistance2 = $sr.Resistance2
            SwingLow = $swingLow; TodayLow = $L[$n - 1]; TodayRangePct = $todayRangePct
        }

        $fs = Get-FundamentalScore -Fund $f -Sector $sector -IsEtf $isEtf
        $ts = Get-TechnicalScore -T $T

        $weekly = ConvertTo-WeeklyBars -Hist $hist
        $wt = Get-WeeklyTrend -Weekly $weekly

        $style = Get-TradingStyle -T $T -FundScore $fs.Score -IsEtf $isEtf
        $plan  = Get-TradePlan -T $T -Style $style.Primary
        $sig   = Get-Signal -Tech $ts.Score -Fund $fs.Score -Plan $plan `
                            -LimitedData $limitedData -Weekly $wt -EarningsIn $f.EarningsIn

        if ($sig.Combined -lt $MinScore) { continue }

        # --- 7. Kumpulkan alasan ---
        $notes = New-Object System.Collections.ArrayList
        foreach ($x in $ts.Notes) { [void]$notes.Add($x) }
        foreach ($x in $fs.Notes) { [void]$notes.Add($x) }
        if ($null -ne $wt.Note -and $wt.Trend -eq 'NAIK') { [void]$notes.Add($wt.Note) }

        $flags = New-Object System.Collections.ArrayList
        foreach ($x in $ts.Flags) { [void]$flags.Add($x) }
        foreach ($x in $fs.Flags) { [void]$flags.Add($x) }
        if ($null -ne $wt.Note -and $wt.Trend -eq 'TURUN') { [void]$flags.Add($wt.Note) }

        [void]$results.Add([pscustomobject]@{
            code = $code
            name = $name
            sector = $sector
            group = $u.Group
            isEtf = $isEtf
            etfDesc = $(if ($isEtf) { Get-EtfDescription -Code $code } else { $null })

            price = [Math]::Round($px, 2)
            priceIdr = [Math]::Round($px * $usdIdr, 0)
            chg1d = $(if ($null -ne $chg1d) { [Math]::Round($chg1d, 2) } else { $null })
            chg5d = $(if ($null -ne $chg5d) { [Math]::Round($chg5d, 2) } else { $null })
            chg1m = $(if ($null -ne $chg1m) { [Math]::Round($chg1m, 2) } else { $null })
            chg3m = $(if ($null -ne $chg3m) { [Math]::Round($chg3m, 2) } else { $null })

            signal = $sig.Signal
            combined = $sig.Combined
            tech = $ts.Score
            fund = $fs.Score
            fundCoverage = $fs.Coverage

            style = $style.Primary
            hold = $style.HoldPeriod
            dayScore = $style.DayScore
            swingScore = $style.SwingScore
            posScore = $style.PosScore

            entryLo = $plan.EntryLow
            entryHi = $plan.EntryHigh
            sl = $plan.StopLoss
            tp1 = $plan.TP1
            tp2 = $plan.TP2
            tp3 = $plan.TP3
            riskPct = $plan.RiskPct
            rewardPct = $plan.RewardPct
            rr = $plan.RRRatio
            netTP1 = $plan.NetTP1
            netSL = $plan.NetSL
            netRR = $plan.NetRR
            breakEven = $plan.BreakEven
            feeBite = $plan.FeeBitePct
            slBasis = $plan.SLBasis
            tpBasis = $plan.TPBasis

            rsi = $(if ($null -ne $rsi) { [Math]::Round($rsi, 1) } else { $null })
            adx = $(if ($null -ne $adx) { [Math]::Round($adx, 1) } else { $null })
            atrPct = $(if ($null -ne $atrPct) { [Math]::Round($atrPct, 2) } else { $null })
            volRatio = $(if ($null -ne $volRatio) { [Math]::Round($volRatio, 2) } else { $null })
            avgValue = $(if ($null -ne $avgValue) { [Math]::Round($avgValue, 0) } else { $null })
            relStrength = $(if ($null -ne $relStrength) { [Math]::Round($relStrength, 2) } else { $null })
            weeklyTrend = $wt.Trend

            per = $f.PER
            forwardPer = $f.ForwardPER
            pbv = $f.PBV
            peg = $f.PEG
            roe = $f.ROE
            netMargin = $f.NetMargin
            divYield = $f.DivYield
            der = $f.DER
            marketCap = $f.MarketCap
            revGrowth = $f.RevGrowth
            earnGrowth = $f.EarnGrowth
            targetMean = $f.TargetMean
            recommendKey = $f.RecommendKey
            numAnalysts = $f.NumAnalysts

            earningsDate = $f.EarningsDate
            earningsIn = $f.EarningsIn
            earningsWarn = $sig.EarningsWarn

            notes = @($notes)
            flags = @($flags)
        })
    }
    catch {
        [void]$failed.Add($code)
    }
}
Write-Progress -Activity 'Memindai saham AS' -Completed

# --- Urutkan berdasarkan skor gabungan ---
$sorted = @($results | Sort-Object -Property combined -Descending)

$meta = [pscustomobject]@{
    GeneratedAt     = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    MarketState     = $mkt.State
    MarketOpen      = ($mkt.State -like '*SEDANG BUKA*')
    EtTime          = $mkt.EtTime
    OpenWib         = $mkt.OpenWib
    CloseWib        = $mkt.CloseWib
    UsdIdr          = [Math]::Round($usdIdr, 0)
    BenchmarkName   = $Global:US_BENCHMARK_NAME
    BenchmarkChg3m  = $(if ($null -ne $benchChg3m) { [Math]::Round($benchChg3m, 2) } else { $null })
    Universe        = $total
    Scanned         = $sorted.Count
    Failed          = $failed.Count
    FeeBuyPct       = $Global:FEE_BUY_PCT
    FeeSellPct      = $Global:FEE_SELL_PCT
    FxSpreadPct     = $Global:FX_SPREAD_PCT
}

# --- Simpan hasil ---
$dataDir = Join-Path $root 'data'
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir | Out-Null }
[pscustomobject]@{ Meta = $meta; Stocks = $sorted } |
    ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $dataDir 'latest.json') -Encoding UTF8

$outPath = Join-Path $root 'output\index.html'
New-ScreenerReport -Results $sorted -OutPath $outPath -Meta $meta

# --- Ringkasan ---
$elapsed = (Get-Date) - $startTime
$cnt = @{}
foreach ($s in $sorted) { $cnt[$s.signal] = 1 + $(if ($cnt.ContainsKey($s.signal)) { $cnt[$s.signal] } else { 0 }) }

Write-Host ''
Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkCyan
Write-Host "   Selesai dalam $([int]$elapsed.TotalMinutes) menit $($elapsed.Seconds) detik" -ForegroundColor Cyan
Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkCyan
Write-Host "   Berhasil dianalisa : $($sorted.Count) saham" -ForegroundColor Gray
if ($failed.Count -gt 0) {
    Write-Host "   Gagal / dilewati   : $($failed.Count) saham" -ForegroundColor DarkGray
}
Write-Host ''
foreach ($k in 'STRONG BUY','BUY','AKUMULASI','SPEKULATIF','PANTAU','HINDARI') {
    $v = $(if ($cnt.ContainsKey($k)) { $cnt[$k] } else { 0 })
    $col = switch ($k) {
        'STRONG BUY' { 'Green' } 'BUY' { 'Green' } 'AKUMULASI' { 'Cyan' }
        'SPEKULATIF' { 'Yellow' } 'HINDARI' { 'Red' } default { 'DarkGray' }
    }
    Write-Host ("   {0,-12} : {1}" -f $k, $v) -ForegroundColor $col
}

$top = @($sorted | Where-Object { $_.signal -eq 'STRONG BUY' -or $_.signal -eq 'BUY' } | Select-Object -First 8)
if ($top.Count -gt 0) {
    Write-Host ''
    Write-Host '   Skor tertinggi:' -ForegroundColor Cyan
    foreach ($t in $top) {
        Write-Host ("   {0,-6} {1,-9} skor {2,5}  {3}" -f $t.code, $t.signal, $t.combined, $t.style) -ForegroundColor Gray
    }
}

Write-Host ''
Write-Host "   Dashboard: $outPath" -ForegroundColor Cyan
Write-Host ''

if (-not $NoOpen) { Start-Process $outPath }
