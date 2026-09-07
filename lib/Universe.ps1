# Universe.ps1 - Daftar saham AS yang di-screen.
#
# Secara default screener memakai daftar hasil .\Update-Universe.ps1 yang
# tersimpan di data\universe.json (S&P 500 terbaru + Nasdaq-100 + ETF).
# Kalau file itu belum ada, dipakai daftar cadangan di bawah ini.

# ---------------------------------------------------------------------------
# Daftar cadangan: saham AS berkapitalisasi besar yang paling sering dibahas.
# Hanya dipakai kalau pengambilan daftar S&P 500 gagal.
# ---------------------------------------------------------------------------
$Global:US_UNIVERSE_FALLBACK = @(
    # --- Teknologi & Semikonduktor ---
    'AAPL','MSFT','NVDA','AVGO','ORCL','CRM','AMD','INTC','QCOM','TXN',
    'ADBE','CSCO','ACN','IBM','NOW','INTU','AMAT','LRCX','KLAC','MU',
    'ADI','SNPS','CDNS','ANET','PANW','FTNT','CRWD','MSI','APH','GLW',
    'NXPI','MCHP','ON','TER','SWKS','MPWR','HPQ','DELL','WDC','STX',
    'IT','CTSH','FICO','ROP','ADSK','TEAM','DDOG','ZS','WDAY','HUBS',

    # --- Komunikasi & Media ---
    'GOOGL','GOOG','META','NFLX','DIS','CMCSA','T','VZ','TMUS','CHTR',
    'EA','TTWO','WBD','FOXA','OMC','IPG','LYV','NWSA','PARA','MTCH',

    # --- Konsumer Siklikal ---
    'AMZN','TSLA','HD','MCD','NKE','LOW','SBUX','BKNG','TJX','ORLY',
    'AZO','CMG','ABNB','MAR','HLT','GM','F','RCL','CCL','DHI',
    'LEN','NVR','YUM','DRI','ROST','LVS','WYNN','MGM','EBAY','ETSY',
    'DPZ','LULU','ULTA','BBY','TSCO','GRMN','APTV','LKQ','POOL','KMX',

    # --- Konsumer Non-Siklikal ---
    'WMT','PG','KO','PEP','COST','PM','MO','MDLZ','CL','KMB',
    'GIS','KHC','HSY','STZ','KDP','MNST','SYY','ADM','KR','DG',
    'DLTR','CHD','CLX','MKC','TSN','HRL','CAG','SJM','TAP','EL',

    # --- Kesehatan ---
    'LLY','UNH','JNJ','ABBV','MRK','TMO','ABT','DHR','PFE','AMGN',
    'BSX','SYK','ELV','MDT','GILD','CI','VRTX','CVS','ISRG','REGN',
    'ZTS','BDX','HCA','MCK','COR','A','IQV','EW','IDXX','DXCM',
    'BIIB','MRNA','WAT','ZBH','BAX','HOLX','RMD','STE','CAH','VTRS',

    # --- Keuangan ---
    'BRK-B','JPM','V','MA','BAC','WFC','GS','MS','AXP','SPGI',
    'BLK','SCHW','C','CB','PGR','MMC','ICE','CME','AON','PNC',
    'USB','TFC','COF','BK','AIG','MET','PRU','TRV','ALL','AFL',
    'AMP','DFS','FI','FIS','GPN','MSCI','MCO','NDAQ','STT','SYF',

    # --- Industri ---
    'GE','CAT','RTX','UNP','HON','BA','LMT','DE','UPS','ADP',
    'ETN','ITW','NOC','GD','WM','CSX','NSC','EMR','PH','TT',
    'CMI','FDX','PCAR','JCI','CARR','GWW','ROK','AME','OTIS','IR',
    'URI','PWR','FAST','DOV','XYL','LUV','DAL','UAL','VRSK','EFX',

    # --- Energi ---
    'XOM','CVX','COP','EOG','SLB','MPC','PSX','VLO','OXY','WMB',
    'KMI','OKE','HES','DVN','FANG','HAL','BKR','TRGP','CTRA','MRO',

    # --- Material & Utilitas ---
    'LIN','SHW','APD','ECL','FCX','NEM','NUE','DOW','DD','PPG',
    'VMC','MLM','ALB','IFF','CF','STLD','PKG','IP','AMCR','BALL',
    'NEE','SO','DUK','SRE','AEP','D','EXC','XEL','ED','PEG',
    'WEC','ES','AEE','DTE','PPL','FE','CMS','CNP','ATO','NRG',

    # --- Properti (REIT) ---
    'PLD','AMT','EQIX','WELL','SPG','PSA','O','CCI','DLR','VICI',
    'EXR','AVB','EQR','INVH','ARE','MAA','SBAC','UDR','ESS','KIM'
) | Select-Object -Unique

