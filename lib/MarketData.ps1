# MarketData.ps1 - Pengambilan data pasar AS (harga historis + fundamental).
# Sumber: endpoint publik Yahoo Finance. Tidak perlu API key, tidak perlu daftar.

$Script:UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
$Script:YSession = $null
$Script:YCrumb = $null

# Zona waktu bursa AS. Windows sudah menangani pergantian DST sendiri, jadi
# Maret-November otomatis jadi EDT (UTC-4) dan sisanya EST (UTC-5).
$Script:TzET = $null
try { $Script:TzET = [System.TimeZoneInfo]::FindSystemTimeZoneById('Eastern Standard Time') } catch { }

function Get-EtNow {
    <# Waktu sekarang di New York. #>
    if ($null -ne $Script:TzET) {
        return [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $Script:TzET)
    }
    return [DateTime]::UtcNow.AddHours(-5)   # cadangan kalau zona waktu tidak ketemu
}

function ConvertTo-Et {
    param([int64]$UnixTs)
    $utc = [DateTimeOffset]::FromUnixTimeSeconds($UnixTs).UtcDateTime
    if ($null -ne $Script:TzET) {
        return [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $Script:TzET)
    }
    return $utc.AddHours(-5)
}

function Initialize-YahooSession {
    <# Membuat sesi + crumb yang dibutuhkan endpoint fundamental. #>
    $sess = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    try {
        Invoke-WebRequest -Uri 'https://fc.yahoo.com' -WebSession $sess -UseBasicParsing `
            -TimeoutSec 20 -UserAgent $Script:UA -ErrorAction Stop | Out-Null
    } catch {
        # Endpoint ini memang membalas 404 tapi tetap menanamkan cookie. Aman diabaikan.
    }
    $crumb = $null
    for ($i = 0; $i -lt 3; $i++) {
        try {
            $crumb = (Invoke-WebRequest -Uri 'https://query2.finance.yahoo.com/v1/test/getcrumb' `
                -WebSession $sess -UseBasicParsing -TimeoutSec 20 -UserAgent $Script:UA -ErrorAction Stop).Content
            if ($crumb -and $crumb.Length -gt 3) { break }
        } catch { Start-Sleep -Milliseconds 800 }
    }
    $Script:YSession = $sess
    $Script:YCrumb = $crumb
    return [bool]($crumb -and $crumb.Length -gt 3)
}

