import SwiftUI
import UIKit
import CoreImage

/// M1 主界面：开启/停止服务，展示访问地址（IP + 端口）与二维码。
struct ContentView: View {
    @State private var server = HTTPServer()
    @State private var isRunning = false
    @State private var port: UInt16 = 0
    @State private var errorMessage: String?

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
                Button(isRunning ? "停止服务" : "开启服务") {
                    isRunning ? stopService() : startService()
                }
            }
        }
    }

    // MARK: - 服务控制

    private func startService() {
        errorMessage = nil
        do {
            let boundPort = try server.start()
            port = boundPort
            isRunning = true
            // 传输期间保持屏幕常亮，避免自动息屏导致服务中断
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            errorMessage = "服务启动失败：\(error.localizedDescription)"
        }
    }

    private func stopService() {
        server.stop()
        isRunning = false
        port = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - 子视图

    private var statusCard: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(isRunning ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(isRunning ? "服务已开启" : "服务未开启")
                    .font(.headline)
            }
            Text(isRunning ? "电脑浏览器打开下方地址即可访问" : "点击右上角「开启服务」")
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
            Text("访问地址")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(urlString)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .textSelection(.enabled)
            if ipAddress == "—" {
                Text("未获取到 WiFi 地址，请确认手机已连接 WiFi")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Text("确保电脑与手机连接同一个 WiFi")
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
            Text("扫码或在电脑浏览器中输入上方地址")
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
