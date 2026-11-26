#if os(macOS)
import SwiftUI
import Observation

// MARK: - 纯数据与解析逻辑（便于单元测试）

struct SigningTeam: Identifiable, Equatable {
    let id: String      // 10 位 Team ID（证书 OU 字段）
    let label: String   // 展示名（如 Apple Development 账号邮箱）
}

struct IOSDevice: Identifiable, Equatable {
    let udid: String
    let coreDeviceID: String
    let name: String
    let model: String
    let osVersion: String
    let transport: String
    let paired: Bool
    let developerModeEnabled: Bool

    var id: String { udid }
    var transportLabel: String {
        switch transport {
        case "wired": "USB"
        case "localNetwork": "Wi-Fi"
        default: transport
        }
    }
}

enum IOSInstallKeys {
    static let teamID = "iosInstall.teamID"
    static let bundleID = "iosInstall.bundleID"
}

enum IOSInstallerCore {
    static let repoSlug = "XmShrine/MiniBujo"

    /// 解析 `openssl x509 -noout -subject` 输出（可能有多行，每行一张证书），提取 OU 作为 Team ID
    static func parseSigningTeams(from subjectOutput: String) -> [SigningTeam] {
        var seen = Set<String>()
        var result: [SigningTeam] = []
        for rawLine in subjectOutput.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let ou = extractField("OU", from: line),
                  ou.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil,
                  !seen.contains(ou) else { continue }
            seen.insert(ou)
            let cn = extractField("CN", from: line) ?? ""
            let cleanedCN = cn.replacingOccurrences(of: "Apple Development: ", with: "")
            let label = cleanedCN.isEmpty ? ou : "\(cleanedCN) (\(ou))"
            result.append(SigningTeam(id: ou, label: label))
        }
        return result
    }

    private static func extractField(_ key: String, from subject: String) -> String? {
        let pattern = "(?:^|[,/\\s])\(key)=([^,/]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)),
              let range = Range(match.range(at: 1), in: subject) else { return nil }
        return subject[range].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 解析 `xcrun devicectl list devices --json-output` 输出，只保留物理 iOS / iPadOS 真机
    static func parseDevices(from jsonData: Data) -> [IOSDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let res = root["result"] as? [String: Any],
              let list = res["devices"] as? [[String: Any]] else { return [] }

        var out: [IOSDevice] = []
        for item in list {
            let props = item["properties"] as? [String: Any]
            let hw = (item["hardwareProperties"] as? [String: Any]) ?? props ?? [:]
            let dev = (item["deviceProperties"] as? [String: Any]) ?? props ?? [:]
            let conn = (item["connectionProperties"] as? [String: Any]) ?? props ?? [:]

            let reality = (hw["reality"] as? String) ?? ""
            let platform = ((hw["platform"] as? String) ?? "").lowercased()
            guard reality == "physical", platform.isEmpty || platform == "ios" else { continue }

            let udid = (hw["udid"] as? String) ?? (item["identifier"] as? String) ?? ""
            guard !udid.isEmpty else { continue }
            let coreID = (item["identifier"] as? String) ?? udid
            let name = (dev["name"] as? String) ?? "iPhone"
            let model = (hw["marketingName"] as? String) ?? (hw["productType"] as? String) ?? "iOS 设备"
            let osVer = (dev["osVersionNumber"] as? String) ?? ""
            let transport = (conn["transportType"] as? String) ?? ""
            let paired = (conn["pairingState"] as? String) == "paired"
            let devMode = (dev["developerModeStatus"] as? String) != "disabled"

            out.append(IOSDevice(
                udid: udid, coreDeviceID: coreID, name: name, model: model,
                osVersion: osVer, transport: transport, paired: paired, developerModeEnabled: devMode
            ))
        }
        return out
    }

    /// 按 Team ID 生成唯一且固定的个人 Bundle ID，以后每次更新沿用同一个 ID，数据不会丢失
    static func defaultBundleID(forTeamID teamID: String) -> String {
        let clean = teamID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return clean.isEmpty ? "com.minibujo.personal" : "com.minibujo.\(clean)"
    }

    /// 优先下载与当前 Mac 版一致的 Release tag 源码，失败则回落到 main 分支最新源码
    static func sourceArchiveURLs(appVersion: String) -> [URL] {
        var urls: [URL] = []
        let ver = appVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ver.isEmpty, let tagURL = URL(string: "https://github.com/\(repoSlug)/archive/refs/tags/v\(ver).tar.gz") {
            urls.append(tagURL)
        }
        if let mainURL = URL(string: "https://github.com/\(repoSlug)/archive/refs/heads/main.tar.gz") {
            urls.append(mainURL)
        }
        return urls
    }

    static func xcodebuildArguments(
        projectPath: String,
        udid: String,
        derivedDataPath: String,
        teamID: String,
        bundleID: String
    ) -> [String] {
        [
            "-project", projectPath,
            "-scheme", "MiniBujo",
            "-configuration", "Debug",
            "-destination", "id=\(udid)",
            "-derivedDataPath", derivedDataPath,
            "-allowProvisioningUpdates",
            "CODE_SIGN_STYLE=Automatic",
            "DEVELOPMENT_TEAM=\(teamID)",
            "PRODUCT_BUNDLE_IDENTIFIER=\(bundleID)",
            "build"
        ]
    }
}

