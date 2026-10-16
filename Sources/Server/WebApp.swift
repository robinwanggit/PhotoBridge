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
.topbar { padding: 16px 24px; border-bottom: 1px solid #e5e5ea; background: rgba(255,255,255,.85); backdrop-filter: saturate(180%) blur(20px); }
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
.loading { text-align: center; padding: 22px; color: #6e6e73; font-size: 13px; }
.hint { text-align: center; padding: 28px 24px; color: #6e6e73; font-size: 14px; line-height: 1.7; }
.empty { text-align: center; padding: 80px 24px; color: #a1a1a6; }
.sentinel { height: 1px; }
.lightbox { position: fixed; inset: 0; background: rgba(0,0,0,.9); display: flex; align-items: center; justify-content: center; z-index: 20; }
.lightbox[hidden] { display: none; }
.lightbox img { max-width: 96vw; max-height: 92vh; border-radius: 6px; }
.lb-close { position: absolute; top: 16px; right: 22px; background: none; border: none; color: #fff; font-size: 22px; cursor: pointer; }
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
      <h1 id="albumTitle">图库</h1>
      <div class="sub" id="albumSub">正在加载…</div>
    </header>
    <div class="scroll" id="scroll">
      <div id="content"></div>
      <div id="sentinel" class="sentinel"></div>
      <div id="loading" class="loading" hidden>加载中…</div>
      <div id="hint" class="hint" hidden></div>
    </div>
  </main>
</div>
<div id="lightbox" class="lightbox" hidden>
  <button class="lb-close" id="lbClose">&#10005;</button>
  <img id="lbImg" alt="">
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

  var state = {
    albumId: 'ALL', offset: 0, limit: 80, total: 0,
    hasMore: true, loading: false, sectionKey: null, sectionGrid: null
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
        head.textContent = fmtDate(it.created);
        content.appendChild(head);
        var grid = document.createElement('div');
        grid.className = 'grid';
        content.appendChild(grid);
        state.sectionKey = key;
        state.sectionGrid = grid;
      }
      state.sectionGrid.appendChild(makeCell(it));
    });
  }

  function makeCell(it) {
    var cell = document.createElement('div');
    cell.className = 'cell';
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
    cell.addEventListener('click', function () { openLightbox(it); });
    thumbIO.observe(img);
    return cell;
  }

  function openLightbox(it) {
    lbImg.src = '/api/thumb?id=' + encodeURIComponent(it.id) + '&w=1400';
    lightbox.hidden = false;
  }

  function closeLightbox() {
    lightbox.hidden = true;
    lbImg.src = '';
  }

  document.getElementById('lbClose').addEventListener('click', closeLightbox);
  lightbox.addEventListener('click', function (e) { if (e.target === lightbox) closeLightbox(); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeLightbox(); });

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

  loadAlbums().then(function (ok) {
    if (ok) selectAlbum('ALL', '图库');
  });
})();
</script>
</body>
</html>
"""
}
