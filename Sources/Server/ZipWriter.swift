import Foundation

/// 极简 ZIP 打包器：只做 store（不压缩），逐条目写入磁盘临时文件。
///
/// 照片与视频本身已压缩，store 足够且几乎不耗 CPU；条目边写边落盘，
/// 不在内存里拼装整个 ZIP，避免大相册造成内存峰值。
/// 供「下载为 ZIP」落盘方式使用（PRD 5.7 zip 内部按日期目录 + 文件名）。
final class ZipWriter {

    private struct Entry {
        let name: String
        let crc: UInt32
        let size: UInt32
        let offset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private let fileURL: URL
    private let handle: FileHandle
    private var entries: [Entry] = []
    private var offset: UInt64 = 0
    private var finished = false

    /// 创建临时 ZIP 文件。失败（无磁盘空间等）返回 nil。
    init?() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photobridge-" + UUID().uuidString + ".zip")
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else {
            return nil
        }
        self.fileURL = url
        self.handle = handle
    }

    /// 追加一个条目。`name` 使用 `/` 分隔的相对路径（日期目录 + 文件名）。
    func add(name: String, data: Data) {
        guard !finished, let nameData = name.data(using: .utf8) else { return }
        let dos = ZipWriter.dosDateTime(Date())
        let crc = ZipWriter.crc32(data)
        let size = UInt32(truncatingIfNeeded: data.count)
        let nameLen = UInt16(truncatingIfNeeded: nameData.count)
        let startOffset = offset

        var local = Data()
        local.appendLE(UInt32(0x04034b50))  // local file header signature
        local.appendLE(UInt16(20))          // version needed to extract
        local.appendLE(UInt16(0x0800))      // general purpose flag: UTF-8 文件名
        local.appendLE(UInt16(0))           // compression method: store
        local.appendLE(dos.time)
        local.appendLE(dos.date)
        local.appendLE(crc)
        local.appendLE(size)                // compressed size
        local.appendLE(size)                // uncompressed size
        local.appendLE(nameLen)
        local.appendLE(UInt16(0))           // extra field length
        local.append(nameData)

        append(local)
        append(data)

        entries.append(Entry(name: name,
                              crc: crc,
                              size: size,
                              offset: UInt32(truncatingIfNeeded: startOffset),
                              dosTime: dos.time,
                              dosDate: dos.date))
    }

    /// 写入中央目录并收尾，返回临时 ZIP 文件地址。调用后本对象不再写入。
    func finish() -> URL {
        guard !finished else { return fileURL }
        finished = true

        let centralOffset = offset
        var central = Data()
        for entry in entries {
            guard let nameData = entry.name.data(using: .utf8) else { continue }
            central.appendLE(UInt32(0x02014b50)) // central directory signature
            central.appendLE(UInt16(20))    // version made by
            central.appendLE(UInt16(20))    // version needed
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))     // store
            central.appendLE(entry.dosTime)
            central.appendLE(entry.dosDate)
            central.appendLE(entry.crc)
            central.appendLE(entry.size)
            central.appendLE(entry.size)
            central.appendLE(UInt16(truncatingIfNeeded: nameData.count))
            central.appendLE(UInt16(0))     // extra length
            central.appendLE(UInt16(0))     // comment length
            central.appendLE(UInt16(0))     // disk number start
            central.appendLE(UInt16(0))     // internal attributes
            central.appendLE(UInt32(0))     // external attributes
            central.appendLE(entry.offset)
            central.append(nameData)
        }
        append(central)

        let count = UInt16(truncatingIfNeeded: entries.count)
        var end = Data()
        end.appendLE(UInt32(0x06054b50))    // end of central directory signature
        end.appendLE(UInt16(0))             // disk number
        end.appendLE(UInt16(0))             // disk with central directory
        end.appendLE(count)                 // entries on this disk
        end.appendLE(count)                 // total entries
        end.appendLE(UInt32(truncatingIfNeeded: central.count))
        end.appendLE(UInt32(truncatingIfNeeded: centralOffset))
        end.appendLE(UInt16(0))             // comment length
        append(end)

        try? handle.close()
        return fileURL
    }

    /// 放弃本次打包，删除临时文件。
    func discard() {
        finished = true
        try? handle.close()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - 内部写入

    private func append(_ data: Data) {
        handle.write(data)
        offset += UInt64(data.count)
    }

    // MARK: - CRC32 / DOS 时间

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// 把日期转换为 ZIP 使用的 DOS 时间/日期（本地时间）。
    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((parts.year ?? 1980) - 1980, 0)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        let second = parts.second ?? 0
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        let dosDate = UInt16((year << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
}

// MARK: - 小端写入

private extension Data {
    /// 小端写入 16 位无符号整数。
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    /// 小端写入 32 位无符号整数。
    mutating func appendLE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