// MARK: - 后台执行器

@MainActor
@Observable
final class IOSInstaller {
    enum State: Equatable {
        case idle
        case checking
        case running(String)
        case succeeded(String)
        case failed(String)
    }

    var state: State = .idle
    var xcodeInstalled = true
    var xcodePath = ""
    var teams: [SigningTeam] = []
    var devices: [IOSDevice] = []
    var selectedUDID = ""
    var teamID: String {
        didSet { UserDefaults.standard.set(teamID, forKey: IOSInstallKeys.teamID) }
    }
    var bundleID: String {
        didSet { UserDefaults.standard.set(bundleID, forKey: IOSInstallKeys.bundleID) }
    }
    var logs = ""

    @ObservationIgnored private var activeTask: Task<Void, Never>?

    var isBusy: Bool {
        if case .running = state { return true }
        if case .checking = state { return true }
        return false
    }

    var canInstall: Bool {
        !isBusy && xcodeInstalled && !selectedUDID.isEmpty
            && !teamID.trimmingCharacters(in: .whitespaces).isEmpty
            && !bundleID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init() {
        teamID = UserDefaults.standard.string(forKey: IOSInstallKeys.teamID) ?? ""
        bundleID = UserDefaults.standard.string(forKey: IOSInstallKeys.bundleID) ?? ""
    }

    func refreshEnvironment() {
        guard !isBusy else { return }
        state = .checking
        Task {
            let (devPath, detectedTeams, detectedDevices) = await Task.detached(priority: .userInitiated) {
                let path = Self.detectXcodePath()
                let teams = Self.detectSigningTeams()
                let devices = path.isEmpty ? [] : Self.detectDevices()
                return (path, teams, devices)
            }.value

            xcodePath = devPath
            xcodeInstalled = !devPath.isEmpty
            teams = detectedTeams
            devices = detectedDevices

            if teamID.isEmpty, let first = detectedTeams.first {
                teamID = first.id
            }
            if bundleID.isEmpty, !teamID.isEmpty {
                bundleID = IOSInstallerCore.defaultBundleID(forTeamID: teamID)
            }
            if !devices.contains(where: { $0.udid == selectedUDID }) {
                selectedUDID = devices.first(where: { $0.paired })?.udid ?? devices.first?.udid ?? ""
            }
            state = .idle
        }
    }

    func selectTeam(_ id: String) {
        let oldDefault = IOSInstallerCore.defaultBundleID(forTeamID: teamID)
        teamID = id
        if bundleID.isEmpty || bundleID == oldDefault {
            bundleID = IOSInstallerCore.defaultBundleID(forTeamID: id)
        }
    }

    func startInstall() {
        guard canInstall else { return }
        let targetUDID = selectedUDID
        let targetDeviceName = devices.first(where: { $0.udid == targetUDID })?.name ?? "iPhone"
        let cleanTeam = teamID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""

        logs = ""
        state = .running("正在获取最新源码…")

        activeTask?.cancel()
        activeTask = Task {
            do {
                let projectDir = try await prepareSource(appVersion: appVersion)
                let projectFile = projectDir.appendingPathComponent("MiniBujo.xcodeproj").path
                let cacheBase = Self.cacheDirectory()
                let derivedData = cacheBase.appendingPathComponent("DerivedData", isDirectory: true).path

                state = .running("正在用本机 Xcode 编译并签名（首次约 1 分钟）…")
                appendLog("▶ xcodebuild (\(cleanTeam) / \(cleanBundle))")

                let buildArgs = IOSInstallerCore.xcodebuildArguments(
                    projectPath: projectFile, udid: targetUDID,
                    derivedDataPath: derivedData, teamID: cleanTeam, bundleID: cleanBundle
                )
                let buildResult = try await runProcess("/usr/bin/xcodebuild", buildArgs) { [weak self] chunk in
                    Task { @MainActor in self?.appendLog(chunk) }
                }
                guard buildResult.code == 0 else {
                    throw InstallError.message(Self.friendlyError(from: buildResult.output, fallback: "编译或签名失败（退出码 \(buildResult.code)）"))
                }

                let appPath = "\(derivedData)/Build/Products/Debug-iphoneos/MiniBujo.app"
                guard FileManager.default.fileExists(atPath: appPath) else {
                    throw InstallError.message("编译完成，但未找到生成的 MiniBujo.app")
                }

                state = .running("正在安装到「\(targetDeviceName)」…")
                appendLog("▶ xcrun devicectl device install app --device \(targetUDID)")
                let installResult = try await runProcess("/usr/bin/xcrun", [
                    "devicectl", "device", "install", "app", "--device", targetUDID, appPath
                ]) { [weak self] chunk in
                    Task { @MainActor in self?.appendLog(chunk) }
                }
                guard installResult.code == 0 else {
                    throw InstallError.message(Self.friendlyError(from: installResult.output, fallback: "安装到设备失败（退出码 \(installResult.code)）"))
                }

                state = .succeeded("已安装到「\(targetDeviceName)」！签名设置已记住，下次直接点安装即可。")
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        state = .idle
    }

    private func appendLog(_ text: String) {
        logs.append(text)
        if logs.count > 24000 {
            logs = String(logs.suffix(20000))
        }
    }

    private func prepareSource(appVersion: String) async throws -> URL {
        let fm = FileManager.default
        let cache = Self.cacheDirectory()
        let srcRoot = cache.appendingPathComponent("Source", isDirectory: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)

        let urls = IOSInstallerCore.sourceArchiveURLs(appVersion: appVersion)
        var downloadedData: Data?
        var chosenURL: URL?
        for url in urls {
            appendLog("▶ 下载源码：\(url.absoluteString)\n")
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 10_000 {
                    downloadedData = data
                    chosenURL = url
                    break
                }
            } catch {
                appendLog("  下载失败，尝试下一个地址：\(error.localizedDescription)\n")
            }
        }
        guard let archiveData = downloadedData, chosenURL != nil else {
            throw InstallError.message("无法从 GitHub 下载最新源码，请检查网络连接。")
        }

        let tarURL = cache.appendingPathComponent("source.tar.gz")
        try archiveData.write(to: tarURL, options: .atomic)
        try? fm.removeItem(at: srcRoot)
        try fm.createDirectory(at: srcRoot, withIntermediateDirectories: true)

        let untar = try await runProcess("/usr/bin/tar", ["-xzf", tarURL.path, "-C", srcRoot.path, "--strip-components=1"])
        guard untar.code == 0 else {
            throw InstallError.message("解压源码失败：\(untar.output)")
        }
        guard fm.fileExists(atPath: srcRoot.appendingPathComponent("MiniBujo.xcodeproj").path) else {
            throw InstallError.message("源码包中未找到 MiniBujo.xcodeproj")
        }
        return srcRoot
    }

    private static func cacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MiniBujo/iOSInstaller", isDirectory: true)
    }

    nonisolated private static func detectXcodePath() -> String {
        let res = syncRun("/usr/bin/xcode-select", ["-p"])
        let path = res.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard res.code == 0, path.contains(".app/Contents/Developer") else { return "" }
        return path
    }

    nonisolated private static func detectSigningTeams() -> [SigningTeam] {
        let certs = syncRun("/usr/bin/security", ["find-certificate", "-a", "-c", "Apple Development", "-p"])
        guard certs.code == 0, certs.output.contains("BEGIN CERTIFICATE") else { return [] }
        // 拆出每一张 PEM 证书，分别取 subject（openssl x509 默认只解析第一张）
        let blocks = certs.output.components(separatedBy: "-----END CERTIFICATE-----")
        var subjects = ""
        for b in blocks where b.contains("-----BEGIN CERTIFICATE-----") {
            let pem = b + "-----END CERTIFICATE-----\n"
            let subj = syncRun("/usr/bin/openssl", ["x509", "-noout", "-subject"], stdin: pem)
            if subj.code == 0 { subjects += subj.output + "\n" }
        }
        return IOSInstallerCore.parseSigningTeams(from: subjects)
    }

    nonisolated private static func detectDevices() -> [IOSDevice] {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("minibujo-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let res = syncRun("/usr/bin/xcrun", ["devicectl", "list", "devices", "--json-output", tmp.path])
        guard res.code == 0, let data = try? Data(contentsOf: tmp) else { return [] }
        return IOSInstallerCore.parseDevices(from: data)
    }

    private static func friendlyError(from output: String, fallback: String) -> String {
        if output.contains("No profiles for") || output.contains("No Account for Team") || output.contains("requires a provisioning profile") {
            return "签名账号未就绪：请先打开一次 Xcode → Settings → Accounts 登录你的 Apple ID，然后重试。"
        }
        if output.contains("cannot be registered to your development team") || output.contains("is not available") {
            return "Bundle ID 已被占用，请在下方换一个专属的 Bundle ID（例如末尾加几个字母）后重试。"
        }
        if output.contains("locked") || output.contains("Locked") {
            return "iPhone 当前处于锁屏状态，请先解锁手机并在弹窗点「信任」后重试。"
        }
        if output.contains("Developer Mode") {
            return "iPhone 尚未开启「开发者模式」，请到手机「设置 → 隐私与安全性 → 开发者模式」开启后重试。"
        }
        return fallback
    }

    enum InstallError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case let .message(s) = self { return s }
            return nil
        }
    }

