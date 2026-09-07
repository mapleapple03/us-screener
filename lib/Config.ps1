# Config.ps1 - Semua angka yang boleh Anda ubah sendiri ada di file ini.
#
# Tidak ada bagian lain dari screener yang perlu disentuh. Kalau tarif Pluang
# berubah, atau Anda pindah broker, cukup edit baris-baris di bawah ini.

# ---------------------------------------------------------------------------
# 1. BIAYA TRANSAKSI SAHAM AS
# ---------------------------------------------------------------------------
# PENTING - ANGKA DI BAWAH INI ADALAH PERKIRAAN, BUKAN TARIF RESMI.
#
# Saya TIDAK bisa memverifikasi tarif Pluang saat ini dari komputer Anda.
# Silakan buka aplikasi Pluang -> menu Biaya (atau pluang.com/biaya), lalu
# samakan angka di bawah. Salah angka di sini = target profit bersih ikut salah.
#
# Untuk saham AS dari Indonesia ada DUA lapis biaya yang sering terlewat:
#   a. Fee transaksi saham (% dari nilai order)
#   b. Selisih kurs USD/IDR waktu top-up dan tarik dana (spread kurs)
# Keduanya dihitung terpisah supaya kelihatan mana yang paling menggerus profit.
$Global:FEE_BUY_PCT   = 0.10   # % biaya beli
$Global:FEE_SELL_PCT  = 0.10   # % biaya jual
$Global:FX_SPREAD_PCT = 0.25   # % spread kurs USD/IDR, sekali arah (masuk & keluar)

# Kurs USD/IDR untuk menampilkan harga dalam rupiah.
# Diisi otomatis dari Yahoo (IDR=X) setiap kali screener jalan.
# Angka di bawah hanya dipakai kalau pengambilan kurs gagal.
$Global:USDIDR_FALLBACK = 16300

# ---------------------------------------------------------------------------
# 2. AMBANG LIKUIDITAS (nilai transaksi harian rata-rata, dalam USD)
# ---------------------------------------------------------------------------
# Dipakai untuk menilai apakah saham cukup ramai untuk keluar-masuk posisi.
$Global:LIQ_EXCELLENT = 500e6   # sangat likuid
$Global:LIQ_GOOD      = 100e6
$Global:LIQ_OK        = 20e6
$Global:LIQ_MIN       = 5e6     # di bawah ini dianggap tipis

# ---------------------------------------------------------------------------
# 3. BATAS RISIKO PER GAYA TRADING (% dari harga)
# ---------------------------------------------------------------------------
# Stop loss tidak akan pernah lebih lebar dari angka ini.
$Global:MAXRISK_DAY   = 3.0
$Global:MAXRISK_SWING = 8.0
$Global:MAXRISK_POS   = 15.0

# ---------------------------------------------------------------------------
# 4. KALIBRASI VALUASI PASAR AS
# ---------------------------------------------------------------------------
# Saham AS wajar diperdagangkan di PER & PBV lebih tinggi daripada saham IDX.
# Memakai patokan IDX di sini akan membuat hampir semua saham AS terlihat
# "mahal", jadi rentangnya digeser sesuai kebiasaan pasar AS.
$Global:PER_BEST   = 12    # PER 12x ke bawah = murah untuk ukuran pasar AS
$Global:PER_WORST  = 45    # PER 45x ke atas = mahal
$Global:PBV_BEST   = 1.5
$Global:PBV_WORST  = 12.0
$Global:DIV_BEST   = 4.0   # % dividend yield yang dianggap bagus di AS
$Global:ROE_BEST   = 25.0  # %

# ---------------------------------------------------------------------------
# 5. BENCHMARK PASAR
# ---------------------------------------------------------------------------
$Global:US_BENCHMARK      = '^GSPC'   # S&P 500, untuk hitung kekuatan relatif
$Global:US_BENCHMARK_NAME = 'S&P 500'
