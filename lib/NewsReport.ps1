# NewsReport.ps1 - Membuat dashboard berita saham AS (satu file HTML, offline).

function New-NewsReport {
    param(
        [Parameter(Mandatory)] $Categories,
        [Parameter(Mandatory)] [string]$OutPath,
        $Tickers,
        $Earnings,
        $Meta
    )

    $payload = [pscustomobject]@{
        Meta       = $Meta
        Categories = $Categories
        Tickers    = $Tickers
        Earnings   = $Earnings
    }
    $json = $payload | ConvertTo-Json -Depth 7 -Compress

    $template = @'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Berita Saham AS</title>
<style>
  :root{
    --bg:#0b0f16; --panel:#121926; --panel2:#182234; --line:#243044;
    --tx:#e6edf7; --dim:#8b9bb4;
    --up:#2ecc71; --down:#ff5c5c; --warn:#f0b429; --acc:#4aa3ff;
  }
  *{box-sizing:border-box}
  /* Atribut hidden kalah dari aturan display di bawah, jadi dipaksa di sini. */
  [hidden]{display:none!important}
  body{margin:0;background:var(--bg);color:var(--tx);
       font:14px/1.6 "Segoe UI",system-ui,-apple-system,sans-serif}
  a{color:inherit;text-decoration:none}
  .wrap{max-width:1080px;margin:0 auto;padding:20px 18px 70px}

  header{border-bottom:1px solid var(--line);padding-bottom:16px;margin-bottom:18px}
  h1{margin:0 0 4px;font-size:22px}
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

  .nav{display:flex;gap:7px;flex-wrap:wrap;margin:16px 0}
  .nav button{background:var(--panel);color:var(--dim);border:1px solid var(--line);
              border-radius:8px;padding:9px 16px;font-size:13px;cursor:pointer;font-family:inherit}
  .nav button.on{background:var(--panel2);color:var(--tx);border-color:var(--acc)}

  .bar{background:var(--panel);border:1px solid var(--line);border-radius:10px;
       padding:12px;display:flex;flex-wrap:wrap;gap:9px;align-items:center;margin-bottom:18px}
  input,select{background:var(--panel2);color:var(--tx);border:1px solid var(--line);
               border-radius:7px;padding:8px 11px;font-size:13px;font-family:inherit}
  input:focus,select:focus{outline:none;border-color:var(--acc)}
  input[type=search]{min-width:230px;flex:1}
  .bar label{font-size:11.5px;color:var(--dim);margin-right:-4px}

  section{margin-bottom:26px}
  .sechead{display:flex;align-items:baseline;gap:10px;margin-bottom:9px;flex-wrap:wrap}
  .sechead h2{margin:0;font-size:17px}
  .sechead .cnt{font-size:12px;color:var(--dim)}

  .why{background:#101f2e;border:1px solid #1d3450;border-left:3px solid var(--acc);
       border-radius:8px;padding:12px 15px;font-size:13px;line-height:1.65;
       color:#c3d4e8;margin-bottom:12px}
  .why b{color:var(--acc);display:block;font-size:11px;text-transform:uppercase;
         letter-spacing:.7px;margin-bottom:5px}

  .item{background:var(--panel);border:1px solid var(--line);border-radius:10px;
        padding:13px 15px;margin-bottom:8px;display:block}
  .item:hover{border-color:#31415c;background:var(--panel2)}
  .item .t{font-size:14.5px;font-weight:600;line-height:1.45;margin-bottom:5px}
  .item .s{font-size:12.5px;color:var(--dim);line-height:1.5}
  .meta{display:flex;flex-wrap:wrap;gap:7px;align-items:center;margin-top:8px;font-size:11.5px;color:var(--dim)}
  .dot{width:3px;height:3px;border-radius:50%;background:var(--dim);display:inline-block}
  .tone{font-size:10.5px;font-weight:700;padding:2px 8px;border-radius:4px;letter-spacing:.4px}
  .tone.positif{background:#0f3320;color:#4cd484}
  .tone.negatif{background:#3a1717;color:#ff8080}
  .tone.netral{background:var(--panel2);color:var(--dim)}
  .tick{font-size:11px;font-weight:700;background:#123043;color:#6cc6f5;
        padding:2px 8px;border-radius:4px;letter-spacing:.4px}

  table{width:100%;border-collapse:collapse;font-size:13px}
  th,td{padding:9px 11px;text-align:left;border-bottom:1px solid var(--line)}
  th{color:var(--dim);font-size:11px;text-transform:uppercase;letter-spacing:.6px;font-weight:600}
  td.num{text-align:right;font-variant-numeric:tabular-nums}
  tr:hover td{background:var(--panel2)}
  .soon{color:var(--warn);font-weight:600}

  .tkhead{display:flex;justify-content:space-between;align-items:center;
          background:var(--panel2);border:1px solid var(--line);border-radius:9px;
          padding:10px 14px;margin-bottom:8px}
  .tkhead .l{font-size:16px;font-weight:700}
  .tkhead .n{font-size:12px;color:var(--dim);font-weight:400;margin-left:7px}
  .up{color:var(--up)} .down{color:var(--down)}
  .empty{text-align:center;color:var(--dim);padding:44px 20px}
  footer{margin-top:36px;padding-top:16px;border-top:1px solid var(--line);
         color:var(--dim);font-size:11.5px;line-height:1.7}
  /* --- Layar ponsel --- */
  @media(max-width:560px){
    .wrap{padding:14px 11px 60px}
    .bar{display:grid;grid-template-columns:1fr 1fr;gap:8px}
    .bar label{display:none}
    .bar select{width:100%}
    .bar input[type=search]{grid-column:1 / -1;min-width:0;width:100%}
    .nav button{flex:1;padding:9px 6px;font-size:12px}
    h1{font-size:19px}
    /* Tabel agenda lebih lebar dari layar ponsel - biar bisa digeser ke samping
       daripada memaksa seluruh halaman ikut melar. */
    .tablewrap{overflow-x:auto;-webkit-overflow-scrolling:touch}
    table{min-width:520px}
  }
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>Berita Saham Amerika Serikat</h1>
    <div class="sub">Berita makro, laporan keuangan, dan kabar saham pantauan Anda - dikelompokkan per tema.</div>
    <div class="status" id="status"></div>
    <nav class="apps">
      <a href="index.html">Screener</a>
      <a href="berita.html" class="on">Berita &amp; Agenda</a>
    </nav>
  </header>

  <div class="nav">
    <button data-v="tema" class="on">Berita per Tema</button>
    <button data-v="saham">Saham Pantauan</button>
    <button data-v="agenda">Agenda Laporan Keuangan</button>
  </div>

  <div class="bar" id="bar">
    <input type="search" id="q" placeholder="Cari kata kunci di judul berita...">
    <label>Tema</label>
    <select id="fcat"><option value="">Semua tema</option></select>
    <label>Nada</label>
    <select id="ftone">
      <option value="">Semua nada</option>
      <option value="positif">Positif</option>
      <option value="negatif">Negatif</option>
      <option value="netral">Netral</option>
    </select>
  </div>

  <div id="body"></div>

  <footer>
    <b>Penjelasan "Apa artinya" ditulis per TEMA, bukan per artikel.</b>
    Teksnya dipilih otomatis dari daftar tetap berdasarkan kata kunci di judul, jadi ia
    menjelaskan <i>jenis</i> beritanya - bukan isi spesifik artikel itu. Selalu klik
    judulnya dan baca sendiri sebelum mengambil keputusan.
    <br>Nada berita (positif/negatif) juga ditebak dari kata kunci judul dan sering meleset
    untuk judul yang memakai kiasan atau pertanyaan.
    <br>Berita bukan rekomendasi jual/beli. Semua tautan menuju situs sumber aslinya.
  </footer>
</div>

<script>
const DATA = __DATA__;
const M = DATA.Meta || {};
const CATS = DATA.Categories || [];
const TICKS = DATA.Tickers || [];
const EARN = DATA.Earnings || [];
let VIEW = "tema";

const $ = id => document.getElementById(id);
const esc = s => String(s==null?"":s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const arr = x => x==null ? [] : (Array.isArray(x)?x:[x]);

function ago(iso){
  if(!iso) return "";
  const d = new Date(iso);
  if(isNaN(d)) return "";
  const m = Math.floor((Date.now()-d.getTime())/60000);
  if(m<1) return "baru saja";
  if(m<60) return m+" menit lalu";
  const h = Math.floor(m/60);
  if(h<24) return h+" jam lalu";
  const dd = Math.floor(h/24);
  if(dd<7) return dd+" hari lalu";
  return d.toLocaleDateString("id-ID",{day:"numeric",month:"short"});
}
function pct(v){
  if(v==null||isNaN(v)) return "-";
  return (v>0?"+":"")+Number(v).toLocaleString("id-ID",{minimumFractionDigits:2,maximumFractionDigits:2})+"%";
}
const cls = v => v==null?"":(v>0?"up":(v<0?"down":""));

function initHeader(){
  const st = [];
  if(M.MarketState) st.push('<span class="chip'+(M.MarketOpen?' open':'')+'">'+esc(M.MarketState)+'</span>');
  if(M.OpenWib) st.push('<span class="chip">Jam bursa WIB <b>'+esc(M.OpenWib)+' - '+esc(M.CloseWib)+'</b></span>');
  if(M.GeneratedAt) st.push('<span class="chip">Diperbarui <b>'+esc(M.GeneratedAt)+' WIB</b></span>');
  if(M.TotalNews) st.push('<span class="chip"><b>'+M.TotalNews+'</b> berita</span>');
  if(M.WatchlistSource) st.push('<span class="chip">Pantauan: <b>'+esc(M.WatchlistSource)+'</b></span>');
  $("status").innerHTML = st.join("");

  $("fcat").innerHTML = '<option value="">Semua tema</option>' +
    CATS.map(c=>'<option>'+esc(c.name)+'</option>').join("");
}

function itemHtml(it, showTicker){
  const tk = (showTicker && it.ticker) ? '<span class="tick">'+esc(it.ticker)+'</span><span class="dot"></span>' : '';
  return '<a class="item" href="'+esc(it.link)+'" target="_blank" rel="noopener">'+
    '<div class="t">'+esc(it.title)+'</div>'+
    (it.summary?'<div class="s">'+esc(it.summary)+'</div>':'')+
    '<div class="meta">'+tk+
      '<span class="tone '+esc(it.tone)+'">'+esc(it.tone)+'</span><span class="dot"></span>'+
      '<span>'+esc(it.source)+'</span>'+
      (it.published?'<span class="dot"></span><span>'+ago(it.published)+'</span>':'')+
    '</div></a>';
}

function matches(it){
  const q = $("q").value.trim().toLowerCase();
  const ft = $("ftone").value;
  if(q && !((it.title||"").toLowerCase().includes(q) || (it.summary||"").toLowerCase().includes(q))) return false;
  if(ft && it.tone!==ft) return false;
  return true;
}

function renderTema(){
  const fc = $("fcat").value;
  let html = "", shown = 0;
  CATS.forEach(c=>{
    if(fc && c.name!==fc) return;
    const items = arr(c.items).filter(matches);
    if(items.length===0) return;
    shown += items.length;
    html += '<section><div class="sechead"><h2>'+esc(c.name)+'</h2>'+
            '<span class="cnt">'+items.length+' berita</span></div>'+
            '<div class="why"><b>Apa artinya buat investor</b>'+esc(c.why)+'</div>'+
            items.map(i=>itemHtml(i,true)).join("")+'</section>';
  });
  return shown ? html : '<div class="empty">Tidak ada berita yang cocok dengan filter ini.</div>';
}

function renderSaham(){
  let html = "", shown = 0;
  TICKS.forEach(t=>{
    const items = arr(t.items).filter(matches);
    if(items.length===0) return;
    shown += items.length;
    html += '<section><div class="tkhead"><div><span class="l">'+esc(t.code)+'</span>'+
            '<span class="n">'+esc(t.name||"")+'</span></div>'+
            '<div>'+(t.signal?'<span class="tick">'+esc(t.signal)+'</span> ':'')+
            '<span class="'+cls(t.chg1d)+'">'+pct(t.chg1d)+'</span></div></div>'+
            items.map(i=>itemHtml(i,false)).join("")+'</section>';
  });
  if(!shown) return '<div class="empty">Belum ada berita untuk saham pantauan Anda, atau tidak cocok dengan filter.</div>';
  return html;
}

function renderAgenda(){
  if(EARN.length===0){
    return '<div class="empty">Belum ada agenda laporan keuangan.<br>'+
           'Jalankan <b>Run-Screener.ps1</b> dulu - jadwalnya diambil dari hasil screener.</div>';
  }
  const rows = EARN.map(e=>{
    const soon = (e.days!=null && e.days<=7) ? ' class="soon"' : '';
    return '<tr><td><b>'+esc(e.code)+'</b></td><td>'+esc(e.name||"")+'</td>'+
      '<td>'+esc(e.date)+'</td>'+
      '<td'+soon+'>'+(e.days==null?"-":(e.days===0?"hari ini":e.days+" hari lagi"))+'</td>'+
      '<td>'+esc(e.signal||"-")+'</td>'+
      '<td class="num '+cls(e.chg1d)+'">'+pct(e.chg1d)+'</td></tr>';
  }).join("");

  return '<section>'+
    '<div class="why"><b>Kenapa agenda ini penting</b>'+
    'Laporan keuangan kuartalan adalah jadwal resmi yang sudah diketahui pasar sejak jauh hari. '+
    'Harga saham bisa melompat atau anjlok 10-20% dalam semalam setelah laporannya keluar, dan '+
    'stop loss sering terlewati karena harga MELOMPAT (gap), bukan bergerak turun perlahan. '+
    'Aturan praktis untuk pemula: jangan membuka posisi baru dalam 2-3 hari menjelang tanggal ini, '+
    'kecuali Anda memang sengaja ingin bertaruh pada hasil laporannya.</div>'+
    '<div class="tablewrap"><table><thead><tr><th>Kode</th><th>Perusahaan</th><th>Tanggal</th>'+
    '<th>Hitung mundur</th><th>Sinyal screener</th><th class="num">Hari ini</th></tr></thead>'+
    '<tbody>'+rows+'</tbody></table></div></section>';
}

function render(){
  $("bar").hidden = (VIEW==="agenda");
  if(VIEW==="tema") $("body").innerHTML = renderTema();
  else if(VIEW==="saham") $("body").innerHTML = renderSaham();
  else $("body").innerHTML = renderAgenda();
}

document.querySelectorAll(".nav button").forEach(b=>{
  b.addEventListener("click",()=>{
    document.querySelectorAll(".nav button").forEach(x=>x.classList.remove("on"));
    b.classList.add("on");
    VIEW = b.dataset.v;
    render();
  });
});
["q","fcat","ftone"].forEach(id=>{
  $(id).addEventListener(id==="q"?"input":"change", render);
});

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
