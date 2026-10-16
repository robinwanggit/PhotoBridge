# PhotoBridge（M4 多选与导出）

把 iPhone 相册通过无线传到 Windows 电脑的 App。当前为 **M4 里程碑：多选 + 两种导出模式 + 两种落盘方式**。

> 进度：M1（iOS 工程骨架 + 内嵌 HTTPS 服务器 + 自签证书）已通过；M2（PIN 鉴权、Bonjour 发现）按规划跳过；M3（相册浏览）已通过；M4 在浏览之上加入了「选择并导出到电脑」的能力。

## 本里程碑（M4）能做什么

在电脑 Chrome/Edge 打开 App 显示的地址后，可以：

- 沿用 M3 的相册浏览：相册列表、日期分组缩略图、懒加载、分页、放大预览；
- 点右上角 **「选择」** 进入多选模式，然后：
  - **单选**：点击任意缩略图切换选中；
  - **全选已加载**：选中当前视图里已经加载出来的项目；
  - **全选本相册**：选中当前相册的全部项目（含尚未加载出来的）；
  - **按日期整选**：在任意日期标题右侧点「选本日」，选中该日全部项目；
  - **跨相册保持**：切换到别的相册后，已选集合仍然保留；
- 选择 **两种导出模式**：
  - **未修改的原片**（对应照片分享里的「导出未修改的原片」）：取原始资源，保留原始格式与文件名；
  - **拷贝照片**（对应「拷贝照片」）：取 iOS 处理后的成品；
- 选择 **两种落盘方式**：
  - **下载到文件夹**：用浏览器的 File System Access API 直接把文件写进你选的文件夹（仅 Chrome/Edge 支持）；
  - **下载为 ZIP**：由手机端打包成一个 ZIP 下载，内部按「拍摄日期目录 / 文件名」组织；
- 重名文件自动追加序号（如 `IMG_0001 (1).HEIC`）。

> 说明：M4 让「选择 + 导出 + 两种落盘方式」跑通。**传输进度面板、速度、中断提示与断点续传**属于 M5–M6，尚未实现；因此「下载到文件夹」过程中只在底栏显示简单的进度文案，ZIP 模式由浏览器自身的下载器接管。

## 目录结构

```
PhotoBridge/
├── project.yml                      # XcodeGen 工程配置（无 Mac 时由 CI 生成 .xcodeproj）
├── Sources/
│   ├── App/
│   │   ├── PhotoBridgeApp.swift     # App 入口
│   │   └── ContentView.swift        # 主界面：开启服务、请求相册权限、展示地址与二维码
│   ├── Server/
│   │   ├── Certificate.swift        # 加载内置自签证书为 SecIdentity
│   │   ├── PhotoLibrary.swift       # PhotoKit 数据源：相册列表 / 资产分页 / 整选 id / 缩略图
│   │   ├── AssetExporter.swift      # 导出：未修改的原片 / 拷贝照片；批量打包 ZIP
│   │   ├── ZipWriter.swift          # 极简 ZIP 打包器（store 方式，落临时文件）
│   │   ├── WebApp.swift             # 内嵌的单页网页应用（浏览 + 多选 + 导出）
│   │   └── HTTPServer.swift         # NWListener 内嵌 HTTPS 服务器 + 路由 + 文件流式下发
│   └── Resources/
│       ├── Info.plist               # 含局域网 + 相册权限说明
│       ├── cert.p12                 # 内置自签证书（密码 photobridge，历史文件，已改为源码内嵌）
│       └── Assets.xcassets/
└── .github/workflows/build.yml      # CI：macOS runner 产出未签名 IPA
```

## 服务端接口（M4）

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 返回内嵌的单页网页应用 |
| GET | `/api/albums` | 相册列表 `{ authorized, status, albums:[{id,title,kind,count}] }` |
| GET | `/api/assets?album=<id>&offset=<n>&limit=<n>` | 某相册的资产分页（按拍摄时间倒序） |
| GET | `/api/ids?album=<id>&from=<秒>&to=<秒>` | 某相册（可选拍摄时间区间）内全部资产 id，供前端整选 |
| GET | `/api/thumb?id=<资产id>&w=<像素>` | 正方形 JPEG 缩略图（w 限制在 64–2048） |
| GET | `/api/export?id=<资产id>&mode=original\|copy` | 导出单个文件；响应头带 `Content-Disposition` 与 `X-Photo-Path`（日期目录/文件名） |
| POST | `/api/zip` | 请求体 `{ ids:[...], mode:"original"\|copy" }`，返回打包好的 ZIP |

- `album=ALL` 表示「图库」（系统用户图库/相机胶卷）。
- 资产 id 与相册 id 均为 PhotoKit 的 `localIdentifier`；前端会对其 URL 编码。
- 单个资产不可用（原始数据仅在 iCloud、本机缺失）时会被跳过并计入失败，不阻塞整批（PRD 5.2）。

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

## 使用验证（M4）

1. 确保 iPhone 与 Windows 电脑连**同一个 WiFi**。
2. 打开 PhotoBridge，点击右上角「开启服务」。首次会弹出 **相册访问权限** 请求，请选择「允许访问所有照片」。
3. 界面会显示 `https://<手机IP>:8443` 与二维码。
4. 在电脑 Chrome/Edge 中输入该地址（或扫码），浏览器提示证书不安全时点「高级」→「继续前往」。
5. 点右上角 **「选择」**，勾选若干张照片（可试「全选已加载 / 全选本相册 / 选本日」）。
6. 选择导出模式与落盘方式：
   - 选「下载到文件夹」→ 点「开始导出」→ 在弹窗中选择目标文件夹 → 底栏显示写入进度，完成后显示「成功 N 张」；
   - 选「下载为 ZIP」→ 点「开始导出」→ 浏览器开始下载 `PhotoBridge-original.zip` / `PhotoBridge-copy.zip`。
7. 打开目标文件夹 / 解压 ZIP，文件按「拍摄日期目录」组织。

> 若页面提示「相册权限未开启」，请在 iPhone 上授权相册访问后刷新网页。
> 若地址显示 `—`，说明未获取到 WiFi 接口地址，请确认手机已连接 WiFi（非蜂窝）。
> 非 Chrome/Edge 浏览器不支持「下载到文件夹」，会自动禁用该项并建议改用 ZIP。

## M4 已知限制（后续里程碑处理）

- 自签证书为**随包共享**的单张证书（所有安装共用同一私钥），后续应改为每台设备首次启动时生成独立证书。
- 无 PIN 鉴权、无 Bonjour/mDNS 自动发现，需手动输入 IP（M2 按规划跳过）。
- 传输进度仅有简单文案，缺少总张数/已完成张数/速度/中断原因面板与断点续传（M5–M6）。
- ZIP 为手机端**先打包成临时文件再流式下发**；浏览器侧用 `fetch` 收成 Blob 触发下载，超大选择在浏览器侧仍会占用内存（M5 改为流式）。
- 「下载到文件夹」逐张串行下载写入，未做并发与断点续传。
- iCloud 上未落到本机的照片，导出可能需要从云端下载或失败（已允许网络访问，失败项跳过）。
- 不支持后台运行，传输期间需保持 App 在前台（App 已设置屏幕常亮）。
