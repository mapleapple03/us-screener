# News.ps1 - Pengambilan dan pengolahan berita pasar saham AS.
#
# Sumber: RSS publik (Yahoo Finance, CNBC, Google News). Tidak perlu API key.
#
# CATATAN PENTING SOAL "ARTI BERITA INI":
# Penjelasan yang muncul di bawah tiap judul TIDAK ditulis oleh AI yang membaca
# artikelnya. Penjelasan itu dipilih dari daftar tetap di file ini berdasarkan
# KATA KUNCI yang muncul di judul. Jadi:
#   - Penjelasannya benar untuk JENIS beritanya (mis. "berita soal suku bunga").
#   - Penjelasannya TIDAK tahu isi spesifik artikel itu.
# Selalu klik judulnya untuk baca sendiri sebelum ambil keputusan.

$Script:NewsUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'

function ConvertFrom-HtmlText {
    <# Membersihkan tag HTML dan mengembalikan karakter khusus ke bentuk normal. #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = $Text -replace '<[^>]+>', ' '
    $t = $t -replace '&nbsp;', ' '
    $t = $t -replace '&amp;', '&'
    $t = $t -replace '&lt;', '<'
    $t = $t -replace '&gt;', '>'
    $t = $t -replace '&quot;', '"'
    $t = $t -replace '&#39;|&apos;|&#x27;', "'"
    $t = $t -replace '&#x2018;|&#x2019;|&#8216;|&#8217;', "'"
    $t = $t -replace '&#x201C;|&#x201D;|&#8220;|&#8221;', '"'
    $t = $t -replace '&#8230;|&hellip;', '...'
    $t = $t -replace '&#8211;|&ndash;|&#8212;|&mdash;', '-'
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function Get-NodeText {
    <# Ambil isi teks sebuah node RSS. Feed yang berbeda membungkus isinya dengan
       cara berbeda: ada yang teks polos, ada yang CDATA, ada yang punya atribut
       sehingga PowerShell mengembalikannya sebagai objek XmlElement - bukan string.
       Tanpa penanganan ini, ringkasan berita bisa muncul sebagai
       "System.Xml.XmlElement" di dashboard. #>
    param($Node)
    if ($null -eq $Node) { return '' }
    if ($Node -is [string]) { return $Node }
    if ($Node -is [System.Xml.XmlElement]) { return $Node.InnerText }
    # Node dengan atribut: PowerShell menaruh teksnya di properti '#text'.
    $t = $Node.'#text'
    if (-not [string]::IsNullOrWhiteSpace($t)) { return [string]$t }
    return [string]$Node
}

function Get-RssFeed {
    <# Ambil satu feed RSS dan kembalikan daftar berita. #>
    param(
        [string]$Url,
        [string]$Source,
        [string]$Scope = 'Makro',
        [int]$Max = 25
    )

    $items = New-Object System.Collections.ArrayList
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 25 `
            -UserAgent $Script:NewsUA -ErrorAction Stop
        $xml = [xml]$resp.Content
    } catch {
        return $items   # feed mati / internet putus - dilewati diam-diam
    }

    $nodes = @($xml.rss.channel.item)
    if ($nodes.Count -eq 0) { return $items }

    $count = 0
    foreach ($node in $nodes) {
        if ($count -ge $Max) { break }
        if ($null -eq $node) { continue }

        $title = ConvertFrom-HtmlText (Get-NodeText $node.title)
        if ([string]::IsNullOrWhiteSpace($title)) { continue }

        $link = Get-NodeText $node.link
        if ([string]::IsNullOrWhiteSpace($link) -and $null -ne $node.guid) {
            $link = Get-NodeText $node.guid
        }

        $desc = ConvertFrom-HtmlText (Get-NodeText $node.description)
        # Sebagian feed (terutama Google News) mengisi ringkasan dengan judul yang
        # sama persis. Menampilkannya dua kali cuma bikin ramai, jadi dibuang.
        $nt = ($title.ToLower() -replace '[^a-z0-9]', '')
        $nd = ($desc.ToLower()  -replace '[^a-z0-9]', '')
        if ($nd.Length -gt 0 -and $nt.Length -gt 0 -and
            ($nd.StartsWith($nt) -or $nt.StartsWith($nd))) { $desc = '' }
        if ($desc.Length -gt 300) { $desc = $desc.Substring(0, 300) + '...' }

        # Waktu terbit -> WIB
        $pub = $null
        $raw = Get-NodeText $node.pubDate
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            try { $pub = ([DateTimeOffset]::Parse($raw)).UtcDateTime.AddHours(7) } catch { }
        }

        # Google News membungkus nama media di dalam judul setelah tanda "-".
        $src = $Source
        if ($null -ne $node.source) {
            $s = ConvertFrom-HtmlText (Get-NodeText $node.source)
            if (-not [string]::IsNullOrWhiteSpace($s)) { $src = $s }
        }

        [void]$items.Add([pscustomobject]@{
            Title     = $title
            Link      = $link
            Summary   = $desc
            Source    = $src
            Scope     = $Scope
            Published = $pub
        })
        $count++
    }
    return $items
}

function Get-TickerNews {
    <# Berita khusus satu saham dari Yahoo Finance. #>
    param([string]$Symbol, [int]$Max = 6)
    $url = "https://feeds.finance.yahoo.com/rss/2.0/headline?s=$Symbol&region=US&lang=en-US"
    $items = Get-RssFeed -Url $url -Source 'Yahoo Finance' -Scope 'Saham' -Max $Max
    foreach ($it in $items) { $it | Add-Member -NotePropertyName Ticker -NotePropertyValue $Symbol -Force }
    return $items
}

# ===========================================================================
#  PENGELOMPOKAN BERITA
# ===========================================================================
# Urutan penting: pola yang lebih spesifik diletakkan lebih dulu.
$Script:NewsRules = @(
    @{
        Cat = 'Suku Bunga & The Fed'
        Pat = 'federal reserve|\bthe fed\b|\bfed\b|fomc|interest rate|rate cut|rate hike|powell|monetary policy|basis point|yield curve|treasury yield'
        Why = 'Suku bunga adalah rem dan gas pasar saham. Kalau bunga TURUN, pinjaman jadi murah, perusahaan lebih gampang tumbuh, dan menaruh uang di deposito jadi kurang menarik - uang mengalir ke saham. Kalau bunga NAIK, yang terjadi kebalikannya. Saham teknologi paling sensitif karena nilainya bertumpu pada laba di masa depan.'
    }
    @{
        Cat = 'Inflasi & Data Ekonomi'
        Pat = 'inflation|\bcpi\b|\bppi\b|consumer price|jobs report|payroll|unemployment|\bgdp\b|retail sales|consumer confidence|jobless claim|recession|economic data'
        Why = 'Data ekonomi menentukan langkah The Fed berikutnya. Inflasi tinggi atau lapangan kerja terlalu kuat membuat bank sentral menahan suku bunga tetap tinggi - kurang bagus untuk saham. Data yang melemah bisa membuka jalan penurunan bunga, tapi kalau terlalu lemah pasar malah takut resesi.'
    }
    @{
        Cat = 'Laporan Keuangan'
        Pat = 'earnings|quarterly result|\bq[1-4]\b results|beats estimate|misses estimate|guidance|outlook|revenue rose|revenue fell|profit rose|profit fell|forecast'
        Why = 'Laporan keuangan kuartalan adalah momen paling menentukan untuk satu saham. Harga bisa melompat atau anjlok 10-20% dalam semalam. Yang digerakkan pasar bukan cuma angka laba, tapi apakah angkanya di atas atau di bawah PERKIRAAN analis, dan bagaimana panduan (guidance) untuk kuartal berikutnya.'
    }
    @{
        Cat = 'Analis & Rating'
        Pat = 'upgrade|downgrade|price target|analyst|initiated coverage|buy rating|sell rating|overweight|underweight|outperform'
        Why = 'Perubahan rekomendasi analis bisa menggerakkan harga jangka pendek karena banyak institusi mengikutinya. Tapi ingat: target harga analis sering meleset dan biasanya menyusul harga, bukan mendahului. Pakai sebagai bahan pertimbangan, bukan alasan tunggal untuk membeli.'
    }
    @{
        Cat = 'Merger & Akuisisi'
        Pat = 'acquisition|acquire|merger|takeover|buyout|deal to buy|stake in|\bipo\b|spin off|spinoff'
        Why = 'Dalam aksi akuisisi, saham perusahaan yang DIBELI biasanya melonjak mendekati harga penawaran, sementara saham perusahaan PEMBELI sering turun karena pasar khawatir harganya kemahalan atau utangnya bertambah.'
    }
    @{
        Cat = 'Dividen & Buyback'
        Pat = 'dividend|buyback|share repurchase|special dividend|payout'
        Why = 'Buyback (perusahaan membeli sahamnya sendiri) mengurangi jumlah saham beredar sehingga laba per saham naik - umumnya dianggap kabar baik. Kenaikan dividen menandakan manajemen yakin arus kasnya kuat. Sebaliknya, pemotongan dividen hampir selalu sinyal ada masalah.'
    }
    @{
        Cat = 'Regulasi & Hukum'
        Pat = 'lawsuit|antitrust|\bsec\b |regulator|investigation|fine|settlement|court|ruling|subpoena|probe'
        Why = 'Masalah hukum dan regulasi menambah ketidakpastian, dan pasar sangat tidak suka ketidakpastian. Dampaknya bisa berupa denda besar, larangan praktik bisnis tertentu, atau dalam kasus antitrust, pemecahan perusahaan.'
    }
    @{
        Cat = 'Teknologi & AI'
        Pat = '\bai\b|artificial intelligence|chip|semiconductor|data center|cloud|nvidia|openai|machine learning|gpu'
        Why = 'AI adalah tema terbesar pasar AS beberapa tahun terakhir dan menjadi penggerak utama indeks. Karena bobot saham teknologi di S&P 500 sangat besar, berita AI yang bagus atau jelek bisa menggerakkan SELURUH indeks, bukan cuma saham teknologinya.'
    }
    @{
        Cat = 'Energi & Komoditas'
        Pat = 'oil price|crude|\bopec\b|natural gas|gold price|commodity|barrel|energy price'
        Why = 'Harga minyak menyentuh dua sisi sekaligus: bagus untuk saham energi, tapi menaikkan biaya bagi hampir semua sektor lain dan mendorong inflasi. Emas biasanya naik ketika investor takut - jadi emas menguat sering berarti pasar sedang cemas.'
    }
    @{
        Cat = 'Geopolitik'
        Pat = 'war|military|missile|sanction|tariff|trade war|conflict|invasion|iran|russia|ukraine|china tension|geopolitic'
        Why = 'Ketegangan geopolitik biasanya membuat pasar turun sesaat karena investor lari ke aset aman (emas, dolar, obligasi AS). Kecuali konfliknya mengganggu pasokan energi atau rantai pasok chip, dampaknya ke harga saham sering hanya sebentar.'
    }
    @{
        Cat = 'Kripto & Bitcoin'
        Pat = 'bitcoin|crypto|ethereum|blockchain|coinbase|stablecoin|digital asset'
        Why = 'Harga kripto sering bergerak searah dengan saham teknologi karena sama-sama tergolong aset berisiko: naik saat investor berani, turun saat investor takut. Jadi berita kripto bisa jadi petunjuk awal soal selera risiko pasar secara umum, walaupun Anda tidak memegang kripto sama sekali.'
    }
    @{
        Cat = 'Properti & Perumahan'
        Pat = 'housing|mortgage|home sales|home price|real estate|homebuilder|rent price'
        Why = 'Sektor properti adalah termometer suku bunga. Ketika bunga KPR di AS naik, penjualan rumah langsung melambat - dan karena membeli rumah biasanya diikuti belanja perabot, renovasi, dan pindahan, pelemahannya menular ke banyak sektor lain.'
    }
    @{
        Cat = 'Pasar Umum'
        Pat = 'stock market|s&p 500|nasdaq|dow jones|wall street|stocks close|stocks rise|stocks fall|rally|selloff|correction|market open|investors|futures'
        Why = 'Ringkasan pergerakan pasar secara keseluruhan. Berguna untuk tahu arah angin: kalau indeks sedang turun, saham bagus pun ikut tertekan. Jangan melawan arah pasar hanya karena grafik satu saham terlihat bagus.'
    }
    @{
        Cat = 'Perusahaan & Bisnis'
        Pat = '\bceo\b|chief executive|layoff|job cuts|hiring|new product|launches|unveils|partnership|expansion|factory|plant|recall|strike|union|airline|retailer|automaker|bank\b|startup'
        Why = 'Berita operasional satu perusahaan: pergantian pimpinan, PHK, produk baru, atau kemitraan. Dampaknya ke harga saham biasanya lebih kecil dan lebih pendek dibanding laporan keuangan, kecuali beritanya menyangkut hal mendasar seperti CEO mundur mendadak atau penarikan produk besar-besaran.'
    }
)

function Get-NewsCategory {
    param([string]$Title, [string]$Summary)
    $text = ("$Title $Summary").ToLower()
    foreach ($r in $Script:NewsRules) {
        if ($text -match $r.Pat) { return $r.Cat }
    }
    return 'Lainnya'
}

function Get-NewsExplainer {
    <# Penjelasan "kenapa berita jenis ini penting" berdasarkan kategori.
       Bukan ringkasan artikelnya - lihat catatan di bagian atas file ini. #>
    param([string]$Category)
    foreach ($r in $Script:NewsRules) {
        if ($r.Cat -eq $Category) { return $r.Why }
    }
    return 'Berita umum seputar pasar saham AS. Klik judulnya untuk membaca isi lengkapnya.'
}

function Get-NewsTone {
    <# Tebakan kasar nada berita dari kata kunci di judul.
       Sangat sederhana - jangan dijadikan dasar keputusan. #>
    param([string]$Title)
    $t = $Title.ToLower()
    $up = 'surge|soar|jump|rally|beat|beats|record high|upgrade|rise|rises|gain|gains|climb|boost|strong|top estimates|raises guidance|breakthrough'
    $dn = 'plunge|plummet|sink|slump|tumble|crash|miss|misses|downgrade|fall|falls|drop|drops|slide|weak|cut|cuts|warns|warning|layoff|bankruptcy|selloff|lawsuit|probe'
    $isUp = ($t -match $up)
    $isDn = ($t -match $dn)
    if ($isUp -and -not $isDn) { return 'positif' }
    if ($isDn -and -not $isUp) { return 'negatif' }
    return 'netral'
}

function Get-MacroNews {
    <# Kumpulan berita makro & pasar secara keseluruhan. #>
    param([int]$PerFeed = 18)

    $feeds = @(
        @{ Url = 'https://www.cnbc.com/id/20910258/device/rss/rss.html'; Src = 'CNBC Economy' }
        @{ Url = 'https://www.cnbc.com/id/20409666/device/rss/rss.html'; Src = 'CNBC Markets' }
        @{ Url = 'https://www.cnbc.com/id/100003114/device/rss/rss.html'; Src = 'CNBC Top News' }
        @{ Url = 'https://finance.yahoo.com/news/rssindex';               Src = 'Yahoo Finance' }
        @{ Url = 'https://news.google.com/rss/search?q=federal+reserve+interest+rates&hl=en-US&gl=US&ceid=US:en'; Src = 'Google News' }
        @{ Url = 'https://news.google.com/rss/search?q=us+stock+market+today&hl=en-US&gl=US&ceid=US:en';          Src = 'Google News' }
    )

    $all = New-Object System.Collections.ArrayList
    foreach ($f in $feeds) {
        $items = Get-RssFeed -Url $f.Url -Source $f.Src -Scope 'Makro' -Max $PerFeed
        foreach ($it in $items) { [void]$all.Add($it) }
    }
    return $all
}

function Get-EarningsNews {
    <# Berita seputar laporan keuangan. #>
    param([int]$Max = 20)
    return (Get-RssFeed -Url 'https://www.cnbc.com/id/15839135/device/rss/rss.html' `
                        -Source 'CNBC Earnings' -Scope 'Laporan' -Max $Max)
}

function Remove-DuplicateNews {
    <# Buang berita kembar. Judul yang sama sering muncul di beberapa feed. #>
    param($Items)
    $seen = @{}
    $out = New-Object System.Collections.ArrayList
    foreach ($it in $Items) {
        # Kunci: 60 karakter pertama judul, huruf dan angka saja.
        $key = ($it.Title.ToLower() -replace '[^a-z0-9]', '')
        if ($key.Length -gt 60) { $key = $key.Substring(0, 60) }
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$out.Add($it)
    }
    return $out
}
