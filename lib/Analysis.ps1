# Analysis.ps1 - Skoring fundamental & teknikal saham AS, klasifikasi gaya
# trading, penyusunan rencana trading (entry / SL / TP), dan alasan naratif.
#
# Semua angka yang boleh diubah ada di lib\Config.ps1, bukan di file ini.

# ---------------------------------------------------------------------------
# BIAYA TRANSAKSI
# ---------------------------------------------------------------------------
function Get-NetResult {
    <# Hitung hasil bersih setelah biaya beli, biaya jual, DAN spread kurs.
       Beli di $Entry berarti keluar uang $Entry * (1 + biayaBeli).
       Jual di $Exit berarti terima uang $Exit * (1 - biayaJual).

       Spread kurs dihitung dua kali (tukar rupiah ke dolar saat masuk, dan
       dolar ke rupiah saat keluar) karena modal Anda berasal dari rupiah. #>
    param([double]$Entry, [double]$Exit)
    if ($Entry -le 0) { return 0.0 }
    $fx = $Global:FX_SPREAD_PCT / 100.0
    $modal  = $Entry * (1.0 + $Global:FEE_BUY_PCT  / 100.0) * (1.0 + $fx)
    $terima = $Exit  * (1.0 - $Global:FEE_SELL_PCT / 100.0) * (1.0 - $fx)
    return 100.0 * ($terima - $modal) / $modal
}

function Get-BreakEvenPrice {
    <# Harga jual minimum agar tidak rugi setelah semua biaya + spread kurs. #>
    param([double]$Entry)
    if ($Entry -le 0) { return 0.0 }
    $fx = $Global:FX_SPREAD_PCT / 100.0
    $modal = $Entry * (1.0 + $Global:FEE_BUY_PCT / 100.0) * (1.0 + $fx)
    return $modal / ((1.0 - $Global:FEE_SELL_PCT / 100.0) * (1.0 - $fx))
}

# ---------------------------------------------------------------------------
# PEMBULATAN HARGA
# Bursa AS memakai satu fraksi harga saja: 1 sen ($0,01) untuk saham di atas
# $1. Saham di bawah $1 boleh sampai 4 angka di belakang koma.
# ---------------------------------------------------------------------------
function Get-UsTick {
    param([double]$Price)
    if ($Price -lt 1.0) { return 0.0001 }
    return 0.01
}

function ConvertTo-UsPrice {
    # Mode: 'Down' untuk stop loss / batas bawah entry, 'Up' untuk target,
    # 'Near' untuk pembulatan terdekat.
    param([double]$Price, [string]$Mode = 'Near')
    if ($Price -le 0) { return 0 }
    $t = Get-UsTick -Price $Price
    switch ($Mode) {
        'Down' { $v = [Math]::Floor($Price / $t) * $t }
        'Up'   { $v = [Math]::Ceiling($Price / $t) * $t }
        default { $v = [Math]::Round($Price / $t, 0) * $t }
    }
    if ($v -lt $t) { $v = $t }
    if ($t -eq 0.01) { return [Math]::Round($v, 2) }
    return [Math]::Round($v, 4)
}

# ---------------------------------------------------------------------------
# Skoring pembantu: memetakan nilai ke skala 0-1 secara linear.
# ---------------------------------------------------------------------------
function Get-LinearScore {
    param([double]$Value, [double]$Worst, [double]$Best)
    if ($Best -gt $Worst) {
        if ($Value -le $Worst) { return 0.0 }
        if ($Value -ge $Best)  { return 1.0 }
        return ($Value - $Worst) / ($Best - $Worst)
    } else {
        # Semakin kecil semakin baik (mis. PER, DER).
        if ($Value -ge $Worst) { return 0.0 }
        if ($Value -le $Best)  { return 1.0 }
        return ($Worst - $Value) / ($Worst - $Best)
    }
}

