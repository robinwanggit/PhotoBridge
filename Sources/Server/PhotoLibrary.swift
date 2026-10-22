import Foundation
import Photos
import UIKit

/// PhotoKit 数据源。M3 阶段只做「浏览」：
/// 读取图库 / 相册列表、按分页返回资产元数据、按需生成缩略图。
///
/// 选择与下载（导出原片 / 拷贝照片）留待 M4。
final class PhotoLibrary {
    static let shared = PhotoLibrary()

    private let imageManager = PHCachingImageManager()

    private init() {}

    // MARK: - 本地化相册标题

    /// 按 App 当前语言返回的相册名：图库 / Library / …
    private static func localizedTitle(_ key: String) -> String {
        let lang = Localization.shared.currentLanguage
        let map: [String: [String: String]] = [
            "library":  ["zh-Hans":"图库","zh-Hant":"圖庫","en":"Library","fr":"Bibliothèque","de":"Mediathek","ja":"ライブラリ","ko":"라이브러리","it":"Libreria","es":"Librería","hi":"लाइब्रेरी","ar":"المكتبة","ru":"Медиатека","bn":"লাইব্রেরি","pt":"Biblioteca","id":"Perpustakaan","th":"แกลเลอรี","mn":"Цом","bo":"པར་མཛོད་ཁང་"],
            "untitled": ["zh-Hans":"未命名","zh-Hant":"未命名","en":"Untitled","fr":"Sans titre","de":"Unbenannt","ja":"無題","ko":"제목 없음","it":"Senza titolo","es":"Sin título","hi":"बिना शीर्षक के","ar":"بلا عنوان","ru":"Без названия","bn":"শিরোনামহীন","pt":"Sem título","id":"Tanpa judul","th":"ไม่มีชื่อ","mn":"Нэргүй","bo":"མིང་མེད་པ་"],
        ]
        return map[key]?[lang] ?? map[key]?["en"] ?? key
    }

    /// 当前语言下「最近删除 / 隐藏」等要排除的系统相册标题。
    private static var excludedTitles: Set<String> {
        // 系统相册 localizedTitle 由设备当前语言决定，与 App 语言独立
        let device = Locale.current.languageCode
        switch device {
        case "zh":  return ["最近删除", "隐藏"]
        case "ja":  return ["最近削除した項目", "非表示"]
        case "ko":  return ["최근 삭제한 항목", "숨겨진 항목"]
        case "fr":  return ["Supprimés récemment", "Masqués"]
        case "de":  return ["Zuletzt gelöscht", "Ausgeblendet"]
        case "es":  return ["Eliminados recientemente", "Ocultos"]
        case "it":  return ["Eliminati di recente", "Nascosti"]
        case "ru":  return ["Недавно удаленные", "Скрытые"]
        case "pt":  return ["Apagados recentemente", "Ocultos"]
        case "hi":  return ["हाल ही में हटाए गए", "छिपा हुआ"]
        default:    return ["Recently Deleted", "Hidden"]
        }
    }

    // MARK: - 授权状态

    /// 当前相册授权状态。只读取，不主动弹系统授权框（弹框由 App 端负责）。
    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    private var isAuthorized: Bool {
        let status = authorizationStatus()
        return status == .authorized || status == .limited
    }

