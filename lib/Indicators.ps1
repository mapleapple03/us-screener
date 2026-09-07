# Indicators.ps1 - Perhitungan indikator teknikal murni (tanpa dependensi eksternal).
# Semua fungsi menerima array [double] dan mengembalikan array sepanjang input,
# dengan nilai $null pada periode pemanasan (warm-up).

function Get-SMA {
    param([double[]]$Data, [int]$Period)
    $n = $Data.Count; $out = New-Object object[] $n
    if ($n -lt $Period) { return $out }
    $sum = 0.0
    for ($i = 0; $i -lt $n; $i++) {
        $sum += $Data[$i]
        if ($i -ge $Period) { $sum -= $Data[$i - $Period] }
        if ($i -ge $Period - 1) { $out[$i] = $sum / $Period }
    }
    return $out
}

function Get-EMA {
    param([double[]]$Data, [int]$Period)
    $n = $Data.Count; $out = New-Object object[] $n
    if ($n -lt $Period) { return $out }
    $k = 2.0 / ($Period + 1.0)
    $seed = 0.0
    for ($i = 0; $i -lt $Period; $i++) { $seed += $Data[$i] }
    $prev = $seed / $Period
    $out[$Period - 1] = $prev
    for ($i = $Period; $i -lt $n; $i++) {
        $prev = ($Data[$i] - $prev) * $k + $prev
        $out[$i] = $prev
    }
    return $out
}

function Get-WilderSmooth {
    # Perataan Wilder (dipakai RSI, ATR, ADX).
    param([double[]]$Data, [int]$Period)
    $n = $Data.Count; $out = New-Object object[] $n
    if ($n -lt $Period) { return $out }
    $sum = 0.0
    for ($i = 0; $i -lt $Period; $i++) { $sum += $Data[$i] }
    $prev = $sum / $Period
    $out[$Period - 1] = $prev
    for ($i = $Period; $i -lt $n; $i++) {
        $prev = ($prev * ($Period - 1) + $Data[$i]) / $Period
        $out[$i] = $prev
    }
    return $out
}

function Get-RSI {
    param([double[]]$Close, [int]$Period = 14)
    $n = $Close.Count; $out = New-Object object[] $n
    if ($n -lt $Period + 1) { return $out }
    $gain = New-Object double[] $n
    $loss = New-Object double[] $n
    for ($i = 1; $i -lt $n; $i++) {
        $d = $Close[$i] - $Close[$i - 1]
        if ($d -gt 0) { $gain[$i] = $d } else { $loss[$i] = [Math]::Abs($d) }
    }
    $ag = 0.0; $al = 0.0
    for ($i = 1; $i -le $Period; $i++) { $ag += $gain[$i]; $al += $loss[$i] }
    $ag = $ag / $Period; $al = $al / $Period
    if ($al -eq 0) { $out[$Period] = 100.0 } else { $out[$Period] = 100.0 - (100.0 / (1.0 + $ag / $al)) }
    for ($i = $Period + 1; $i -lt $n; $i++) {
        $ag = ($ag * ($Period - 1) + $gain[$i]) / $Period
        $al = ($al * ($Period - 1) + $loss[$i]) / $Period
        if ($al -eq 0) { $out[$i] = 100.0 } else { $out[$i] = 100.0 - (100.0 / (1.0 + $ag / $al)) }
    }
    return $out
}

function Get-TrueRange {
    param([double[]]$High, [double[]]$Low, [double[]]$Close)
    $n = $High.Count; $tr = New-Object double[] $n
    $tr[0] = $High[0] - $Low[0]
    for ($i = 1; $i -lt $n; $i++) {
        $a = $High[$i] - $Low[$i]
        $b = [Math]::Abs($High[$i] - $Close[$i - 1])
        $c = [Math]::Abs($Low[$i] - $Close[$i - 1])
        $tr[$i] = [Math]::Max($a, [Math]::Max($b, $c))
    }
    return $tr
}

function Get-ATR {
    param([double[]]$High, [double[]]$Low, [double[]]$Close, [int]$Period = 14)
    $tr = Get-TrueRange -High $High -Low $Low -Close $Close
    return (Get-WilderSmooth -Data $tr -Period $Period)
}

