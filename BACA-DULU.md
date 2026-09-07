# Screener & Berita Saham Amerika Serikat

Dua alat untuk belajar dan memantau saham AS, berjalan sepenuhnya di komputer Anda.
Tanpa Python, tanpa Node, tanpa API key, tanpa langganan. Cukup PowerShell bawaan Windows.

| Alat | Isi | Hasil | Lama |
|---|---|---|---|
| **Screener** | 609 saham (S&P 500 + Nasdaq-100 + 42 ETF), skor fundamental + teknikal, rencana SL/TP | `output\index.html` | ~35 menit |
| **Berita** | Berita makro & per saham, dikelompokkan per tema + agenda laporan keuangan | `output\berita.html` | ~30 detik |

---

## 1. Cara pakai

### Perbarui semuanya sekarang
Klik dua kali **`Update.bat`**. Screener jalan dulu (~35 menit), lalu berita (~30 detik),
lalu kedua dashboard terbuka otomatis.

### Cuma mau berita (cepat)
Klik dua kali **`Berita.bat`**.

### Lewat PowerShell

```bash
powershell -ExecutionPolicy Bypass -File .\Run-Screener.ps1
```

```bash
powershell -ExecutionPolicy Bypass -File .\Run-News.ps1
```

| Parameter | Fungsi |
|---|---|
| `-Limit 30` | Screener: hanya pindai 30 saham pertama (untuk uji coba cepat) |
| `-MinScore 60` | Screener: hanya tampilkan saham dengan skor gabungan di atas 60 |
| `-NoOpen` | Jangan buka dashboard otomatis setelah selesai |
| `-Watchlist AAPL,NVDA` | Berita: ikuti saham tertentu saja |
| `-TopN 20` | Berita: ambil 20 saham terbaik dari screener (default 12) |

### Perbarui daftar saham
Daftar S&P 500 berubah beberapa nama per tahun. Sesekali (sebulan sekali cukup):

```bash
powershell -ExecutionPolicy Bypass -File .\Update-Universe.ps1
```

---

## 2. Jadwal otomatis harian

Bursa AS tutup pukul **03.00–04.00 WIB**. Jadi paling enak alatnya jalan sendiri pagi hari,
saat data semalam sudah lengkap.

Buka PowerShell **sebagai Administrator**, lalu:

```bash
powershell -ExecutionPolicy Bypass -File .\Install-Schedule.ps1
```

Ini memasang dua tugas di Windows Task Scheduler:

- **Screener** — tiap Senin–Jumat pukul 06.30 WIB
- **Berita** — tiap Senin–Jumat pukul 06.45 dan 19.00 WIB

Kalau komputer sedang mati saat jadwalnya lewat, Windows menjalankannya begitu komputer menyala.

Ganti jamnya: `.\Install-Schedule.ps1 -ScreenerTime 05:30 -NewsTime 05:45`
Matikan jadwal: `.\Install-Schedule.ps1 -Remove`

---

## 3. Membuka dari HP Android

Kedua dashboard sudah terbit di internet:

| | Alamat |
|---|---|
| **Screener** | https://mapleapple03.github.io/us-screener/ |
| **Berita & Agenda** | https://mapleapple03.github.io/us-screener/berita.html |

Di dalam dashboard ada tombol **Screener** dan **Berita & Agenda** di bagian atas,
jadi cukup simpan satu alamat saja — berpindah tinggal satu ketukan.

### Pasang di layar utama HP (jadi seperti aplikasi)

1. Buka alamat di atas lewat **Chrome** di HP
2. Ketuk menu **tiga titik** di pojok kanan atas
3. Pilih **"Add to Home screen"** / **"Tambahkan ke layar utama"**

Ikonnya (garis biru naik dengan titik hijau) akan muncul di layar utama dan terbuka
layar penuh tanpa address bar. Ikonnya sengaja dibedakan dari screener IDX Anda yang
memakai ikon batang hijau.

### Memperbarui isi situs

Situs **tidak** ikut ter-update sendiri saat screener jalan di komputer. Setelah
`Update.bat` selesai, unggah hasilnya:

```bash
powershell -ExecutionPolicy Bypass -File .\Publish-Web.ps1 -Push
```

Perubahan tampil di HP sekitar 1–2 menit kemudian. Kalau halaman di HP masih versi
lama, tarik ke bawah untuk refresh.

Mau otomatis tiap hari? Tambahkan baris itu ke akhir `Update.bat`, atau jalankan
`Publish-Web.ps1 -Push` lewat Task Scheduler beberapa menit setelah screener selesai.