    private func statusString(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted:    return "restricted"
        case .denied:        return "denied"
        case .authorized:    return "authorized"
        case .limited:       return "limited"
        @unknown default:    return "unknown"
        }
    }

    // MARK: - 相册列表

    /// 返回 `{ authorized, status, albums: [{ id, title, kind, count }] }`。
    /// kind: library（图库）/ smart（智能相册）/ user（我的相簿）。
    func albumsJSON() -> [String: Any] {
        let status = authorizationStatus()
        guard isAuthorized else {
            return [
                "authorized": false,
                "status": statusString(status),
                "albums": [Any](),
            ]
        }

        var albums: [[String: Any]] = []

        // 「图库」= 系统用户图库（相机胶卷），与系统相册 App 的「图库」一致
        albums.append([
            "id": "ALL",
            "title": Self.localizedTitle("library"),
            "kind": "library",
            "count": libraryFetch(options: nil).count,
        ])

        // 智能相册 / 媒体类型
        let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smart.enumerateObjects { collection, _, _ in
            let subtype = collection.assetCollectionSubtype
            guard subtype != .smartAlbumUserLibrary, subtype != .smartAlbumAllHidden else { return }
            let title = collection.localizedTitle ?? ""
            guard !Self.excludedTitles.contains(title) else { return }
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return }
            albums.append([
                "id": collection.localIdentifier,
                "title": title.isEmpty ? Self.localizedTitle("untitled") : title,
                "kind": "smart",
                "count": count,
            ])
        }

        // 用户自建相簿
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return }
            albums.append([
                "id": collection.localIdentifier,
                "title": collection.localizedTitle ?? Self.localizedTitle("untitled"),
                "kind": "user",
                "count": count,
            ])
        }

        return [
            "authorized": true,
            "status": "authorized",
            "albums": albums,
        ]
    }

    // MARK: - 资产分页

    /// 返回某相册内按拍摄时间倒序的资产分页。
    /// 返回 `{ authorized, status, items, total, hasMore }`。
    func assetsJSON(album: String, offset: Int, limit: Int) -> [String: Any] {
        let status = authorizationStatus()
        guard isAuthorized else {
            return [
                "authorized": false,
                "status": statusString(status),
                "items": [Any](),
                "total": 0,
                "hasMore": false,
            ]
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        guard let fetch = fetchResult(album: album, options: options) else {
            return [
                "authorized": true,
                "status": "authorized",
                "items": [Any](),
                "total": 0,
                "hasMore": false,
            ]
        }

        let total = fetch.count
        var items: [[String: Any]] = []
        var hasMore = false

        if offset >= 0, offset < total, limit > 0 {
            let end = min(offset + limit, total)
            items.reserveCapacity(end - offset)
            for index in offset..<end {
                let asset = fetch.object(at: index)
                var item: [String: Any] = [
                    "id": asset.localIdentifier,
                    "created": asset.creationDate?.timeIntervalSince1970 ?? 0,
                    "w": asset.pixelWidth,
                    "h": asset.pixelHeight,
                    "isVideo": asset.mediaType == .video,
                    "favorite": asset.isFavorite,
                ]
                if asset.mediaType == .video {
                    item["duration"] = asset.duration
                }
                item["fmt"] = formatLabel(for: asset)
                items.append(item)
            }
            hasMore = end < total
        }

        return [
            "authorized": true,
            "status": "authorized",
            "items": items,
            "total": total,
            "hasMore": hasMore,
        ]
    }

    /// 资产在相册中的原始格式标签（HEIC / JPG / PNG / MOV …），供电脑端核对拿到的是哪种格式。
    private func formatLabel(for asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        let wanted: PHAssetResourceType = (asset.mediaType == .video) ? .fullSizeVideo : .fullSizePhoto
        let resource = resources.first { $0.type == wanted }
            ?? resources.first { $0.type == .photo || $0.type == .fullSizePhoto
                                 || $0.type == .video || $0.type == .fullSizeVideo }
            ?? resources.first
        guard let name = resource?.originalFilename else { return "" }
        return (name as NSString).pathExtension.uppercased()
    }

    // MARK: - 资产 id 列表（整选）

    /// 返回某相册（可限定拍摄时间区间）内全部资产的 id，供前端「整选」使用。
    /// 返回 `{ authorized, status, ids }`。from / to 为 Unix 秒（闭区间下界、开区间上界）。
    func assetIDsJSON(album: String, from: Double?, to: Double?) -> [String: Any] {
        let status = authorizationStatus()
        guard isAuthorized else {
            return ["authorized": false, "status": statusString(status), "ids": [Any]()]
        }

        let options = PHFetchOptions()
        var predicates: [NSPredicate] = []
        if let from = from {
            predicates.append(NSPredicate(format: "creationDate >= %@", Date(timeIntervalSince1970: from) as NSDate))
        }
        if let to = to {
            predicates.append(NSPredicate(format: "creationDate < %@", Date(timeIntervalSince1970: to) as NSDate))
        }
        if !predicates.isEmpty {
            options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        guard let fetch = fetchResult(album: album, options: options) else {
            return ["authorized": true, "status": "authorized", "ids": [String]()]
        }
        var ids: [String] = []
        ids.reserveCapacity(fetch.count)
        fetch.enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }

        return ["authorized": true, "status": "authorized", "ids": ids]
    }

    // MARK: - 缩略图

    /// 生成指定资产的正方形 JPEG 缩略图。失败返回 nil。
    func thumbnailJPEG(id: String, width: Int) -> Data? {
        guard isAuthorized, !id.isEmpty else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let side = CGFloat(min(max(width, 64), 2048))
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        var image: UIImage?
        let semaphore = DispatchSemaphore(value: 0)
        imageManager.requestImage(for: asset,
                                  targetSize: CGSize(width: side, height: side),
                                  contentMode: .aspectFill,
                                  options: options) { result, _ in
            if image == nil { image = result }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 20) == .timedOut { return nil }
        guard let image = image else { return nil }
        return image.jpegData(compressionQuality: 0.8)
    }

    // MARK: - 工具

    /// 按相册 id 取数；"ALL" 走系统用户图库，其余按 localIdentifier 解析相册。找不到返回 nil。
    private func fetchResult(album: String, options: PHFetchOptions?) -> PHFetchResult<PHAsset>? {
        if album == "ALL" {
            return libraryFetch(options: options)
        }
        guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album],
                                                                      options: nil).firstObject else {
            return nil
        }
        return PHAsset.fetchAssets(in: collection, options: options)
    }

    /// 「图库」使用的取数：优先取系统用户图库集合，取不到则退回全库。
    private func libraryFetch(options: PHFetchOptions?) -> PHFetchResult<PHAsset> {
        let library = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                             subtype: .smartAlbumUserLibrary,
                                                             options: nil).firstObject
        if let library = library {
            return PHAsset.fetchAssets(in: library, options: options)
        }
        return PHAsset.fetchAssets(with: options)
    }
}