function Get-MACD {
    param([double[]]$Close, [int]$Fast = 12, [int]$Slow = 26, [int]$Signal = 9)
    $ef = Get-EMA -Data $Close -Period $Fast
    $es = Get-EMA -Data $Close -Period $Slow
    $n = $Close.Count
    $macd = New-Object object[] $n
    $valid = New-Object System.Collections.ArrayList
    $firstIdx = -1
    for ($i = 0; $i -lt $n; $i++) {
        if ($null -ne $ef[$i] -and $null -ne $es[$i]) {
            $macd[$i] = [double]$ef[$i] - [double]$es[$i]
            if ($firstIdx -lt 0) { $firstIdx = $i }
            [void]$valid.Add([double]$macd[$i])
        }
    }
    $sig  = New-Object object[] $n
    $hist = New-Object object[] $n
    if ($valid.Count -ge $Signal) {
        $sigArr = Get-EMA -Data ([double[]]$valid.ToArray()) -Period $Signal
        for ($k = 0; $k -lt $sigArr.Count; $k++) {
            if ($null -ne $sigArr[$k]) {
                $idx = $firstIdx + $k
                $sig[$idx]  = $sigArr[$k]
                $hist[$idx] = [double]$macd[$idx] - [double]$sigArr[$k]
            }
        }
    }
    return [pscustomobject]@{ MACD = $macd; Signal = $sig; Histogram = $hist }
}

function Get-ADX {
    # Directional Movement Index - mengukur KEKUATAN tren (bukan arahnya).
    param([double[]]$High, [double[]]$Low, [double[]]$Close, [int]$Period = 14)
    $n = $High.Count
    $result = [pscustomobject]@{
        ADX = (New-Object object[] $n); PlusDI = (New-Object object[] $n); MinusDI = (New-Object object[] $n)
    }
    if ($n -lt ($Period * 2 + 2)) { return $result }

    $pDM = New-Object double[] $n
    $mDM = New-Object double[] $n
    for ($i = 1; $i -lt $n; $i++) {
        $up = $High[$i] - $High[$i - 1]
        $dn = $Low[$i - 1] - $Low[$i]
        if ($up -gt $dn -and $up -gt 0) { $pDM[$i] = $up }
        if ($dn -gt $up -and $dn -gt 0) { $mDM[$i] = $dn }
    }
    $tr  = Get-TrueRange -High $High -Low $Low -Close $Close
    $atr = Get-WilderSmooth -Data $tr  -Period $Period
    $sp  = Get-WilderSmooth -Data $pDM -Period $Period
    $sm  = Get-WilderSmooth -Data $mDM -Period $Period

    $dx = New-Object double[] $n
    $dxValid = New-Object System.Collections.ArrayList
    $firstDx = -1
    for ($i = 0; $i -lt $n; $i++) {
        if ($null -ne $atr[$i] -and [double]$atr[$i] -gt 0 -and $null -ne $sp[$i] -and $null -ne $sm[$i]) {
            $pdi = 100.0 * [double]$sp[$i] / [double]$atr[$i]
            $mdi = 100.0 * [double]$sm[$i] / [double]$atr[$i]
            $result.PlusDI[$i]  = $pdi
            $result.MinusDI[$i] = $mdi
            $den = $pdi + $mdi
            if ($den -gt 0) { $dx[$i] = 100.0 * [Math]::Abs($pdi - $mdi) / $den }
            if ($firstDx -lt 0) { $firstDx = $i }
            [void]$dxValid.Add($dx[$i])
        }
    }
    if ($dxValid.Count -ge $Period) {
        $adxArr = Get-WilderSmooth -Data ([double[]]$dxValid.ToArray()) -Period $Period
        for ($k = 0; $k -lt $adxArr.Count; $k++) {
            if ($null -ne $adxArr[$k]) { $result.ADX[$firstDx + $k] = $adxArr[$k] }
        }
    }
    return $result
}

function Get-Bollinger {
    param([double[]]$Close, [int]$Period = 20, [double]$Mult = 2.0)
    $n = $Close.Count
    $mid = Get-SMA -Data $Close -Period $Period
    $up = New-Object object[] $n; $lo = New-Object object[] $n; $bw = New-Object object[] $n
    for ($i = $Period - 1; $i -lt $n; $i++) {
        if ($null -eq $mid[$i]) { continue }
        $m = [double]$mid[$i]; $ss = 0.0
        for ($k = $i - $Period + 1; $k -le $i; $k++) { $ss += [Math]::Pow($Close[$k] - $m, 2) }
        $sd = [Math]::Sqrt($ss / $Period)
        $up[$i] = $m + $Mult * $sd
        $lo[$i] = $m - $Mult * $sd
        # Lebar pita dalam persen - dipakai untuk deteksi squeeze (konsolidasi ketat).
        if ($m -gt 0) { $bw[$i] = 100.0 * (2.0 * $Mult * $sd) / $m }
    }
    return [pscustomobject]@{ Middle = $mid; Upper = $up; Lower = $lo; Bandwidth = $bw }
}

