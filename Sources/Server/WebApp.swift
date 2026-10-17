import Foundation

/// App 内置托管的单页网页应用（相册浏览）。服务器在 `GET /` 时原样返回这段 HTML。
///
/// 纯前端渲染、无外部依赖；缩略图走 IntersectionObserver 懒加载，
/// 资产列表走「滚动到底自动加载下一页」的分页。
/// 界面文案支持 18 种语言，启动时通过 `/api/lang` 获取 App 当前语言。
enum WebApp {
    static let html = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PhotoBridge</title>
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
    <div class="side-foot" id="sideFoot"></div>
  </aside>
  <main class="main">
    <header class="topbar">
      <div class="titles">
        <h1 id="albumTitle"></h1>
        <div class="sub" id="albumSub"></div>
      </div>
      <button class="btn toggle" id="selectToggle"></button>
    </header>
    <div class="scroll" id="scroll">
      <div id="content"></div>
      <div id="sentinel" class="sentinel"></div>
      <div id="loading" class="loading" hidden></div>
      <div id="hint" class="hint" hidden></div>
    </div>
    <div class="export-bar" id="exportBar" hidden>
      <div class="count" id="selCount"></div>
      <div class="actions">
        <button class="btn" id="selAllView"></button>
        <button class="btn" id="selAllAlbum"></button>
        <button class="btn" id="selClear"></button>
      </div>
      <div class="spacer"></div>
      <div class="modes">
        <span class="seg-label" id="segLabelExport"></span>
        <div class="seg" id="modeSeg">
          <button data-mode="original" class="on"></button>
          <button data-mode="copy"></button>
        </div>
        <span class="seg-label" id="segLabelSave"></span>
        <div class="seg" id="landSeg">
          <button data-land="folder" class="on"></button>
          <button data-land="zip"></button>
        </div>
      </div>
      <div class="run">
        <span class="run-status" id="runStatus"></span>
        <button class="btn primary" id="runExport" disabled></button>
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
  // ===== i18n：18 种语言 =====
  var I18N = {
    "zh-Hans": {
      title: "PhotoBridge · 相册", local_direct: "局域网直连 · 数据不出本地",
      library: "图库", loading: "加载中…", select: "选择", done: "完成",
      selected_count: "已选 {0} 项", select_all_loaded: "全选已加载",
      select_all_album: "全选本相册", clear: "清除",
      export_lbl: "导出", original: "未修改的原片", copy_photo: "拷贝照片",
      save_lbl: "落盘", download_folder: "下载到文件夹", download_zip: "下载为 ZIP",
      start_export: "开始导出", unknown_date: "未知日期", today: "今天", yesterday: "昨天",
      date_fmt: "{0}年{1}月{2}日", cannot_access_album: "无法访问相册",
      no_permission: "相册权限未开启：请在 iPhone 上打开 PhotoBridge 并允许访问照片，然后刷新本页。",
      no_permission_short: "相册权限未开启：请在 iPhone 上允许访问照片后刷新本页。",
      cannot_connect: "无法连接手机服务",
      cannot_connect_hint: "无法连接手机服务，请确认手机端 PhotoBridge 正在运行，且电脑与手机在同一 WiFi。",
      group_library: "图库", group_smart: "媒体类型", group_user: "我的相簿",
      album: "相册", total_items: "共 {0} 个项目", album_empty: "此相册为空",
      network_error: "网络中断，请刷新页面重试。", select_day: "选本日",
      fetching_album: "正在获取本相册全部项目…", fetching_day: "正在获取当日全部项目…",
      fetch_failed: "获取失败，请重试", folder_unsupported: "当前浏览器不支持选择文件夹，请改用「下载为 ZIP」",
      folder_cancelled: "已取消选择文件夹", writing_progress: "正在写入 {0} / {1}…",
      export_done: "导出完成：成功 {0} 张", export_done_fail: "，失败 {0} 张",
      packing: "正在打包 {0} 张，请稍候…", pack_failed: "打包失败：",
      zip_done: "已生成 ZIP（{0} 张），浏览器已开始下载", photos: "相册"
    },
    "zh-Hant": {
      title: "PhotoBridge · 相簿", local_direct: "區域網路直連 · 資料不外流",
      library: "圖庫", loading: "載入中…", select: "選擇", done: "完成",
      selected_count: "已選 {0} 項", select_all_loaded: "全選已載入",
      select_all_album: "全選本相簿", clear: "清除",
      export_lbl: "匯出", original: "未修改的原片", copy_photo: "拷貝照片",
      save_lbl: "儲存位置", download_folder: "下載到資料夾", download_zip: "下載為 ZIP",
      start_export: "開始匯出", unknown_date: "未知日期", today: "今天", yesterday: "昨天",
      date_fmt: "{0}年{1}月{2}日", cannot_access_album: "無法存取相簿",
      no_permission: "相簿權限未開啟：請在 iPhone 上開啟 PhotoBridge 並允許存取照片，然後重新整理本頁。",
      no_permission_short: "相簿權限未開啟：請在 iPhone 上允許存取照片後重新整理本頁。",
      cannot_connect: "無法連線手機服務",
      cannot_connect_hint: "無法連線手機服務，請確認手機端 PhotoBridge 正在執行，且電腦與手機在同一 WiFi。",
      group_library: "圖庫", group_smart: "媒體類型", group_user: "我的相簿",
      album: "相簿", total_items: "共 {0} 個項目", album_empty: "此相簿為空",
      network_error: "網路中斷，請重新整理頁面重試。", select_day: "選本日",
      fetching_album: "正在取得本相簿全部項目…", fetching_day: "正在取得當日全部項目…",
      fetch_failed: "取得失敗，請重試", folder_unsupported: "目前瀏覽器不支援選擇資料夾，請改用「下載為 ZIP」",
      folder_cancelled: "已取消選擇資料夾", writing_progress: "正在寫入 {0} / {1}…",
      export_done: "匯出完成：成功 {0} 張", export_done_fail: "，失敗 {0} 張",
      packing: "正在打包 {0} 張，請稍候…", pack_failed: "打包失敗：",
      zip_done: "已產生 ZIP（{0} 張），瀏覽器已開始下載", photos: "相簿"
    },
    "en": {
      title: "PhotoBridge · Photos", local_direct: "Direct LAN connection · data stays local",
      library: "Library", loading: "Loading…", select: "Select", done: "Done",
      selected_count: "{0} selected", select_all_loaded: "Select All Loaded",
      select_all_album: "Select All in Album", clear: "Clear",
      export_lbl: "Export", original: "Unmodified Original", copy_photo: "Duplicate Photo",
      save_lbl: "Destination", download_folder: "Download to Folder", download_zip: "Download as ZIP",
      start_export: "Start Export", unknown_date: "Unknown date", today: "Today", yesterday: "Yesterday",
      date_fmt: "{1}/{2}/{0}", cannot_access_album: "Cannot Access Album",
      no_permission: "Photo access not granted: open PhotoBridge on your iPhone, allow access to photos, then refresh this page.",
      no_permission_short: "Photo access not granted: allow access to photos on your iPhone, then refresh this page.",
      cannot_connect: "Cannot connect to phone service",
      cannot_connect_hint: "Cannot connect to the phone service. Make sure PhotoBridge is running on your iPhone and that your computer and phone are on the same WiFi network.",
      group_library: "Library", group_smart: "Media Types", group_user: "My Albums",
      album: "Album", total_items: "{0} items", album_empty: "This album is empty",
      network_error: "Network interrupted. Please refresh the page and try again.", select_day: "Select Day",
      fetching_album: "Fetching all items in this album…", fetching_day: "Fetching all items for this day…",
      fetch_failed: "Fetch failed, please retry", folder_unsupported: "This browser does not support folder selection. Please use \"Download as ZIP\" instead.",
      folder_cancelled: "Folder selection cancelled", writing_progress: "Writing {0} / {1}…",
      export_done: "Export complete: {0} succeeded", export_done_fail: ", {0} failed",
      packing: "Packing {0} items, please wait…", pack_failed: "Pack failed: ",
      zip_done: "ZIP generated ({0} items), download has started", photos: "Photos"
    },
    "fr": {
      title: "PhotoBridge · Photos", local_direct: "Connexion LAN directe · les données restent locales",
      library: "Bibliothèque", loading: "Chargement…", select: "Sélectionner", done: "Terminé",
      selected_count: "{0} sélectionné(s)", select_all_loaded: "Tout sélectionner (chargé)",
      select_all_album: "Tout sélectionner (album)", clear: "Effacer",
      export_lbl: "Exporter", original: "Original non modifié", copy_photo: "Dupliquer la photo",
      save_lbl: "Destination", download_folder: "Télécharger dans un dossier", download_zip: "Télécharger en ZIP",
      start_export: "Démarrer l'export", unknown_date: "Date inconnue", today: "Aujourd'hui", yesterday: "Hier",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "Accès à l'album impossible",
      no_permission: "Accès aux photos non autorisé : ouvrez PhotoBridge sur votre iPhone, autorisez l'accès aux photos, puis actualisez cette page.",
      no_permission_short: "Accès aux photos non autorisé : autorisez l'accès aux photos sur votre iPhone, puis actualisez cette page.",
      cannot_connect: "Connexion au service du téléphone impossible",
      cannot_connect_hint: "Connexion au service du téléphone impossible. Vérifiez que PhotoBridge est en cours d'exécution sur votre iPhone et que l'ordinateur et le téléphone sont sur le même réseau WiFi.",
      group_library: "Bibliothèque", group_smart: "Types de média", group_user: "Mes albums",
      album: "Album", total_items: "{0} éléments", album_empty: "Cet album est vide",
      network_error: "Réseau interrompu. Veuillez actualiser la page et réessayer.", select_day: "Sélectionner le jour",
      fetching_album: "Récupération de tous les éléments de l'album…", fetching_day: "Récupération de tous les éléments du jour…",
      fetch_failed: "Échec de la récupération, réessayez", folder_unsupported: "Ce navigateur ne prend pas en charge la sélection de dossier. Utilisez plutôt « Télécharger en ZIP ».",
      folder_cancelled: "Sélection du dossier annulée", writing_progress: "Écriture de {0} / {1}…",
      export_done: "Export terminé : {0} réussi(s)", export_done_fail: ", {0} échoué(s)",
      packing: "Compression de {0} éléments, veuillez patienter…", pack_failed: "Échec de la compression : ",
      zip_done: "ZIP généré ({0} éléments), le téléchargement a commencé", photos: "Photos"
    },
    "de": {
      title: "PhotoBridge · Fotos", local_direct: "Direkte LAN-Verbindung · Daten bleiben lokal",
      library: "Mediathek", loading: "Laden…", select: "Auswählen", done: "Fertig",
      selected_count: "{0} ausgewählt", select_all_loaded: "Alle Geladenen auswählen",
      select_all_album: "Alle im Album auswählen", clear: "Löschen",
      export_lbl: "Exportieren", original: "Unverändertes Original", copy_photo: "Foto duplizieren",
      save_lbl: "Ziel", download_folder: "In Ordner herunterladen", download_zip: "Als ZIP herunterladen",
      start_export: "Export starten", unknown_date: "Unbekanntes Datum", today: "Heute", yesterday: "Gestern",
      date_fmt: "{2}.{1}.{0}", cannot_access_album: "Album kann nicht zugegriffen werden",
      no_permission: "Fotozugriff nicht erlaubt: Öffnen Sie PhotoBridge auf Ihrem iPhone, erlauben Sie den Zugriff auf Fotos und aktualisieren Sie dann diese Seite.",
      no_permission_short: "Fotozugriff nicht erlaubt: Erlauben Sie den Zugriff auf Fotos auf Ihrem iPhone und aktualisieren Sie dann diese Seite.",
      cannot_connect: "Verbindung zum Telefondienst nicht möglich",
      cannot_connect_hint: "Verbindung zum Telefondienst nicht möglich. Stellen Sie sicher, dass PhotoBridge auf Ihrem iPhone läuft und dass Computer und Telefon sich im selben WiFi-Netzwerk befinden.",
      group_library: "Mediathek", group_smart: "Medientypen", group_user: "Meine Alben",
      album: "Album", total_items: "{0} Elemente", album_empty: "Dieses Album ist leer",
      network_error: "Netzwerk unterbrochen. Bitte aktualisieren Sie die Seite und versuchen Sie es erneut.", select_day: "Tag auswählen",
      fetching_album: "Alle Elemente dieses Albums werden abgerufen…", fetching_day: "Alle Elemente dieses Tages werden abgerufen…",
      fetch_failed: "Abruf fehlgeschlagen, bitte erneut versuchen", folder_unsupported: "Dieser Browser unterstützt keine Ordnerauswahl. Bitte verwenden Sie stattdessen „Als ZIP herunterladen“.",
      folder_cancelled: "Ordnerauswahl abgebrochen", writing_progress: "Schreibe {0} / {1}…",
      export_done: "Export abgeschlossen: {0} erfolgreich", export_done_fail: ", {0} fehlgeschlagen",
      packing: "Packe {0} Elemente, bitte warten…", pack_failed: "Packen fehlgeschlagen: ",
      zip_done: "ZIP erstellt ({0} Elemente), Download hat begonnen", photos: "Fotos"
    },
    "ja": {
      title: "PhotoBridge · 写真", local_direct: "LAN直接続 · データはローカルに保持",
      library: "ライブラリ", loading: "読み込み中…", select: "選択", done: "完了",
      selected_count: "{0} 件選択中", select_all_loaded: "読み込み済みをすべて選択",
      select_all_album: "このアルバムをすべて選択", clear: "クリア",
      export_lbl: "書き出し", original: "無変更のオリジナル", copy_photo: "写真を複製",
      save_lbl: "保存先", download_folder: "フォルダにダウンロード", download_zip: "ZIPでダウンロード",
      start_export: "書き出し開始", unknown_date: "日付不明", today: "今日", yesterday: "昨日",
      date_fmt: "{0}年{1}月{2}日", cannot_access_album: "アルバムにアクセスできません",
      no_permission: "写真へのアクセスが許可されていません。iPhone で PhotoBridge を開き、写真へのアクセスを許可してから、このページを更新してください。",
      no_permission_short: "写真へのアクセスが許可されていません。iPhone で写真へのアクセスを許可してから、このページを更新してください。",
      cannot_connect: "スマホのサービスに接続できません",
      cannot_connect_hint: "スマホのサービスに接続できません。iPhone で PhotoBridge が実行中であり、パソコンとスマホが同じ WiFi に接続されていることを確認してください。",
      group_library: "ライブラリ", group_smart: "メディアの種類", group_user: "マイアルバム",
      album: "アルバム", total_items: "{0} 項目", album_empty: "このアルバムは空です",
      network_error: "ネットワークが切断されました。ページを更新して再試行してください。", select_day: "この日を選択",
      fetching_album: "このアルバムのすべての項目を取得中…", fetching_day: "この日のすべての項目を取得中…",
      fetch_failed: "取得に失敗しました。再試行してください", folder_unsupported: "このブラウザはフォルダ選択に対応していません。「ZIPでダウンロード」を使用してください。",
      folder_cancelled: "フォルダ選択をキャンセルしました", writing_progress: "{0} / {1} を書き込み中…",
      export_done: "書き出し完了：{0} 枚成功", export_done_fail: "、{0} 枚失敗",
      packing: "{0} 項目をパック中です。しばらくお待ちください…", pack_failed: "パックに失敗しました：",
      zip_done: "ZIP を生成しました（{0} 項目）。ダウンロードが開始されました", photos: "写真"
    },
    "ko": {
      title: "PhotoBridge · 사진", local_direct: "LAN 직접 연결 · 데이터는 로컬에 유지",
      library: "라이브러리", loading: "불러오는 중…", select: "선택", done: "완료",
      selected_count: "{0}개 선택됨", select_all_loaded: "불러온 항목 모두 선택",
      select_all_album: "이 앨범 모두 선택", clear: "지우기",
      export_lbl: "내보내기", original: "수정되지 않은 원본", copy_photo: "사진 복제",
      save_lbl: "위치", download_folder: "폴더로 다운로드", download_zip: "ZIP으로 다운로드",
      start_export: "내보내기 시작", unknown_date: "알 수 없는 날짜", today: "오늘", yesterday: "어제",
      date_fmt: "{0}년 {1}월 {2}일", cannot_access_album: "앨범에 접근할 수 없습니다",
      no_permission: "사진 접근이 허용되지 않았습니다. iPhone에서 PhotoBridge를 열고 사진 접근을 허용한 후 이 페이지를 새로고침하세요.",
      no_permission_short: "사진 접근이 허용되지 않았습니다. iPhone에서 사진 접근을 허용한 후 이 페이지를 새로고침하세요.",
      cannot_connect: "휴대폰 서비스에 연결할 수 없습니다",
      cannot_connect_hint: "휴대폰 서비스에 연결할 수 없습니다. iPhone에서 PhotoBridge가 실행 중이고 컴퓨터와 휴대폰이 동일한 WiFi 네트워크에 있는지 확인하세요.",
      group_library: "라이브러리", group_smart: "미디어 유형", group_user: "내 앨범",
      album: "앨범", total_items: "{0}개 항목", album_empty: "이 앨범은 비어 있습니다",
      network_error: "네트워크가 끊겼습니다. 페이지를 새로고침하고 다시 시도하세요.", select_day: "이 날짜 선택",
      fetching_album: "이 앨범의 모든 항목을 가져오는 중…", fetching_day: "이 날짜의 모든 항목을 가져오는 중…",
      fetch_failed: "가져오기 실패, 다시 시도하세요", folder_unsupported: "이 브라우저는 폴더 선택을 지원하지 않습니다. 대신 \"ZIP으로 다운로드\"를 사용하세요.",
      folder_cancelled: "폴더 선택이 취소되었습니다", writing_progress: "{0} / {1} 쓰는 중…",
      export_done: "내보내기 완료: {0}개 성공", export_done_fail: ", {0}개 실패",
      packing: "{0}개 항목을 압축하는 중입니다. 잠시만 기다려 주세요…", pack_failed: "압축 실패: ",
      zip_done: "ZIP이 생성되었습니다({0}개 항목). 다운로드가 시작되었습니다", photos: "사진"
    },
    "it": {
      title: "PhotoBridge · Foto", local_direct: "Connessione LAN diretta · i dati restano locali",
      library: "Libreria", loading: "Caricamento…", select: "Seleziona", done: "Fine",
      selected_count: "{0} selezionati", select_all_loaded: "Seleziona tutti i caricati",
      select_all_album: "Seleziona tutto l'album", clear: "Cancella",
      export_lbl: "Esporta", original: "Originale non modificato", copy_photo: "Duplica foto",
      save_lbl: "Destinazione", download_folder: "Scarica nella cartella", download_zip: "Scarica come ZIP",
      start_export: "Avvia esportazione", unknown_date: "Data sconosciuta", today: "Oggi", yesterday: "Ieri",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "Impossibile accedere all'album",
      no_permission: "Accesso alle foto non consentito: apri PhotoBridge sul tuo iPhone, consenti l'accesso alle foto, quindi aggiorna questa pagina.",
      no_permission_short: "Accesso alle foto non consentito: consenti l'accesso alle foto sul tuo iPhone, quindi aggiorna questa pagina.",
      cannot_connect: "Impossibile connettersi al servizio del telefono",
      cannot_connect_hint: "Impossibile connettersi al servizio del telefono. Assicurati che PhotoBridge sia in esecuzione sul tuo iPhone e che computer e telefono siano sulla stessa rete WiFi.",
      group_library: "Libreria", group_smart: "Tipi di media", group_user: "I miei album",
      album: "Album", total_items: "{0} elementi", album_empty: "Questo album è vuoto",
      network_error: "Rete interrotta. Aggiorna la pagina e riprova.", select_day: "Seleziona giorno",
      fetching_album: "Recupero di tutti gli elementi dell'album…", fetching_day: "Recupero di tutti gli elementi del giorno…",
      fetch_failed: "Recupero fallito, riprova", folder_unsupported: "Questo browser non supporta la selezione della cartella. Usa invece \"Scarica come ZIP\".",
      folder_cancelled: "Selezione cartella annullata", writing_progress: "Scrittura di {0} / {1}…",
      export_done: "Esportazione completata: {0} riusciti", export_done_fail: ", {0} falliti",
      packing: "Compressione di {0} elementi, attendere…", pack_failed: "Compressione fallita: ",
      zip_done: "ZIP generato ({0} elementi), il download è iniziato", photos: "Foto"
    },
    "es": {
      title: "PhotoBridge · Fotos", local_direct: "Conexión LAN directa · los datos permanecen locales",
      library: "Biblioteca", loading: "Cargando…", select: "Seleccionar", done: "Listo",
      selected_count: "{0} seleccionados", select_all_loaded: "Seleccionar todo lo cargado",
      select_all_album: "Seleccionar todo el álbum", clear: "Limpiar",
      export_lbl: "Exportar", original: "Original sin modificar", copy_photo: "Duplicar foto",
      save_lbl: "Destino", download_folder: "Descargar a carpeta", download_zip: "Descargar como ZIP",
      start_export: "Iniciar exportación", unknown_date: "Fecha desconocida", today: "Hoy", yesterday: "Ayer",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "No se puede acceder al álbum",
      no_permission: "Acceso a fotos no permitido: abre PhotoBridge en tu iPhone, permite el acceso a las fotos y luego actualiza esta página.",
      no_permission_short: "Acceso a fotos no permitido: permite el acceso a las fotos en tu iPhone y luego actualiza esta página.",
      cannot_connect: "No se puede conectar al servicio del teléfono",
      cannot_connect_hint: "No se puede conectar al servicio del teléfono. Asegúrate de que PhotoBridge esté en ejecución en tu iPhone y de que la computadora y el teléfono estén en la misma red WiFi.",
      group_library: "Biblioteca", group_smart: "Tipos de medio", group_user: "Mis álbumes",
      album: "Álbum", total_items: "{0} elementos", album_empty: "Este álbum está vacío",
      network_error: "Red interrumpida. Actualiza la página e inténtalo de nuevo.", select_day: "Seleccionar día",
      fetching_album: "Obteniendo todos los elementos del álbum…", fetching_day: "Obteniendo todos los elementos del día…",
      fetch_failed: "Error al obtener, inténtalo de nuevo", folder_unsupported: "Este navegador no admite la selección de carpetas. Usa \"Descargar como ZIP\" en su lugar.",
      folder_cancelled: "Selección de carpeta cancelada", writing_progress: "Escribiendo {0} / {1}…",
      export_done: "Exportación completada: {0} correctos", export_done_fail: ", {0} fallidos",
      packing: "Empaquetando {0} elementos, espera…", pack_failed: "Error al empaquetar: ",
      zip_done: "ZIP generado ({0} elementos), la descarga ha comenzado", photos: "Fotos"
    },
    "hi": {
      title: "PhotoBridge · तस्वीरें", local_direct: "सीधा LAN कनेक्शन · डेटा स्थानीय रहता है",
      library: "लाइब्रेरी", loading: "लोड हो रहा है…", select: "चुनें", done: "हो गया",
      selected_count: "{0} चुने गए", select_all_loaded: "सभी लोड किए गए चुनें",
      select_all_album: "इस एल्बम के सभी चुनें", clear: "साफ़ करें",
      export_lbl: "निर्यात", original: "असंशोधित मूल", copy_photo: "फ़ोटो कॉपी करें",
      save_lbl: "गंतव्य", download_folder: "फ़ोल्डर में डाउनलोड करें", download_zip: "ZIP के रूप में डाउनलोड करें",
      start_export: "निर्यात शुरू करें", unknown_date: "अज्ञात तिथि", today: "आज", yesterday: "कल",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "एल्बम एक्सेस नहीं कर सकते",
      no_permission: "फ़ोटो एक्सेस की अनुमति नहीं है: अपने iPhone पर PhotoBridge खोलें, फ़ोटो एक्सेस की अनुमति दें, फिर इस पेज को रिफ्रेश करें।",
      no_permission_short: "फ़ोटो एक्सेस की अनुमति नहीं है: अपने iPhone पर फ़ोटो एक्सेस की अनुमति दें, फिर इस पेज को रिफ्रेश करें।",
      cannot_connect: "फ़ोन सेवा से कनेक्ट नहीं हो सका",
      cannot_connect_hint: "फ़ोन सेवा से कनेक्ट नहीं हो सका। सुनिश्चित करें कि आपके iPhone पर PhotoBridge चल रहा है और कंप्यूटर व फ़ोन एक ही WiFi पर हैं।",
      group_library: "लाइब्रेरी", group_smart: "मीडिया प्रकार", group_user: "मेरे एल्बम",
      album: "एल्बम", total_items: "{0} आइटम", album_empty: "यह एल्बम खाली है",
      network_error: "नेटवर्क टूट गया। कृपया पेज रिफ्रेश करके पुनः प्रयास करें।", select_day: "दिन चुनें",
      fetching_album: "इस एल्बम के सभी आइटम प्राप्त कर रहे हैं…", fetching_day: "इस दिन के सभी आइटम प्राप्त कर रहे हैं…",
      fetch_failed: "प्राप्त करने में विफल, कृपया पुनः प्रयास करें", folder_unsupported: "यह ब्राउज़र फ़ोल्डर चयन का समर्थन नहीं करता। कृपया इसके बजाय \"ZIP के रूप में डाउनलोड करें\" का उपयोग करें।",
      folder_cancelled: "फ़ोल्डर चयन रद्द किया गया", writing_progress: "{0} / {1} लिख रहे हैं…",
      export_done: "निर्यात पूर्ण: {0} सफल", export_done_fail: ", {0} विफल",
      packing: "{0} आइटम पैक कर रहे हैं, कृपया प्रतीक्षा करें…", pack_failed: "पैक करने में विफल: ",
      zip_done: "ZIP बनाया गया ({0} आइटम), डाउनलोड शुरू हो गया है", photos: "तस्वीरें"
    },
    "ar": {
      title: "PhotoBridge · صور", local_direct: "اتصال مباشر بالشبكة المحلية · تظل البيانات محلياً",
      library: "المكتبة", loading: "جارٍ التحميل…", select: "تحديد", done: "تم",
      selected_count: "تم تحديد {0}", select_all_loaded: "تحديد كل ما تم تحميله",
      select_all_album: "تحديد كامل الألبوم", clear: "مسح",
      export_lbl: "تصدير", original: "الأصلي غير المعدّل", copy_photo: "نسخ الصورة",
      save_lbl: "الوجهة", download_folder: "تنزيل إلى مجلد", download_zip: "تنزيل كملف ZIP",
      start_export: "بدء التصدير", unknown_date: "تاريخ غير معروف", today: "اليوم", yesterday: "أمس",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "تعذّر الوصول إلى الألبوم",
      no_permission: "لم يتم منح الوصول إلى الصور: افتح PhotoBridge على جهاز iPhone الخاص بك، اسمح بالوصول إلى الصور، ثم حدّث هذه الصفحة.",
      no_permission_short: "لم يتم منح الوصول إلى الصور: اسمح بالوصول إلى الصور على جهاز iPhone الخاص بك، ثم حدّث هذه الصفحة.",
      cannot_connect: "تعذّر الاتصال بخدمة الهاتف",
      cannot_connect_hint: "تعذّر الاتصال بخدمة الهاتف. تأكد من تشغيل PhotoBridge على جهاز iPhone الخاص بك وأن الكمبيوتر والهاتف على نفس شبكة WiFi.",
      group_library: "المكتبة", group_smart: "أنواع الوسائط", group_user: "ألبوماتي",
      album: "ألبوم", total_items: "{0} عنصر", album_empty: "هذا الألبوم فارغ",
      network_error: "انقطع الاتصال بالشبكة. يرجى تحديث الصفحة وإعادة المحاولة.", select_day: "تحديد اليوم",
      fetching_album: "جارٍ جلب كل عناصر الألبوم…", fetching_day: "جارٍ جلب كل عناصر هذا اليوم…",
      fetch_failed: "فشل الجلب، يرجى إعادة المحاولة", folder_unsupported: "هذا المتصفح لا يدعم اختيار المجلد. يرجى استخدام «تنزيل كملف ZIP» بدلاً من ذلك.",
      folder_cancelled: "تم إلغاء اختيار المجلد", writing_progress: "جارٍ الكتابة {0} / {1}…",
      export_done: "اكتمل التصدير: نجحت {0}", export_done_fail: "، فشلت {0}",
      packing: "جارٍ تجميع {0} عنصرًا، يرجى الانتظار…", pack_failed: "فشل التجميع: ",
      zip_done: "تم إنشاء ملف ZIP ({0} عنصر)، بدأ التنزيل", photos: "صور"
    },
    "ru": {
      title: "PhotoBridge · Фото", local_direct: "Прямое LAN-подключение · данные остаются локально",
      library: "Библиотека", loading: "Загрузка…", select: "Выбрать", done: "Готово",
      selected_count: "Выбрано: {0}", select_all_loaded: "Выбрать все загруженные",
      select_all_album: "Выбрать весь альбом", clear: "Очистить",
      export_lbl: "Экспорт", original: "Неизменённый оригинал", copy_photo: "Дублировать фото",
      save_lbl: "Назначение", download_folder: "Загрузить в папку", download_zip: "Загрузить как ZIP",
      start_export: "Начать экспорт", unknown_date: "Неизвестная дата", today: "Сегодня", yesterday: "Вчера",
      date_fmt: "{2}.{1}.{0}", cannot_access_album: "Не удаётся получить доступ к альбому",
      no_permission: "Доступ к фото не разрешён: откройте PhotoBridge на iPhone, разрешите доступ к фото, затем обновите эту страницу.",
      no_permission_short: "Доступ к фото не разрешён: разрешите доступ к фото на iPhone, затем обновите эту страницу.",
      cannot_connect: "Не удаётся подключиться к службе телефона",
      cannot_connect_hint: "Не удаётся подключиться к службе телефона. Убедитесь, что PhotoBridge запущен на вашем iPhone и что компьютер и телефон находятся в одной сети WiFi.",
      group_library: "Библиотека", group_smart: "Типы медиа", group_user: "Мои альбомы",
      album: "Альбом", total_items: "{0} элементов", album_empty: "Этот альбом пуст",
      network_error: "Сеть прервана. Обновите страницу и попробуйте снова.", select_day: "Выбрать день",
      fetching_album: "Получение всех элементов альбома…", fetching_day: "Получение всех элементов за этот день…",
      fetch_failed: "Не удалось получить, попробуйте снова", folder_unsupported: "Этот браузер не поддерживает выбор папки. Используйте вместо этого «Загрузить как ZIP».",
      folder_cancelled: "Выбор папки отменён", writing_progress: "Запись {0} / {1}…",
      export_done: "Экспорт завершён: успешно {0}", export_done_fail: ", не удалось {0}",
      packing: "Упаковка {0} элементов, подождите…", pack_failed: "Ошибка упаковки: ",
      zip_done: "ZIP создан ({0} элементов), загрузка началась", photos: "Фото"
    },
    "bn": {
      title: "PhotoBridge · ছবি", local_direct: "সরাসরি LAN সংযোগ · ডেটা স্থানীয় থাকে",
      library: "লাইব্রেরি", loading: "লোড হচ্ছে…", select: "নির্বাচন", done: "সম্পন্ন",
      selected_count: "{0}টি নির্বাচিত", select_all_loaded: "সব লোডকৃত নির্বাচন করুন",
      select_all_album: "এই অ্যালবামের সব নির্বাচন করুন", clear: "মুছুন",
      export_lbl: "রপ্তানি", original: "অপরিবর্তিত মূল", copy_photo: "ছবি কপি করুন",
      save_lbl: "গন্তব্য", download_folder: "ফোল্ডারে ডাউনলোড করুন", download_zip: "ZIP হিসেবে ডাউনলোড করুন",
      start_export: "রপ্তানি শুরু করুন", unknown_date: "অজানা তারিখ", today: "আজ", yesterday: "গতকাল",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "অ্যালবাম অ্যাক্সেস করা যাচ্ছে না",
      no_permission: "ছবিতে অ্যাক্সেস অনুমোদিত নয়: আপনার iPhone-এ PhotoBridge খুলুন, ছবিতে অ্যাক্সেস অনুমতি দিন, তারপর এই পেজটি রিফ্রেশ করুন।",
      no_permission_short: "ছবিতে অ্যাক্সেস অনুমোদিত নয়: আপনার iPhone-এ ছবিতে অ্যাক্সেস অনুমতি দিন, তারপর এই পেজটি রিফ্রেশ করুন।",
      cannot_connect: "ফোন পরিষেবায় সংযোগ করা যাচ্ছে না",
      cannot_connect_hint: "ফোন পরিষেবায় সংযোগ করা যাচ্ছে না। নিশ্চিত করুন যে আপনার iPhone-এ PhotoBridge চলছে এবং কম্পিউটার ও ফোন একই WiFi-তে রয়েছে।",
      group_library: "লাইব্রেরি", group_smart: "মিডিয়ার ধরন", group_user: "আমার অ্যালবাম",
      album: "অ্যালবাম", total_items: "{0}টি আইটেম", album_empty: "এই অ্যালবামটি খালি",
      network_error: "নেটওয়ার্ক বিচ্ছিন্ন। দয়া করে পেজটি রিফ্রেশ করে আবার চেষ্টা করুন।", select_day: "দিন নির্বাচন করুন",
      fetching_album: "এই অ্যালবামের সব আইটেম আনা হচ্ছে…", fetching_day: "এই দিনের সব আইটেম আনা হচ্ছে…",
      fetch_failed: "আনতে ব্যর্থ, আবার চেষ্টা করুন", folder_unsupported: "এই ব্রাউজারটি ফোল্ডার নির্বাচন সমর্থন করে না। এর বদলে «ZIP হিসেবে ডাউনলোড করুন» ব্যবহার করুন।",
      folder_cancelled: "ফোল্ডার নির্বাচন বাতিল করা হয়েছে", writing_progress: "{0} / {1} লেখা হচ্ছে…",
      export_done: "রপ্তানি সম্পন্ন: {0}টি সফল", export_done_fail: ", {0}টি ব্যর্থ",
      packing: "{0}টি আইটেম প্যাক করা হচ্ছে, অপেক্ষা করুন…", pack_failed: "প্যাক করতে ব্যর্থ: ",
      zip_done: "ZIP তৈরি হয়েছে ({0}টি আইটেম), ডাউনলোড শুরু হয়েছে", photos: "ছবি"
    },
    "pt": {
      title: "PhotoBridge · Fotos", local_direct: "Conexão LAN direta · dados permanecem locais",
      library: "Biblioteca", loading: "Carregando…", select: "Selecionar", done: "Concluído",
      selected_count: "{0} selecionados", select_all_loaded: "Selecionar todos carregados",
      select_all_album: "Selecionar todo o álbum", clear: "Limpar",
      export_lbl: "Exportar", original: "Original sem modificações", copy_photo: "Duplicar foto",
      save_lbl: "Destino", download_folder: "Baixar para pasta", download_zip: "Baixar como ZIP",
      start_export: "Iniciar exportação", unknown_date: "Data desconhecida", today: "Hoje", yesterday: "Ontem",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "Não é possível acessar o álbum",
      no_permission: "Acesso às fotos não permitido: abra o PhotoBridge no seu iPhone, permita o acesso às fotos e depois atualize esta página.",
      no_permission_short: "Acesso às fotos não permitido: permita o acesso às fotos no seu iPhone e depois atualize esta página.",
      cannot_connect: "Não foi possível conectar ao serviço do telefone",
      cannot_connect_hint: "Não foi possível conectar ao serviço do telefone. Certifique-se de que o PhotoBridge está em execução no seu iPhone e que o computador e o telefone estão na mesma rede WiFi.",
      group_library: "Biblioteca", group_smart: "Tipos de mídia", group_user: "Meus álbuns",
      album: "Álbum", total_items: "{0} itens", album_empty: "Este álbum está vazio",
      network_error: "Rede interrompida. Atualize a página e tente novamente.", select_day: "Selecionar dia",
      fetching_album: "Buscando todos os itens do álbum…", fetching_day: "Buscando todos os itens do dia…",
      fetch_failed: "Falha ao buscar, tente novamente", folder_unsupported: "Este navegador não suporta seleção de pasta. Use \"Baixar como ZIP\" em vez disso.",
      folder_cancelled: "Seleção de pasta cancelada", writing_progress: "Gravando {0} / {1}…",
      export_done: "Exportação concluída: {0} com sucesso", export_done_fail: ", {0} falharam",
      packing: "Compactando {0} itens, aguarde…", pack_failed: "Falha ao compactar: ",
      zip_done: "ZIP gerado ({0} itens), o download começou", photos: "Fotos"
    },
    "id": {
      title: "PhotoBridge · Foto", local_direct: "Koneksi LAN langsung · data tetap lokal",
      library: "Pustaka", loading: "Memuat…", select: "Pilih", done: "Selesai",
      selected_count: "{0} dipilih", select_all_loaded: "Pilih Semua yang Dimuat",
      select_all_album: "Pilih Semua Album", clear: "Hapus",
      export_lbl: "Ekspor", original: "Asli Tanpa Modifikasi", copy_photo: "Duplikat Foto",
      save_lbl: "Tujuan", download_folder: "Unduh ke Folder", download_zip: "Unduh sebagai ZIP",
      start_export: "Mulai Ekspor", unknown_date: "Tanggal tidak diketahui", today: "Hari ini", yesterday: "Kemarin",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "Tidak dapat mengakses album",
      no_permission: "Akses foto tidak diizinkan: buka PhotoBridge di iPhone Anda, izinkan akses ke foto, lalu segarkan halaman ini.",
      no_permission_short: "Akses foto tidak diizinkan: izinkan akses ke foto di iPhone Anda, lalu segarkan halaman ini.",
      cannot_connect: "Tidak dapat terhubung ke layanan ponsel",
      cannot_connect_hint: "Tidak dapat terhubung ke layanan ponsel. Pastikan PhotoBridge berjalan di iPhone Anda dan komputer serta ponsel berada di jaringan WiFi yang sama.",
      group_library: "Pustaka", group_smart: "Jenis Media", group_user: "Album Saya",
      album: "Album", total_items: "{0} item", album_empty: "Album ini kosong",
      network_error: "Jaringan terputus. Silakan segarkan halaman dan coba lagi.", select_day: "Pilih Hari",
      fetching_album: "Mengambil semua item album ini…", fetching_day: "Mengambil semua item hari ini…",
      fetch_failed: "Gagal mengambil, silakan coba lagi", folder_unsupported: "Peramban ini tidak mendukung pemilihan folder. Gunakan \"Unduh sebagai ZIP\" sebagai gantinya.",
      folder_cancelled: "Pemilihan folder dibatalkan", writing_progress: "Menulis {0} / {1}…",
      export_done: "Ekspor selesai: {0} berhasil", export_done_fail: ", {0} gagal",
      packing: "Mengemas {0} item, mohon tunggu…", pack_failed: "Gagal mengemas: ",
      zip_done: "ZIP dibuat ({0} item), unduhan telah dimulai", photos: "Foto"
    },
    "th": {
      title: "PhotoBridge · รูปภาพ", local_direct: "เชื่อมต่อ LAN โดยตรง · ข้อมูลยังคงอยู่ในเครื่อง",
      library: "คลัง", loading: "กำลังโหลด…", select: "เลือก", done: "เสร็จสิ้น",
      selected_count: "เลือกแล้ว {0} รายการ", select_all_loaded: "เลือกทั้งหมดที่โหลดมา",
      select_all_album: "เลือกทั้งหมดในอัลบั้ม", clear: "ล้าง",
      export_lbl: "ส่งออก", original: "ต้นฉบับที่ไม่ได้แก้ไข", copy_photo: "ทำสำเนารูปภาพ",
      save_lbl: "ปลายทาง", download_folder: "ดาวน์โหลดลงโฟลเดอร์", download_zip: "ดาวน์โหลดเป็น ZIP",
      start_export: "เริ่มส่งออก", unknown_date: "วันที่ไม่ทราบ", today: "วันนี้", yesterday: "เมื่อวาน",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "ไม่สามารถเข้าถึงอัลบั้ม",
      no_permission: "ไม่ได้รับอนุญาตให้เข้าถึงรูปภาพ: เปิด PhotoBridge บน iPhone ของคุณ อนุญาตให้เข้าถึงรูปภาพ แล้วรีเฟรชหน้านี้",
      no_permission_short: "ไม่ได้รับอนุญาตให้เข้าถึงรูปภาพ: อนุญาตให้เข้าถึงรูปภาพบน iPhone ของคุณ แล้วรีเฟรชหน้านี้",
      cannot_connect: "ไม่สามารถเชื่อมต่อกับบริการโทรศัพท์",
      cannot_connect_hint: "ไม่สามารถเชื่อมต่อกับบริการโทรศัพท์ได้ ตรวจสอบให้แน่ใจว่า PhotoBridge กำลังทำงานบน iPhone ของคุณและคอมพิวเตอร์กับโทรศัพท์อยู่บนเครือข่าย WiFi เดียวกัน",
      group_library: "คลัง", group_smart: "ประเภทสื่อ", group_user: "อัลบั้มของฉัน",
      album: "อัลบั้ม", total_items: "{0} รายการ", album_empty: "อัลบั้มนี้ว่างเปล่า",
      network_error: "เครือข่ายขัดจังหวะ โปรดรีเฟรชหน้าแล้วลองอีกครั้ง", select_day: "เลือกวัน",
      fetching_album: "กำลังดึงรายการทั้งหมดในอัลบั้มนี้…", fetching_day: "กำลังดึงรายการทั้งหมดในวันนี้…",
      fetch_failed: "ดึงข้อมูลล้มเหลว โปรดลองอีกครั้ง", folder_unsupported: "เบราว์เซอร์นี้ไม่รองรับการเลือกโฟลเดอร์ โปรดใช้ «ดาวน์โหลดเป็น ZIP» แทน",
      folder_cancelled: "ยกเลิกการเลือกโฟลเดอร์", writing_progress: "กำลังเขียน {0} / {1}…",
      export_done: "ส่งออกเสร็จสมบูรณ์: สำเร็จ {0} รายการ", export_done_fail: " ล้มเหลว {0} รายการ",
      packing: "กำลังบีบอัด {0} รายการ โปรดรอสักครู่…", pack_failed: "บีบอัดล้มเหลว: ",
      zip_done: "สร้าง ZIP แล้ว ({0} รายการ) เริ่มดาวน์โหลดแล้ว", photos: "รูปภาพ"
    },
    "mn": {
      title: "PhotoBridge · Зураг", local_direct: "Шууд LAN холболт · өгөгдөл локалд үлдэнэ",
      library: "Номын сан", loading: "Ачаалж байна…", select: "Сонгох", done: "Дууссан",
      selected_count: "{0} сонгогдсон", select_all_loaded: "Ачилтийн бүгийг сонгох",
      select_all_album: "Энэ альбомыг бүгдийг нь сонгох", clear: "Цэвэрлэх",
      export_lbl: "Экспорт", original: "Өөрчлөгдөөгүй эх", copy_photo: "Зургийг хуулбарлах",
      save_lbl: "Очих цэг", download_folder: "Хавтаст татах", download_zip: "ZIP болгон татах",
      start_export: "Экспорт эхлүүлэх", unknown_date: "Мэдэгдэхгүй огноо", today: "Өнөөдөр", yesterday: "Өчигдөр",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "Альбомд хандах боломжгүй",
      no_permission: "Зургад хандах эрх олгогдоогүй: iPhone дээрээ PhotoBridge нээж, зургад хандахыг зөвшөөрсний дараа энэ хуудсыг шинэчлэнэ үү.",
      no_permission_short: "Зургад хандах эрх олгогдоогүй: iPhone дээрээ зургад хандахыг зөвшөөрсний дараа энэ хуудсыг шинэчлэнэ үү.",
      cannot_connect: "Утасны үйлчилгээнд холбогдож чадсангүй",
      cannot_connect_hint: "Утасны үйлчилгээнд холбогдож чадсангүй. iPhone дээр PhotoBridge ажиллаж буйг баталгаажуулж, компьютер, утас нь ижил WiFi сүлжээнд байна гэдгийг шалгана уу.",
      group_library: "Номын сан", group_smart: "Медиа төрлүүд", group_user: "Миний альбом",
      album: "Альбом", total_items: "{0} зүйл", album_empty: "Энэ альбом хоосон байна",
      network_error: "Сүлжээ тасарсан. Хуудсыг шинэчилж дахин оролдоно уу.", select_day: "Өдрийг сонгох",
      fetching_album: "Энэ альбомны бүх зүйлийг авч байна…", fetching_day: "Энэ өдрийн бүх зүйлийг авч байна…",
      fetch_failed: "Авч чадсангүй, дахин оролдоно уу", folder_unsupported: "Энэ хөтөч хавтас сонгохыг дэмжихгүй. Оронд нь «ZIP болгон татах» ашиглана уу.",
      folder_cancelled: "Хавтас сонголт цуцлагдсан", writing_progress: "{0} / {1} бичиж байна…",
      export_done: "Экспорт дууссан: {0} амжилттай", export_done_fail: ", {0} амжилтгүй",
      packing: "{0} зүйлийг багцалж байна, түр хүлээнэ үү…", pack_failed: "Багцалж чадсангүй: ",
      zip_done: "ZIP үүсгэгдлээ ({0} зүйл), татаж эхэллээ", photos: "Зураг"
    },
    "bo": {
      title: "PhotoBridge · པར་རིས།", local_direct: "LAN ཐུག་གཏུག · གནད་དོན་མ་ཕྱིར་འཁོར",
      library: "ཚོགས་ཁང་།", loading: "གསར་བསྐྲུན་བྱ་བཞིན།", select: "འདེམས་རོགས།", done: "མཐུན་སྒྲིལ།",
      selected_count: "{0} འདེམས་ཡོད", select_all_loaded: "བསྐྲུན་ཚར་ཚང་མ་འདེམས།",
      select_all_album: "དཔེ་དེབ་འདི་ཚང་མ་འདེམས།", clear: "སེལ་རོགས།",
      export_lbl: "ཕྱིར་སྤྲད།", original: "གསར་བཅོས་མ་བྱས་པའི་གཞུང་།", copy_photo: "པར་རིས་བསྐྱར་དུ་བྱ།",
      save_lbl: "གནས་གཞི།", download_folder: "ཐུམ་ཚན་ལ་ཕབ་ལེན།", download_zip: "ZIP ཏུ་ཕབ་ལེན།",
      start_export: "ཕྱིར་སྤྲད་འགོ་བཙུགས།", unknown_date: "མ་ཤེས་པའི་ཚེས་གྲངས།", today: "དེ་རིང་།", yesterday: "ཁ་སང་།",
      date_fmt: "{2}/{1}/{0}", cannot_access_album: "དཔེ་དེབ་ལ་ཁ་གཏུགས་ཆོག་མེད།",
      no_permission: "པར་རིས་ལ་ཁ་གཏུགས་མ་ཆོག། ཁྱེད་ཀྱི་ iPhone ནང་ PhotoBridge ཁ་ཕྱེ་པར་པར་རིས་ལ་ཁ་གཏུགས་ཆོག་པ་བྱས་རྗེས་འདིའི་ཤོག་བུ་གསར་བསྐྲུན་བྱ་རོགས།",
      no_permission_short: "པར་རིས་ལ་ཁ་གཏུགས་མ་ཆོག། ཁྱེད་ཀྱི་ iPhone ནང་པར་རིས་ལ་ཁ་གཏུགས་ཆོག་པ་བྱས་རྗེས་འདིའི་ཤོག་བུ་གསར་བསྐྲུན་བྱ་རོགས།",
      cannot_connect: "གློག་གི་རྡུལ་ཕྲན་གྱི་ཞབས་ཞུ་ལ་མཐུད་ཆོག་མེད།",
      cannot_connect_hint: "གློག་གི་རྡུལ་ཕྲན་གྱི་ཞབས་ཞུ་ལ་མཐུད་ཆོག་མེད། ཁྱེད་ཀྱི་ iPhone ནང་ PhotoBridge འཁོར་བཞིན་ཡོད་མེད་ལ་བརྟག་དང་། གློག་ཀླད་དང་གློག་གི་རྡུལ་ཕྲན་ WiFi འདྲ་མཉམ་ཞིག་ཏུ་ཡོད་མེད་ལ་བརྟག་རོགས།",
      group_library: "ཚོགས་ཁང་།", group_smart: "བརྡ་རྫས་ཀྱི་རིགས་པ།", group_user: "ངའི་དཔེ་དེབ།",
      album: "དཔེ་དེབ།", total_items: "{0} ཡིག་ཆ།", album_empty: "དཔེ་དེབ་འདི་སྟོང་ཡོད།",
      network_error: "འཕྲིན་ལམ་འཆིག་ཆད། ཤོག་བུ་གསར་བསྐྲུན་བྱས་ནས་བསྐྱར་བདེན་རོགས།", select_day: "དེ་རིང་འདེམས།",
      fetching_album: "དཔེ་དེབ་འདིའི་ཡིག་ཆ་ཚང་མ་ལེན་བཞིན…", fetching_day: "དེ་རིང་གི་ཡིག་ཆ་ཚང་མ་ལེན་བཞིན…",
      fetch_failed: "ལེན་མ་ཐུབ། བསྐྱར་བདེན་རོགས།", folder_unsupported: "འདིའི་བརྗེ་ལེན་ནི་ཐུམ་ཚན་འདེམས་པ་རུང་མཁྱེན། དེ་བསྒང་《ZIP ཏུ་ཕབ་ལེན།》བེད་སྤྱད་རོགས།",
      folder_cancelled: "ཐུམ་ཚན་འདེམས་པ་ཆད་ཆད།", writing_progress: "{0} / {1} བྲིས་བཞིན…",
      export_done: "ཕྱིར་སྤྲད་མཐུན་སྒྲིལ། {0} གྲུབ", export_done_fail: "། {0} མ་གྲུབ",
      packing: "{0} ཡིག་ཆ་སྒྲིལ་བཞིན། སྐུ་མདུན་སྐྱོད་རོགས…", pack_failed: "སྒྲིལ་མ་ཐུབ། ",
      zip_done: "ZIP གསར་བཟོ་གྲུབ ({0} ཡིག་ཆ།) ཕབ་ལེན་འགོ་བཙུགས།", photos: "པར་རིས།"
    }
  };