    private struct ProcResult { let code: Int32; let output: String }

    nonisolated private static func syncRun(_ launchPath: String, _ args: [String], stdin: String? = nil) -> ProcResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = outPipe
        if let stdin {
            let inPipe = Pipe()
            p.standardInput = inPipe
            inPipe.fileHandleForWriting.write(Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        do { try p.run() } catch { return ProcResult(code: -1, output: error.localizedDescription) }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return ProcResult(code: p.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    private func runProcess(_ launchPath: String, _ args: [String], onChunk: (@Sendable (String) -> Void)? = nil) async throws -> ProcResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    let p = Process()
                    p.executableURL = URL(fileURLWithPath: launchPath)
                    p.arguments = args
                    let pipe = Pipe()
                    p.standardOutput = pipe
                    p.standardError = pipe
                    var collected = Data()
                    let lock = NSLock()
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        guard !chunk.isEmpty else { return }
                        lock.lock(); collected.append(chunk); lock.unlock()
                        if let onChunk { onChunk(String(decoding: chunk, as: UTF8.self)) }
                    }
                    do {
                        try p.run()
                        p.waitUntilExit()
                        pipe.fileHandleForReading.readabilityHandler = nil
                        let tail = pipe.fileHandleForReading.readDataToEndOfFile()
                        if !tail.isEmpty {
                            lock.lock(); collected.append(tail); lock.unlock()
                            if let onChunk { onChunk(String(decoding: tail, as: UTF8.self)) }
                        }
                        cont.resume(returning: ProcResult(code: p.terminationStatus, output: String(decoding: collected, as: UTF8.self)))
                    } catch {
                        pipe.fileHandleForReading.readabilityHandler = nil
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: {}
    }
}

// MARK: - 界面

struct IOSInstallerView: View {
    @State private var installer = IOSInstaller()
    @State private var showLogs = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                if !installer.xcodeInstalled {
                    Label("未检测到完整版 Xcode，请先从 App Store 安装 Xcode 并在 Xcode → Settings → Accounts 登录一次 Apple ID。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(C.red)
                } else {
                    HStack {
                        if installer.devices.isEmpty {
                            Text("未检测到已配对的 iPhone / iPad（请用数据线连接或确保在同一 Wi-Fi 并解锁设备）")
                                .foregroundStyle(C.ink2)
                        } else {
                            Picker("目标设备", selection: $installer.selectedUDID) {
                                ForEach(installer.devices) { d in
                                    Text("\(d.name) · \(d.model) (iOS \(d.osVersion)\(d.transportLabel.isEmpty ? "" : " · \(d.transportLabel)"))")
                                        .tag(d.udid)
                                }
                            }
                        }
                        Button("刷新") { installer.refreshEnvironment() }
                            .disabled(installer.isBusy)
                    }
                }
            } header: {
                Text("已连接的设备")
            }

            Section {
                if !installer.teams.isEmpty {
                    Picker("本机已登录账号", selection: Binding(
                        get: { installer.teamID },
                        set: { installer.selectTeam($0) }
                    )) {
                        ForEach(installer.teams) { t in
                            Text(t.label).tag(t.id)
                        }
                        if !installer.teamID.isEmpty && !installer.teams.contains(where: { $0.id == installer.teamID }) {
                            Text("自定义 (\(installer.teamID))").tag(installer.teamID)
                        }
                    }
                }
                TextField("Team ID（10 位字母数字，自动识别或手动填写）", text: $installer.teamID)
                    .disabled(installer.isBusy)
                TextField("专属 Bundle ID（固定后不丢数据）", text: $installer.bundleID)
                    .disabled(installer.isBusy)
            } header: {
                Text("个人签名（只需设置一次，以后更新自动沿用）")
            } footer: {
                Text("免费个人 Apple ID 只需在 Xcode 里登录过一次。这里的 Team ID 和专属 Bundle ID 会保存在本机，以后每次更新只需点下方一键安装，无需打开 Xcode 手动改签名。")
            }

            Section {
                statusBlock
                if !installer.logs.isEmpty {
                    DisclosureGroup("查看详细日志", isExpanded: $showLogs) {
                        ScrollView {
                            Text(installer.logs)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 150)
                    }
                }
            } header: {
                Text("安装进度")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("安装 / 更新到 iPhone")
        .frame(minWidth: 480, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
                    .disabled(installer.isBusy)
            }
            ToolbarItem(placement: .confirmationAction) {
                if installer.isBusy {
                    Button("取消") { installer.cancel() }
                } else {
                    Button("一键安装 / 更新") { installer.startInstall() }
                        .disabled(!installer.canInstall)
                }
            }
        }
        .onAppear { installer.refreshEnvironment() }
    }

    @ViewBuilder private var statusBlock: some View {
        switch installer.state {
        case .idle:
            Text("准备就绪：将自动拉取当前版本源码、用你的个人账号签名并安装到所选设备。")
                .foregroundStyle(C.ink2)
        case .checking:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在检测本机 Xcode、签名账号和已连设备…") }
        case let .running(msg):
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(msg) }
        case let .succeeded(msg):
            Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(C.green)
        case let .failed(msg):
            Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(C.red)
        }
    }
}
#endif