### Catatan privasi

Repositori `us-screener` bersifat **publik** — itu syarat GitHub Pages gratis.
Siapa pun yang tahu alamatnya bisa membuka dashboard Anda, termasuk melihat daftar
saham pantauan. Isinya hanya olahan data pasar yang memang sudah publik: tidak ada
data akun, saldo, atau posisi Anda di dalamnya.

Yang **tidak** ikut terunggah (sudah dikecualikan lewat `.gitignore`):
`output\`, `data\universe.json`, dan `data\latest.json`.

### Kalau tidak mau ada di internet

Ada pilihan lain yang sepenuhnya privat — server kecil di WiFi rumah Anda:

```bash
powershell -ExecutionPolicy Bypass -File .\Serve-Local.ps1
```

Skrip akan menampilkan alamat seperti `http://192.168.1.5:8080/` untuk dibuka di HP.
Syaratnya: komputer menyala, HP di WiFi yang sama, dan PowerShell dijalankan
**sebagai Administrator** (kalau tidak, hanya bisa dibuka di komputer itu sendiri).
Tidak bisa dipakai dari kantor atau lewat kuota internet.

---

## 4. WAJIB DIBACA: biaya transaksi masih perkiraan

Angka biaya di `lib\Config.ps1` **bukan tarif resmi Pluang** — saya tidak bisa
memverifikasinya dari komputer Anda. Yang dipakai sekarang:

```
FEE_BUY_PCT   = 0.10 %    biaya beli
FEE_SELL_PCT  = 0.10 %    biaya jual
FX_SPREAD_PCT = 0.25 %    spread kurs USD/IDR, sekali arah
```

**Buka aplikasi Pluang → menu Biaya, lalu samakan angkanya.** Kalau salah, kolom
"Untung bersih di TP1", "Risk/Reward bersih", dan "Balik modal di harga" ikut salah.

Untuk saham AS dari Indonesia ada **dua lapis biaya** yang sering terlewat:

1. **Fee transaksi** — persentase dari nilai order
2. **Spread kurs USD/IDR** — selisih kurs saat rupiah Anda ditukar ke dolar dan sebaliknya.
   Ini sering **lebih besar** daripada fee transaksinya sendiri, tapi tidak kelihatan
   karena tidak muncul sebagai "biaya" di layar.

Screener menghitung keduanya. Kolom "Biaya + spread kurs memakan X% dari potensi untung"
di tiap kartu menunjukkan seberapa besar gigitannya.

---

## 4. Belajar: apa bedanya pasar AS dengan IDX

Ini bagian terpenting kalau Anda baru pindah dari saham Indonesia.

### Jam & mekanisme

| | IDX | Amerika Serikat |
|---|---|---|
| Jam bursa (WIB) | 09.00–15.49 | **20.30–03.00** (Mar–Nov) / **21.30–04.00** (Nov–Mar) |
| Satuan beli | 1 lot = 100 lembar | **1 lembar**, bahkan bisa pecahan di Pluang |
| Fraksi harga | Bertingkat (Rp 1 / 2 / 5 / 10 / 25) | **$0,01** untuk semua saham di atas $1 |
| Batas naik/turun harian | ARA / ARB | **Tidak ada** batas per saham. Saham bisa turun 30% dalam sehari |
| Penyelesaian dana | T+2 | T+1 |

Jam bursa AS bergeser satu jam dua kali setahun karena di sana ada waktu musim panas
(*daylight saving time*). Dashboard selalu menampilkan jam bursa dalam WIB yang sudah benar,
jadi tidak perlu Anda hitung sendiri.

**Konsekuensi paling praktis:** bursa AS buka saat Anda tidur. Day trade saham AS dari
Indonesia berarti begadang tiap malam. Karena itu screener ini sengaja **menurunkan skor
gaya "Day Trade"** dan lebih sering menyarankan Swing Trade atau Investasi.

### Tidak ada ARA/ARB — ini penting

Di IDX, saham yang jatuh berhenti di batas ARB. Di AS **tidak ada rem itu**. Kalau laporan
keuangan mengecewakan, saham bisa dibuka esok harinya 20% lebih rendah — dan **stop loss
Anda terlewati begitu saja**, karena harga *melompat* (gap), bukan bergerak turun perlahan
melewati angka stop Anda.