  var RTL_LANGS = { "ar": true };
  var currentLang = "en";

  function t(key) {
    var tbl = I18N[currentLang] || I18N.en;
    if (tbl[key] != null) return tbl[key];
    if (I18N.en[key] != null) return I18N.en[key];
    return key;
  }
  function tfmt(key) {
    var str = t(key);
    for (var i = 1; i < arguments.length; i++) {
      str = str.replace(new RegExp('\\\\{' + (i - 1) + '\\\\}', 'g'), arguments[i]);
    }
    return str;
  }

  function applyRTL() {
    var rtl = !!RTL_LANGS[currentLang];
    document.documentElement.setAttribute('dir', rtl ? 'rtl' : 'ltr');
    document.documentElement.setAttribute('lang', currentLang);
  }

  function setLang(code) {
    currentLang = (I18N[code] ? code : (code === 'zh-Hans' || code === 'zh-Hant' ? code : 'en'));
    if (!I18N[currentLang]) currentLang = 'en';
    applyRTL();
    applyStaticText();
  }

  function applyStaticText() {
    document.title = t('title');
    document.getElementById('sideFoot').textContent = t('local_direct');
    document.getElementById('selectToggle').textContent = state.selecting ? t('done') : t('select');
    document.getElementById('loading').textContent = t('loading');
    updateSelection();
    document.getElementById('selAllView').textContent = t('select_all_loaded');
    document.getElementById('selAllAlbum').textContent = t('select_all_album');
    document.getElementById('selClear').textContent = t('clear');
    document.getElementById('segLabelExport').textContent = t('export_lbl');
    document.getElementById('segLabelSave').textContent = t('save_lbl');
    var modeBtns = modeSeg.querySelectorAll('button');
    modeBtns[0].textContent = t('original');
    modeBtns[1].textContent = t('copy_photo');
    var landBtns = landSeg.querySelectorAll('button');
    landBtns[0].textContent = t('download_folder');
    landBtns[1].textContent = t('download_zip');
    document.getElementById('runExport').textContent = t('start_export');
  }

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
    if (isNaN(d.getTime())) return t('unknown_date');
    var today = new Date();
    function sameDay(a, b) {
      return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    if (sameDay(d, today)) return t('today');
    if (sameDay(d, new Date(today.getTime() - 86400000))) return t('yesterday');
    return tfmt('date_fmt', d.getFullYear(), d.getMonth() + 1, d.getDate());
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
        albumTitle.textContent = t('cannot_access_album');
        albumSub.textContent = '';
        showHint(t('no_permission'));
        return false;
      }
      renderSidebar(data.albums || []);
      return true;
    }).catch(function () {
      albumSub.textContent = t('cannot_connect');
      showHint(t('cannot_connect_hint'));
      return false;
    });
  }

  function renderSidebar(albums) {
    var groups = { library: t('group_library'), smart: t('group_smart'), user: t('group_user') };
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
    albumTitle.textContent = title || t('album');
    albumSub.textContent = t('loading');
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
        showHint(t('no_permission_short'));
        return;
      }
      state.total = data.total;
      albumSub.textContent = tfmt('total_items', data.total);
      var items = data.items || [];
      if (state.offset === 0 && items.length === 0) {
        content.innerHTML = '<div class="empty">' + t('album_empty') + '</div>';
        state.hasMore = false;
        return;
      }
      renderItems(items);
      state.offset += items.length;
      state.hasMore = !!data.hasMore;
    }).catch(function () {
      state.hasMore = false;
      showHint(t('network_error'));
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
        pick.textContent = t('select_day');
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
    selectToggle.textContent = on ? t('done') : t('select');
    if (!on) setRunStatus('');
  }

  function updateSelection() {
    var count = 0;
    for (var id in state.selected) { if (state.selected[id]) count++; }
    state.selectedCount = count;
    selCountEl.textContent = tfmt('selected_count', count);
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
    runStatusPrompt(t('fetching_album'));
    fetch('/api/ids?album=' + encodeURIComponent(state.albumId))
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (!data.authorized) { setRunStatus(t('no_permission_short')); return; }
        addIds(data.ids || []);
        setRunStatus('');
      })
      .catch(function () { setRunStatus(t('fetch_failed')); });
  }

  function selectDay(ts) {
    if (!ts) { selectAllView(); return; }
    var d = new Date(ts * 1000);
    d.setHours(0, 0, 0, 0);
    var from = Math.floor(d.getTime() / 1000);
    var to = from + 86400;
    runStatusPrompt(t('fetching_day'));
    fetch('/api/ids?album=' + encodeURIComponent(state.albumId) + '&from=' + from + '&to=' + to)
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (!data.authorized) { setRunStatus(t('no_permission_short')); return; }
        addIds(data.ids || []);
        setRunStatus('');
      })
      .catch(function () { setRunStatus(t('fetch_failed')); });
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
      setRunStatus(t('folder_unsupported'));
      runExportBtn.disabled = false;
      return;
    }
    var root;
    try {
      root = await window.showDirectoryPicker({ mode: 'readwrite' });
    } catch (e) {
      setRunStatus(t('folder_cancelled'));
      runExportBtn.disabled = false;
      return;
    }
    var ok = 0, fail = 0;
    for (var i = 0; i < ids.length; i++) {
      setRunStatus(tfmt('writing_progress', i + 1, ids.length));
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
    var msg = tfmt('export_done', ok);
    if (fail) msg += tfmt('export_done_fail', fail);
    setRunStatus(msg);
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
    setRunStatus(tfmt('packing', ids.length));
    try {
      var res = await fetch('/api/zip', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ids: ids, mode: state.exportMode })
      });
      if (!res.ok) {
        var msg = 'HTTP ' + res.status;
        try { var j = await res.json(); if (j && j.error) msg = j.error; } catch (e) {}
        setRunStatus(t('pack_failed') + msg);
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
      setRunStatus(tfmt('zip_done', ids.length));
    } catch (e) {
      setRunStatus(t('pack_failed') + (e && e.message ? e.message : e));
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
      folderBtn.title = t('folder_unsupported');
    }
    var zipBtn = landSeg.querySelector('[data-land="zip"]');
    if (zipBtn) {
      var siblings = landSeg.querySelectorAll('button');
      for (var si = 0; si < siblings.length; si++) siblings[si].classList.toggle('on', siblings[si] === zipBtn);
      state.landMode = 'zip';
    }
  }

  // ===== 初始化：先设英文兜底，再拉取 App 语言 =====
  setLang('en');
  updateSelection();

  fetch('/api/lang').then(function (res) { return res.json(); }).then(function (data) {
    if (data && data.lang) setLang(data.lang);
  }).catch(function () {}).then(function () {
    loadAlbums().then(function (ok) {
      if (ok) selectAlbum('ALL', t('library'));
    });
  });
})();
</script>
</body>
</html>
"""
}
