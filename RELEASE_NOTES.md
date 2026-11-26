# Mini Bujo 1.4

- macOS 版新增内置 **「安装 / 更新到 iPhone…」**（菜单栏「Mini Bujo」或顶栏「文件」菜单）：
  - 自动检测本机已装的 Xcode、已登录的个人 Apple 开发者 Team ID，以及通过 USB 或同 Wi-Fi 连接的 iPhone / iPad。
  - 个人签名设置（Team ID 与专属 Bundle ID）只需确认一次并存本机，以后每次更新自动拉取对应版本源码、自动覆盖签名并安装到手机，无需再手动打开 Xcode 修改工程配置。
- macOS 版关闭 App Sandbox 以支持调用本机 Xcode 工具链，首次升级启动时自动迁移旧沙盒容器中的本机手帐数据与偏好设置（已关联 iCloud 文件夹的用户无感继续同步）。

## 下载与更新

已安装 1.1 ~ 1.3.1 的用户可以在菜单栏「Mini Bujo → 检查更新…」中安装本次更新。

首次安装请下载 `MiniBujo-1.4-macOS.zip`，解压后移到「应用程序」。同一安装包支持 Apple 芯片和 Intel，要求 macOS 14 或更新版本。

本项目没有付费 Apple 开发者账号，下载版使用 ad-hoc 本地签名，未经 Apple 公证。如被 macOS 拦截，请确认来源后按 README 的「隐私与安全性 → 仍要打开」说明操作。更新包另有 Sparkle 的 Ed25519 签名。