# ===========================================================================
#  SKOR FUNDAMENTAL
# ===========================================================================
function Get-FundamentalScore {
    param($Fund, [string]$Sector, [bool]$IsEtf = $false)

    $notes = New-Object System.Collections.ArrayList
    $flags = New-Object System.Collections.ArrayList

    # --- ETF tidak punya laporan keuangan ---
    # ETF adalah keranjang berisi puluhan sampai ratusan saham, jadi rasio
    # seperti ROE atau DER tidak berarti apa-apa. Menilainya dengan ukuran
    # saham biasa hanya akan menghasilkan angka yang menyesatkan.
    if ($IsEtf) {
        [void]$notes.Add('ETF: risiko sudah tersebar ke banyak saham sekaligus')
        return [pscustomobject]@{
            Score = 60.0; Coverage = 0; Notes = $notes; Flags = $flags
            IsBank = $false; IsEtf = $true
        }
    }

    $isBank = ($Sector -match 'Financial')
    $parts  = New-Object System.Collections.ArrayList

    function AddPart($list, [double]$w, [double]$s, [string]$label) {
        [void]$list.Add([pscustomobject]@{ Weight = $w; Score = $s; Label = $label })
    }

    # --- 1. Valuasi (PER & PBV) ---
    # Patokan digeser ke atas dibanding IDX: pasar AS memang menghargai
    # perusahaannya lebih mahal karena pertumbuhan dan likuiditasnya lebih baik.
    if ($null -ne $Fund.PER -and $Fund.PER -gt 0) {
        $s = Get-LinearScore -Value $Fund.PER -Worst $Global:PER_WORST -Best $Global:PER_BEST
        AddPart $parts 13 $s 'PER'
        if ($Fund.PER -lt 15)     { [void]$notes.Add("PER {0:N1}x tergolong murah untuk pasar AS" -f $Fund.PER) }
        elseif ($Fund.PER -gt 40) { [void]$flags.Add("PER {0:N1}x sangat mahal" -f $Fund.PER) }
    }
    if ($null -ne $Fund.PBV -and $Fund.PBV -gt 0) {
        $pbvBest = $Global:PBV_BEST; $pbvWorst = $Global:PBV_WORST
        if ($isBank) { $pbvBest = 0.9; $pbvWorst = 3.0 }   # bank wajar dinilai dari nilai buku
        $s = Get-LinearScore -Value $Fund.PBV -Worst $pbvWorst -Best $pbvBest
        AddPart $parts 8 $s 'PBV'
        if ($Fund.PBV -lt 1.2) { [void]$notes.Add("PBV {0:N2}x di sekitar nilai buku" -f $Fund.PBV) }
    }
    # PEG membandingkan PER dengan pertumbuhan laba. PEG di bawah 1 artinya
    # harga masih murah RELATIF terhadap kecepatan tumbuhnya - ukuran yang
    # jauh lebih adil untuk saham teknologi AS daripada PER telanjang.
    if ($null -ne $Fund.PEG -and $Fund.PEG -gt 0) {
        $s = Get-LinearScore -Value $Fund.PEG -Worst 3.5 -Best 0.8
        AddPart $parts 9 $s 'PEG'
        if ($Fund.PEG -lt 1.0) { [void]$notes.Add("PEG {0:N2} - harga wajar dibanding laju pertumbuhan laba" -f $Fund.PEG) }
    }

    # --- 2. Profitabilitas ---
    if ($null -ne $Fund.ROE) {
        $s = Get-LinearScore -Value ($Fund.ROE * 100) -Worst 3 -Best $Global:ROE_BEST
        AddPart $parts 15 $s 'ROE'
        if ($Fund.ROE -gt 0.20)     { [void]$notes.Add("ROE {0:N1}% sangat sehat" -f ($Fund.ROE * 100)) }
        elseif ($Fund.ROE -lt 0.05) { [void]$flags.Add("ROE {0:N1}% rendah" -f ($Fund.ROE * 100)) }
    }
    if ($null -ne $Fund.NetMargin) {
        $nmBest = 22.0; if ($isBank) { $nmBest = 35.0 }
        $s = Get-LinearScore -Value ($Fund.NetMargin * 100) -Worst 0 -Best $nmBest
        AddPart $parts 10 $s 'NetMargin'
        if ($Fund.NetMargin -lt 0)        { [void]$flags.Add('Margin bersih negatif (perusahaan masih rugi)') }
        elseif ($Fund.NetMargin -gt 0.20) { [void]$notes.Add("margin bersih {0:N1}% tebal" -f ($Fund.NetMargin * 100)) }
    }
    if ($null -ne $Fund.ROA) {
        $roaBest = 12.0; if ($isBank) { $roaBest = 2.0 }
        $s = Get-LinearScore -Value ($Fund.ROA * 100) -Worst 0 -Best $roaBest
        AddPart $parts 6 $s 'ROA'
    }

    # --- 3. Pertumbuhan ---
    if ($null -ne $Fund.RevGrowth) {
        $s = Get-LinearScore -Value ($Fund.RevGrowth * 100) -Worst -10 -Best 22
        AddPart $parts 11 $s 'RevGrowth'
        if ($Fund.RevGrowth -gt 0.15)      { [void]$notes.Add("pendapatan tumbuh {0:N1}% YoY" -f ($Fund.RevGrowth * 100)) }
        elseif ($Fund.RevGrowth -lt -0.05) { [void]$flags.Add("pendapatan turun {0:N1}% YoY" -f ($Fund.RevGrowth * 100)) }
    }
    if ($null -ne $Fund.EarnGrowth) {
        $s = Get-LinearScore -Value ($Fund.EarnGrowth * 100) -Worst -20 -Best 28
        AddPart $parts 11 $s 'EarnGrowth'
        if ($Fund.EarnGrowth -gt 0.20)      { [void]$notes.Add("laba tumbuh {0:N1}% YoY" -f ($Fund.EarnGrowth * 100)) }
        elseif ($Fund.EarnGrowth -lt -0.15) { [void]$flags.Add("laba turun {0:N1}% YoY" -f ($Fund.EarnGrowth * 100)) }
    }

    # --- 4. Kesehatan neraca (tidak relevan untuk bank) ---
    if (-not $isBank) {
        if ($null -ne $Fund.DER) {
            $s = Get-LinearScore -Value $Fund.DER -Worst 200 -Best 25
            AddPart $parts 8 $s 'DER'
            if ($Fund.DER -gt 180)    { [void]$flags.Add("DER {0:N0}% utang berat" -f $Fund.DER) }
            elseif ($Fund.DER -lt 50) { [void]$notes.Add("DER {0:N0}% neraca kuat" -f $Fund.DER) }
        }
        if ($null -ne $Fund.CurrentRatio) {
            $s = Get-LinearScore -Value $Fund.CurrentRatio -Worst 0.8 -Best 2.2
            AddPart $parts 5 $s 'CurrentRatio'
            if ($Fund.CurrentRatio -lt 1.0) { [void]$flags.Add("Current ratio {0:N2} likuiditas ketat" -f $Fund.CurrentRatio) }
        }
        # Arus kas bebas positif = perusahaan menghasilkan uang tunai sungguhan,
        # bukan hanya laba di atas kertas.
        if ($null -ne $Fund.FreeCashflow) {
            if ($Fund.FreeCashflow -gt 0) {
                AddPart $parts 6 1.0 'FCF'
                [void]$notes.Add('arus kas bebas positif')
            } else {
                AddPart $parts 6 0.0 'FCF'
                [void]$flags.Add('arus kas bebas negatif (bakar uang tunai)')
            }
        }
    }

    # --- 5. Dividen ---
    # Di AS dividen umumnya lebih kecil daripada di IDX karena perusahaan
    # lebih sering buyback saham. Yield 2% di AS sudah tergolong lumayan.
    if ($null -ne $Fund.DivYield -and $Fund.DivYield -gt 0) {
        $s = Get-LinearScore -Value ($Fund.DivYield * 100) -Worst 0 -Best $Global:DIV_BEST
        AddPart $parts 8 $s 'DivYield'
        if ($Fund.DivYield -gt 0.025) { [void]$notes.Add("dividend yield {0:N2}%" -f ($Fund.DivYield * 100)) }
    }

    # Normalisasi terhadap bobot yang tersedia (metrik kosong tidak menghukum).
    $tw = 0.0; $ws = 0.0
    foreach ($p in $parts) { $tw += $p.Weight; $ws += $p.Weight * $p.Score }
    $score = 50.0
    if ($tw -gt 0) { $score = 100.0 * $ws / $tw }

    # Kepercayaan data: makin banyak metrik tersedia makin bisa dipercaya.
    $coverage = [Math]::Min(1.0, $tw / 85.0)

    return [pscustomobject]@{
        Score    = [Math]::Round($score, 1)
        Coverage = [Math]::Round($coverage * 100, 0)
        Notes    = $notes
        Flags    = $flags
        IsBank   = $isBank
        IsEtf    = $false
    }
}

