# Mini Bujo

一本放在 Mac、iPhone 和 iPad 里的极简子弹手帐。原生 SwiftUI 界面，宽屏左右摊开，手机竖屏上下排布；不用注册账号，也没有业务后端。

- **月 / 周 / 日计划**：日历标记、时间轴、任务、事件、笔记和未完成任务迁移。
- **习惯与身体记录**：每周打卡、评分、睡眠、体重和静息心率（bpm），分别展示睡眠条和趋势图。
- **心情像素**：用颜色记录一年里的每天，自定义颜色含义。
- **集合与搜索**：长期清单、自定义卡片和全文检索。
- **系统提醒**：重要日期、带时间的安排、晚间打卡和周日小结。
- **可编辑显示**：顶栏点「显示」，可以改笔记本形态（点阵 / 横线 / 方格 / 空白）、字体（手写体 / 圆体 / 衬线 / 系统 / 等宽）和字体大小（小 / 标准 / 大 / 特大）、背景颜色（经典纸白 / 米黄 / 淡绿 / 淡蓝 / 淡粉）。显示偏好只存本机，不写进手帐文件，不影响和网页版互通。

### 系统字体开得很大时

手帐是固定版面的纸面：月历的星期栏、打卡表格这类地方一格只有一个词。系统「字体大小」开到无障碍级别时，系统控件会跟着放大，曾把星期栏的 Mon / Tue / Sun 撑成两行、整张日历错位。现在 App 把系统缩放限制在不撑坏版面的范围内，固定版面处的文字一律单行、放不下自动缩小；想调整字号请用上面「显示」里 App 自己的字体大小。

## macOS：下载与首次安装

需要 **macOS 14 或更新版本**；同一安装包支持 Apple 芯片和 Intel Mac。

