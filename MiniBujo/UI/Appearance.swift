import SwiftUI

// MARK: - 可编辑显示 + 系统大字体保护
//
// 显示偏好是「这台设备」的设置（每台手机 / 电脑的屏幕和系统字号都不同），
// 所以和已有的 view / hideBanner 一样存 UserDefaults，不写进手帐 JSON，
// 避免同步到另一台设备后把对方的版面也改掉，也不动和网页版互通的数据格式。
//
// 这里只放纯数据和取值逻辑：真正的字体在 Theme.swift 的 Font.hand / Font.ui
// 里读取下面的选择，纸面颜色在 Theme.swift 的 C 里读取，纸面形态在
// Theme.swift 的 DotPaper 里读取。设置界面改了 UserDefaults 后，
// RootView 用 @AppStorage 观察同一批 key 并刷新视图树，整页会立即生效。

enum AppearanceKeys {
    static let paperForm = "appearance.paperForm"
    static let font = "appearance.font"
    static let textSize = "appearance.textSize"
    static let palette = "appearance.palette"
}

/// 笔记本形态：纸面长什么样
enum PaperForm: String, CaseIterable, Identifiable {
    case dots   // 点阵（原来的样子）
    case lines  // 横线
    case grid   // 方格
    case blank  // 空白

    var id: String { rawValue }
    var label: String {
        switch self {
        case .dots: "点阵"
        case .lines: "横线"
        case .grid: "方格"
        case .blank: "空白"
        }
    }

    static func from(_ raw: String?) -> PaperForm { PaperForm(rawValue: raw ?? "") ?? .dots }
    static var current: PaperForm { from(UserDefaults.standard.string(forKey: AppearanceKeys.paperForm)) }
}

/// 字体：手写体是标题 / 日期这类「写在手帐上」的字，正文在个别字体下仍保持易读
enum DisplayFont: String, CaseIterable, Identifiable {
    case handwriting
    case rounded
    case serif
    case system
    case mono

    var id: String { rawValue }
    var label: String {
        switch self {
        case .handwriting: "手写体"
        case .rounded: "圆体"
        case .serif: "衬线"
        case .system: "系统"
        case .mono: "等宽"
        }
    }

    /// 正文字体设计；手写体只用于标题，正文回落到系统字体保证可读性
    var bodyDesign: Font.Design {
        switch self {
        case .handwriting, .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }

    static func from(_ raw: String?) -> DisplayFont { DisplayFont(rawValue: raw ?? "") ?? .handwriting }
    static var current: DisplayFont { from(UserDefaults.standard.string(forKey: AppearanceKeys.font)) }
}

/// 字号：整体缩放倍数（不是系统字号，系统字号在 RootView 里另有上限保护）
enum DisplayTextSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large
    case extraLarge

    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        case .extraLarge: "特大"
        }
    }
    var scale: CGFloat {
        switch self {
        case .small: 0.88
        case .standard: 1.0
        case .large: 1.14
        case .extraLarge: 1.28
        }
    }

    static func from(_ raw: String?) -> DisplayTextSize { DisplayTextSize(rawValue: raw ?? "") ?? .standard }
    static var current: DisplayTextSize { from(UserDefaults.standard.string(forKey: AppearanceKeys.textSize)) }
    static var currentScale: CGFloat { current.scale }
}

/// 背景颜色：每种配色都同时给出浅色 / 深色两套，两种外观下墨色对比都成立
enum PaperPalette: String, CaseIterable, Identifiable {
    case classic
    case cream
    case mint
    case sky
    case rose

    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: "经典纸白"
        case .cream: "米黄"
        case .mint: "淡绿"
        case .sky: "淡蓝"
        case .rose: "淡粉"
        }
    }

    // (浅色, 深色)，和 Theme.swift 里 Color(light:dark:) 的入参一致
    var desk: (UInt32, UInt32) {
        switch self {
        case .classic: (0xe7e4dc, 0x131312)
        case .cream: (0xe3d5b8, 0x1d1811)
        case .mint: (0xd8e2d2, 0x121a13)
        case .sky: (0xd2dde8, 0x11171d)
        case .rose: (0xe8d8d2, 0x1d1416)
        }
    }
    var paper: (UInt32, UInt32) {
        switch self {
        case .classic: (0xfbfaf6, 0x22211f)
        case .cream: (0xfdf6e0, 0x2e2718)
        case .mint: (0xf2f7ee, 0x232d24)
        case .sky: (0xeef4fb, 0x222c36)
        case .rose: (0xfbf1ee, 0x2e2326)
        }
    }
    var line: (UInt32, UInt32) {
        switch self {
        case .classic: (0xd9d4c9, 0x3a3834)
        case .cream: (0xded0ac, 0x4a4030)
        case .mint: (0xc9d6c2, 0x40503f)
        case .sky: (0xc2d2e2, 0x3d4c5c)
        case .rose: (0xe0c8c0, 0x50403e)
        }
    }
    var grid: (UInt32, UInt32) {
        switch self {
        case .classic: (0xd6d1c5, 0x383631)
        case .cream: (0xdccfa9, 0x47402f)
        case .mint: (0xc6d4bd, 0x3d4f3c)
        case .sky: (0xbccfe0, 0x3a4a5a)
        case .rose: (0xdec4bb, 0x4e3e3c)
        }
    }
    /// 设置界面里色板圆点的代表色（浅色纸面）
    var swatch: UInt32 { paper.0 }

    static func from(_ raw: String?) -> PaperPalette { PaperPalette(rawValue: raw ?? "") ?? .classic }
    static var current: PaperPalette { from(UserDefaults.standard.string(forKey: AppearanceKeys.palette)) }
}