# ===========================================================================
#  SKOR TEKNIKAL
# ===========================================================================
function Get-TechnicalScore {
    param($T)   # objek berisi seluruh indikator terakhir

    $notes = New-Object System.Collections.ArrayList
    $flags = New-Object System.Collections.ArrayList
    $score = 0.0
    $px = $T.Price

    # --- 1. Struktur tren (30 poin) ---
    # Komponen yang datanya belum ada dikeluarkan dari pembagi, jadi saham yang
    # riwayatnya masih pendek tidak dihukum hanya karena masih baru.
    $trendEarn = 0.0; $trendMax = 0.0
    if ($null -ne $T.EMA20) {
        $trendMax += 7
        if ($px -gt $T.EMA20) { $trendEarn += 7 }
    }
    if ($null -ne $T.EMA50) {
        $trendMax += 8
        if ($px -gt $T.EMA50) { $trendEarn += 8 }
    }
    if ($null -ne $T.EMA200) {
        $trendMax += 9
        if ($px -gt $T.EMA200) { $trendEarn += 9 }
        else { [void]$flags.Add('harga masih di bawah MA200 (tren besar belum bullish)') }
    }
    if ($null -ne $T.EMA20 -and $null -ne $T.EMA50) {
        $trendMax += 6
        if ($T.EMA20 -gt $T.EMA50) { $trendEarn += 6 }
    }
    if ($trendMax -gt 0) { $trend = 30.0 * $trendEarn / $trendMax } else { $trend = 15.0 }
    $trend = [Math]::Max(0, [Math]::Min(30, $trend))
    $score += $trend

    if ($null -ne $T.EMA20 -and $null -ne $T.EMA50 -and $null -ne $T.EMA200 -and
        $T.EMA20 -gt $T.EMA50 -and $T.EMA50 -gt $T.EMA200 -and $px -gt $T.EMA20) {
        [void]$notes.Add('susunan MA rapi bullish (MA20 > MA50 > MA200)')
    }

    # --- 2. Momentum: MACD + RSI (25 poin) ---
    $momEarn = 0.0; $momMax = 0.0
    if ($null -ne $T.MACD -and $null -ne $T.MACDSignal) {
        $momMax += 8
        if ($T.MACD -gt $T.MACDSignal) { $momEarn += 8 }
    }
    if ($null -ne $T.MACD) {
        $momMax += 4
        if ($T.MACD -gt 0) { $momEarn += 4 }
    }
    if ($null -ne $T.MACDHist -and $null -ne $T.MACDHistPrev) {
        $momMax += 7
        if ($T.MACDHist -gt $T.MACDHistPrev) { $momEarn += 4 }
        if ($T.MACDHist -gt 0 -and $T.MACDHistPrev -le 0) {
            $momEarn += 3
            [void]$notes.Add('MACD baru golden cross (momentum berbalik naik)')
        }
        if ($T.MACDHist -lt 0 -and $T.MACDHistPrev -ge 0) {
            [void]$flags.Add('MACD baru dead cross (momentum melemah)')
        }
    }
    if ($null -ne $T.RSI) {
        $momMax += 6
        if ($T.RSI -ge 50 -and $T.RSI -le 68)     { $momEarn += 6; [void]$notes.Add("RSI {0:N0} di zona sehat" -f $T.RSI) }
        elseif ($T.RSI -gt 68 -and $T.RSI -le 78) { $momEarn += 3 }
        elseif ($T.RSI -gt 78)                    { [void]$flags.Add("RSI {0:N0} overbought, rawan koreksi" -f $T.RSI) }
        elseif ($T.RSI -ge 40)                    { $momEarn += 3 }
        else { [void]$flags.Add("RSI {0:N0} lemah" -f $T.RSI) }
        if ($T.RSI -lt 32) { [void]$notes.Add("RSI {0:N0} oversold, potensi pantulan teknikal" -f $T.RSI) }
    }
    if ($momMax -gt 0) { $mom = 25.0 * $momEarn / $momMax } else { $mom = 12.5 }
    $mom = [Math]::Max(0, [Math]::Min(25, $mom))
    $score += $mom

    # --- 3. Kekuatan tren: ADX (15 poin) ---
    $str = 0.0
    if ($null -ne $T.ADX) {
        if ($T.ADX -ge 25)     { $str += 9; [void]$notes.Add("ADX {0:N0} tren kuat" -f $T.ADX) }
        elseif ($T.ADX -ge 20) { $str += 6 }
        elseif ($T.ADX -ge 15) { $str += 3 }
        else { [void]$flags.Add("ADX {0:N0} pasar sideways" -f $T.ADX) }
        if ($null -ne $T.PlusDI -and $null -ne $T.MinusDI -and $T.PlusDI -gt $T.MinusDI) { $str += 6 }
    }
    $str = [Math]::Min(15, $str)
    $score += $str

    # --- 4. Konfirmasi volume (15 poin) ---
    $vol = 0.0
    if ($null -ne $T.VolRatio) {
        if ($T.VolRatio -ge 2.0)     { $vol += 9; [void]$notes.Add("volume {0:N1}x rata-rata, minat beli tinggi" -f $T.VolRatio) }
        elseif ($T.VolRatio -ge 1.3) { $vol += 7; [void]$notes.Add("volume {0:N1}x di atas rata-rata" -f $T.VolRatio) }
        elseif ($T.VolRatio -ge 0.8) { $vol += 4 }
        else { $vol += 1; [void]$flags.Add('volume tipis, minat pasar rendah') }
    }
    # Likuiditas dolar - saham terlalu sepi berbahaya untuk keluar posisi.
    if ($null -ne $T.AvgValue) {
        if ($T.AvgValue -ge $Global:LIQ_EXCELLENT)  { $vol += 6 }
        elseif ($T.AvgValue -ge $Global:LIQ_GOOD)   { $vol += 5 }
        elseif ($T.AvgValue -ge $Global:LIQ_OK)     { $vol += 3 }
        elseif ($T.AvgValue -ge $Global:LIQ_MIN)    { $vol += 1 }
        else { [void]$flags.Add('likuiditas rendah untuk ukuran pasar AS, spread bisa lebar') }
    }
    $vol = [Math]::Min(15, $vol)
    $score += $vol

    # --- 5. Kualitas entry (15 poin): jangan kejar harga yang sudah terbang ---
    $ent = 0.0
    if ($null -ne $T.ExtensionPct) {
        if ($T.ExtensionPct -le 3)      { $ent += 7 }
        elseif ($T.ExtensionPct -le 7)  { $ent += 5 }
        elseif ($T.ExtensionPct -le 12) { $ent += 2 }
        else { [void]$flags.Add("harga {0:N1}% jauh di atas MA20, risiko kejar harga" -f $T.ExtensionPct) }
    }
    if ($null -ne $T.BBPos) {
        if ($T.BBPos -ge 0.2 -and $T.BBPos -le 0.75) { $ent += 4 }
        elseif ($T.BBPos -gt 0.95) { [void]$flags.Add('harga menempel Bollinger atas, rawan koreksi jangka pendek') }
        elseif ($T.BBPos -lt 0.1)  { $ent += 2 }
    }
    if ($null -ne $T.PctFrom52wHigh -and $T.PctFrom52wHigh -le 8 -and $T.PctFrom52wHigh -ge 0) {
        $ent += 4
        [void]$notes.Add("hanya {0:N1}% dari puncak 52 minggu" -f $T.PctFrom52wHigh)
    }
    $ent = [Math]::Min(15, $ent)
    $score += $ent

    # --- Bonus/malus kekuatan relatif terhadap S&P 500 ---
    # Di pasar AS ini penting: indeksnya sendiri sudah naik terus, jadi saham
    # yang cuma "ikut arus" sebetulnya tidak menambah nilai dibanding beli ETF.
    if ($null -ne $T.RelStrength) {
        if ($T.RelStrength -gt 8)      { $score += 4; [void]$notes.Add("outperform $($Global:US_BENCHMARK_NAME) {0:N1}% dalam 3 bulan" -f $T.RelStrength) }
        elseif ($T.RelStrength -gt 2)  { $score += 2 }
        elseif ($T.RelStrength -lt -10){ $score -= 4; [void]$flags.Add("underperform $($Global:US_BENCHMARK_NAME) {0:N1}% dalam 3 bulan" -f $T.RelStrength) }
    }

    $score = [Math]::Max(0, [Math]::Min(100, $score))

    return [pscustomobject]@{
        Score      = [Math]::Round($score, 1)
        TrendPart  = [Math]::Round($trend, 1)
        MomPart    = [Math]::Round($mom, 1)
        StrPart    = [Math]::Round($str, 1)
        VolPart    = [Math]::Round($vol, 1)
        EntryPart  = [Math]::Round($ent, 1)
        Notes      = $notes
        Flags      = $flags
    }
}