Ini alasan screener memberi peringatan kuning kalau laporan keuangan tinggal ≤ 7 hari lagi,
dan otomatis menurunkan sinyal belinya.

### Risiko kurs: keuntungan Anda ada dua lapis

Saham AS dibeli pakai dolar. Jadi hasil akhir dalam rupiah = **gerak saham × gerak kurs**.

- Saham naik 10%, rupiah melemah terhadap dolar → untung Anda **lebih dari** 10%
- Saham naik 10%, rupiah menguat 8% → untung Anda tinggal sekitar 2%

Ini pedang bermata dua, bukan bonus. Dashboard menampilkan harga dalam USD **dan** rupiah
memakai kurs terkini supaya terasa nyata.

### Pajak dividen

Dividen dari saham AS dipotong pajak oleh pemerintah AS untuk investor asing. Tarif
umumnya **30%**, dan bisa lebih rendah kalau ada perjanjian pajak antara Indonesia dan AS
serta formulir **W-8BEN** sudah Anda isi. **Tanyakan ke Pluang** bagaimana penanganannya
di aplikasi mereka — screener ini tidak menghitung pajak dividen.

### Valuasi terlihat "mahal", dan itu normal

PER 30x di IDX terdengar mahal. Di AS itu biasa. Pasar AS menghargai perusahaannya lebih
tinggi karena pertumbuhan, likuiditas, dan jangkauan pasarnya lebih besar. Screener ini
sudah memakai **patokan AS**, bukan patokan IDX:

| | Murah | Mahal |
|---|---|---|
| PER | di bawah 12x | di atas 45x |
| PBV | di bawah 1,5x | di atas 12x |
| Dividend yield | 4% sudah bagus | — |

Kalau memakai patokan IDX, hampir semua saham AS akan terlihat mahal dan skornya jadi
tidak berguna. Angka-angka ini bisa Anda ubah di `lib\Config.ps1`.

### Dividen kecil bukan berarti pelit

Perusahaan AS lebih sering mengembalikan uang lewat **buyback** (membeli sahamnya sendiri)
daripada dividen. Buyback mengurangi jumlah saham beredar, sehingga laba per saham naik dan
harga terdorong. Jadi dividend yield 0% di AS tidak sama artinya dengan di IDX.

### ETF: cara paling aman untuk memulai

ETF adalah **sekeranjang saham dalam satu kode**. Beli `SPY` sekali = ikut memiliki 500
perusahaan terbesar AS sekaligus. Risikonya jauh lebih tersebar daripada menaruh semua
uang di satu emiten.

Screener memberi label `ETF` dan **tidak menilai fundamentalnya** — rasio seperti ROE atau
DER tidak berarti untuk sekeranjang saham, jadi memaksakan penilaian itu hanya akan
menghasilkan angka yang menyesatkan.

42 ETF di daftar sudah diberi penjelasan singkat di dashboard. Beberapa yang menarik untuk
Anda: `EIDO` (saham Indonesia di bursa AS), `SPY`/`VOO` (S&P 500), `QQQ` (teknologi),
`SCHD` (fokus dividen).

---

## 5. Cara membaca dashboard screener

### Sinyal

| Sinyal | Artinya |
|---|---|
| **STRONG BUY** | Teknikal ≥ 72 dan fundamental ≥ 62. Tren dan laporan keuangan sama-sama mendukung |
| **BUY** | Teknikal ≥ 62 dan fundamental ≥ 50 |
| **AKUMULASI** | Fundamental sangat bagus (≥ 68) tapi tren belum kencang. Cocok dicicil |
| **SPEKULATIF** | Teknikal bagus, fundamental biasa saja. Risiko lebih tinggi |
| **PANTAU** | Belum saatnya. Masukkan watchlist dulu |
| **HINDARI** | Teknikal atau fundamentalnya lemah |

Sinyal **diturunkan otomatis** kalau: risk/reward bersih di bawah 1,2 : 1, tren mingguan
masih turun, atau laporan keuangan tinggal ≤ 7 hari lagi.

### Tiga skor

- **Teknikal (0–100)** — tren (30) + momentum (25) + kekuatan tren (15) + volume (15) + kualitas entry (15),
  ditambah bonus kalau saham mengungguli S&P 500 dalam 3 bulan
- **Fundamental (0–100)** — valuasi, profitabilitas, pertumbuhan, kesehatan neraca, dividen
- **Gabungan** — 55% teknikal + 45% fundamental

Metrik yang datanya kosong **tidak menghukum** skor; pembaginya menyesuaikan otomatis.

