import SwiftUI
import UIKit
import CoreImage
import Photos

/// 主界面：开启/停止服务，展示访问地址（IP + 端口）与二维码。
struct ContentView: View {
    @ObservedObject private var loc = Localization.shared
    @State private var server = HTTPServer()
    @State private var isRunning = false
    @State private var port: UInt16 = 0
    @State private var errorMessage: String?
    @State private var showLanguagePicker = false

    private var ipAddress: String { HTTPServer.localIPv4Address() ?? "—" }
    private var urlString: String {
        guard isRunning, port != 0 else { return "" }
        return "https://\(ipAddress):\(port)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                statusCard
                if isRunning {
                    addressCard
                    qrCard
                }
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("PhotoBridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showLanguagePicker = true
                    } label: {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel(loc.tr("language"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isRunning ? loc.tr("stop_service") : loc.tr("start_service")) {
                        isRunning ? stopService() : startService()
                    }
                }
            }
            .sheet(isPresented: $showLanguagePicker) {
                LanguagePickerView()
            }
        }
        .environment(\.layoutDirection, loc.isRTL ? .rightToLeft : .leftToRight)
    }

    // MARK: - 服务控制

    private func startService() {
        errorMessage = nil
        // 先请求相册权限，否则电脑端打开页面后无法浏览相册
        requestPhotoAccess()
        do {
            let boundPort = try server.start()
            port = boundPort
            isRunning = true
            // 传输期间保持屏幕常亮，避免自动息屏导致服务中断
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = String(format: loc.tr("start_failed"), error.localizedDescription)
        }
    }

    private func stopService() {
        server.stop()
        isRunning = false
        port = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 请求相册读取权限（首次会弹系统授权框）。回调不阻塞界面。
    private func requestPhotoAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
    }

    // MARK: - 子视图

    private var statusCard: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(isRunning ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(isRunning ? loc.tr("service_running") : loc.tr("service_stopped"))
                    .font(.headline)
            }
            Text(isRunning ? loc.tr("running_hint") : loc.tr("stopped_hint"))
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var addressCard: some View {
        VStack(spacing: 6) {
            Text(loc.tr("access_address"))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(urlString)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .textSelection(.enabled)
            if ipAddress == "—" {
                Text(loc.tr("no_wifi"))
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Text(loc.tr("same_wifi"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var qrCard: some View {
        VStack(spacing: 10) {
            if let image = qrCodeImage(for: urlString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 180, height: 180)
                    .padding(8)
                    .background(Color.white)
                    .cornerRadius(12)
            }
            Text(loc.tr("scan_qr"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - 二维码

    private func qrCodeImage(for string: String) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaled = output.transformed(by: scale)
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - 语言选择弹窗

/// 语言选择列表：包含「跟随系统」与全部 18 种支持语言。
struct LanguagePickerView: View {
    @ObservedObject private var loc = Localization.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        loc.setLanguage(nil)
                    } label: {
                        HStack {
                            Text(loc.tr("follow_system"))
                            Spacer()
                            if UserDefaults.standard.string(forKey: "AppLanguage") == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
                Section {
                    ForEach(Localization.supported, id: \.code) { lang in
                        Button {
                            loc.setLanguage(lang.code)
                        } label: {
                            HStack {
                                Text(lang.name)
                                Spacer()
                                if loc.currentLanguage == lang.code {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle(loc.tr("select_language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(loc.tr("done")) {
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, loc.isRTL ? .rightToLeft : .leftToRight)
    }
}