# ===========================================================================
#  KONFIRMASI TREN MINGGUAN (multi-timeframe)
# ===========================================================================
function Get-WeeklyTrend {
    <# Sinyal harian yang melawan tren mingguan jauh lebih sering gagal.
       Fungsi ini menilai arah timeframe mingguan secara terpisah, lalu dipakai
       untuk mengoreksi sinyal harian. #>
    param($Weekly)

    if ($null -eq $Weekly -or $Weekly.Count -lt 32) {
        return [pscustomobject]@{ Trend = 'TIDAK DIKETAHUI'; Score = 0; Note = $null; Available = $false }
    }

    $wc = $Weekly.Close
    $e10 = Get-LastValid (Get-EMA -Data $wc -Period 10)
    $e30 = Get-LastValid (Get-EMA -Data $wc -Period 30)
    $wrsi = Get-LastValid (Get-RSI -Close $wc -Period 14)
    $px = $wc[$wc.Count - 1]

    $pts = 0
    if ($null -ne $e10 -and $px -gt $e10)  { $pts += 2 } else { $pts -= 2 }
    if ($null -ne $e30 -and $px -gt $e30)  { $pts += 2 } else { $pts -= 2 }
    if ($null -ne $e10 -and $null -ne $e30 -and $e10 -gt $e30) { $pts += 2 } else { $pts -= 1 }
    if ($null -ne $wrsi -and $wrsi -ge 50) { $pts += 1 } else { $pts -= 1 }

    $trend = 'NETRAL'; $note = $null
    if ($pts -ge 5)      { $trend = 'NAIK';  $note = 'tren mingguan searah naik (konfirmasi timeframe besar)' }
    elseif ($pts -ge 2)  { $trend = 'NAIK LEMAH' }
    elseif ($pts -le -4) { $trend = 'TURUN'; $note = 'tren mingguan masih turun - sinyal harian melawan arus besar' }
    elseif ($pts -le -1) { $trend = 'TURUN LEMAH' }

    return [pscustomobject]@{
        Trend = $trend; Score = $pts; Note = $note; Available = $true
        EMA10 = $e10; EMA30 = $e30; RSI = $wrsi
    }
}

