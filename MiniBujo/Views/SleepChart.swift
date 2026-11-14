import SwiftUI

/// 睡眠：每天一根从入睡到起床的斜线条（像手帐里画的阴影条）；体重单独画在下面一条红色折线。
/// 坐标和网页版 sleepSVG() 一样按 320 宽算，再整体缩放。
struct SleepModel {
    let bed: [Double?], wake: [Double?], wt: [Double?]
    let tv: [Double], wv: [Double]
    let Wd: Double = 320, L: Double = 38, R: Double = 30
    var slot: Double { (Wd - L - R) / 7 }
    var SH: Double { tv.isEmpty ? 0 : 150 }
    var WH: Double { wv.isEmpty ? 0 : 72 }
    var gap: Double { SH > 0 && WH > 0 ? 16 : 0 }
    var H: Double { 8 + SH + gap + WH + 18 }
    var isEmpty: Bool { tv.isEmpty && wv.isEmpty }
    func x(_ i: Int) -> Double { L + (Double(i) + 0.5) * slot }

    init(_ s: Sleep) {
        func toH(_ v: String) -> Double? {
            let p = v.split(separator: ":").map { Double($0) }
            guard let h = p.first ?? nil else { return nil }
            return h + ((p.count > 1 ? p[1] : 0) ?? 0) / 60
        }
        // 以「前一天傍晚 → 第二天中午」为一个睡眠窗口：凌晨的入睡时间、早上的起床时间都 +24
        let bed = s.bed.map { toH($0).map { $0 < 15 ? $0 + 24 : $0 } }
        let wake = s.wake.enumerated().map { i, v -> Double? in
            guard let x = toH(v) else { return nil }
            let w = x + 24
            if let b = bed[i], w <= b { return w + 24 }
            return w
        }
        self.bed = bed
        self.wake = wake
        wt = s.wt.map { Double($0.trimmingCharacters(in: .whitespaces)) }
        tv = (bed + wake).compactMap { $0 }
        wv = wt.compactMap { $0 }
    }

    static func fmt(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}

struct SleepChart: View {
    let sleep: Sleep

    var body: some View {
        let m = SleepModel(sleep)
        if m.isEmpty {
            Hint("填入睡、起床时间或体重后，这里会画出睡眠条和体重线。")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Canvas { ctx, size in draw(m, in: &ctx, k: size.width / m.Wd) }
                    .aspectRatio(m.Wd / m.H, contentMode: .fit)
                    .padding(.top, 8)
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Canvas { ctx, size in
                            let r = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
                            hatch(&ctx, r, k: 1)
                            ctx.stroke(Path(r), with: .color(C.ink), lineWidth: 1.5)
                        }
                        .frame(width: 10, height: 12)
                        Text("入睡 → 起床")
                    }
                    HStack(spacing: 5) {
                        Rectangle().fill(C.red).frame(width: 18, height: 2)
                        Text("体重")
                    }
                }
                .font(.ui(12)).foregroundStyle(C.ink2)
            }
        }
    }

    private func hatch(_ ctx: inout GraphicsContext, _ r: CGRect, k: CGFloat) {
        ctx.drawLayer { l in
            l.clip(to: Path(r))
            var p = Path()
            var x = r.minX - r.height
            while x < r.maxX {
                p.move(to: .init(x: x, y: r.maxY)); p.addLine(to: .init(x: x + r.height, y: r.minY))
                x += 5 * k
            }
            l.stroke(p, with: .color(C.ink), lineWidth: 1.2 * k)
        }
    }

    private func draw(_ m: SleepModel, in ctx: inout GraphicsContext, k: CGFloat) {
        func P(_ x: Double, _ y: Double) -> CGPoint { .init(x: x * k, y: y * k) }
        func label(_ s: String, _ x: Double, _ y: Double, _ anchor: UnitPoint, color: Color = C.ink3, bold: Bool = false) {
            ctx.draw(Text(s).font(.system(size: 10 * k, weight: bold ? .semibold : .regular)).foregroundStyle(color),
                     at: P(x, y - 3.5), anchor: anchor)
        }
        func hline(_ y: Double) {
            var p = Path(); p.move(to: P(m.L, y)); p.addLine(to: P(m.Wd - m.R, y))
            ctx.stroke(p, with: .color(C.line), lineWidth: 1)
        }

        for i in 0..<7 { label(Dates.WD[i], m.x(i), m.H - 4, .center) }

        if m.SH > 0 {
            let T = 8.0, ih = m.SH - 14
            let lo = (m.tv.min()!).rounded(.down)
            let span = max((m.tv.max()!).rounded(.up) - lo, 2)
            func y(_ v: Double) -> Double { T + (v - lo) / span * ih }
            let step = span > 10 ? 3.0 : span > 5 ? 2 : 1
            var t = lo
            while t <= lo + span {
                hline(y(t))
                label("\(Int(t) % 24):00", m.L - 5, y(t) + 3.5, .trailing)
                t += step
            }
            let bw = m.slot * 0.5
            for i in 0..<7 {
                if let b = m.bed[i], let w = m.wake[i] {
                    let r = CGRect(x: (m.x(i) - bw / 2) * k, y: y(b) * k, width: bw * k, height: (y(w) - y(b)) * k)
                    hatch(&ctx, r, k: k)
                    ctx.stroke(Path(roundedRect: r, cornerRadius: 1.5 * k), with: .color(C.ink), lineWidth: 1.5 * k)
                    ctx.draw(Text(SleepModel.fmt(w - b) + "h").font(.system(size: 10 * k, weight: .semibold)).foregroundStyle(C.ink2),
                             at: P(m.x(i), y(w) + 11 - 3.5), anchor: .center)
                } else if let v = m.bed[i] ?? m.wake[i] {
                    let c = Path(ellipseIn: CGRect(x: (m.x(i) - 3) * k, y: (y(v) - 3) * k, width: 6 * k, height: 6 * k))
                    ctx.fill(c, with: .color(C.paper))
                    ctx.stroke(c, with: .color(C.ink), lineWidth: 1.6 * k)
                }
            }
        }

        if m.WH > 0 {
            let T = 8 + m.SH + m.gap, lo = m.wv.min()!, hi = m.wv.max()!, pad = max((hi - lo) * 0.15, 0.3)
            func y(_ v: Double) -> Double { T + 16 + (hi + pad - v) / (hi - lo + 2 * pad) * (m.WH - 22) }
            hline(T)
            label("体重", m.L - 5, T + 11, .trailing, bold: true)
            var path = Path(), pen = false
            for (i, v) in m.wt.enumerated() {
                guard let v else { pen = false; continue }
                if pen { path.addLine(to: P(m.x(i), y(v))) } else { path.move(to: P(m.x(i), y(v))) }
                pen = true
            }
            ctx.stroke(path, with: .color(C.red), style: StrokeStyle(lineWidth: 1.8 * k, lineCap: .round, lineJoin: .round))
            for (i, v) in m.wt.enumerated() {
                guard let v else { continue }
                let c = Path(ellipseIn: CGRect(x: (m.x(i) - 2.6) * k, y: (y(v) - 2.6) * k, width: 5.2 * k, height: 5.2 * k))
                ctx.fill(c, with: .color(C.paper))
                ctx.stroke(c, with: .color(C.red), lineWidth: 1.6 * k)
                label(SleepModel.fmt(v), m.x(i), y(v) - 6, .center, color: C.red)
            }
        }
    }
}