// MARK: - 设置界面

struct AppearanceSettingsView: View {
    @AppStorage(AppearanceKeys.paperForm) private var paperFormRaw = PaperForm.dots.rawValue
    @AppStorage(AppearanceKeys.font) private var fontRaw = DisplayFont.handwriting.rawValue
    @AppStorage(AppearanceKeys.textSize) private var textSizeRaw = DisplayTextSize.standard.rawValue
    @AppStorage(AppearanceKeys.palette) private var paletteRaw = PaperPalette.classic.rawValue
    @Environment(\.dismiss) private var dismiss

    private var appearanceID: String {
        "\(paperFormRaw)-\(fontRaw)-\(textSizeRaw)-\(paletteRaw)"
    }

    var body: some View {
        Form {
            Section {
                preview.id(appearanceID)
            } header: {
                Text("预览")
            }

            Section {
                Picker("笔记本形态", selection: $paperFormRaw) {
                    ForEach(PaperForm.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("背景颜色", selection: $paletteRaw) {
                    ForEach(PaperPalette.allCases) { Text($0.label).tag($0.rawValue) }
                }
                HStack(spacing: 8) {
                    ForEach(PaperPalette.allCases) { p in
                        Circle().fill(Color(hex: p.swatch))
                            .overlay(Circle().stroke(paletteRaw == p.rawValue ? C.ink : C.line, lineWidth: paletteRaw == p.rawValue ? 2 : 1))
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                            .onTapGesture { paletteRaw = p.rawValue }
                            .accessibilityLabel(p.label)
                            .accessibilityAddTraits(paletteRaw == p.rawValue ? [.isButton, .isSelected] : .isButton)
                    }
                }
            } header: {
                Text("纸面")
            }

            Section {
                Picker("字体", selection: $fontRaw) {
                    ForEach(DisplayFont.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("字体大小", selection: $textSizeRaw) {
                    ForEach(DisplayTextSize.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } header: {
                Text("字体")
            } footer: {
                Text("这里的字号是 App 自己的字号，和系统「显示与亮度」里的字体大小互相独立。系统字体开得很大时，App 会把缩放限制在不撑坏日历和表格的范围内，星期、日期这类固定版面的字会自动缩小到一行放下，不再断行。")
            }

            Section {
                Button("恢复默认显示") {
                    paperFormRaw = PaperForm.dots.rawValue
                    fontRaw = DisplayFont.handwriting.rawValue
                    textSizeRaw = DisplayTextSize.standard.rawValue
                    paletteRaw = PaperPalette.classic.rawValue
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("显示")
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 440)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
    }

    /// 一小块用当前设置渲染的纸面，改任何一项都能马上看到效果
    private var preview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("November").font(.hand(30)).foregroundStyle(C.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("手帐预览 · preview").font(.ui(12.5)).foregroundStyle(C.ink3)
                    .lineLimit(1).minimumScaleFactor(0.7).allowsTightening(true)
            }
            HStack(spacing: 0) {
                ForEach(Dates.WD, id: \.self) { wd in
                    Text(wd).font(.hand(16)).foregroundStyle(C.ink2)
                        .lineLimit(1).minimumScaleFactor(0.55).allowsTightening(true)
                        .frame(maxWidth: .infinity)
                }
            }
            Text("字体和字体大小、笔记本形态、背景颜色，都可以在这里改。")
                .font(.ui(13.5)).foregroundStyle(C.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DotPaper())
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(C.line))
    }
}