function Invoke-YahooJson {
    param([string]$Url, [int]$Retries = 3)
    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            $resp = Invoke-WebRequest -Uri $Url -WebSession $Script:YSession -UseBasicParsing `
                -TimeoutSec 30 -UserAgent $Script:UA -ErrorAction Stop
            return ($resp.Content | ConvertFrom-Json)
        } catch {
            $msg = $_.Exception.Message
            if ($msg -match '404|Not Found') { return $null }   # ticker tidak ada, jangan retry
            Start-Sleep -Milliseconds (600 * ($i + 1))
        }
    }
    return $null
}

function Get-UsSessionProgress {
    <# Seberapa jauh sesi perdagangan AS hari ini sudah berjalan
       (0 = belum buka, 1 = sudah tutup).
       Dipakai untuk menyetarakan volume yang masih berjalan dengan rata-rata
       volume harian penuh - kalau tidak, saham akan terlihat "sepi" hanya
       karena bursa baru buka satu jam.

       Jam bursa NYSE/Nasdaq: 09:30 - 16:00 waktu New York, Senin-Jumat. #>
    $et = Get-EtNow
    $dow = $et.DayOfWeek
    if ($dow -eq [DayOfWeek]::Saturday -or $dow -eq [DayOfWeek]::Sunday) { return 1.0 }

    $t = $et.TimeOfDay.TotalMinutes
    $open  = 9 * 60 + 30
    $close = 16 * 60
    if ($t -le $open)  { return 0.0 }
    if ($t -ge $close) { return 1.0 }
    return ($t - $open) / ($close - $open)
}

function Get-UsMarketStatus {
    <# Keterangan singkat status bursa AS dalam bahasa Indonesia, plus jam
       bukanya dalam WIB supaya mudah dibaca dari Indonesia. #>
    $et  = Get-EtNow
    $wib = [DateTime]::UtcNow.AddHours(7)
    $p   = Get-UsSessionProgress

    $dow = $et.DayOfWeek
    if ($dow -eq [DayOfWeek]::Saturday -or $dow -eq [DayOfWeek]::Sunday) {
        $state = 'Bursa AS tutup (akhir pekan)'
    } elseif ($p -le 0) {
        $state = 'Bursa AS belum buka hari ini'
    } elseif ($p -ge 1) {
        $state = 'Bursa AS sudah tutup hari ini'
    } else {
        $state = 'Bursa AS SEDANG BUKA'
    }

    # Jam buka 09:30 ET diterjemahkan ke WIB. Selisih ET-WIB: 11 jam saat EDT,
    # 12 jam saat EST. Dihitung dari selisih riil supaya selalu benar.
    $offsetHours = [Math]::Round(($wib - $et).TotalHours, 0)
    $openWib  = (Get-Date -Hour 9  -Minute 30 -Second 0).AddHours($offsetHours).ToString('HH:mm')
    $closeWib = (Get-Date -Hour 16 -Minute 0  -Second 0).AddHours($offsetHours).ToString('HH:mm')

    return [pscustomobject]@{
        State       = $state
        Progress    = $p
        EtTime      = $et.ToString('yyyy-MM-dd HH:mm')
        WibTime     = $wib.ToString('yyyy-MM-dd HH:mm')
        OpenWib     = $openWib
        CloseWib    = $closeWib
        OffsetHours = $offsetHours
    }
}

function Test-BarIsToday {
    <# Apakah bar terakhir adalah bar hari ini (waktu New York)? #>
    param([int64]$UnixTs)
    $bar = ConvertTo-Et -UnixTs $UnixTs
    $now = Get-EtNow
    return ($bar.Date -eq $now.Date)
}

function Get-PriceHistory {
    <# Ambil OHLCV harian. Mengembalikan objek berisi array open/high/low/close/volume. #>
    param([string]$Symbol, [string]$Range = '2y', [string]$Interval = '1d', [int]$MinBars = 30)

    $url = "https://query1.finance.yahoo.com/v8/finance/chart/$Symbol`?range=$Range&interval=$Interval"
    $j = Invoke-YahooJson -Url $url
    if ($null -eq $j -or $null -eq $j.chart -or $null -eq $j.chart.result) { return $null }

    $res = $j.chart.result[0]
    if ($null -eq $res -or $null -eq $res.timestamp) { return $null }

    $q = $res.indicators.quote[0]
    $n = $res.timestamp.Count
    $o = New-Object System.Collections.ArrayList
    $h = New-Object System.Collections.ArrayList
    $l = New-Object System.Collections.ArrayList
    $c = New-Object System.Collections.ArrayList
    $v = New-Object System.Collections.ArrayList
    $t = New-Object System.Collections.ArrayList

    for ($i = 0; $i -lt $n; $i++) {
        # Buang bar yang datanya bolong (hari libur bursa / suspend).
        if ($null -eq $q.close[$i] -or $null -eq $q.open[$i] -or `
            $null -eq $q.high[$i] -or $null -eq $q.low[$i]) { continue }
        if ([double]$q.close[$i] -le 0) { continue }
        [void]$o.Add([double]$q.open[$i])
        [void]$h.Add([double]$q.high[$i])
        [void]$l.Add([double]$q.low[$i])
        [void]$c.Add([double]$q.close[$i])
        if ($null -eq $q.volume[$i]) { [void]$v.Add(0.0) } else { [void]$v.Add([double]$q.volume[$i]) }
        [void]$t.Add([int64]$res.timestamp[$i])
    }
    if ($c.Count -lt $MinBars) { return $null }

    return [pscustomobject]@{
        Symbol    = $Symbol
        Open      = $o.ToArray()
        High      = $h.ToArray()
        Low       = $l.ToArray()
        Close     = $c.ToArray()
        Volume    = $v.ToArray()
        Timestamp = $t.ToArray()
        Count     = $c.Count
        Currency  = $res.meta.currency
        Name      = $res.meta.longName
    }
}

function ConvertTo-WeeklyBars {
    <# Merangkum bar harian menjadi bar mingguan secara lokal. Data harian 2 tahun
       menghasilkan ~104 bar mingguan - cukup untuk EMA30 mingguan. Dengan begini
       konfirmasi timeframe besar tidak perlu request HTTP tambahan sama sekali. #>
    param($Hist)
    if ($null -eq $Hist -or $Hist.Count -lt 10) { return $null }

    $cal  = [System.Globalization.CultureInfo]::InvariantCulture.Calendar
    $rule = [System.Globalization.CalendarWeekRule]::FirstFourDayWeek

    $O = New-Object System.Collections.ArrayList
    $H = New-Object System.Collections.ArrayList
    $L = New-Object System.Collections.ArrayList
    $C = New-Object System.Collections.ArrayList
    $V = New-Object System.Collections.ArrayList
    $T = New-Object System.Collections.ArrayList

    $curKey = $null
    $wo = 0.0; $wh = 0.0; $wl = 0.0; $wc = 0.0; $wv = 0.0; $wt = 0

    for ($i = 0; $i -lt $Hist.Count; $i++) {
        $dt = ConvertTo-Et -UnixTs $Hist.Timestamp[$i]
        $key = '{0}-{1}' -f $dt.Year, $cal.GetWeekOfYear($dt, $rule, [DayOfWeek]::Monday)

        if ($key -ne $curKey) {
            if ($null -ne $curKey) {
                [void]$O.Add($wo); [void]$H.Add($wh); [void]$L.Add($wl)
                [void]$C.Add($wc); [void]$V.Add($wv); [void]$T.Add($wt)
            }
            $curKey = $key
            $wo = $Hist.Open[$i]; $wh = $Hist.High[$i]; $wl = $Hist.Low[$i]
            $wt = $Hist.Timestamp[$i]; $wv = 0.0
        }
        if ($Hist.High[$i] -gt $wh) { $wh = $Hist.High[$i] }
        if ($Hist.Low[$i]  -lt $wl) { $wl = $Hist.Low[$i] }
        $wc = $Hist.Close[$i]
        $wv += $Hist.Volume[$i]
    }
    if ($null -ne $curKey) {
        [void]$O.Add($wo); [void]$H.Add($wh); [void]$L.Add($wl)
        [void]$C.Add($wc); [void]$V.Add($wv); [void]$T.Add($wt)
    }
    if ($C.Count -lt 10) { return $null }

    return [pscustomobject]@{
        Symbol = $Hist.Symbol
        Open = $O.ToArray(); High = $H.ToArray(); Low = $L.ToArray()
        Close = $C.ToArray(); Volume = $V.ToArray(); Timestamp = $T.ToArray()
        Count = $C.Count
    }
}

function Get-Fundamentals {
    <# Ambil rasio fundamental + jadwal laporan keuangan berikutnya.
       Field yang kosong dikembalikan sebagai $null. #>
    param([string]$Symbol)

    $mods = 'defaultKeyStatistics,financialData,summaryDetail,summaryProfile,price,calendarEvents'
    $url  = "https://query2.finance.yahoo.com/v10/finance/quoteSummary/$Symbol`?modules=$mods&crumb=$($Script:YCrumb)"
    $j = Invoke-YahooJson -Url $url
    if ($null -eq $j -or $null -eq $j.quoteSummary -or $null -eq $j.quoteSummary.result) { return $null }

    $r = $j.quoteSummary.result[0]
    if ($null -eq $r) { return $null }

    function Val($node) { if ($null -ne $node -and $null -ne $node.raw) { return [double]$node.raw } else { return $null } }

    # Yahoo kadang mengembalikan angka tidak masuk akal. Nilai di luar rentang
    # wajar diperlakukan sebagai DATA KOSONG, bukan sebagai "sangat murah" -
    # kalau tidak, skor fundamental jadi menyesatkan.
    function SaneVal($node, [double]$Min, [double]$Max) {
        $v = Val $node
        if ($null -eq $v) { return $null }
        if ($v -lt $Min -or $v -gt $Max) { return $null }
        return $v
    }

    $nameLong = $r.price.longName
    if ([string]::IsNullOrWhiteSpace($nameLong)) { $nameLong = $r.price.shortName }

    # --- Tanggal laporan keuangan (earnings) berikutnya ---
    $earnDate = $null; $earnDays = $null
    $ed = $r.calendarEvents.earnings.earningsDate
    if ($null -ne $ed) {
        $first = @($ed)[0]
        if ($null -ne $first -and $null -ne $first.raw) {
            $d = (ConvertTo-Et -UnixTs ([int64]$first.raw)).Date
            $earnDate = $d.ToString('yyyy-MM-dd')
            $earnDays = [int]([Math]::Round(($d - (Get-EtNow).Date).TotalDays, 0))
        }
    }

    return [pscustomobject]@{
        Name         = $nameLong
        ShortName    = $r.price.shortName
        Sector       = $r.summaryProfile.sector
        Industry     = $r.summaryProfile.industry
        Country      = $r.summaryProfile.country
        MarketCap    = SaneVal $r.price.marketCap 1e6 1e18
        PER          = SaneVal $r.summaryDetail.trailingPE 0.3 2000
        ForwardPER   = SaneVal $r.summaryDetail.forwardPE 0.3 2000
        PBV          = SaneVal $r.defaultKeyStatistics.priceToBook 0.02 500
        PEG          = SaneVal $r.defaultKeyStatistics.pegRatio -20 50
        EPS          = Val $r.defaultKeyStatistics.trailingEps
        ROE          = SaneVal $r.financialData.returnOnEquity -10 20
        ROA          = SaneVal $r.financialData.returnOnAssets -10 10
        NetMargin    = SaneVal $r.financialData.profitMargins -50 50
        OpMargin     = SaneVal $r.financialData.operatingMargins -50 50
        GrossMargin  = SaneVal $r.financialData.grossMargins -50 50
        DER          = SaneVal $r.financialData.debtToEquity 0 10000
        CurrentRatio = SaneVal $r.financialData.currentRatio 0 100
        RevGrowth    = SaneVal $r.financialData.revenueGrowth -1 100
        EarnGrowth   = SaneVal $r.financialData.earningsGrowth -10 100
        DivYield     = SaneVal $r.summaryDetail.dividendYield 0 1
        PayoutRatio  = SaneVal $r.summaryDetail.payoutRatio 0 10
        FreeCashflow = Val $r.financialData.freeCashflow
        TotalCash    = Val $r.financialData.totalCash
        TotalDebt    = Val $r.financialData.totalDebt
        Beta         = SaneVal $r.summaryDetail.beta -10 10
        TargetMean   = Val $r.financialData.targetMeanPrice
        RecommendKey = $r.financialData.recommendationKey
        NumAnalysts  = Val $r.financialData.numberOfAnalystOpinions
        EarningsDate = $earnDate
        EarningsIn   = $earnDays
    }
}

function Get-UsdIdrRate {
    <# Kurs USD/IDR terkini dari Yahoo. Dipakai untuk menampilkan harga dalam
       rupiah. Kalau gagal, dipakai angka cadangan dari lib\Config.ps1. #>
    $h = Get-PriceHistory -Symbol 'IDR=X' -Range '5d' -MinBars 1
    if ($null -ne $h -and $h.Count -gt 0) {
        $v = $h.Close[$h.Count - 1]
        if ($v -gt 5000 -and $v -lt 50000) { return [double]$v }
    }
    return [double]$Global:USDIDR_FALLBACK
}
