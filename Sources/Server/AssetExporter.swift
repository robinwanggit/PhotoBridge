import Foundation
import Photos
import UIKit
import AVFoundation

/// 导出模式，对应 PRD 5.3 的两种语义。
enum ExportMode: String {
    /// 未修改的原片：取相册中的原始资源文件（原始格式与原始文件名）。
    case original
    /// 拷贝照片：取 iOS 处理后的成品文件。
    case copy
}

/// 一次导出的结果。
struct ExportedFile {
    let data: Data
    /// 文件名（不含目录）。
    let filename: String
    let mimeType: String
    /// 相对路径（拍摄日期目录 + 文件名），对应 PRD 5.7 的目录规则。
    let relativePath: String
}

enum ExportError: Error, LocalizedError {
    case unauthorized
    case assetNotFound
    /// 资产不可用（典型：原始数据仅在 iCloud，本机缺失）。
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:            return "相册权限未开启"
        case .assetNotFound:           return "资产不存在"
        case .unavailable(let reason): return reason
        }
    }
}

/// 把 PhotoKit 资产导出为可下载的文件。
enum AssetExporter {

    static func export(assetId: String, mode: ExportMode) throws -> ExportedFile {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw ExportError.unauthorized
        }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = assets.firstObject else {
            throw ExportError.assetNotFound
        }
        switch mode {
        case .original: return try exportOriginal(asset)
        case .copy:     return try exportCopy(asset)
        }
    }

    // MARK: - 批量打包 ZIP

    /// 就地把多个资产打包成 ZIP（store 方式，落临时文件），返回 ZIP 文件地址。
    ///
    /// 单资产失败（如原始数据仅在 iCloud）时跳过该资产、不阻塞整批（PRD 5.2）；
    /// 重名文件按 PRD 5.7 追加序号。全部失败时抛出第一个错误。
    static func packZip(ids: [String], mode: ExportMode) throws -> URL {
        guard let zip = ZipWriter() else {
            throw ExportError.unavailable("无法创建临时文件（磁盘空间不足？）")
        }
        var usedNames = Set<String>()
        var firstError: Error?
        var successCount = 0

        for id in ids {
            do {
                let file = try export(assetId: id, mode: mode)
                var name = file.relativePath
                if usedNames.contains(name) {
                    name = uniquified(name, in: usedNames)
                }
                usedNames.insert(name)
                zip.add(name: name, data: file.data)
                successCount += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        guard successCount > 0 else {
            zip.discard()
            throw firstError ?? ExportError.unavailable("没有可导出的项目")
        }
        return zip.finish()
    }

    /// 为重复的相对路径追加序号：`dir/name.jpg` -> `dir/name (1).jpg`。
    private static func uniquified(_ path: String, in used: Set<String>) -> String {
        let nsPath = path as NSString
        let dir = nsPath.deletingLastPathComponent
        let filename = nsPath.lastPathComponent as NSString
        let ext = filename.pathExtension
        let base = filename.deletingPathExtension
        var index = 1
        while true {
            let candidateName = ext.isEmpty
                ? "\(base) (\(index))"
                : "\(base) (\(index)).\(ext)"
            let candidate = dir.isEmpty ? candidateName : dir + "/" + candidateName
            if !used.contains(candidate) { return candidate }
            index += 1
        }
    }

    // MARK: - 未修改的原片

    private static func exportOriginal(_ asset: PHAsset) throws -> ExportedFile {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = primaryResource(resources, mediaType: asset.mediaType) else {
            throw ExportError.unavailable("没有可用的原始资源")
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let semaphore = DispatchSemaphore(value: 0)
        var collected = Data()
        var failure: Error?
        PHAssetResourceManager.default().requestData(for: resource,
                                                     options: options,
                                                     dataReceivedHandler: { chunk in
            collected.append(chunk)
        }, completionHandler: { error in
            failure = error
            semaphore.signal()
        })
        if semaphore.wait(timeout: .now() + 300) == .timedOut {
            throw ExportError.unavailable("读取原始资源超时（原始数据可能仅在 iCloud）")
        }
        if let failure = failure {
            throw ExportError.unavailable(failure.localizedDescription)
        }
        guard !collected.isEmpty else {
            throw ExportError.unavailable("原始资源内容为空")
        }

        let name = resource.originalFilename
        return ExportedFile(data: collected,
                            filename: name,
                            mimeType: mimeType(forFilename: name),
                            relativePath: relativePath(for: asset, filename: name))
    }

    private static func primaryResource(_ resources: [PHAssetResource],
                                        mediaType: PHAssetMediaType) -> PHAssetResource? {
        func first(_ type: PHAssetResourceType) -> PHAssetResource? {
            return resources.first { $0.type == type }
        }
        if mediaType == .video {
            return first(.fullSizeVideo) ?? first(.video) ?? resources.first
        }
        return first(.fullSizePhoto) ?? first(.photo) ?? resources.first
    }

    // MARK: - 拷贝照片

    private static func exportCopy(_ asset: PHAsset) throws -> ExportedFile {
        if asset.mediaType == .video {
            return try exportVideoCopy(asset)
        }
        return try exportImageCopy(asset)
    }

    private static func exportImageCopy(_ asset: PHAsset) throws -> ExportedFile {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        let semaphore = DispatchSemaphore(value: 0)
        var imageData: Data?
        var dataUTI: String?
        var failure: Error?
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, info in
            imageData = data
            dataUTI = uti
            if let info = info, let error = info[PHImageErrorKey] as? Error {
                failure = error
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 300) == .timedOut {
            throw ExportError.unavailable("渲染成品超时（原始数据可能仅在 iCloud）")
        }
        if let failure = failure {
            throw ExportError.unavailable(failure.localizedDescription)
        }
        guard let data = imageData, !data.isEmpty else {
            throw ExportError.unavailable("成品数据为空")
        }

        let ext = imageExtension(forUTI: dataUTI)
        let name = baseName(of: asset) + "." + ext
        return ExportedFile(data: data,
                            filename: name,
                            mimeType: mimeType(forExtension: ext),
                            relativePath: relativePath(for: asset, filename: name))
    }

    private static func exportVideoCopy(_ asset: PHAsset) throws -> ExportedFile {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat

        let semaphore = DispatchSemaphore(value: 0)
        var session: AVAssetExportSession?
        var failure: Error?
        PHImageManager.default().requestExportSession(forVideo: asset,
                                                      options: options,
                                                      exportPreset: AVAssetExportPresetPassthrough) { result, info in
            session = result
            if let info = info, let error = info[PHImageErrorKey] as? Error {
                failure = error
            }
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 60) == .timedOut {
            throw ExportError.unavailable("创建视频导出会话超时")
        }
        if let failure = failure {
            throw ExportError.unavailable(failure.localizedDescription)
        }
        guard let exportSession = session else {
            throw ExportError.unavailable("无法创建视频导出会话")
        }

        let outputType: AVFileType = exportSession.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let ext = (outputType == .mp4) ? "mp4" : "mov"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        exportSession.outputURL = tempURL
        exportSession.outputFileType = outputType

        let exportSemaphore = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously { exportSemaphore.signal() }
        if exportSemaphore.wait(timeout: .now() + 3600) == .timedOut {
            exportSession.cancelExport()
            throw ExportError.unavailable("视频导出超时")
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }
        guard exportSession.status == .completed else {
            throw ExportError.unavailable(exportSession.error?.localizedDescription ?? "视频导出失败")
        }
        let data = try Data(contentsOf: tempURL)

        let name = baseName(of: asset) + "." + ext
        return ExportedFile(data: data,
                            filename: name,
                            mimeType: mimeType(forExtension: ext),
                            relativePath: relativePath(for: asset, filename: name))
    }

    // MARK: - 命名与类型工具

    private static func baseName(of asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        let wanted: PHAssetResourceType
        if asset.mediaType == .video {
            wanted = .fullSizeVideo
        } else {
            wanted = .fullSizePhoto
        }
        let resource = resources.first { $0.type == wanted }
            ?? resources.first { asset.mediaType == .video ? $0.type == .video : $0.type == .photo }
            ?? resources.first
        if let resource = resource {
            return stripExtension(resource.originalFilename)
        }
        return "Photo_" + String(Int(asset.creationDate?.timeIntervalSince1970 ?? 0))
    }

    private static func stripExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return name }
        return String(name[name.startIndex..<dot])
    }

    private static func relativePath(for asset: PHAsset, filename: String) -> String {
        return dayString(asset.creationDate) + "/" + filename
    }

    private static func dayString(_ date: Date?) -> String {
        guard let date = date else { return "unknown" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func imageExtension(forUTI uti: String?) -> String {
        switch uti {
        case "public.jpeg":              return "jpg"
        case "public.heic", "public.heif": return "heic"
        case "public.png":               return "png"
        case "public.tiff":              return "tiff"
        case "com.compuserve.gif":       return "gif"
        default:                         return "jpg"
        }
    }

    private static func mimeType(forFilename name: String) -> String {
        return mimeType(forExtension: (name as NSString).pathExtension.lowercased())
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "heic":       return "image/heic"
        case "heif":       return "image/heif"
        case "png":        return "image/png"
        case "gif":        return "image/gif"
        case "tiff", "tif": return "image/tiff"
        case "dng":        return "image/x-adobe-dng"
        case "mov":        return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "avi":        return "video/x-msvideo"
        default:           return "application/octet-stream"
        }
    }
}