function Get-Stochastic {
    param([double[]]$High, [double[]]$Low, [double[]]$Close, [int]$Period = 14, [int]$SmoothD = 3)
    $n = $Close.Count
    $k = New-Object object[] $n
    for ($i = $Period - 1; $i -lt $n; $i++) {
        $hh = -[double]::MaxValue; $ll = [double]::MaxValue
        for ($j = $i - $Period + 1; $j -le $i; $j++) {
            if ($High[$j] -gt $hh) { $hh = $High[$j] }
            if ($Low[$j]  -lt $ll) { $ll = $Low[$j] }
        }
        if (($hh - $ll) -gt 0) { $k[$i] = 100.0 * ($Close[$i] - $ll) / ($hh - $ll) } else { $k[$i] = 50.0 }
    }
    $d = New-Object object[] $n
    for ($i = $Period - 1 + $SmoothD - 1; $i -lt $n; $i++) {
        $s = 0.0; $cnt = 0
        for ($j = $i - $SmoothD + 1; $j -le $i; $j++) { if ($null -ne $k[$j]) { $s += [double]$k[$j]; $cnt++ } }
        if ($cnt -gt 0) { $d[$i] = $s / $cnt }
    }
    return [pscustomobject]@{ K = $k; D = $d }
}

function Get-VolumeProfile {
    <# Membangun profil volume: berapa banyak volume yang benar-benar diperdagangkan
       di tiap tingkat harga. Volume tiap bar disebar merata sepanjang rentang
       high-low bar tersebut, sehingga hasilnya lebih realistis dibanding hanya
       menaruh seluruh volume di harga penutupan. #>
    param([double[]]$High, [double[]]$Low, [double[]]$Volume, [int]$Lookback = 120, [int]$Bins = 60)

    $n = $High.Count
    $start = [Math]::Max(0, $n - $Lookback)
    $lo = [double]::MaxValue; $hi = -[double]::MaxValue
    for ($i = $start; $i -lt $n; $i++) {
        if ($Low[$i]  -lt $lo) { $lo = $Low[$i] }
        if ($High[$i] -gt $hi) { $hi = $High[$i] }
    }
    if ($hi -le $lo) { return $null }

    $binSize = ($hi - $lo) / $Bins
    if ($binSize -le 0) { return $null }
    $vol = New-Object double[] $Bins

    for ($i = $start; $i -lt $n; $i++) {
        $bl = [int][Math]::Floor(($Low[$i]  - $lo) / $binSize)
        $bh = [int][Math]::Floor(($High[$i] - $lo) / $binSize)
        if ($bl -lt 0) { $bl = 0 }
        if ($bh -gt ($Bins - 1)) { $bh = $Bins - 1 }
        if ($bh -lt $bl) { $bh = $bl }
        $span = $bh - $bl + 1
        $share = $Volume[$i] / $span
        for ($b = $bl; $b -le $bh; $b++) { $vol[$b] += $share }
    }

    $maxVol = 0.0
    foreach ($v in $vol) { if ($v -gt $maxVol) { $maxVol = $v } }

    return [pscustomobject]@{
        Min = $lo; Max = $hi; BinSize = $binSize; Bins = $Bins; Volume = $vol; MaxVolume = $maxVol
    }
}

function Get-VolumeNear {
    <# Volume yang diperdagangkan di sekitar suatu harga, dinormalisasi 0-1
       terhadap tingkat harga paling ramai. Makin tinggi = level makin "nyata". #>
    param($Profile, [double]$Price, [double]$TolPct = 2.0)
    if ($null -eq $Profile -or $Profile.MaxVolume -le 0) { return 0.0 }
    $tol = $Price * $TolPct / 100.0
    $a = [int][Math]::Floor((($Price - $tol) - $Profile.Min) / $Profile.BinSize)
    $b = [int][Math]::Floor((($Price + $tol) - $Profile.Min) / $Profile.BinSize)
    if ($a -lt 0) { $a = 0 }
    if ($b -gt ($Profile.Bins - 1)) { $b = $Profile.Bins - 1 }
    if ($b -lt $a) { return 0.0 }
    $sum = 0.0
    for ($i = $a; $i -le $b; $i++) { $sum += $Profile.Volume[$i] }
    # Dibagi jumlah bin agar rentang lebar tidak otomatis menang.
    $avg = $sum / ($b - $a + 1)
    return [Math]::Min(1.0, $avg / $Profile.MaxVolume)
}

