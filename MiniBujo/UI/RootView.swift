import SwiftUI
import UniformTypeIdentifiers

/// 版面宽度：wide = 两页摊开（iPad 横屏 / Mac），narrow = 手机竖屏
struct LayoutInfo {
    var wide = false
    var narrow = false
}

private struct LayoutKey: EnvironmentKey { static let defaultValue = LayoutInfo() }
extension EnvironmentValues {
    var layout: LayoutInfo {
        get { self[LayoutKey.self] }
        set { self[LayoutKey.self] = newValue }
    }
}

/// 让页面上的按钮能打开文件选择器 / 导出
@MainActor
@Observable
final class FileActions {
    enum Importing { case folder, json }
    var importing: Importing?
    var exporting = false
}

struct RootView: View {
    @Environment(BujoStore.self) private var store
    @Environment(FileSync.self) private var sync
    @State private var files = FileActions()

    var body: some View {
        GeometryReader { g in
            let layout = LayoutInfo(wide: g.size.width >= 900, narrow: g.size.width < 520)
            VStack(spacing: 0) {
                TopBar()
                Divider().overlay(C.line)
                if layout.wide { wideBody } else { narrowBody }
            }
            .environment(\.layout, layout)
        }
        .background(C.desk.ignoresSafeArea())
        .environment(files)
        .overlay(alignment: .bottom) { toast }
        .alert(store.confirm?.title ?? "", isPresented: Binding(
            get: { store.confirm != nil }, set: { if !$0 { store.confirm = nil } }
        ), presenting: store.confirm) { c in
            Button(c.button, role: .destructive) { c.action() }
            Button("取消", role: .cancel) {}
        } message: { c in
            Text(c.message)
        }
        .fileImporter(isPresented: Binding(get: { files.importing != nil }, set: { if !$0 { files.importing = nil } }),
                      allowedContentTypes: files.importing == .folder ? [.folder] : [.json]) { result in
            handleImport(result)
        }
        .fileExporter(isPresented: Binding(get: { files.exporting }, set: { files.exporting = $0 }),
                      document: JSONFile(data: store.doc.serialized()), contentType: .json,
                      defaultFilename: "my-bujo-\(Dates.today()).json") { result in
            if case .success = result { store.showToast("已导出 .json 文件") }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        if files.importing == .folder || url.hasDirectoryPath {
            sync.link(folder: url)
            return
        }
        guard let d = sync.importDoc(from: url) else { store.showToast("这不是 mini bujo 的数据文件"); return }
        store.confirm = ConfirmRequest(title: "导入 \(url.lastPathComponent)？",
                                       message: "会替换掉现在的全部内容\(sync.isLinked ? "，并同步到 iCloud 文件" : "")。",
                                       button: "替换") {
            store.mutate { $0 = d }
            store.showToast("已导入 \(url.lastPathComponent)")
        }
    }

    // MARK: layouts

    private var wideBody: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Banner()
                    NavBar().padding(.top, 16)
                    Spread()
                }
                TabStickers(vertical: true).padding(.top, 70 + 16 + 48)
            }
            .frame(maxWidth: 1240)
            .padding(.horizontal, 20)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var narrowBody: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Banner()
                Section {
                    NavBar()
                    Spread().padding(.horizontal, 4)
                } header: {
                    TabStickers(vertical: false)
                        .padding(.vertical, 10)
                        .background(C.desk)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 48)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var toast: some View {
        if let t = store.toast {
            Text(t)
                .font(.ui(13.5))
                .foregroundStyle(C.paper)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(C.ink))
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: store.toast)
        }
    }
}

struct JSONFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

// MARK: - top bar

struct TopBar: View {
    @Environment(BujoStore.self) private var store
    @Environment(FileSync.self) private var sync
    @Environment(FileActions.self) private var files
    @Environment(\.layout) private var layout

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2.5).fill(C.cover)
                    .overlay(alignment: .trailing) { Rectangle().fill(Color(hex: 0x555555)).frame(width: 3) }
                    .frame(width: 14, height: 18)
                if !layout.narrow { Text("mini bujo").font(.ui(15, .bold)).foregroundStyle(C.ink) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    if !sync.isLinked {
                        Button("关联 iCloud") { files.importing = .folder }.buttonStyle(.pill(.primary, small: false))
                    }
                    Menu {
                        Button(sync.isLinked ? "更换 iCloud 文件夹…" : "关联 iCloud 文件夹…") { files.importing = .folder }
                        Button("导入 .json…") { files.importing = .json }
                        Button("导出 .json…") { files.exporting = true }
                        if sync.isLinked {
                            Divider()
                            Button("取消关联（只存本机）", role: .destructive) { sync.unlink() }
                        }
                    } label: {
                        Text("文件").font(.ui(13.5)).foregroundStyle(C.ink)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(C.paper))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(C.line))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                let st = sync.statusText
                Text(st.text).font(.ui(layout.narrow ? 11.5 : 12.5))
                    .foregroundStyle(st.warn ? C.red : C.ink2)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(.horizontal, layout.narrow ? 16 : 20)
        .padding(.vertical, 8)
        .background(C.desk)
    }
}

