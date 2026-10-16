# PhotoBridge（M1 工程骨架）

把 iPhone 相册通过无线传到 Windows 电脑的 App。本仓库为 M1 里程碑：**iOS 工程骨架 + 内嵌 HTTPS 服务器 + 自签证书**。

> M1 可验证目标：在 iPhone 上开启服务后，同一 WiFi 的电脑浏览器能打开 App 显示的 HTTPS 地址并看到欢迎页面（接受自签证书后）。

## 目录结构

```
PhotoBridge/
├── project.yml                      # XcodeGen 工程配置（无 Mac 时由 CI 生成 .xcodeproj）
├── Sources/
│   ├── App/
│   │   ├── PhotoBridgeApp.swift     # App 入口
│   │   └── ContentView.swift        # 主界面：开启服务、展示地址与二维码
│   ├── Server/
│   │   ├── Certificate.swift        # 加载内置自签证书为 SecIdentity
│   │   └── HTTPServer.swift         # NWListener 内嵌 HTTPS 服务器
│   └── Resources/
│       ├── Info.plist
│       ├── cert.p12                 # 内置自签证书（密码 photobridge）
│       └── Assets.xcassets/
└── .github/workflows/build.yml      # CI：macOS runner 产出未签名 IPA
```

## 构建（无 Mac，走 CI）

1. 将本目录推送到 GitHub 仓库。
2. 在仓库 **Actions** 中手动运行 `Build Unsigned IPA`（或 push 到 `main` 自动触发）。
3. 等待构建完成，从 Artifacts 下载 `PhotoBridge-unsigned-ipa`，解压得到 `PhotoBridge.ipa`。

> 若用 Mac 本地构建：安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 后运行 `xcodegen generate`，再用 Xcode 打开 `PhotoBridge.xcodeproj`。

## 安装到 iPhone（免费 Apple ID，7 天签名）

需要在 Windows 电脑上操作（不需要 Mac）：

1. 安装 [iTunes](https://www.apple.com/itunes/)（提供 Apple Mobile Device 驱动）。
2. 安装 [Sideloadly](https://sideloadly.io/)（或 AltStore）。
3. 用数据线连接 iPhone，打开 Sideloadly：
   - 拖入 `PhotoBridge.ipa`
   - 输入你的 Apple ID（免费账号即可）
   - 点击 Start，等待签名并安装完成
4. 在 iPhone 上：**设置 → 通用 → VPN与设备管理**，信任你的 Apple ID 证书。
5. 打开 PhotoBridge App。

> 免费 Apple ID 签名的 App **7 天后会过期**，到期需用 Sideloadly 重新签名安装。若使用 AltStore 并让 AltServer 在同 WiFi 下运行，可自动刷新签名。

## 使用验证（M1）

1. 确保 iPhone 与 Windows 电脑连**同一个 WiFi**。
2. 打开 PhotoBridge，点击右上角「开启服务」。
3. 界面会显示 `https://<手机IP>:8443` 与二维码。
4. 在电脑 Chrome/Edge 中输入该地址（或扫码）。
5. 浏览器提示证书不安全 → 点「高级」→「继续前往」。
6. 看到绿色"PhotoBridge 已连接"卡片即表示 M1 验证通过。

> 若地址显示 `—`，说明未获取到 WiFi 接口地址，请确认手机已连接 WiFi（非蜂窝）。

## M1 已知限制（后续里程碑处理）

- 自签证书为**随包共享**的单张证书（所有安装共用同一私钥），后续应改为每台设备首次启动时生成独立证书。
- HTTP 服务器目前只返回固定欢迎页，尚未接入相册数据。
- 不支持 Bonjour/mDNS 自动发现，需手动输入 IP。
- 不支持后台运行，传输期间需保持 App 在前台（App 已设置屏幕常亮）。