### Rencana trading

Tiap kartu memberi **area beli**, **stop loss**, dan **2–3 target**, semuanya sudah
dibulatkan ke sen. Yang perlu diperhatikan:

- **Risk/Reward bersih** — sudah dipotong fee dan spread kurs. Di bawah 1 : 1 artinya
  potensi ruginya lebih besar daripada potensi untungnya. Jangan diambil.
- **Balik modal di harga** — harga jual minimum supaya Anda tidak rugi setelah semua biaya.
  Angkanya selalu **di atas** harga beli.
- **Biaya memakan X%** — makin kecil target Anda, makin besar porsi yang dimakan biaya.

### Kekuatan relatif vs S&P 500

Indeks AS sendiri cenderung naik terus. Jadi saham yang cuma "ikut arus" sebenarnya tidak
memberi nilai tambah dibanding beli ETF `SPY` saja — lebih murah dan lebih aman. Kolom
"vs S&P 500 (3 bln)" menunjukkan apakah saham itu benar-benar lebih baik daripada indeksnya.

---

## 6. Cara membaca dashboard berita

Tiga tab:

1. **Berita per Tema** — dikelompokkan jadi 15 tema (Suku Bunga & The Fed, Inflasi,
   Laporan Keuangan, Teknologi & AI, Geopolitik, dst). Tiap tema punya kotak biru
   **"Apa artinya buat investor"**.
2. **Saham Pantauan** — berita khusus saham di `data\watchlist.txt`.
3. **Agenda Laporan Keuangan** — tanggal laporan 30 hari ke depan, dengan hitung mundur.
   Yang tinggal ≤ 7 hari ditandai kuning.

### Batas jujur soal penjelasan "Apa artinya"

Penjelasan itu **tidak ditulis oleh AI yang membaca artikelnya.** Teksnya dipilih dari
daftar tetap di `lib\News.ps1` berdasarkan **kata kunci di judul**. Jadi:

