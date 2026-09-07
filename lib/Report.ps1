# Report.ps1 - Membuat dashboard screener saham AS (satu file HTML, offline).

function New-ScreenerReport {
    param(
        [Parameter(Mandatory)] $Results,
        [Parameter(Mandatory)] [string]$OutPath,
        $Meta
    )

    $payload = [pscustomobject]@{
        Meta   = $Meta
        Stocks = $Results
    }
    $json = $payload | ConvertTo-Json -Depth 6 -Compress

    $template = @'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Screener Saham AS</title>
<style>
  :root{
    --bg:#0b0f16; --panel:#121926; --panel2:#182234; --line:#243044;
    --tx:#e6edf7; --dim:#8b9bb4; --dim2:#5f7a99;
    --up:#2ecc71; --down:#ff5c5c; --warn:#f0b429; --acc:#4aa3ff;
  }
  *{box-sizing:border-box}
  /* Atribut hidden kalah dari aturan display di bawah, jadi dipaksa di sini. */
  [hidden]{display:none!important}
  body{margin:0;background:var(--bg);color:var(--tx);
       font:14px/1.55 "Segoe UI",system-ui,-apple-system,sans-serif}
  a{color:var(--acc)}
  .wrap{max-width:1500px;margin:0 auto;padding:20px 18px 70px}

  header{border-bottom:1px solid var(--line);padding-bottom:16px;margin-bottom:18px}
  h1{margin:0 0 4px;font-size:22px;letter-spacing:.2px}
  .sub{color:var(--dim);font-size:12.5px}
  .status{display:flex;flex-wrap:wrap;gap:8px;margin-top:12px}
  .chip{background:var(--panel);border:1px solid var(--line);border-radius:20px;
        padding:5px 13px;font-size:12px;color:var(--dim)}
  .chip b{color:var(--tx);font-weight:600}
  .chip.open{border-color:#1f6b3f;background:#0f2418;color:#7fe0a5}

  .apps{display:flex;gap:7px;margin:14px 0 0}
  .apps a{flex:1;text-align:center;background:var(--panel);border:1px solid var(--line);
          border-radius:9px;padding:10px 14px;font-size:13.5px;color:var(--dim);
          font-weight:600;text-decoration:none}
  .apps a.on{background:var(--panel2);color:var(--tx);border-color:var(--acc)}
  .apps a:hover{border-color:var(--acc)}

  .tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(120px,1fr));gap:10px;margin:16px 0 18px}
  .tile{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px 14px}
  .tile .n{font-size:23px;font-weight:700;line-height:1.1}
  .tile .l{font-size:11px;color:var(--dim);text-transform:uppercase;letter-spacing:.6px;margin-top:3px}

  .bar{background:var(--panel);border:1px solid var(--line);border-radius:10px;
       padding:12px;display:flex;flex-wrap:wrap;gap:9px;align-items:center;margin-bottom:16px}
  input,select{background:var(--panel2);color:var(--tx);border:1px solid var(--line);
               border-radius:7px;padding:8px 11px;font-size:13px;font-family:inherit}
  input:focus,select:focus{outline:none;border-color:var(--acc)}
  input[type=search]{min-width:210px;flex:1}
  .bar label{font-size:11.5px;color:var(--dim);margin-right:-4px}

  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(400px,1fr));gap:13px}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:12px;
        padding:15px 16px;display:flex;flex-direction:column;gap:11px}
  .card:hover{border-color:#31415c}

  .top{display:flex;justify-content:space-between;align-items:flex-start;gap:10px}
  .tk{font-size:19px;font-weight:700;letter-spacing:.3px}
  .nm{font-size:12px;color:var(--dim);margin-top:1px;max-width:230px}
  .px{text-align:right;white-space:nowrap}
  .px .v{font-size:19px;font-weight:700}
  .px .idr{font-size:11px;color:var(--dim)}
  .px .d{font-size:12.5px;font-weight:600;margin-top:1px}

  .badges{display:flex;flex-wrap:wrap;gap:6px}
  .b{font-size:10.5px;font-weight:700;padding:3px 9px;border-radius:5px;
     letter-spacing:.4px;text-transform:uppercase}
  .b-strongbuy{background:#0d3d24;color:#5ee89b;border:1px solid #1c6b41}
  .b-buy{background:#0f3320;color:#4cd484;border:1px solid #1a5c39}
  .b-akumulasi{background:#123043;color:#6cc6f5;border:1px solid #1d5a7a}
  .b-spekulatif{background:#3a2f10;color:#f0c04a;border:1px solid #6b551a}
  .b-pantau{background:#232c3b;color:#9db2ce;border:1px solid #35435c}
  .b-hindari{background:#3a1717;color:#ff8080;border:1px solid #6b2626}
  .b-soft{background:var(--panel2);color:var(--dim);border:1px solid var(--line);
          font-weight:600;text-transform:none;letter-spacing:0}

  .scores{display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px}
  .sc{background:var(--panel2);border-radius:8px;padding:8px 10px;text-align:center}
  .sc .v{font-size:17px;font-weight:700}
  .sc .l{font-size:10px;color:var(--dim);text-transform:uppercase;letter-spacing:.5px}

  .plan{background:var(--panel2);border-radius:8px;padding:11px 12px}
  .plan .row{display:flex;justify-content:space-between;gap:10px;padding:3px 0;font-size:12.5px}
  .plan .row span:first-child{color:var(--dim)}
  .plan .row b{font-weight:600;font-variant-numeric:tabular-nums}
  .plan .hr{height:1px;background:var(--line);margin:7px 0}
  .plan .note{font-size:11px;color:var(--dim);margin-top:6px;line-height:1.45}

  .why{font-size:12.5px;line-height:1.55}
  .why div{padding:2px 0 2px 15px;position:relative}
  .why .g:before{content:"+";position:absolute;left:0;color:var(--up);font-weight:700}
  .why .r:before{content:"!";position:absolute;left:0;color:var(--down);font-weight:700}

  .earn{background:#2e2410;border:1px solid #6b551a;border-radius:7px;
        padding:8px 11px;font-size:12px;color:#f0c04a}

  .up{color:var(--up)} .down{color:var(--down)} .dim{color:var(--dim)}
  .more{display:block;margin:22px auto 0;background:var(--panel);color:var(--tx);
        border:1px solid var(--line);border-radius:8px;padding:11px 26px;
        font-size:13.5px;cursor:pointer;font-family:inherit}
  .more:hover{border-color:var(--acc)}
  .empty{text-align:center;color:var(--dim);padding:50px 20px}
  footer{margin-top:36px;padding-top:16px;border-top:1px solid var(--line);
         color:var(--dim);font-size:11.5px;line-height:1.7}
  /* --- Layar ponsel --- */
  /* Di layar sempit, label dan kotak filter yang berjajar jadi berantakan.
     Filternya diubah jadi dua kolom rapi dan labelnya disembunyikan - nama
     tiap filter sudah ikut tertulis di pilihan pertamanya ("Semua sinyal", dst). */
  @media(max-width:560px){
    .grid{grid-template-columns:1fr}
    .wrap{padding:14px 11px 60px}
    .bar{display:grid;grid-template-columns:1fr 1fr;gap:8px}
    .bar label{display:none}
    .bar select{width:100%}
    .bar input[type=search]{grid-column:1 / -1;min-width:0;width:100%}
    .tiles{grid-template-columns:repeat(3,1fr);gap:7px}
    .tile{padding:9px 10px}
    .tile .n{font-size:19px}
    .tile .l{font-size:9.5px;letter-spacing:.3px}
    h1{font-size:19px}
  }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>Screener Saham Amerika Serikat</h1>
    <div class="sub">Analisa fundamental + teknikal otomatis. Semua angka dari Yahoo Finance.</div>
    <div class="status" id="status"></div>
    <nav class="apps">
      <a href="index.html" class="on">Screener</a>
      <a href="berita.html">Berita &amp; Agenda</a>
    </nav>
  </header>

  <div class="tiles" id="tiles"></div>

  <div class="bar">
    <input type="search" id="q" placeholder="Cari kode atau nama perusahaan...">
    <label>Sinyal</label>
    <select id="fsig">
      <option value="">Semua sinyal</option>
      <option value="STRONG BUY">STRONG BUY</option>
      <option value="BUY">BUY</option>
      <option value="AKUMULASI">AKUMULASI</option>
      <option value="SPEKULATIF">SPEKULATIF</option>
      <option value="PANTAU">PANTAU</option>
      <option value="HINDARI">HINDARI</option>
      <option value="_beli">STRONG BUY + BUY</option>
    </select>
    <label>Gaya</label>
    <select id="fstyle">
      <option value="">Semua gaya</option>
      <option value="Investasi">Investasi</option>
      <option value="Swing Trade">Swing Trade</option>
      <option value="Day Trade">Day Trade</option>
    </select>
    <label>Jenis</label>
    <select id="fgrp">
      <option value="">Saham + ETF</option>
      <option value="_saham">Saham saja</option>
      <option value="ETF">ETF saja</option>
    </select>
    <label>Sektor</label>
    <select id="fsec"><option value="">Semua sektor</option></select>
    <label>Urut</label>
    <select id="sort">
      <option value="_signal">Sinyal terbaik</option>
      <option value="combined">Skor gabungan</option>
      <option value="tech">Skor teknikal</option>
      <option value="fund">Skor fundamental</option>
      <option value="netRR">Risk/Reward bersih</option>
      <option value="chg1d">Perubahan harian</option>
      <option value="chg3m">Perubahan 3 bulan</option>
      <option value="marketCap">Kapitalisasi pasar</option>
      <option value="code">Kode A-Z</option>
    </select>
  </div>

  <div class="grid" id="grid"></div>
  <button class="more" id="more" hidden>Tampilkan lebih banyak</button>
  <div class="empty" id="empty" hidden>Tidak ada saham yang cocok dengan filter ini.</div>

  <footer>
    <b>Bukan rekomendasi jual/beli.</b> Angka di halaman ini hasil hitungan otomatis
    dari data historis dan bisa saja salah atau tertinggal. Keputusan investasi
    sepenuhnya tanggung jawab Anda. Selalu periksa ulang harga dan berita terbaru
    sebelum memasang order.
    <br>Biaya transaksi yang dipakai untuk menghitung hasil bersih adalah
    <b>perkiraan</b> - sesuaikan di <code>lib\Config.ps1</code> dengan tarif asli aplikasi Anda.
  </footer>
</div>

<script>
const DATA = __DATA__;
const S = DATA.Stocks || [];
const M = DATA.Meta || {};
const PAGE = 24;
const SIGRANK = {"STRONG BUY":0,"BUY":1,"AKUMULASI":2,"SPEKULATIF":3,"PANTAU":4,"HINDARI":5};
let shown = PAGE, view = [];

const $ = id => document.getElementById(id);
const esc = s => String(s==null?"":s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const arr = x => x==null ? [] : (Array.isArray(x)?x:[x]);

function usd(v,d){
  if(v==null||isNaN(v)) return "-";
  return "$"+Number(v).toLocaleString("en-US",{minimumFractionDigits:d==null?2:d,maximumFractionDigits:d==null?2:d});
}
function idr(v){
  if(v==null||isNaN(v)) return "";
  return "Rp "+Number(v).toLocaleString("id-ID",{maximumFractionDigits:0});
}
function num(v,d){
  if(v==null||isNaN(v)) return "-";
  return Number(v).toLocaleString("id-ID",{minimumFractionDigits:d||0,maximumFractionDigits:d||0});
}
function pct(v,d){
  if(v==null||isNaN(v)) return "-";
  return (v>0?"+":"")+Number(v).toLocaleString("id-ID",{minimumFractionDigits:d==null?2:d,maximumFractionDigits:d==null?2:d})+"%";
}
function big(v){
  if(v==null||isNaN(v)) return "-";
  if(v>=1e12) return "$"+(v/1e12).toFixed(2)+" T";
  if(v>=1e9)  return "$"+(v/1e9).toFixed(1)+" M";
  if(v>=1e6)  return "$"+(v/1e6).toFixed(0)+" jt";
  return usd(v,0);
}
const cls = v => v==null?"":(v>0?"up":(v<0?"down":""));
function scoreColor(v){
  if(v>=70) return "var(--up)";
  if(v>=55) return "#8fd14f";
  if(v>=45) return "var(--warn)";
  return "var(--down)";
}

function initHeader(){
  const st = [];
  if(M.MarketState) st.push('<span class="chip'+(M.MarketOpen?' open':'')+'">'+esc(M.MarketState)+'</span>');
  if(M.OpenWib) st.push('<span class="chip">Jam bursa WIB <b>'+esc(M.OpenWib)+' - '+esc(M.CloseWib)+'</b></span>');
  if(M.GeneratedAt) st.push('<span class="chip">Data diambil <b>'+esc(M.GeneratedAt)+' WIB</b></span>');
  if(M.UsdIdr) st.push('<span class="chip">USD/IDR <b>'+num(M.UsdIdr,0)+'</b></span>');
  if(M.BenchmarkChg3m!=null) st.push('<span class="chip">'+esc(M.BenchmarkName)+' 3 bln <b class="'+cls(M.BenchmarkChg3m)+'">'+pct(M.BenchmarkChg3m,1)+'</b></span>');
  if(M.Scanned) st.push('<span class="chip">Dipindai <b>'+num(M.Scanned)+'</b> dari '+num(M.Universe)+'</span>');
  $("status").innerHTML = st.join("");

  const c = k => S.filter(s=>s.signal===k).length;
  const tiles = [
    ["STRONG BUY", c("STRONG BUY"), "var(--up)"],
    ["BUY", c("BUY"), "#4cd484"],
    ["Akumulasi", c("AKUMULASI"), "#6cc6f5"],
    ["Spekulatif", c("SPEKULATIF"), "var(--warn)"],
    ["Pantau", c("PANTAU"), "var(--dim)"],
    ["Hindari", c("HINDARI"), "var(--down)"]
  ];
  $("tiles").innerHTML = tiles.map(t=>
    '<div class="tile"><div class="n" style="color:'+t[2]+'">'+t[1]+'</div><div class="l">'+t[0]+'</div></div>'
  ).join("");

  const secs = [...new Set(S.map(s=>s.sector).filter(Boolean))].sort();
  $("fsec").innerHTML = '<option value="">Semua sektor</option>' + secs.map(s=>'<option>'+esc(s)+'</option>').join("");
}

function render(){
  const q = $("q").value.trim().toLowerCase();
  const fs = $("fsig").value, fst = $("fstyle").value, fg = $("fgrp").value, fsec = $("fsec").value;
  const sort = $("sort").value;

  view = S.filter(s=>{
    if(q && !(s.code.toLowerCase().includes(q) || (s.name||"").toLowerCase().includes(q))) return false;
    if(fs==="_beli"){ if(s.signal!=="STRONG BUY" && s.signal!=="BUY") return false; }
    else if(fs && s.signal!==fs) return false;
    if(fst && s.style!==fst) return false;
    if(fg==="ETF" && !s.isEtf) return false;
    if(fg==="_saham" && s.isEtf) return false;
    if(fsec && s.sector!==fsec) return false;
    return true;
  });

  view.sort((a,b)=>{
    // Urutan bawaan: sinyal paling layak dibeli dulu, baru skor.
    // Saham berskor tinggi bisa saja bersinyal PANTAU karena harganya sudah
    // mepet resistance - bagus, tapi bukan titik masuk yang bagus HARI INI.
    if(sort==="_signal"){
      const ra = SIGRANK[a.signal], rb = SIGRANK[b.signal];
      const d = (ra===undefined?9:ra) - (rb===undefined?9:rb);
      if(d!==0) return d;
      return b.combined - a.combined;
    }
    if(sort==="code") return a.code.localeCompare(b.code);
    const av=a[sort], bv=b[sort];
    if(av==null) return 1;
    if(bv==null) return -1;
    return bv-av;
  });

  shown = PAGE;
  paint();
}

function paint(){
  const slice = view.slice(0, shown);
  $("grid").innerHTML = slice.map(card).join("");
  $("empty").hidden = view.length>0;
  $("more").hidden = shown>=view.length;
  $("more").textContent = "Tampilkan lebih banyak ("+(view.length-shown)+" lagi)";
}

function lvl(label, price, sub, color){
  return '<div class="row"><span>'+label+(sub?' <span class="dim">'+sub+'</span>':'')+
         '</span><b'+(color?' style="color:'+color+'"':'')+'>'+usd(price)+'</b></div>';
}

function card(s){
  const notes = arr(s.notes).slice(0,4).map(n=>'<div class="g">'+esc(n)+'</div>').join("");
  const flags = arr(s.flags).slice(0,4).map(n=>'<div class="r">'+esc(n)+'</div>').join("");
  const sigCls = "b-"+String(s.signal||"").toLowerCase().replace(/\s+/g,"");

  let head = '<div class="top"><div>'+
    '<div class="tk">'+esc(s.code)+'</div>'+
    '<div class="nm">'+esc(s.name||"")+'</div></div>'+
    '<div class="px"><div class="v">'+usd(s.price)+'</div>'+
    (s.priceIdr?'<div class="idr">'+idr(s.priceIdr)+'</div>':'')+
    '<div class="d '+cls(s.chg1d)+'">'+pct(s.chg1d)+' hari ini</div></div></div>';

  let badges = '<div class="badges">'+
    '<span class="b '+sigCls+'">'+esc(s.signal)+'</span>'+
    '<span class="b b-soft">'+esc(s.style)+' &middot; '+esc(s.hold)+'</span>'+
    // Untuk ETF, sektornya memang selalu "ETF" - tidak perlu ditampilkan dua kali.
    (s.isEtf?'<span class="b b-soft">ETF</span>'
            :(s.sector?'<span class="b b-soft">'+esc(s.sector)+'</span>':''))+
    '</div>';

  let scores = '<div class="scores">'+
    '<div class="sc"><div class="v" style="color:'+scoreColor(s.combined)+'">'+num(s.combined,1)+'</div><div class="l">Gabungan</div></div>'+
    '<div class="sc"><div class="v" style="color:'+scoreColor(s.tech)+'">'+num(s.tech,1)+'</div><div class="l">Teknikal</div></div>'+
    '<div class="sc"><div class="v" style="color:'+scoreColor(s.fund)+'">'+num(s.fund,1)+'</div><div class="l">Fundamental</div></div>'+
    '</div>';

  let plan = '<div class="plan">'+
    '<div class="row"><span>Area beli</span><b>'+usd(s.entryLo)+' - '+usd(s.entryHi)+'</b></div>'+
    lvl("Stop loss", s.sl, "("+pct(-s.riskPct,1)+")", "var(--down)")+
    lvl("Target 1", s.tp1, "("+pct(s.rewardPct,1)+")", "var(--up)")+
    lvl("Target 2", s.tp2, "", "var(--up)")+
    (s.tp3!=null?lvl("Target 3", s.tp3, "", "var(--up)"):"")+
    '<div class="hr"></div>'+
    '<div class="row"><span>Risk/Reward bersih</span><b style="color:'+(s.netRR>=1.5?"var(--up)":(s.netRR>=1?"var(--warn)":"var(--down)"))+'">'+num(s.netRR,2)+' : 1</b></div>'+
    '<div class="row"><span>Untung bersih di TP1</span><b class="'+cls(s.netTP1)+'">'+pct(s.netTP1)+'</b></div>'+
    '<div class="row"><span>Balik modal di harga</span><b>'+usd(s.breakEven)+'</b></div>'+
    '<div class="note">Stop loss: '+esc(s.slBasis)+'. Target: '+esc(s.tpBasis)+'.<br>'+
    'Biaya + spread kurs memakan '+num(s.feeBite,0)+'% dari potensi untung di TP1.</div>'+
    '</div>';

  const stats = '<div class="plan"><div class="row"><span>RSI / ADX / ATR</span><b>'+
    num(s.rsi,0)+' &middot; '+num(s.adx,0)+' &middot; '+num(s.atrPct,1)+'%</b></div>'+
    '<div class="row"><span>Volume vs rata-rata</span><b>'+num(s.volRatio,2)+'x</b></div>'+
    '<div class="row"><span>Nilai transaksi/hari</span><b>'+big(s.avgValue)+'</b></div>'+
    (s.marketCap?'<div class="row"><span>Kapitalisasi pasar</span><b>'+big(s.marketCap)+'</b></div>':'')+
    (s.per?'<div class="row"><span>PER / PBV</span><b>'+num(s.per,1)+'x &middot; '+(s.pbv?num(s.pbv,2)+'x':'-')+'</b></div>':'')+
    (s.roe!=null?'<div class="row"><span>ROE / Margin bersih</span><b>'+pct(s.roe*100,1)+' &middot; '+(s.netMargin!=null?pct(s.netMargin*100,1):'-')+'</b></div>':'')+
    (s.divYield?'<div class="row"><span>Dividend yield</span><b>'+pct(s.divYield*100,2)+'</b></div>':'')+
    '<div class="row"><span>vs '+esc(M.BenchmarkName||"S&P 500")+' (3 bln)</span><b class="'+cls(s.relStrength)+'">'+pct(s.relStrength,1)+'</b></div>'+
    (s.targetMean?'<div class="row"><span>Target analis (rata-rata)</span><b>'+usd(s.targetMean)+'</b></div>':'')+
    '</div>';

  const earn = s.earningsWarn
    ? '<div class="earn"><b>Perhatian:</b> '+esc(s.earningsWarn)+'</div>'
    : (s.earningsDate?'<div class="plan"><div class="row"><span>Laporan keuangan berikutnya</span><b>'+esc(s.earningsDate)+'</b></div></div>':'');

  const why = (notes||flags) ? '<div class="why">'+notes+flags+'</div>' : '';
  const etf = s.etfDesc ? '<div class="why"><div class="g">'+esc(s.etfDesc)+'</div></div>' : '';

  return '<div class="card">'+head+badges+scores+etf+plan+earn+stats+why+'</div>';
}

["q","fsig","fstyle","fgrp","fsec","sort"].forEach(id=>{
  $(id).addEventListener(id==="q"?"input":"change", render);
});
$("more").addEventListener("click", ()=>{ shown+=PAGE; paint(); });

initHeader();
render();
</script>
</body>
</html>
'@

    $html = $template.Replace('__DATA__', $json)
    $dir = Split-Path -Parent $OutPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    Set-Content -Path $OutPath -Value $html -Encoding UTF8
}