# ---------------------------------------------------------------------------
# Saham AS populer yang TIDAK masuk S&P 500 (kebanyakan perusahaan asing yang
# listing di bursa AS / ADR, atau nama baru yang belum memenuhi syarat indeks).
#
# Aman kalau ada yang ternyata sudah masuk S&P 500 - nama ganda otomatis
# dibuang saat penggabungan daftar.
# ---------------------------------------------------------------------------
$Global:US_NASDAQ_EXTRA = @(
    # Asia Tenggara - paling dekat dengan keseharian investor Indonesia
    'SE','GRAB',

    # ADR & perusahaan asing besar
    'TSM','ASML','AZN','BABA','PDD','JD','MELI','NU','ARM','TCOM',
    'BIDU','NIO','LI','XPEV','SHOP','SPOT','RELX','SNY','NVS','HSBC',
    'TM','SONY','UL','BUD','RIO','BHP','SHEL','BP','TTE','MUFG',

    # Teknologi & pertumbuhan
    'SNOW','NET','MDB','OKTA','TWLO','DOCU','ZM','ROKU','U','RBLX',
    'PINS','SNAP','AFRM','HOOD','SOFI','TOST','IOT','DUOL','RDDT','APP',

    # Energi baru, antariksa, kripto-terkait
    'RIVN','LCID','PLUG','ENPH','FSLR','RKLB','ASTS','MSTR','SMCI',

    # Konsumer & lain-lain
    'ONON','CAVA','CELH','WING','DKNG','UBER','LYFT','DASH','CHWY','W'
) | Select-Object -Unique

# ---------------------------------------------------------------------------
# ETF populer. ETF = sekeranjang saham dalam satu kode.
# Cocok untuk pemula karena risikonya tersebar, tidak bergantung satu emiten.
# ---------------------------------------------------------------------------
$Global:US_ETF_LIST = @(
    @{ Code = 'SPY';  Name = 'SPDR S&P 500 ETF - mengikuti 500 saham terbesar AS' }
    @{ Code = 'VOO';  Name = 'Vanguard S&P 500 ETF - sama dengan SPY, biaya lebih murah' }
    @{ Code = 'IVV';  Name = 'iShares Core S&P 500 ETF' }
    @{ Code = 'QQQ';  Name = 'Invesco QQQ - 100 saham terbesar Nasdaq, berat di teknologi' }
    @{ Code = 'QQQM'; Name = 'Invesco Nasdaq-100 ETF - versi biaya lebih murah dari QQQ' }
    @{ Code = 'VTI';  Name = 'Vanguard Total Stock Market - hampir seluruh saham AS' }
    @{ Code = 'DIA';  Name = 'SPDR Dow Jones Industrial Average ETF' }
    @{ Code = 'IWM';  Name = 'iShares Russell 2000 - saham berkapitalisasi kecil AS' }
    @{ Code = 'IJH';  Name = 'iShares Core S&P Mid-Cap ETF' }
    @{ Code = 'IJR';  Name = 'iShares Core S&P Small-Cap ETF' }
    @{ Code = 'RSP';  Name = 'Invesco S&P 500 Equal Weight - bobot rata, tidak didominasi raksasa' }
    @{ Code = 'SCHD'; Name = 'Schwab US Dividend Equity - fokus saham dividen' }
    @{ Code = 'VYM';  Name = 'Vanguard High Dividend Yield ETF' }
    @{ Code = 'VIG';  Name = 'Vanguard Dividend Appreciation ETF' }
    @{ Code = 'JEPI'; Name = 'JPMorgan Equity Premium Income - fokus pendapatan bulanan' }
    @{ Code = 'SMH';  Name = 'VanEck Semiconductor ETF - saham chip' }
    @{ Code = 'SOXX'; Name = 'iShares Semiconductor ETF' }
    @{ Code = 'XLK';  Name = 'Sektor Teknologi S&P 500' }
    @{ Code = 'XLF';  Name = 'Sektor Keuangan S&P 500' }
    @{ Code = 'XLE';  Name = 'Sektor Energi S&P 500' }
    @{ Code = 'XLV';  Name = 'Sektor Kesehatan S&P 500' }
    @{ Code = 'XLY';  Name = 'Sektor Konsumer Siklikal S&P 500' }
    @{ Code = 'XLP';  Name = 'Sektor Konsumer Non-Siklikal S&P 500' }
    @{ Code = 'XLI';  Name = 'Sektor Industri S&P 500' }
    @{ Code = 'XLU';  Name = 'Sektor Utilitas S&P 500' }
    @{ Code = 'XLB';  Name = 'Sektor Material S&P 500' }
    @{ Code = 'XLRE'; Name = 'Sektor Properti S&P 500' }
    @{ Code = 'XLC';  Name = 'Sektor Komunikasi S&P 500' }
    @{ Code = 'ARKK'; Name = 'ARK Innovation - saham teknologi agresif, volatil' }
    @{ Code = 'XBI';  Name = 'SPDR Biotech ETF' }
    @{ Code = 'ITA';  Name = 'iShares Aerospace & Defense ETF' }
    @{ Code = 'VNQ';  Name = 'Vanguard Real Estate ETF - properti AS' }
    @{ Code = 'GLD';  Name = 'SPDR Gold Shares - mengikuti harga emas' }
    @{ Code = 'SLV';  Name = 'iShares Silver Trust - mengikuti harga perak' }
    @{ Code = 'IBIT'; Name = 'iShares Bitcoin Trust - ETF Bitcoin spot' }
    @{ Code = 'TLT';  Name = 'iShares 20+ Year Treasury - obligasi AS jangka panjang' }
    @{ Code = 'HYG';  Name = 'iShares High Yield Corporate Bond ETF' }
    @{ Code = 'EEM';  Name = 'iShares MSCI Emerging Markets - termasuk Indonesia' }
    @{ Code = 'VWO';  Name = 'Vanguard Emerging Markets ETF' }
    @{ Code = 'EFA';  Name = 'iShares MSCI EAFE - saham maju di luar AS' }
    @{ Code = 'VEA';  Name = 'Vanguard Developed Markets ETF' }
    @{ Code = 'EIDO'; Name = 'iShares MSCI Indonesia ETF - saham Indonesia di bursa AS' }
)