struct Banner: View {
    @Environment(BujoStore.self) private var store
    @Environment(FileSync.self) private var sync

    var body: some View {
        if !sync.isLinked && !store.hideBanner {
            HStack(alignment: .top, spacing: 12) {
                Text("内容会实时暂存在这台设备上。点 **「关联 iCloud」** 选一个 iCloud 云盘里的文件夹（比如新建一个「Mini Bujo」），手帐会存成里面的 **my-bujo.json**，之后的修改自动写进去。iPhone、iPad、Mac 选同一个文件夹就能同步；网页版也能「打开」这个文件。")
                    .font(.ui(13.5)).foregroundStyle(C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                XButton(help: "不再提示") { store.hideBanner = true }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(C.paper))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(C.ink3, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.top, 14)
        }
    }
}

struct NavBar: View {
    @Environment(BujoStore.self) private var store
    @Environment(\.layout) private var layout

    var body: some View {
        if let lbl = store.navLabel {
            HStack(spacing: 8) {
                arrow("‹", -1)
                Text(lbl).font(.hand(layout.wide ? 26 : 23)).foregroundStyle(C.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                arrow("›", 1)
                Button("今天") { store.nav(0) }.buttonStyle(.pill)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)
            .frame(minHeight: 48)
        } else {
            Color.clear.frame(height: 12)
        }
    }

    private func arrow(_ s: String, _ dir: Int) -> some View {
        Button { store.nav(dir) } label: {
            Text(s).font(.ui(18)).foregroundStyle(C.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(C.paper))
                .overlay(Circle().stroke(C.line))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dir < 0 ? "上一页" : "下一页")
    }
}

/// 书页边上的彩色贴纸标签
struct TabStickers: View {
    @Environment(BujoStore.self) private var store
    let vertical: Bool

    var body: some View {
        if vertical {
            VStack(alignment: .leading, spacing: 8) { ForEach(Tab.allCases) { sticker($0) } }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { ForEach(Tab.allCases) { sticker($0) } }.padding(.vertical, 2)
            }
        }
    }

    private func sticker(_ t: Tab) -> some View {
        let on = store.view == t, c = C.tab(t)
        return Button { store.go(t) } label: {
            HStack(spacing: 6) {
                Text(t.cn).font(.ui(14, .bold)).foregroundStyle(on ? .white : C.ink)
                if vertical { Text(t.en).font(.hand(17)).foregroundStyle(on ? .white : C.ink3) }
            }
            .padding(.leading, vertical ? 10 : 12).padding(.trailing, 12)
            .padding(.vertical, vertical ? 8 : 6)
            .background(on ? c : C.paper)
            .overlay(alignment: vertical ? .leading : .top) {
                Rectangle().fill(c).frame(width: vertical ? 5 : nil, height: vertical ? nil : 4)
            }
            .clipShape(vertical
                       ? AnyShape(UnevenRoundedRectangle(bottomTrailingRadius: 9, topTrailingRadius: 9))
                       : AnyShape(RoundedRectangle(cornerRadius: 8)))
            .shadow(color: .black.opacity(0.18), radius: 3, x: 2, y: 2)
            .offset(x: vertical && on ? 5 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, vertical ? 2 : 0)
    }
}

// MARK: - spread

struct Spread: View {
    @Environment(BujoStore.self) private var store
    @Environment(\.layout) private var layout

    var body: some View {
        let key = "\(store.view.rawValue)-\(store.date)"
        Group {
            if layout.wide {
                HStack(alignment: .top, spacing: 0) {
                    page(left: true).id("L" + key)
                        .overlay(alignment: .trailing) { Rectangle().fill(C.line).frame(width: 1) }
                    page(left: false).id("R" + key)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    page(left: true).id("L" + key)
                    if !(store.view == .day) {
                        DashedLine().frame(height: 1)
                        page(left: false).id("R" + key)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(layout.wide ? 6 : 4)
        .background(RoundedRectangle(cornerRadius: 12).fill(C.cover))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 12)
    }

    private func page(left: Bool) -> some View {
        pageContent(left: left)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, layout.wide ? 30 : 16)
            .padding(.top, layout.wide ? 26 : 20)
            .padding(.bottom, layout.wide ? 34 : 28)
            .frame(minHeight: layout.wide ? 700 : 0, alignment: .top)
            .background(DotPaper())
    }

    @ViewBuilder private func pageContent(left: Bool) -> some View {
        switch store.view {
        case .month: if left { MonthLeft() } else { MonthRight() }
        case .week: if left { WeekLeft() } else { WeekRight() }
        case .day: DayPage(s: left ? store.date : Dates.addDays(store.date, 1))
        case .habits: if left { HabitsLeft() } else { HabitsRight() }
        case .cols: if left { ColsLeft() } else { ColsRight() }
        case .pixels: if left { PixelsLeft() } else { PixelsRight() }
        case .index: if left { IndexLeft() } else { IndexRight() }
        }
    }
}
