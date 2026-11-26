import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 颜色和网页版 style.css 的 :root 一一对应（含深色模式）
extension Color {
    init(light: UInt32, dark: UInt32) {
        func comps(_ h: UInt32) -> (CGFloat, CGFloat, CGFloat) {
            (CGFloat((h >> 16) & 0xff) / 255, CGFloat((h >> 8) & 0xff) / 255, CGFloat(h & 0xff) / 255)
        }
        let (lr, lg, lb) = comps(light), (dr, dg, db) = comps(dark)
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: dr, green: dg, blue: db, alpha: 1) : NSColor(srgbRed: lr, green: lg, blue: lb, alpha: 1)
        })
        #else
        self.init(uiColor: UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(red: dr, green: dg, blue: db, alpha: 1) : UIColor(red: lr, green: lg, blue: lb, alpha: 1)
        })
        #endif
    }
    init(hex: UInt32) { self.init(light: hex, dark: hex) }
}

enum C {
    // 纸面相关的四种颜色由「显示」设置里的背景颜色决定（PaperPalette），
    // 其余墨色不变，这样换纸色时深 / 浅外观下都保持可读。
    static var desk: Color { let p = PaperPalette.current.desk; return Color(light: p.0, dark: p.1) }
    static var paper: Color { let p = PaperPalette.current.paper; return Color(light: p.0, dark: p.1) }
    static let ink = Color(light: 0x1e1e1c, dark: 0xecebe6)
    static let ink2 = Color(light: 0x5d5b56, dark: 0xb5b2aa)
    static let ink3 = Color(light: 0xa29f97, dark: 0x78756e)
    static var line: Color { let p = PaperPalette.current.line; return Color(light: p.0, dark: p.1) }
    static var grid: Color { let p = PaperPalette.current.grid; return Color(light: p.0, dark: p.1) }
    static let cover = Color(light: 0x1c1c1b, dark: 0x3a3935)
    static let red = Color(hex: 0xd9473b)
    static let blue = Color(hex: 0x3b63c4)
    static let yellow = Color(hex: 0xe6be22)
    static let green = Color(hex: 0x3c9657)
    static let orange = Color(hex: 0xe98b2f)
    static let purple = Color(hex: 0x8b5cc4)

    static func mood(_ m: Mood) -> Color {
        switch m { case .red: red; case .orange: orange; case .yellow: yellow; case .green: green; case .blue: blue }
    }
    static func mood(_ raw: String?) -> Color? { raw.flatMap(Mood.init(rawValue:)).map(mood) }
    static func dot(_ raw: String?) -> Color? { raw == "red" ? red : raw == "blue" ? blue : nil }

    static func tab(_ t: Tab) -> Color {
        switch t {
        case .month: red; case .week: blue; case .day: ink2; case .habits: orange
        case .cols: green; case .pixels: purple; case .index: yellow
        }
    }
}

extension Font {
    /// 标题 / 日期这类「手写在纸上」的字：字体和字号倍数都来自「显示」设置。
    /// 默认仍是用户点名要的 Bradley Hand。字号用固定 pt（不跟随系统
    /// Dynamic Type 无限放大），系统大字体另由 RootView 的上限保护，
    /// 否则日历、表格这类固定版面会被撑到断行、错位。
    static func hand(_ size: CGFloat) -> Font {
        let scaled = size * DisplayTextSize.currentScale
        switch DisplayFont.current {
        case .handwriting: return .custom("BradleyHandITCTT-Bold", size: scaled)
        case .rounded: return .system(size: scaled, weight: .bold, design: .rounded)
        case .serif: return .system(size: scaled, weight: .bold, design: .serif)
        case .system: return .system(size: scaled, weight: .bold)
        case .mono: return .system(size: scaled, weight: .bold, design: .monospaced)
        }
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size * DisplayTextSize.currentScale, weight: weight, design: DisplayFont.current.bodyDesign)
    }
}

/// 纸面：形态（点阵 / 横线 / 方格 / 空白）和配色均响应「显示」设置，默认点阵。
/// 名字沿用 DotPaper，调用处不用改。
struct DotPaper: View {
    @AppStorage(AppearanceKeys.paperForm) private var formRaw = PaperForm.dots.rawValue
    @AppStorage(AppearanceKeys.palette) private var paletteRaw = PaperPalette.classic.rawValue
    @AppStorage(AppearanceKeys.textSize) private var textSizeRaw = DisplayTextSize.standard.rawValue

    var body: some View {
        let form = PaperForm.from(formRaw)
        let pal = PaperPalette.from(paletteRaw)
        let scale = DisplayTextSize.from(textSizeRaw).scale
        let gridColor = Color(light: pal.grid.0, dark: pal.grid.1)
        let paperColor = Color(light: pal.paper.0, dark: pal.paper.1)

        Canvas { ctx, size in
            switch form {
            case .blank:
                break
            case .dots:
                let step: CGFloat = 18
                var y: CGFloat = 9
                while y < size.height {
                    var x: CGFloat = 9
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(gridColor))
                        x += step
                    }
                    y += step
                }
            case .lines:
                let step: CGFloat = 27 * scale
                var y: CGFloat = 26 * scale
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(gridColor))
                    y += step
                }
            case .grid:
                let step: CGFloat = 18
                var x: CGFloat = 9
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(gridColor))
                    x += step
                }
                var y: CGFloat = 9
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(gridColor))
                    y += step
                }
            }
        }
        .background(paperColor)
    }
}

