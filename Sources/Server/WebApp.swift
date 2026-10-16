import Foundation

/// App 内置托管的单页网页应用（相册浏览）。服务器在 `GET /` 时原样返回这段 HTML。
///
/// 纯前端渲染、无外部依赖；缩略图走 IntersectionObserver 懒加载，
/// 资产列表走「滚动到底自动加载下一页」的分页。
enum WebApp {
    static let html = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PhotoBridge · 相册</title>
<style>
* { box-sizing: border-box; }
html, body { height: 100%; margin: 0; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
  color: #1d1d1f; background: #f5f5f7; -webkit-font-smoothing: antialiased;
}
.app { display: flex; height: 100vh; }
.sidebar { width: 244px; flex: 0 0 244px; background: #fff; border-right: 1px solid #e5e5ea; display: flex; flex-direction: column; }
.brand { padding: 18px 20px; font-size: 17px; font-weight: 600; border-bottom: 1px solid #f0f0f3; display: flex; align-items: center; gap: 8px; }
.logo { color: #34c759; }
.side-scroll { flex: 1; overflow-y: auto; padding: 8px; }
.side-foot { padding: 12px 20px; font-size: 11px; color: #a1a1a6; border-top: 1px solid #f0f0f3; }
.group-title { padding: 14px 12px 6px; font-size: 11px; font-weight: 600; color: #a1a1a6; letter-spacing: .04em; }
.album { display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 9px 12px; border-radius: 10px; cursor: pointer; font-size: 14px; }
.album:hover { background: #f5f5f7; }
.album.active { background: #e8f5ec; color: #1a7f37; font-weight: 600; }
.album .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.album .count { flex: 0 0 auto; font-size: 12px; color: #a1a1a6; }
.album.active .count { color: #1a7f37; }
.main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
.topbar { display: flex; align-items: center; justify-content: space-between; gap: 16px; padding: 16px 24px; border-bottom: 1px solid #e5e5ea; background: rgba(255,255,255,.85); backdrop-filter: saturate(180%) blur(20px); }
.topbar .titles { min-width: 0; }
.topbar h1 { margin: 0; font-size: 20px; }
.topbar .sub { margin-top: 4px; font-size: 13px; color: #6e6e73; }
.scroll { flex: 1; overflow-y: auto; padding-bottom: 48px; }
.date-head { position: sticky; top: 0; z-index: 2; padding: 12px 24px 6px; font-size: 13px; font-weight: 600; color: #6e6e73; background: linear-gradient(#f5f5f7 72%, rgba(245,245,247,0)); }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 3px; padding: 0 4px; }
.cell { position: relative; aspect-ratio: 1 / 1; background: #e9e9ee; overflow: hidden; cursor: pointer; border-radius: 2px; }
.cell img { position: relative; z-index: 1; width: 100%; height: 100%; object-fit: cover; display: block; opacity: 0; transition: opacity .25s; }
.cell img.loaded { opacity: 1; }
.placeholder { position: absolute; inset: 0; z-index: 0; display: flex; align-items: center; justify-content: center; font-size: 22px; color: #b8b8bf; }
.badge { position: absolute; z-index: 2; left: 6px; bottom: 6px; font-size: 11px; color: #fff; background: rgba(0,0,0,.55); padding: 1px 6px; border-radius: 6px; }
.star { position: absolute; z-index: 2; right: 6px; top: 6px; font-size: 12px; color: #ffd60a; text-shadow: 0 1px 2px rgba(0,0,0,.5); }
.fmt { position: absolute; z-index: 2; right: 6px; bottom: 6px; font-size: 10px; font-weight: 600; letter-spacing: .03em; color: #fff; background: rgba(0,0,0,.55); padding: 1px 6px; border-radius: 6px; }
.lb-info { position: absolute; left: 0; right: 0; bottom: 16px; text-align: center; font-size: 13px; color: rgba(255,255,255,.9); }
.loading { text-align: center; padding: 22px; color: #6e6e73; font-size: 13px; }
.hint { text-align: center; padding: 28px 24px; color: #6e6e73; font-size: 14px; line-height: 1.7; }
.empty { text-align: center; padding: 80px 24px; color: #a1a1a6; }
.sentinel { height: 1px; }
.lightbox { position: fixed; inset: 0; background: rgba(0,0,0,.9); display: flex; align-items: center; justify-content: center; z-index: 20; }
.lightbox[hidden] { display: none; }
.lightbox img { max-width: 96vw; max-height: 92vh; border-radius: 6px; }
.lb-close { position: absolute; top: 16px; right: 22px; background: none; border: none; color: #fff; font-size: 22px; cursor: pointer; }

/* 选择与导出（M4） */
.btn { border: 1px solid #d2d2d7; background: #fff; color: #1d1d1f; font-size: 13px; padding: 7px 14px; border-radius: 9px; cursor: pointer; white-space: nowrap; }
.btn:hover { background: #f5f5f7; }
.btn:disabled { opacity: .45; cursor: not-allowed; }
.btn.primary { background: #0071e3; border-color: #0071e3; color: #fff; }
.btn.primary:hover { background: #0077ed; }
.btn.toggle.on { background: #e8f5ec; border-color: #1a7f37; color: #1a7f37; font-weight: 600; }
.check { position: absolute; z-index: 3; left: 6px; top: 6px; width: 22px; height: 22px; border-radius: 50%; border: 2px solid rgba(255,255,255,.95); background: rgba(0,0,0,.28); box-shadow: 0 0 0 1px rgba(0,0,0,.14); display: none; align-items: center; justify-content: center; color: #fff; font-size: 13px; line-height: 1; }
body.selecting .check { display: flex; }
.cell.selected { outline: 3px solid #0071e3; outline-offset: -3px; }
.cell.selected .check { background: #0071e3; border-color: #0071e3; }
.cell.selected img { opacity: .82; }
.date-head { display: flex; align-items: center; justify-content: space-between; gap: 10px; }
.date-head .pick { display: none; font-size: 12px; font-weight: 500; color: #0071e3; cursor: pointer; padding: 2px 8px; border-radius: 6px; }
.date-head .pick:hover { background: #e8f0fe; }
body.selecting .date-head .pick { display: inline; }
.export-bar { display: flex; align-items: center; flex-wrap: wrap; gap: 10px 16px; padding: 12px 24px; border-top: 1px solid #e5e5ea; background: rgba(255,255,255,.96); backdrop-filter: saturate(180%) blur(20px); }
.export-bar[hidden] { display: none; }
.export-bar .count { font-size: 13px; font-weight: 600; white-space: nowrap; }
.export-bar .spacer { flex: 1 1 0; }
.export-bar .actions { display: flex; gap: 8px; flex-wrap: wrap; }
.modes { display: flex; align-items: center; gap: 18px; flex-wrap: wrap; }
.seg-label { font-size: 12px; color: #6e6e73; margin-right: 6px; }
.seg { display: inline-flex; border: 1px solid #d2d2d7; border-radius: 9px; overflow: hidden; }
.seg button { border: none; background: #fff; color: #1d1d1f; font-size: 12.5px; padding: 7px 12px; cursor: pointer; white-space: nowrap; }
.seg button + button { border-left: 1px solid #d2d2d7; }
.seg button.on { background: #0071e3; color: #fff; }
.seg button:disabled { opacity: .4; cursor: not-allowed; }
.run { display: flex; align-items: center; gap: 10px; }
.run-status { font-size: 12px; color: #6e6e73; max-width: 340px; }
@media (max-width: 1180px) { .export-bar .spacer { display: none; } }
</style>
</head>
<body>
<div class="app">
  <aside class="sidebar">
    <div class="brand"><span class="logo">&#9673;</span> PhotoBridge</div>
    <div class="side-scroll" id="sideScroll"></div>
    <div class="side-foot">局域网直连 · 数据不出本地</div>
  </aside>
  <main class="main">
    <header class="topbar">
      <div class="titles">
        <h1 id="albumTitle">图库</h1>
        <div class="sub" id="albumSub">正在加载…</div>
      </div>
      <button class="btn toggle" id="selectToggle">选择</button>
    </header>
    <div class="scroll" id="scroll">
      <div id="content"></div>
      <div id="sentinel" class="sentinel"></div>
      <div id="loading" class="loading" hidden>加载中…</div>
      <div id="hint" class="hint" hidden></div>
    </div>
    <div class="export-bar" id="exportBar" hidden>
      <div class="count" id="selCount">已选 0 项</div>
      <div class="actions">
        <button class="btn" id="selAllView">全选已加载</button>
        <button class="btn" id="selAllAlbum">全选本相册</button>
        <button class="btn" id="selClear">清除</button>
      </div>
      <div class="spacer"></div>
      <div class="modes">
        <span class="seg-label">导出</span>
        <div class="seg" id="modeSeg">
          <button data-mode="original" class="on">未修改的原片</button>
          <button data-mode="copy">拷贝照片</button>
        </div>
        <span class="seg-label">落盘</span>
        <div class="seg" id="landSeg">
          <button data-land="folder" class="on">下载到文件夹</button>
          <button data-land="zip">下载为 ZIP</button>
        </div>
      </div>
      <div class="run">
        <span class="run-status" id="runStatus"></span>
        <button class="btn primary" id="runExport" disabled>开始导出</button>
      </div>
    </div>
  </main>
</div>
<div id="lightbox" class="lightbox" hidden>
  <button class="lb-close" id="lbClose">&#10005;</button>
  <img id="lbImg" alt="">
  <div class="lb-info" id="lbInfo"></div>
</div>
<script>
(function () {
  var scroll = document.getElementById('scroll');
  var content = document.getElementById('content');
  var sideScroll = document.getElementById('sideScroll');
  var albumTitle = document.getElementById('albumTitle');
  var albumSub = document.getElementById('albumSub');
  var loadingEl = document.getElementById('loading');
  var hintEl = document.getElementById('hint');
  var lightbox = document.getElementById('lightbox');
  var lbImg = document.getElementById('lbImg');
  var lbInfo = document.getElementById('lbInfo');
  var selectToggle = document.getElementById('selectToggle');
  var exportBar = document.getElementById('exportBar');
  var selCountEl = document.getElementById('selCount');
  var selAllViewBtn = document.getElementById('selAllView');
  var selAllAlbumBtn = document.getElementById('selAllAlbum');
  var selClearBtn = document.getElementById('selClear');
  var modeSeg = document.getElementById('modeSeg');
  var landSeg = document.getElementById('landSeg');
  var runStatusEl = document.getElementById('runStatus');
  var runExportBtn = document.getElementById('runExport');

  var state = {
    albumId: 'ALL', offset: 0, limit: 80, total: 0,
    hasMore: true, loading: false, sectionKey: null, sectionGrid: null,
    selecting: false, selected: {}, selectedCount: 0,
    exportMode: 'original', landMode: 'folder',
    cells: {}, renderedIds: []
  };

  // 缩略图懒加载：进入视口前 400px 才真正发起请求
  var thumbIO = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      var img = entry.target;
      thumbIO.unobserve(img);
      if (img.dataset.src) img.src = img.dataset.src;
    });
  }, { root: scroll, rootMargin: '400px' });

  function fmtDate(ts) {
    var d = new Date(ts * 1000);
    if (isNaN(d.getTime())) return '未知日期';
    var today = new Date();
    function sameDay(a, b) {
      return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    if (sameDay(d, today)) return '今天';
    if (sameDay(d, new Date(today.getTime() - 86400000))) return '昨天';
    return d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日';
  }

  function fmtDuration(seconds) {
    var s = Math.round(seconds || 0);
    var m = Math.floor(s / 60);
    var r = s % 60;
    return m + ':' + (r < 10 ? '0' + r : '' + r);
  }

  function showHint(text) {
    hintEl.hidden = false;
    hintEl.textContent = text;
  }

  function loadAlbums() {
    return fetch('/api/albums').then(function (res) { return res.json(); }).then(function (data) {
      if (!data.authorized) {
        albumTitle.textContent = '无法访问相册';
        albumSub.textContent = '';
        showHint('相册权限未开启：请在 iPhone 上打开 PhotoBridge 并允许访问照片，然后刷新本页。');
        return false;
      }
      renderSidebar(data.albums || []);
      return true;
    }).catch(function () {
      albumSub.textContent = '无法连接手机服务';
      showHint('无法连接手机服务，请确认手机端 PhotoBridge 正在运行，且电脑与手机在同一 WiFi。');
      return false;
    });
  }

  function renderSidebar(albums) {
    var groups = { library: '图库', smart: '媒体类型', user: '我的相簿' };
    var order = ['library', 'smart', 'user'];
    sideScroll.innerHTML = '';
    order.forEach(function (kind) {
      var items = albums.filter(function (a) { return a.kind === kind; });
      if (!items.length) return;
      var title = document.createElement('div');
      title.className = 'group-title';
      title.textContent = groups[kind];
      sideScroll.appendChild(title);
      items.forEach(function (a) {
        var row = document.createElement('div');
        row.className = 'album' + (a.id === state.albumId ? ' active' : '');
        row.dataset.id = a.id;
        var name = document.createElement('span');
        name.className = 'name';
        name.textContent = a.title;
        var count = document.createElement('span');
        count.className = 'count';
        count.textContent = a.count;
        row.appendChild(name);
        row.appendChild(count);
        row.addEventListener('click', function () { selectAlbum(a.id, a.title); });
        sideScroll.appendChild(row);
      });
    });
  }

  function selectAlbum(id, title) {
    state.albumId = id;
    state.offset = 0;
    state.total = 0;
    state.hasMore = true;
    state.sectionKey = null;
    state.sectionGrid = null;
    state.cells = {};
    state.renderedIds = [];
    content.innerHTML = '';
    hintEl.hidden = true;
    albumTitle.textContent = title || '相册';
    albumSub.textContent = '加载中…';
    var rows = document.querySelectorAll('.album');
    for (var i = 0; i < rows.length; i++) {
      rows[i].classList.toggle('active', rows[i].dataset.id === id);
    }
    scroll.scrollTop = 0;
    loadMore();
  }

  function loadMore() {
    if (state.loading || !state.hasMore) return;
    state.loading = true;
    loadingEl.hidden = false;
    var url = '/api/assets?album=' + encodeURIComponent(state.albumId) +
              '&offset=' + state.offset + '&limit=' + state.limit;
    fetch(url).then(function (res) { return res.json(); }).then(function (data) {
      if (!data.authorized) {
        state.hasMore = false;
        showHint('相册权限未开启：请在 iPhone 上允许访问照片后刷新本页。');
        return;
      }
      state.total = data.total;
      albumSub.textContent = '共 ' + data.total + ' 个项目';
      var items = data.items || [];
      if (state.offset === 0 && items.length === 0) {
        content.innerHTML = '<div class="empty">此相册为空</div>';
        state.hasMore = false;
        return;
      }
      renderItems(items);
      state.offset += items.length;
      state.hasMore = !!data.hasMore;
    }).catch(function () {
      state.hasMore = false;
      showHint('网络中断，请刷新页面重试。');
    }).then(function () {
      state.loading = false;
      loadingEl.hidden = true;
      // 内容不足一屏时继续加载，填满视口
      if (state.hasMore && scroll.scrollHeight <= scroll.clientHeight + 60) {
        setTimeout(loadMore, 60);
      }
    });
  }

  function renderItems(items) {
    items.forEach(function (it) {
      var key = it.created ? new Date(it.created * 1000).toDateString() : 'unknown';
      if (key !== state.sectionKey) {
        var head = document.createElement('div');
        head.className = 'date-head';
        var label = document.createElement('span');
        label.textContent = fmtDate(it.created);
        head.appendChild(label);
        var pick = document.createElement('span');
        pick.className = 'pick';
        pick.textContent = '选本日';
        pick.addEventListener('click', function (e) {
          e.stopPropagation();
          selectDay(it.created);
        });
        head.appendChild(pick);
        content.appendChild(head);
        var grid = document.createElement('div');
        grid.className = 'grid';
        content.appendChild(grid);
        state.sectionKey = key;
        state.sectionGrid = grid;
      }
      state.renderedIds.push(it.id);
      var cell = makeCell(it);
      state.cells[it.id] = cell;
      state.sectionGrid.appendChild(cell);
    });
  }

  function makeCell(it) {
    var cell = document.createElement('div');
    cell.className = 'cell';
    cell.dataset.id = it.id;
    var placeholder = document.createElement('div');
    placeholder.className = 'placeholder';
    placeholder.textContent = it.isVideo ? '▶' : '▣';
    cell.appendChild(placeholder);
    var img = document.createElement('img');
    img.alt = '';
    img.dataset.src = '/api/thumb?id=' + encodeURIComponent(it.id) + '&w=320';
    img.addEventListener('load', function () {
      img.classList.add('loaded');
      if (placeholder.parentNode) placeholder.parentNode.removeChild(placeholder);
    });
    img.addEventListener('error', function () { placeholder.textContent = '!'; });
    cell.appendChild(img);
    if (it.isVideo) {
      var badge = document.createElement('div');
      badge.className = 'badge';
      badge.textContent = fmtDuration(it.duration);
      cell.appendChild(badge);
    }
    if (it.favorite) {
      var star = document.createElement('div');
      star.className = 'star';
      star.textContent = '★';
      cell.appendChild(star);
    }
    var fmtTag = (it.fmt || '').toUpperCase();
    if (fmtTag && fmtTag !== 'HEIC') {
      var fmt = document.createElement('div');
      fmt.className = 'fmt';
      fmt.textContent = fmtTag;
      cell.appendChild(fmt);
    }
    var check = document.createElement('div');
    check.className = 'check';
    check.textContent = '✓';
    cell.appendChild(check);
    if (state.selected[it.id]) cell.classList.add('selected');
    cell.addEventListener('click', function () {
      if (state.selecting) toggleSelect(it.id);
      else openLightbox(it);
    });
    thumbIO.observe(img);
    return cell;
  }

  function openLightbox(it) {
    lbImg.src = '/api/thumb?id=' + encodeURIComponent(it.id) + '&w=1400';
    var parts = [];
    if (it.fmt) parts.push(it.fmt.toUpperCase());
    if (it.w && it.h) parts.push(it.w + '×' + it.h);
    lbInfo.textContent = parts.join('  ·  ');
    lightbox.hidden = false;
  }

  function closeLightbox() {
    lightbox.hidden = true;
    lbImg.src = '';
    lbInfo.textContent = '';
  }

  document.getElementById('lbClose').addEventListener('click', closeLightbox);
  lightbox.addEventListener('click', function (e) { if (e.target === lightbox) closeLightbox(); });
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    if (!lightbox.hidden) { closeLightbox(); return; }
    if (state.selecting) setSelecting(false);
  });

  // 滚动到底自动加载下一页
  var ticking = false;
  scroll.addEventListener('scroll', function () {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      ticking = false;
      if (scroll.scrollTop + scroll.clientHeight >= scroll.scrollHeight - 900) loadMore();
    });
  });

  // ===== 多选与导出（M4）=====

  var folderSupported = ('showDirectoryPicker' in window);

  function setSelecting(on) {
    state.selecting = on;
    document.body.classList.toggle('selecting', on);
    exportBar.hidden = !on;
    selectToggle.classList.toggle('on', on);
    selectToggle.textContent = on ? '完成' : '选择';
    if (!on) setRunStatus('');
  }

  function updateSelection() {
    var count = 0;
    for (var id in state.selected) { if (state.selected[id]) count++; }
    state.selectedCount = count;
    selCountEl.textContent = '已选 ' + count + ' 项';
    runExportBtn.disabled = count === 0;
  }

  function refreshCells() {
    for (var id in state.cells) {
      state.cells[id].classList.toggle('selected', !!state.selected[id]);
    }
    updateSelection();
  }

  function toggleSelect(id) {
    if (state.selected[id]) delete state.selected[id];
    else state.selected[id] = true;
    if (state.cells[id]) state.cells[id].classList.toggle('selected', !!state.selected[id]);
    updateSelection();
  }

  function addIds(ids) {
    var added = 0;
    ids.forEach(function (id) {
      if (!state.selected[id]) { state.selected[id] = true; added++; }
    });
    refreshCells();
    return added;
  }

  function selectedIds() {
    var ids = [];
    for (var id in state.selected) { if (state.selected[id]) ids.push(id); }
    return ids;
  }

  function selectAllView() {
    addIds(state.renderedIds.slice());
  }

  function selectAllAlbum() {
    runStatusPrompt('正在获取本相册全部项目…');
    fetch('/api/ids?album=' + encodeURIComponent(state.albumId))
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (!data.authorized) { setRunStatus('相册权限未开启'); return; }
        addIds(data.ids || []);
        setRunStatus('');
      })
      .catch(function () { setRunStatus('获取失败，请重试'); });
  }

  function selectDay(ts) {
    if (!ts) { selectAllView(); return; }
    var d = new Date(ts * 1000);
    d.setHours(0, 0, 0, 0);
    var from = Math.floor(d.getTime() / 1000);
    var to = from + 86400;
    runStatusPrompt('正在获取当日全部项目…');
    fetch('/api/ids?album=' + encodeURIComponent(state.albumId) + '&from=' + from + '&to=' + to)
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (!data.authorized) { setRunStatus('相册权限未开启'); return; }
        addIds(data.ids || []);
        setRunStatus('');
      })
      .catch(function () { setRunStatus('获取失败，请重试'); });
  }

  function clearSelection() {
    state.selected = {};
    refreshCells();
    setRunStatus('');
  }

  function setRunStatus(text) { runStatusEl.textContent = text || ''; }
  function runStatusPrompt(text) {
    if (!state.selecting) setSelecting(true);
    setRunStatus(text);
  }

  // 段选控件（导出模式 / 落盘方式）
  function wireSeg(seg, attr, onPick) {
    seg.addEventListener('click', function (e) {
      var btn = e.target.closest ? e.target.closest('button') : null;
      if (!btn || btn.disabled) return;
      var value = btn.getAttribute(attr);
      var buttons = seg.querySelectorAll('button');
      for (var i = 0; i < buttons.length; i++) {
        buttons[i].classList.toggle('on', buttons[i] === btn);
      }
      onPick(value);
    });
  }

  wireSeg(modeSeg, 'data-mode', function (v) { state.exportMode = v; });
  wireSeg(landSeg, 'data-land', function (v) { state.landMode = v; });

  selectToggle.addEventListener('click', function () { setSelecting(!state.selecting); });
  selAllViewBtn.addEventListener('click', selectAllView);
  selAllAlbumBtn.addEventListener('click', selectAllAlbum);
  selClearBtn.addEventListener('click', clearSelection);
  runExportBtn.addEventListener('click', runExport);

  function runExport() {
    var ids = selectedIds();
    if (!ids.length) return;
    runExportBtn.disabled = true;
    if (state.landMode === 'folder') exportToFolder(ids);
    else exportZip(ids);
  }

  async function exportToFolder(ids) {
    if (!folderSupported) {
      setRunStatus('当前浏览器不支持选择文件夹，请改用「下载为 ZIP」');
      runExportBtn.disabled = false;
      return;
    }
    var root;
    try {
      root = await window.showDirectoryPicker({ mode: 'readwrite' });
    } catch (e) {
      setRunStatus('已取消选择文件夹');
      runExportBtn.disabled = false;
      return;
    }
    var ok = 0, fail = 0;
    for (var i = 0; i < ids.length; i++) {
      setRunStatus('正在写入 ' + (i + 1) + ' / ' + ids.length + '…');
      try {
        var res = await fetch('/api/export?id=' + encodeURIComponent(ids[i]) + '&mode=' + state.exportMode);
        if (!res.ok) throw new Error('HTTP ' + res.status);
        var rel = res.headers.get('X-Photo-Path');
        rel = rel ? decodeURIComponent(rel) : '';
        if (!rel) rel = 'unknown/' + ids[i];
        var slash = rel.lastIndexOf('/');
        var dirName = slash >= 0 ? rel.slice(0, slash) : '';
        var fileName = slash >= 0 ? rel.slice(slash + 1) : rel;
        var dir = dirName ? await ensureDir(root, dirName) : root;
        var name = await uniqueName(dir, fileName);
        var fileHandle = await dir.getFileHandle(name, { create: true });
        var writable = await fileHandle.createWritable();
        await res.body.pipeTo(writable);
        ok++;
      } catch (err) {
        fail++;
      }
    }
    setRunStatus('导出完成：成功 ' + ok + ' 张' + (fail ? '，失败 ' + fail + ' 张' : ''));
    runExportBtn.disabled = false;
  }

  async function ensureDir(root, path) {
    var parts = path.split('/');
    var dir = root;
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i]) continue;
      dir = await dir.getDirectoryHandle(parts[i], { create: true });
    }
    return dir;
  }

  async function fileExists(dir, name) {
    try { await dir.getFileHandle(name); return true; }
    catch (e) { return false; }
  }

  async function uniqueName(dir, name) {
    if (!(await fileExists(dir, name))) return name;
    var dot = name.lastIndexOf('.');
    var base = dot > 0 ? name.slice(0, dot) : name;
    var ext = dot > 0 ? name.slice(dot) : '';
    var n = 1;
    var candidate = base + ' (' + n + ')' + ext;
    while (await fileExists(dir, candidate)) {
      n++;
      candidate = base + ' (' + n + ')' + ext;
    }
    return candidate;
  }

  async function exportZip(ids) {
    setRunStatus('正在打包 ' + ids.length + ' 张，请稍候…');
    try {
      var res = await fetch('/api/zip', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids: ids, mode: state.exportMode })
      });
      if (!res.ok) {
        var msg = 'HTTP ' + res.status;
        try { var j = await res.json(); if (j && j.error) msg = j.error; } catch (e) {}
        setRunStatus('打包失败：' + msg);
        runExportBtn.disabled = false;
        return;
      }
      var blob = await res.blob();
      var name = parseFilename(res.headers.get('Content-Disposition')) || 'PhotoBridge.zip';
      var url = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = url;
      a.download = name;
      document.body.appendChild(a);
      a.click();
      a.remove();
      setTimeout(function () { URL.revokeObjectURL(url); }, 8000);
      setRunStatus('已生成 ZIP（' + ids.length + ' 张），浏览器已开始下载');
    } catch (e) {
      setRunStatus('打包失败：' + (e && e.message ? e.message : e));
    }
    runExportBtn.disabled = false;
  }

  function parseFilename(disposition) {
    if (!disposition) return '';
    var star = /filename[*]=UTF-8''([^;]+)/i.exec(disposition);
    if (star) { try { return decodeURIComponent(star[1].trim()); } catch (e) {} }
    var plain = /filename="?([^";]+)"?/i.exec(disposition);
    return plain ? plain[1].trim() : '';
  }

  // 文件夹能力检测：不支持的浏览器禁用该选项并回退到 ZIP
  if (!folderSupported) {
    var folderBtn = landSeg.querySelector('[data-land="folder"]');
    if (folderBtn) {
      folderBtn.disabled = true;
      folderBtn.title = '当前浏览器不支持选择文件夹，请改用「下载为 ZIP」';
    }
    var zipBtn = landSeg.querySelector('[data-land="zip"]');
    if (zipBtn) {
      var siblings = landSeg.querySelectorAll('button');
      for (var si = 0; si < siblings.length; si++) siblings[si].classList.toggle('on', siblings[si] === zipBtn);
      state.landMode = 'zip';
    }
  }

  updateSelection();

  loadAlbums().then(function (ok) {
    if (ok) selectAlbum('ALL', '图库');
  });
})();
</script>
</body>
</html>
"""
}