- Penjelasannya **benar untuk jenis beritanya** ("ini berita soal suku bunga, begini cara
  suku bunga memengaruhi saham")
- Penjelasannya **tidak tahu isi spesifik** artikel itu

Karena itu penjelasan ditampilkan **satu kali per tema**, bukan di bawah tiap judul —
supaya tidak terkesan merangkum artikel yang belum pernah dibaca.

Label **nada berita** (positif/negatif/netral) juga ditebak dari kata kunci judul, dan
sering meleset untuk judul yang memakai kiasan atau kalimat tanya. **Selalu klik judulnya
dan baca sendiri.**

### Mengatur saham pantauan

Edit `data\watchlist.txt` — satu kode per baris, baris berawalan `#` diabaikan.
Kalau semua baris Anda nonaktifkan, berita otomatis mengikuti **saham dengan sinyal beli
terbaik dari screener terakhir**.

---

## 7. Kamus singkat

| Istilah | Arti |
|---|---|
| **Ticker** | Kode saham, mis. `AAPL` untuk Apple |
| **PER** (P/E) | Harga dibagi laba per saham. Berapa tahun laba untuk balik modal |
| **PBV** (P/B) | Harga dibagi nilai buku. Di bawah 1 = dihargai lebih murah dari asetnya |
| **PEG** | PER dibagi laju pertumbuhan laba. Di bawah 1 = murah **relatif** terhadap pertumbuhannya |
| **EPS** | Laba bersih per lembar saham |
| **ROE** | Laba dibagi modal pemegang saham. Seberapa efisien uang investor diputar |
| **DER** | Utang dibanding modal. Makin tinggi makin berisiko |
| **Market cap** | Nilai seluruh perusahaan = harga × jumlah saham beredar |
| **Free cash flow** | Uang tunai sisa setelah semua biaya operasi dan investasi |
| **Earnings** | Laporan keuangan kuartalan. Keluar 4x setahun |
| **Guidance** | Ramalan manajemen untuk kuartal depan. Sering lebih menggerakkan harga daripada laba kuartal berjalan |
| **Gap** | Harga pembukaan melompat jauh dari penutupan kemarin. Stop loss bisa terlewati |
| **RSI** | 0–100. Di atas 70 dianggap kemahalan sesaat, di bawah 30 kemurahan sesaat |
| **MACD** | Pengukur momentum. "Golden cross" = momentum berbalik naik |
| **ADX** | Kekuatan tren, bukan arahnya. Di atas 25 = tren kuat, di bawah 15 = sideways |
| **ATR** | Rata-rata rentang gerak harian. Dipakai menentukan jarak stop loss yang wajar |
| **MA / EMA** | Rata-rata harga beberapa hari terakhir. MA200 = patokan tren jangka panjang |
| **Support / Resistance** | Harga tempat penurunan sering berhenti / kenaikan sering tertahan |
| **R:R** | Risk/Reward. 2:1 artinya potensi untung dua kali lipat potensi rugi |
| **ETF** | Sekeranjang saham dalam satu kode |
| **Buyback** | Perusahaan membeli sahamnya sendiri. Mengurangi saham beredar, mendorong EPS naik |
| **The Fed** | Bank sentral AS. Penentu suku bunga — penggerak pasar nomor satu |
| **CPI** | Data inflasi bulanan AS |

---

## 8. Yang alat ini TIDAK lakukan

- **Tidak memesan saham.** Murni analisa; Anda tetap memasang order sendiri di Pluang.
- **Tidak tahu berita hari ini saat menghitung skor.** Skor dihitung dari harga dan laporan
  keuangan. Saham bisa berskor tinggi pagi ini lalu jatuh malamnya karena berita buruk.
  Karena itu ada dashboard berita — pakai keduanya bersamaan.
- **Tidak membaca isi artikel berita.** Lihat bagian 6.
- **Tidak menghitung pajak dividen AS.**
- **Tidak memeriksa apakah suatu saham tersedia di Pluang.** Pluang hanya menyediakan
  sebagian saham AS. Cek di aplikasinya sebelum menyusun rencana.
- **Bukan rekomendasi jual/beli.** Semua hitungan otomatis dan bisa salah. Keputusan
  investasi sepenuhnya tanggung jawab Anda.

---

## 9. Struktur file

```
us-screener\
  Update.bat              Klik dua kali: perbarui screener + berita
  Berita.bat              Klik dua kali: perbarui berita saja (cepat)
  Run-Screener.ps1        Screener utama
  Run-News.ps1            Pengambil berita
  Update-Universe.ps1     Perbarui daftar S&P 500
  Install-Schedule.ps1    Pasang/hapus jadwal otomatis harian
  BACA-DULU.md            File ini
  lib\
    Config.ps1            >> SEMUA ANGKA YANG BOLEH DIUBAH ADA DI SINI <<
    Universe.ps1          Daftar saham + ETF
    MarketData.ps1        Pengambil data Yahoo Finance, jam bursa, kurs
    Indicators.ps1        RSI, MACD, ADX, ATR, Bollinger, support/resistance
    Analysis.ps1          Skoring, gaya trading, rencana SL/TP, sinyal
    News.ps1              RSS, pengelompokan tema, penjelasan
    Report.ps1            Pembuat dashboard screener
    NewsReport.ps1        Pembuat dashboard berita
  data\
    universe.json         Daftar 609 saham (hasil Update-Universe.ps1)
    latest.json           Hasil screener terakhir
    watchlist.txt         >> SAHAM YANG INGIN ANDA IKUTI BERITANYA <<
  output\
    index.html            Dashboard screener
    berita.html           Dashboard berita
```

---

## 10. Kalau ada masalah

**"running scripts is disabled on this system"**
Selalu jalankan lewat `Update.bat`, atau tambahkan `-ExecutionPolicy Bypass` seperti contoh di atas.

**Banyak saham gagal dipindai**
Yahoo membatasi jumlah permintaan kalau terlalu cepat. Jalankan ulang beberapa menit
kemudian; saham yang gagal biasanya berhasil di percobaan berikutnya.

**Kolom fundamental kosong (PER, ROE, dll)**
Yahoo kadang menolak permintaan data fundamental. Skor fundamental tetap dihitung dari
metrik yang tersedia. Untuk ETF ini normal dan memang disengaja.

**PBV / ROE kosong padahal perusahaannya besar**
Disengaja. Perusahaan dengan modal negatif (mis. karena buyback besar-besaran)
menghasilkan PBV dan ROE yang tidak masuk akal. Nilai di luar batas wajar diperlakukan
sebagai **data kosong**, bukan sebagai "sangat murah" — kalau tidak, skornya jadi menyesatkan.

**Jadwal otomatis tidak jalan**
Pasang ulang lewat PowerShell yang dijalankan **sebagai Administrator**.

**Berita kosong / sedikit**
Feed RSS kadang tidak bisa diakses. Jalankan ulang `Berita.bat`.