# ===========================================================================
#  KLASIFIKASI GAYA TRADING
# ===========================================================================
function Get-TradingStyle {
    param($T, $FundScore, [bool]$IsEtf = $false)

    $day = 0.0; $swing = 0.0; $pos = 0.0

    # --- Day trade butuh: likuiditas besar, volatilitas harian cukup, volume ramai ---
    if ($null -ne $T.AvgValue) {
        if ($T.AvgValue -ge 1e9)                   { $day += 35 }
        elseif ($T.AvgValue -ge $Global:LIQ_EXCELLENT) { $day += 28 }
        elseif ($T.AvgValue -ge $Global:LIQ_GOOD)  { $day += 16 }
        else { $day -= 25 }
    }
    if ($null -ne $T.ATRPct) {
        if ($T.ATRPct -ge 3.0)     { $day += 30 }
        elseif ($T.ATRPct -ge 2.0) { $day += 22 }
        elseif ($T.ATRPct -ge 1.3) { $day += 10 }
        else { $day -= 12 }   # terlalu adem, tidak ada ruang profit intraday
    }
    if ($null -ne $T.VolRatio) {
        if ($T.VolRatio -ge 1.8)     { $day += 22 }
        elseif ($T.VolRatio -ge 1.2) { $day += 14 }
        elseif ($T.VolRatio -lt 0.7) { $day -= 10 }
    }
    if ($null -ne $T.TodayRangePct -and $T.TodayRangePct -ge 2.0) { $day += 8 }

    # Bursa AS buka 21:30 - 04:00 WIB. Day trade praktis berarti begadang.
    # Skornya diturunkan supaya screener tidak menyarankan gaya yang secara
    # praktis sulit dijalankan dari Indonesia.
    $day -= 12

    # --- Swing trade butuh: tren jelas + volatilitas menengah + tidak overextended ---
    if ($null -ne $T.ADX) {
        if ($T.ADX -ge 25)     { $swing += 28 }
        elseif ($T.ADX -ge 18) { $swing += 20 }
        elseif ($T.ADX -ge 14) { $swing += 8 }
        else { $swing -= 8 }
    }
    if ($null -ne $T.ATRPct) {
        if ($T.ATRPct -ge 1.5 -and $T.ATRPct -le 6.0) { $swing += 22 }
        elseif ($T.ATRPct -gt 6.0) { $swing += 6 }
        else { $swing += 8 }
    }
    if ($null -ne $T.EMA20 -and $null -ne $T.EMA50 -and $T.EMA20 -gt $T.EMA50) { $swing += 18 }
    if ($null -ne $T.ExtensionPct -and $T.ExtensionPct -le 8) { $swing += 14 }
    if ($null -ne $T.AvgValue -and $T.AvgValue -ge $Global:LIQ_OK) { $swing += 12 }
    if ($null -ne $T.MACDHist -and $null -ne $T.MACDHistPrev -and $T.MACDHist -gt $T.MACDHistPrev) { $swing += 8 }

    # --- Investasi/posisi: fundamental kuat + tren besar naik + volatilitas rendah ---
    if ($null -ne $FundScore) {
        if ($FundScore -ge 70)     { $pos += 34 }
        elseif ($FundScore -ge 58) { $pos += 24 }
        elseif ($FundScore -ge 45) { $pos += 10 }
        else { $pos -= 18 }
    }
    if ($null -ne $T.EMA200 -and $T.Price -gt $T.EMA200) { $pos += 24 }
    if ($null -ne $T.ATRPct -and $T.ATRPct -le 3.0) { $pos += 14 }
    if ($null -ne $T.AvgValue -and $T.AvgValue -ge $Global:LIQ_GOOD) { $pos += 12 }
    if ($null -ne $T.DivYield -and $T.DivYield -gt 0.02) { $pos += 10 }

    # ETF dirancang untuk dipegang lama, bukan untuk digoreng harian.
    if ($IsEtf) { $pos += 25; $day -= 30 }

    $day = [Math]::Max(0, [Math]::Min(100, $day))
    $swing = [Math]::Max(0, [Math]::Min(100, $swing))
    $pos = [Math]::Max(0, [Math]::Min(100, $pos))

    $best = 'Swing Trade'; $bestScore = $swing
    if ($day -gt $bestScore) { $best = 'Day Trade'; $bestScore = $day }
    if ($pos -gt $bestScore) { $best = 'Investasi'; $bestScore = $pos }

    $hold = '3 - 15 hari bursa'
    if ($best -eq 'Day Trade') { $hold = 'Intraday sampai 2 hari' }
    if ($best -eq 'Investasi') { $hold = '3 bulan ke atas' }

    return [pscustomobject]@{
        Primary    = $best
        HoldPeriod = $hold
        DayScore   = [Math]::Round($day, 0)
        SwingScore = [Math]::Round($swing, 0)
        PosScore   = [Math]::Round($pos, 0)
    }
}