function Get-UsUniverse {
    <# Ambil daftar dari data\universe.json kalau ada, kalau tidak pakai daftar
       cadangan. Mengembalikan array objek { Code, Name, Sector, Group }. #>
    param([string]$Root)

    $path = Join-Path $Root 'data\universe.json'
    if (Test-Path $path) {
        try {
            $u = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $list = @($u.Stocks | Where-Object { $_.Code })
            if ($list.Count -gt 0) {
                $Global:US_UNIVERSE_SOURCE = "$($u.Source) - $($list.Count) saham, diperbarui $($u.UpdatedAt)"
                return $list
            }
        } catch { }
    }

    # --- Rakit daftar cadangan ---
    $out = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($c in $Global:US_UNIVERSE_FALLBACK) {
        if ($seen.ContainsKey($c)) { continue }
        $seen[$c] = $true
        [void]$out.Add([pscustomobject]@{ Code = $c; Name = ''; Sector = ''; Group = 'S&P 500' })
    }
    foreach ($c in $Global:US_NASDAQ_EXTRA) {
        if ($seen.ContainsKey($c)) { continue }
        $seen[$c] = $true
        [void]$out.Add([pscustomobject]@{ Code = $c; Name = ''; Sector = ''; Group = 'Nasdaq-100' })
    }
    foreach ($e in $Global:US_ETF_LIST) {
        if ($seen.ContainsKey($e.Code)) { continue }
        $seen[$e.Code] = $true
        [void]$out.Add([pscustomobject]@{ Code = $e.Code; Name = $e.Name; Sector = 'ETF'; Group = 'ETF' })
    }

    $Global:US_UNIVERSE_SOURCE = "daftar cadangan ($($out.Count) saham) - jalankan .\Update-Universe.ps1 untuk daftar S&P 500 terbaru"
    return $out.ToArray()
}

function Get-EtfDescription {
    <# Penjelasan singkat untuk kode ETF, kalau ada. #>
    param([string]$Code)
    foreach ($e in $Global:US_ETF_LIST) {
        if ($e.Code -eq $Code) { return $e.Name }
    }
    return $null
}