**[前往最新版本下载](https://github.com/XmShrine/MiniBujo/releases/latest)**，在 Assets 中选择 `MiniBujo-版本号-macOS.zip`。不要选择 GitHub 自动提供的 `Source code`，它是源码，不是 App。

1. 解压 ZIP，将 `MiniBujo.app` 拖到「应用程序」后再打开。
2. 本项目没有付费 Apple 开发者账号。下载版使用 **ad-hoc 本地签名，未经 Apple 公证**，首次打开可能提示无法验证开发者或 Apple 无法检查恶意软件。
3. 如果你确认下载来源是本仓库，可在尝试打开后，到 **系统设置 → 隐私与安全性 → 仍要打开**，按提示确认。不要关闭整个系统的 Gatekeeper，也不要为来源不明的安装包放行。参见 [Apple 的说明](https://support.apple.com/102445)。
4. 每个 Release 提供 `SHA256SUMS.txt`，可用 `shasum -a 256 下载文件.zip` 比对文件哈希；哈希用于检查文件一致性，不代表 Apple 公证。

不同 macOS 版本可能要求再次确认新安装的版本；不承诺首次授权后永远不再提示。受组织管理的 Mac 也可能禁止打开未公证软件。

### App 内更新

macOS 版内置 [Sparkle 2](https://sparkle-project.org/)，在菜单栏 **Mini Bujo → 检查更新…** 中检查新版本。允许自动检查后，App 会按 Sparkle 的调度检查版本；你可以选择是否下载、安装并重启。

更新清单来自本仓库最新正式 Release 的 `appcast.xml`，安装包同样来自 GitHub Releases。更新包带有 **Ed25519 签名**，App 使用内置公钥验证下载内容；这与 Apple 的开发者签名、公证是不同机制。更新重启前会保存当前手帐。

以前没有更新器的旧版，需要手动安装一次带更新功能的版本。GitHub 在你所在网络无法访问时，更新检查或下载也会失败；**这套 GitHub 方案不保证国内网络可达**，以后可以迁移到可达的下载服务。更新器不会上传手帐内容。

## 数据保存、同步与网页版互通

内容默认保存在本机的 Application Support/MiniBujo/my-bujo.json；沙盒运行时，该路径位于应用自己的容器内。更新 App 不会主动删除这个文件。

点击 **关联 iCloud**，选择 iCloud 云盘里的一个文件夹（例如自己新建的 `Mini Bujo`）。App 会读写其中的 `my-bujo.json`，由 iCloud 云盘同步。所有设备选择同一个文件夹，即可共享同一本手帐。

这里使用「用户选择文件夹」的权限，**不需要付费账号提供的 App 专属 iCloud 容器，也不需要打开 Xcode 的 iCloud Capability**。关联按钮本身不会替你创建云盘账号或完成系统登录；请先让设备上的 iCloud 云盘正常可用。

JSON 与[网页版极简手帐](https://trick-1.pages.dev/BUJ_min/index.html)互通，可以在「文件」菜单导入、导出。导入会替换当前全部内容，操作前建议导出备份。多端冲突采用更新时间较新的整份文档覆盖，**不做逐条合并**；尽量避免多台设备离线同时修改。

## iOS / iPadOS：用自己的账号编译安装

需要 **iOS / iPadOS 17 或更新版本**。本项目目前没有 App Store / TestFlight 分发；macOS 的 ZIP 不能安装到 iPhone。**iOS 不含 Sparkle，不提供 App 内安装更新**。

在 Mac 上使用 Xcode 为自己的设备编译：

1. 克隆仓库并打开 `MiniBujo.xcodeproj`。项目当前使用 Xcode 27.2 格式；建议使用同版本或支持该项目格式、设备系统的更新版本。首次打开需要联网解析 Swift Package 依赖。
2. 在 **Xcode → Settings → Accounts** 添加自己的 Apple ID。
3. 选择项目中的 **MiniBujo target → Signing & Capabilities**，开启自动签名，将 **Team 改成自己的 Personal Team**。源码保留原作者的 Team ID，新用户不能直接使用它签名。
4. 如提示 Bundle Identifier 已被占用，把它改成你自己的唯一标识，例如 `com.yourname.minibujo`；运行测试时，测试 target 的 Team 和标识也要相应调整。之后尽量固定这个标识，否则系统会将它视为另一个 App，原来的本机数据也不会自动跟过去。
5. 连接并配对 iPhone / iPad，在设备系统要求时开启「开发者模式」、信任开发者，然后在 Xcode 顶部选择真实设备，按 **⌘R** 编译并安装。只想预览界面时，可选择 iOS Simulator。
6. 免费 Personal Team 的安装与签名受 Apple 的期限及设备限制，过期后可能需要重新连接 Xcode 安装。它不等同于永久签名，也不适合向所有人发送同一个 IPA；以 Xcode 当时显示的限制为准。Apple 说明：[开发者账号对比](https://developer.apple.com/support/compare-memberships/)。

**这个项目的 iOS 编译特别之处：**

- `Config/Info.plist` 用于 iOS，声明后台刷新任务 `com.xmshrine.minibujo.refresh`；它与 macOS 的 `Config/MacInfo.plist` 分开。不要把 Sparkle 的 macOS 配置直接复制到 iOS。
- `Packages/MiniBujoUpdates` 使用平台条件依赖，只有 macOS 链接 Sparkle；不要直接把 Sparkle 二进制加到同时支持 iOS 的 App target，否则 iOS 会报「no library for this platform」。
- 不需要添加 iCloud 容器。在手机上点击「关联 iCloud」，通过系统文件选择器选同一个云盘文件夹即可。
- iOS 后台刷新由系统决定执行时机，不能保证实时同步和无限期提醒。回到前台会重新读取文件、安排通知；通知需在系统中授权。

## 从源码构建 macOS

用 Xcode 打开工程，选择 MiniBujo scheme、My Mac 目的地后运行。使用自己的开发团队，或在本地使用 ad-hoc 签名。发布脚本不依赖作者的开发证书：

```sh
# VERSION 是展示版本，BUILD_NUMBER 必须比已发布版本递增
bash scripts/package-macos.sh 1.2 3
```

脚本构建 Universal App、验证本地签名、打 ZIP、签署 Sparkle 更新并生成清单，输出在 `build/releases/v1.2/`。`build/` 不提交到 Git。

### 维护者发布更新

首次发布的更新密钥保存在维护者本机钥匙串中，account 为 `com.xmshrine.minibujo`。公钥在 `Config/MacInfo.plist` 中；**私钥不在仓库、不应粘贴到 Issue、聊天或提交记录中**。换电脑应安全迁移同一私钥，丢失后不能直接用一个新密钥更新已安装的 App。

1. 更新代码并运行测试，按上面的脚本构建一个更高版本；需要访问钥匙串中的对应私钥。Fork 项目应生成自己的密钥，同时将更新清单地址改成自己的仓库。
2. 将 ZIP、`appcast.xml`、`SHA256SUMS.txt` 一起上传到同一个 Release，tag 必须与脚本对应，例如 `v1.2`。脚本会输出创建 **draft Release** 的命令，先检查附件和更新说明。
3. 确认无误后发布，并设为 **Latest 正式 Release**。App 的固定清单地址是 `https://github.com/XmShrine/MiniBujo/releases/latest/download/appcast.xml`；只有 draft 或 prerelease 而没有正式 Release 时，该地址不可用。
4. 至少用一个较旧的测试副本走完「检查 → 下载 → 验签 → 安装 → 重启」，再确认数据保留。更新会替换整个 App；不会热更新正在运行的 Swift 代码。

没有付费账号的分发策略是 ad-hoc 签名 + Sparkle 更新签名。为使本地签名 App 能加载 Sparkle，macOS 权限中关闭了 library validation，保留 App Sandbox 和 Hardened Runtime。若未来使用 Developer ID 公证分发，应重新收紧并验证这项权限。

## 目录

```text
MiniBujo/               SwiftUI 应用、界面、数据模型、文件同步、通知
MiniBujoTests/          JSON 兼容、日期、任务迁移、通知计划测试
Packages/MiniBujoUpdates/  仅在 macOS 启用的 Sparkle 封装
Config/                 iOS / macOS Info.plist 与 macOS 沙盒权限
scripts/                macOS 打包和更新清单生成
```

发布安装包不包含维护者的手帐数据。工程不默认上传分析数据；系统通知、文件选择与 iCloud 同步使用 Apple 提供的系统功能。