# ===========================================================================
#  RENCANA TRADING: ENTRY / STOP LOSS / TAKE PROFIT
# ===========================================================================
function Get-TradePlan {
    param($T, [string]$Style)

    $px  = $T.Price
    $atr = $T.ATR
    if ($null -eq $atr -or $atr -le 0) { $atr = $px * 0.02 }

    $entryLo = $px; $entryHi = $px; $sl = 0.0
    $tp1 = 0.0; $tp2 = 0.0; $tp3 = $null
    $slBasis = ''; $tpBasis = ''

    if ($Style -eq 'Day Trade') {
        $entryLo = $px - 0.25 * $atr
        $entryHi = $px + 0.25 * $atr
        $slRaw   = [Math]::Min($T.TodayLow - 0.20 * $atr, $px - 1.0 * $atr)
        $slFloor = $px * (1 - $Global:MAXRISK_DAY / 100.0)
        if ($slRaw -lt $slFloor) { $slRaw = $slFloor; $slBasis = "batas risiko maksimum $($Global:MAXRISK_DAY)%" }
        else { $slBasis = 'di bawah low hari ini - 0,2 ATR' }
        $sl  = $slRaw
        $r   = $px - $sl
        $tp1 = $px + 1.5 * $r
        $tp2 = $px + 2.5 * $r
        $tpBasis = 'kelipatan risiko (1,5R / 2,5R)'
        if ($null -ne $T.Resistance -and $T.Resistance -gt $px -and $T.Resistance -lt $tp1) {
            $tp1 = $T.Resistance
            $tpBasis = 'TP1 di resistance terdekat, TP2 kelipatan risiko'
        }
    }
    elseif ($Style -eq 'Investasi') {
        $entryLo = $px * 0.96
        $entryHi = $px * 1.01
        $slRaw = $px - 3.0 * $atr
        if ($null -ne $T.EMA50 -and $T.EMA50 -lt $px) {
            $cand = $T.EMA50 * 0.96
            if ($cand -lt $slRaw) { $slRaw = $cand }
            $slBasis = 'di bawah MA50 (invalidasi tren jangka menengah)'
        } else { $slBasis = '3x ATR di bawah harga' }
        $sl = $slRaw
        if ($sl -lt $px * (1 - $Global:MAXRISK_POS / 100.0)) {
            $sl = $px * (1 - $Global:MAXRISK_POS / 100.0)
            $slBasis = "batas risiko maksimum $($Global:MAXRISK_POS)%"
        }
        $r  = $px - $sl
        $tp1 = $px + 2.0 * $r
        $tp2 = $px + 3.5 * $r
        if ($null -ne $T.High52w -and $T.High52w -gt $tp2) { $tp3 = $T.High52w }
        $tpBasis = 'target bertahap 2R / 3,5R, TP3 di puncak 52 minggu'
    }
    else {
        # --- Swing Trade (default) ---
        $entryLo = $px - 0.6 * $atr
        if ($null -ne $T.EMA20 -and $T.EMA20 -lt $px -and $T.EMA20 -gt ($px - 2.5 * $atr)) {
            $entryLo = $T.EMA20
        }
        $entryHi = $px + 0.35 * $atr

        $slSwing = $T.SwingLow - 0.35 * $atr
        $slAtr   = $px - 2.0 * $atr
        if ($slSwing -lt $slAtr) {
            $sl = $slAtr; $slBasis = '2x ATR di bawah harga (swing low terlalu jauh)'
        } else {
            $sl = $slSwing; $slBasis = 'di bawah swing low terakhir'
        }
        $floor = $px * (1 - $Global:MAXRISK_SWING / 100.0)
        if ($sl -lt $floor) { $sl = $floor; $slBasis = "batas risiko maksimum $($Global:MAXRISK_SWING)%" }

        $r   = $px - $sl
        $tp1 = $px + 2.0 * $r
        $tp2 = $px + 3.5 * $r
        $tpBasis = 'target bertahap 2R / 3,5R'
        if ($null -ne $T.Resistance -and $T.Resistance -gt ($px + 0.5 * $r) -and $T.Resistance -lt $tp2) {
            $tp1 = $T.Resistance
            $tpBasis = 'TP1 di resistance terdekat, TP2 kelipatan risiko'
        }
        if ($null -ne $T.Resistance2 -and $T.Resistance2 -gt $tp1) { $tp3 = $T.Resistance2 }
    }

    # --- Jaga agar level-level tetap masuk akal satu sama lain ---
    $tick   = Get-UsTick -Price $px
    $minGap = [Math]::Max($tick * 2, 0.4 * $atr)

    $minStopAtr = 1.0
    if     ($Style -eq 'Day Trade') { $minStopAtr = 0.6 }
    elseif ($Style -eq 'Investasi') { $minStopAtr = 1.5 }
    $maxSL = $px - [Math]::Max($tick * 2, $minStopAtr * $atr)
    if ($sl -gt $maxSL) { $sl = $maxSL }

    $sl      = ConvertTo-UsPrice -Price $sl      -Mode 'Down'
    $entryLo = ConvertTo-UsPrice -Price $entryLo -Mode 'Down'
    $entryHi = ConvertTo-UsPrice -Price $entryHi -Mode 'Up'

    if ($entryLo -le ($sl + $minGap)) {
        $entryLo = ConvertTo-UsPrice -Price ($sl + $minGap) -Mode 'Up'
    }
    if ($entryLo -gt $px) { $entryLo = ConvertTo-UsPrice -Price $px -Mode 'Down' }
    if ($entryHi -lt $entryLo) { $entryHi = $entryLo }

    $tp1 = ConvertTo-UsPrice -Price $tp1 -Mode 'Up'
    $tp2 = ConvertTo-UsPrice -Price $tp2 -Mode 'Up'
    if ($tp1 -le $entryHi) { $tp1 = ConvertTo-UsPrice -Price ($entryHi + $minGap) -Mode 'Up' }
    if ($tp2 -le $tp1)     { $tp2 = ConvertTo-UsPrice -Price ($tp1 + $minGap) -Mode 'Up' }
    if ($null -ne $tp3) {
        $tp3 = ConvertTo-UsPrice -Price $tp3 -Mode 'Up'
        if ($tp3 -le $tp2) { $tp3 = $null }
    }

    $riskPct = 0.0; $rewardPct = 0.0; $rr = 0.0
    if ($px -gt 0 -and $px -gt $sl) {
        $riskPct   = 100.0 * ($px - $sl) / $px
        $rewardPct = 100.0 * ($tp1 - $px) / $px
        $rr        = ($tp1 - $px) / ($px - $sl)
    }

    # --- Hitung ulang setelah biaya transaksi + spread kurs ---
    # Untung di layar belum tentu untung di rekening rupiah Anda.
    $netTP1 = Get-NetResult -Entry $px -Exit $tp1
    $netTP2 = Get-NetResult -Entry $px -Exit $tp2
    $netSL  = Get-NetResult -Entry $px -Exit $sl
    $breakEven = ConvertTo-UsPrice -Price (Get-BreakEvenPrice -Entry $px) -Mode 'Up'
    $netRR = 0.0
    if ($netSL -lt 0) { $netRR = $netTP1 / [Math]::Abs($netSL) }
    $feeBite = 0.0
    if ($rewardPct -gt 0) { $feeBite = 100.0 * ($rewardPct - $netTP1) / $rewardPct }

    return [pscustomobject]@{
        EntryLow   = $entryLo
        EntryHigh  = $entryHi
        StopLoss   = $sl
        TP1        = $tp1
        TP2        = $tp2
        TP3        = $tp3
        RiskPct    = [Math]::Round($riskPct, 2)
        RewardPct  = [Math]::Round($rewardPct, 2)
        RRRatio    = [Math]::Round($rr, 2)
        SLBasis    = $slBasis
        TPBasis    = $tpBasis
        NetTP1     = [Math]::Round($netTP1, 2)
        NetTP2     = [Math]::Round($netTP2, 2)
        NetSL      = [Math]::Round($netSL, 2)
        NetRR      = [Math]::Round($netRR, 2)
        BreakEven  = $breakEven
        FeeBitePct = [Math]::Round($feeBite, 0)
    }
}

