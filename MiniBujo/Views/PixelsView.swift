import SwiftUI

private let moodEmoji: [Mood: String] = [.red: "🔴", .orange: "🟠", .yellow: "🟡", .green: "🟢", .blue: "🔵"]

struct PixelsLeft: View {
    @Environment(BujoStore.self) private var store
    @Environment(\.layout) private var layout

    var body: some View {
        let y = Dates.year(store.date), t = Dates.today()
        let w: CGFloat = layout.narrow ? 19 : 22, h: CGFloat = layout.narrow ? 14 : 15, sp: CGFloat = layout.narrow ? 1.5 : 2
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("year in pixels", sub: "\(y) · 每天一格心情")
            Grid(horizontalSpacing: sp, verticalSpacing: sp) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    ForEach(Array("JFMAMJJASOND".enumerated()), id: \.offset) { _, c in
                        Text(String(c)).font(.hand(15)).foregroundStyle(C.ink2).frame(width: w)
                    }
                }
                ForEach(1...31, id: \.self) { d in
                    GridRow {
                        Text("\(d)").font(.hand(13)).foregroundStyle(C.ink3).gridColumnAlignment(.trailing).padding(.trailing, 2)
                        ForEach(1...12, id: \.self) { m in
                            if d > Dates.daysInMonth(y, m) {
                                Color.clear.frame(width: w, height: h)
                            } else {
                                let s = "\(y)-\(Dates.pad(m))-\(Dates.pad(d))"
                                pixel(s, mood: store.doc.days[s]?.mood, today: s == t, w: w, h: h)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pixel(_ s: String, mood: String?, today: Bool, w: CGFloat, h: CGFloat) -> some View {
        let fill = C.mood(mood)
        return Menu {
            Section(s) {
                ForEach(Mood.allCases, id: \.self) { m in
                    Button("\(moodEmoji[m]!) \(store.doc.moodLabel(m))") { store.setMood(s, m) }
                }
            }
            Button("清除") { store.setMood(s, nil) }
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(fill ?? .clear)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(today ? C.ink : fill == nil ? C.line : .clear, lineWidth: today ? 1.5 : 1))
                .frame(width: w, height: h)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(s)
    }
}

struct PixelsRight: View {
    @Environment(BujoStore.self) private var store
    @Environment(\.layout) private var layout

    var body: some View {
        let y = String(store.date.prefix(4))
        var counts: [Mood: Int] = [:]
        for (d, o) in store.doc.days where d.hasPrefix(y) {
            if let m = o.mood.flatMap(Mood.init(rawValue:)) { counts[m, default: 0] += 1 }
        }
        let mx = max(1, counts.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 0) {
            PageHeader("legend", sub: "五种颜色的含义可以自己改")
            VStack(spacing: 10) {
                ForEach(Mood.allCases, id: \.self) { m in
                    HStack(spacing: 10) {
                        Circle().fill(C.mood(m)).frame(width: 18, height: 18)
                        TextField("颜色含义", text: Binding(get: { store.doc.moodLabel(m) },
                                                         set: { v in store.mutate { $0.moodLabels[m.rawValue] = v } }))
                            .textFieldStyle(.plain).font(.ui(14)).foregroundStyle(C.ink)
                            .padding(.vertical, 3)
                            .overlay(alignment: .bottom) { DashedLine().frame(height: 1) }
                        HStack(spacing: 6) {
                            Capsule().fill(C.mood(m))
                                .frame(width: CGFloat(counts[m] ?? 0) / CGFloat(mx) * (layout.narrow ? 40 : 70), height: 6)
                            Text("\(counts[m] ?? 0)").font(.ui(12)).foregroundStyle(C.ink3)
                        }
                        .frame(width: layout.narrow ? 70 : 120, alignment: .leading)
                    }
                }
            }
            Hint("点左边的格子选颜色；日视图顶部也能直接设当天心情。")
        }
    }
}
