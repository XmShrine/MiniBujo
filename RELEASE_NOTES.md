# Mini Bujo 1.1

- macOS 新增「检查更新…」，可以通过 GitHub Releases 下载、验证并安装后续版本。
- 更新包使用 Ed25519 签名，重启安装前保存当前手帐。
- 同一个 macOS ZIP 支持 Apple 芯片和 Intel，要求 macOS 14 或更新版本。
- 补充 iOS / iPadOS 使用自己的 Apple ID 编译安装、iCloud 文件夹同步和源码构建说明。

## 下载与首次打开

下载下方的 `MiniBujo-1.1-macOS.zip`，解压并将 App 移到「应用程序」。本项目没有付费 Apple 开发者账号，安装包使用 ad-hoc 本地签名，未经 Apple 公证。如果 macOS 拦截，请在确认来源后，按 README 的「隐私与安全性 → 仍要打开」说明操作；不要关闭系统的 Gatekeeper。

以前未包含更新器的版本，需要手动安装这一次。以后的更新可以在 App 内检查；GitHub 的网络可达性会影响检查和下载。系统仍可能要求对新版再次确认。

`appcast.xml` 供更新器读取，`SHA256SUMS.txt` 供手动校验安装包一致性；普通用户只需下载 ZIP。