# ===========================================================================
#  SINYAL AKHIR
# ===========================================================================
function Get-Signal {
    param([double]$Tech, [double]$Fund, $Plan, [bool]$LimitedData = $false,
          $Weekly = $null, $EarningsIn = $null)

    $combined = 0.55 * $Tech + 0.45 * $Fund

    $sig = 'HINDARI'
    if     ($Tech -ge 72 -and $Fund -ge 62) { $sig = 'STRONG BUY' }
    elseif ($Tech -ge 62 -and $Fund -ge 50) { $sig = 'BUY' }
    elseif ($Tech -ge 55 -and $Fund -ge 68) { $sig = 'AKUMULASI' }
    elseif ($Tech -ge 55)                   { $sig = 'SPEKULATIF' }
    elseif ($Tech -ge 45)                   { $sig = 'PANTAU' }
    elseif ($Tech -lt 35 -or $Fund -lt 28)  { $sig = 'HINDARI' }
    else { $sig = 'PANTAU' }

    # Risk/reward jelek menurunkan kualitas sinyal beli. Yang dipakai adalah RR
    # BERSIH (setelah biaya + spread kurs), karena itu yang benar-benar diterima.
    if ($null -ne $Plan -and ($sig -eq 'STRONG BUY' -or $sig -eq 'BUY')) {
        $rrCheck = $Plan.RRRatio
        if ($null -ne $Plan.NetRR -and $Plan.NetRR -gt 0) { $rrCheck = $Plan.NetRR }
        if ($rrCheck -lt 1.2) { $sig = 'PANTAU' }
    }

    if ($LimitedData -and $sig -eq 'STRONG BUY') { $sig = 'BUY' }

    # --- Koreksi timeframe mingguan ---
    if ($null -ne $Weekly -and $Weekly.Available) {
        if ($Weekly.Trend -eq 'TURUN') {
            if     ($sig -eq 'STRONG BUY') { $sig = 'BUY' }
            elseif ($sig -eq 'BUY')        { $sig = 'SPEKULATIF' }
            elseif ($sig -eq 'AKUMULASI')  { $sig = 'PANTAU' }
        }
        elseif ($Weekly.Trend -eq 'NAIK' -and $sig -eq 'BUY' -and $Tech -ge 68 -and $Fund -ge 58) {
            $sig = 'STRONG BUY'
        }
    }

    # --- Koreksi jadwal laporan keuangan ---
    # Ini khas pasar AS: harga saham bisa lompat atau anjlok 10-20% dalam satu
    # malam setelah laporan kuartalan keluar, tidak peduli sebagus apa grafiknya.
    # Stop loss pun sering terlewati karena harga melompat (gap), bukan bergerak.
    # Masuk posisi baru beberapa hari sebelum laporan = berjudi, bukan analisa.
    $earnWarn = $null
    if ($null -ne $EarningsIn -and $EarningsIn -ge 0 -and $EarningsIn -le 7) {
        $earnWarn = "laporan keuangan tinggal $EarningsIn hari lagi - harga bisa melompat semalam"
        if     ($sig -eq 'STRONG BUY') { $sig = 'BUY' }
        elseif ($sig -eq 'BUY')        { $sig = 'PANTAU' }
        elseif ($sig -eq 'SPEKULATIF') { $sig = 'PANTAU' }
    }

    return [pscustomobject]@{
        Signal      = $sig
        Combined    = [Math]::Round($combined, 1)
        EarningsWarn = $earnWarn
    }
}