function Get-SupportResistance {
    # Cari titik swing (pivot) dalam N bar terakhir, lalu ambil support terdekat
    # di bawah harga dan resistance terdekat di atas harga.
    param([double[]]$High, [double[]]$Low, [double]$Price, [int]$Lookback = 120, [int]$Wing = 3, $Profile = $null)
    $n = $High.Count
    $start = [Math]::Max($Wing, $n - $Lookback)
    $sup = New-Object System.Collections.ArrayList
    $res = New-Object System.Collections.ArrayList

    for ($i = $start; $i -lt ($n - $Wing); $i++) {
        $isHigh = $true; $isLow = $true
        for ($j = $i - $Wing; $j -le $i + $Wing; $j++) {
            if ($j -eq $i) { continue }
            if ($High[$j] -ge $High[$i]) { $isHigh = $false }
            if ($Low[$j]  -le $Low[$i])  { $isLow  = $false }
        }
        if ($isHigh -and $High[$i] -gt $Price) { [void]$res.Add($High[$i]) }
        if ($isLow  -and $Low[$i]  -lt $Price) { [void]$sup.Add($Low[$i]) }
    }

    # Volume dipakai untuk MENYARING, bukan untuk mengurutkan. Sebagai target,
    # yang penting adalah rintangan TERDEKAT - level lebih jauh yang volumenya
    # lebih tebal tetap baru relevan setelah yang dekat ditembus. Jadi: buang dulu
    # pivot yang cuma sentuhan sekilas (volume tipis), lalu ambil yang terdekat.
    $minStrength = 0.25

    function Select-Level($levels, $px, $prof, [bool]$Below) {
        if ($levels.Count -eq 0) { return $null }
        $pool = $levels
        if ($null -ne $prof) {
            $strong = @($levels | Where-Object {
                (Get-VolumeNear -Profile $prof -Price $_ -TolPct 2.0) -ge $minStrength
            })
            if ($strong.Count -gt 0) { $pool = $strong }   # kalau tidak ada yang lolos, pakai semua
        }
        if ($Below) { return (@($pool) | Sort-Object -Descending)[0] }   # support terdekat di bawah
        return (@($pool) | Sort-Object)[0]                               # resistance terdekat di atas
    }

    $nearSup = $null; $nearRes = $null; $res2 = $null
    $supStr = 0.0; $resStr = 0.0

    $nearSup = Select-Level $sup $Price $Profile $true
    if ($null -ne $nearSup -and $null -ne $Profile) {
        $supStr = Get-VolumeNear -Profile $Profile -Price $nearSup -TolPct 2.0
    }

    $nearRes = Select-Level $res $Price $Profile $false
    if ($null -ne $nearRes) {
        if ($null -ne $Profile) { $resStr = Get-VolumeNear -Profile $Profile -Price $nearRes -TolPct 2.0 }
        # Target lanjutan: rintangan berikutnya, harus terpisah cukup jauh dari yang
        # pertama. Pivot yang cuma beda beberapa tick sebenarnya level yang sama.
        $above = @($res | Where-Object { $_ -gt ($nearRes * 1.03) })
        $res2 = Select-Level $above $Price $Profile $false
    }

    return [pscustomobject]@{
        Support = $nearSup; Resistance = $nearRes; Resistance2 = $res2
        SupportStrength    = [Math]::Round($supStr * 100, 0)
        ResistanceStrength = [Math]::Round($resStr * 100, 0)
    }
}

function Get-SwingLow {
    # Titik terendah dalam N bar terakhir - dasar penempatan stop loss swing.
    param([double[]]$Low, [int]$Lookback = 10)
    $n = $Low.Count
    $start = [Math]::Max(0, $n - $Lookback)
    $min = [double]::MaxValue
    for ($i = $start; $i -lt $n; $i++) { if ($Low[$i] -lt $min) { $min = $Low[$i] } }
    return $min
}

function Get-Highest {
    param([double[]]$Data, [int]$Lookback)
    $n = $Data.Count; $start = [Math]::Max(0, $n - $Lookback); $m = -[double]::MaxValue
    for ($i = $start; $i -lt $n; $i++) { if ($Data[$i] -gt $m) { $m = $Data[$i] } }
    return $m
}

function Get-Lowest {
    param([double[]]$Data, [int]$Lookback)
    $n = $Data.Count; $start = [Math]::Max(0, $n - $Lookback); $m = [double]::MaxValue
    for ($i = $start; $i -lt $n; $i++) { if ($Data[$i] -lt $m) { $m = $Data[$i] } }
    return $m
}

function Get-LastValid {
    # Ambil nilai valid terakhir dari array indikator ($Back=1 berarti satu bar sebelumnya).
    param($Arr, [int]$Back = 0)
    if ($null -eq $Arr) { return $null }
    $idx = $Arr.Count - 1 - $Back
    if ($idx -lt 0) { return $null }
    if ($null -eq $Arr[$idx]) { return $null }
    return [double]$Arr[$idx]
}