// MARK: - small components

struct PillButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, danger }
    var kind: Kind = .normal
    var small = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(small ? 12.5 : 13.5))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .padding(.horizontal, small ? 9 : 12)
            .padding(.vertical, small ? 4 : 6)
            .foregroundStyle(kind == .primary ? C.paper : kind == .danger ? C.red : C.ink)
            .background(RoundedRectangle(cornerRadius: 7).fill(kind == .primary ? C.ink : C.paper))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(kind == .primary ? C.ink : C.line))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ kind: PillButtonStyle.Kind, small: Bool = true) -> PillButtonStyle { PillButtonStyle(kind: kind, small: small) }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var sub: String = ""
    var size: CGFloat = 34
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.hand(size)).foregroundStyle(C.ink).lineLimit(1).minimumScaleFactor(0.6)
            if !sub.isEmpty {
                Text(sub).font(.ui(13)).foregroundStyle(C.ink3)
                    .lineLimit(1).minimumScaleFactor(0.7).allowsTightening(true)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.bottom, 14)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(_ title: String, sub: String = "", size: CGFloat = 34) {
        self.init(title: title, sub: sub, size: size) { EmptyView() }
    }
}

/// 「重要 · main ------」这种小节标题
struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(.ui(13, .semibold)).foregroundStyle(C.ink2)
            DashedLine().frame(height: 1)
            trailing
        }
        .padding(.top, 22).padding(.bottom, 6)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text: text) { EmptyView() } }
}

struct DashedLine: View {
    var color: Color = C.line
    var body: some View {
        GeometryReader { g in
            Path { p in p.move(to: .init(x: 0, y: g.size.height / 2)); p.addLine(to: .init(x: g.size.width, y: g.size.height / 2)) }
                .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }
}

struct Hint: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        Text(text).font(.ui(12.5)).foregroundStyle(C.ink3).padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 红 / 蓝圆点贴纸按钮
struct DotSticker: View {
    let dot: String?
    var label: String = ""
    var size: CGFloat = 24
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if let c = C.dot(dot) {
                    Circle().fill(c)
                } else {
                    Circle().strokeBorder(C.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                }
                if !label.isEmpty {
                    Text(label).font(.hand(size * 0.65)).foregroundStyle(dot == nil ? C.ink : .white)
                        .lineLimit(1).minimumScaleFactor(0.55).allowsTightening(true)
                        .padding(1)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("贴圆点：红 → 蓝 → 无")
    }
}

struct XButton: View {
    var help: String = "删除"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("×").font(.ui(17)).foregroundStyle(C.ink3).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// 可以按边单独画的描边（表格用）
struct EdgeBorder: Shape {
    var edges: [Edge]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for e in edges {
            switch e {
            case .top: p.move(to: .init(x: r.minX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.minY))
            case .bottom: p.move(to: .init(x: r.minX, y: r.maxY)); p.addLine(to: .init(x: r.maxX, y: r.maxY))
            case .leading: p.move(to: .init(x: r.minX, y: r.minY)); p.addLine(to: .init(x: r.minX, y: r.maxY))
            case .trailing: p.move(to: .init(x: r.maxX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.maxY))
            }
        }
        return p
    }
}

/// 自动长高的多行输入框（随手记、卡片正文、本周小结）
struct GrowingEditor: View {
    @Binding var text: String
    var placeholder: String = ""
    var font: Font = .ui(15)
    var minHeight: CGFloat = 60
    var ruled = false

    var body: some View {
        let scale = DisplayTextSize.currentScale
        let spacing: CGFloat = ruled ? 9 * scale : 2
        let vPad: CGFloat = ruled ? 4 * scale : 2
        // 隐藏的 Text 负责撑开高度，TextEditor 叠在上面
        Text(text.isEmpty ? placeholder : text + " ")
            .font(font).lineSpacing(spacing)
            .foregroundStyle(text.isEmpty ? C.ink3 : .clear)
            .padding(.vertical, vPad)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(font).lineSpacing(spacing)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .padding(.horizontal, editorInset)
                    .padding(.top, editorTopInset + vPad)
            }
            .background {
                if ruled {
                    Canvas { ctx, size in
                        let step: CGFloat = 27 * scale
                        var y: CGFloat = 26 * scale
                        while y < size.height {
                            ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(C.line))
                            y += step
                        }
                    }
                }
            }
    }

    // TextEditor 自带的内边距，抵消掉让文字和占位符对齐
    #if os(macOS)
    private var editorInset: CGFloat { -5 }
    private var editorTopInset: CGFloat { 0 }
    #else
    private var editorInset: CGFloat { -5 }
    private var editorTopInset: CGFloat { -8 }
    #endif
}
