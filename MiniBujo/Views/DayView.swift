import SwiftUI

struct DayPage: View {
    @Environment(BujoStore.self) private var store
    let s: String

    var body: some View {
        let o = store.doc.days[s], i = Dates.wdIdx(s)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text("\(s.dropFirst(5).prefix(2))/\(s.suffix(2))/\(s.prefix(4))").font(.hand(30)).foregroundStyle(C.ink)
                    .lineLimit(1).minimumScaleFactor(0.65).allowsTightening(true).layoutPriority(1)
                Text(Dates.WD_FULL[i]).font(.hand(24)).foregroundStyle(C.ink2)
                    .lineLimit(1).minimumScaleFactor(0.55).allowsTightening(true)
                DotSticker(dot: o?.dot, size: 26) { store.cycleDot(s) }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                Text("心情").font(.ui(12.5)).foregroundStyle(C.ink3)
                ForEach(Mood.allCases, id: \.self) { m in
                    let on = o?.mood == m.rawValue
                    Button { store.setMood(s, on ? nil : m) } label: {
                        Circle().fill(C.mood(m)).frame(width: 18, height: 18)
                            .opacity(on ? 1 : 0.3)
                            .overlay { if on { Circle().stroke(C.ink, lineWidth: 1.5).padding(-3.5) } }
                            .padding(3)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(store.doc.moodLabel(m))
                }
            }

            SectionTitle("重要 · main")
            BulletList(ref: .day(s, "main"))
            SectionTitle("轻松 · light")
            BulletList(ref: .day(s, "light"), placeholder: "轻松一点的事…")

            HStack(spacing: 6) {
                Button("未完成 → 明天") { store.migrateAll([.day(s, "main"), .day(s, "light")]) }
                Button((o?.showTime ?? false) ? "收起时间轴" : "展开时间轴") { store.editDay(s) { $0.showTime.toggle() } }
                Button("+ 卡片") { store.editDay(s) { $0.cards.append(Card()) } }
            }
            .buttonStyle(.pill)
            .padding(.top, 14)

            if o?.showTime ?? false { Timeline(s: s) }
            ForEach(o?.cards ?? []) { CardView(s: s, card: $0) }

            SectionTitle("随手记 · notes")
            GrowingEditor(text: Binding(get: { store.doc.days[s]?.note ?? "" }, set: { v in store.editDay(s) { $0.note = v } }),
                          placeholder: "今天的想法、小日记…", minHeight: 90, ruled: true)
        }
    }
}

private struct Timeline: View {
    @Environment(BujoStore.self) private var store
    let s: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(6..<24, id: \.self) { h in
                let hk = Dates.pad(h)
                HStack(alignment: .top, spacing: 8) {
                    Text("\(h)").font(.hand(17)).foregroundStyle(C.ink3)
                        .lineLimit(1).minimumScaleFactor(0.6).allowsTightening(true)
                        .frame(width: 28, height: 26, alignment: .trailing)
                    TextField("", text: Binding(get: { store.doc.days[s]?.times[hk] ?? "" },
                                                set: { v in store.editDay(s) { $0.times[hk] = v } }), axis: .vertical)
                        .textFieldStyle(.plain).font(.ui(14)).foregroundStyle(C.ink)
                        .padding(.leading, 8).padding(.vertical, 4)
                        .frame(minHeight: 26)
                        .overlay(alignment: .leading) { Rectangle().fill(C.ink).frame(width: 1.8) }
                        .overlay(alignment: .bottom) { DashedLine().frame(height: 1) }
                }
            }
        }
        .padding(.top, 6)
    }
}

private struct CardView: View {
    @Environment(BujoStore.self) private var store
    @Environment(\.layout) private var layout
    let s: String
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                TextField("卡片标题（比如：菜谱）", text: bind(\.title))
                    .textFieldStyle(.plain).font(.ui(15, .semibold)).foregroundStyle(C.ink)
                Button { edit { $0.tag.toggle() } } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(card.tag ? C.yellow : .clear)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(card.tag ? C.yellow : C.ink3, style: StrokeStyle(lineWidth: 1.5, dash: card.tag ? [] : [3, 2])))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("黄色标签：会出现在索引里")
                XButton(help: "删除卡片") {
                    let del = { store.editDay(s) { $0.cards.removeAll { $0.id == card.id } } }
                    if card.title.isEmpty && card.body.isEmpty { del() }
                    else { store.confirm = ConfirmRequest(title: "删除这张卡片？", action: del) }
                }
            }
            GrowingEditor(text: bind(\.body), placeholder: "内容…", font: .ui(14), minHeight: 40)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(C.ink, lineWidth: 1.8))
        .overlay(alignment: .topTrailing) {
            if card.tag {
                UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4).fill(C.yellow)
                    .frame(width: layout.wide ? 16 : 10, height: 22)
                    .offset(x: layout.wide ? 31 : 17, y: 10)
            }
        }
        .padding(.top, 14)
    }

    private func edit(_ f: @escaping (inout Card) -> Void) {
        store.editDay(s) { d in if let i = d.cards.firstIndex(where: { $0.id == card.id }) { f(&d.cards[i]) } }
    }

    private func bind(_ kp: WritableKeyPath<Card, String>) -> Binding<String> {
        Binding(get: { store.doc.days[s]?.cards.first { $0.id == card.id }?[keyPath: kp] ?? "" },
                set: { v in edit { $0[keyPath: kp] = v } })
    }
}
