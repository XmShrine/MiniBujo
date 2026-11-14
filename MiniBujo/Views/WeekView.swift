import SwiftUI

struct WeekLeft: View {
    @Environment(BujoStore.self) private var store
    @Environment(\.layout) private var layout

    var body: some View {
        let mon = Dates.mondayOf(store.date)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("week \(Dates.weekNo(mon))", sub: "\(Dates.fmtMD(mon)) – \(Dates.fmtMD(Dates.addDays(mon, 6))) · 周视图")
            if layout.narrow {
                VStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { DayBox(mon: mon, i: $0) }
                    HStack(alignment: .top, spacing: 8) { DayBox(mon: mon, i: 5, small: true); DayBox(mon: mon, i: 6, small: true) }
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(spacing: 8) {
                    pair { DayBox(mon: mon, i: 0) } _: { DayBox(mon: mon, i: 1) }
                    pair { DayBox(mon: mon, i: 2) } _: { DayBox(mon: mon, i: 3) }
                    pair { DayBox(mon: mon, i: 4) } _: {
                        VStack(spacing: 8) { DayBox(mon: mon, i: 5, small: true); DayBox(mon: mon, i: 6, small: true) }
                    }
                }
            }
            Hint("方框里的内容和日视图是同一份 · 点 **Mon / Tue…** 进入那一天")
        }
    }

    private func pair<A: View, B: View>(@ViewBuilder _ a: () -> A, @ViewBuilder _ b: () -> B) -> some View {
        HStack(alignment: .top, spacing: 8) { a(); b() }
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DayBox: View {
    @Environment(BujoStore.self) private var store
    let mon: String
    let i: Int
    var small = false

    var body: some View {
        let s = Dates.addDays(mon, i), o = store.doc.days[s], light = o?.light.count ?? 0
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                DotSticker(dot: o?.dot, label: "\(Dates.dayOfMonth(s))", size: 22) { store.cycleDot(s) }
                Button { store.go(.day, s) } label: {
                    Text(Dates.WD[i]).font(.hand(20)).foregroundStyle(C.ink)
                }
                .buttonStyle(.plain)
                .help("打开日视图")
            }
            BulletList(ref: .day(s, "main"), compact: true, placeholder: "")
            if light > 0 { Text("+ \(light) 项轻松任务").font(.ui(12)).foregroundStyle(C.ink3) }
        }
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: small ? 71 : 150, maxHeight: .infinity, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(C.ink, lineWidth: 1.8))
        .overlay {
            if s == Dates.today() {
                RoundedRectangle(cornerRadius: 3).inset(by: 2.5).stroke(C.yellow.opacity(0.7), lineWidth: 2)
            }
        }
    }
}

struct WeekRight: View {
    @Environment(BujoStore.self) private var store
    @Environment(\.layout) private var layout

    var body: some View {
        let mon = Dates.mondayOf(store.date)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("overview", sub: "这周要做完、但不必绑在某一天的事")
            let cols = layout.narrow ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 18), GridItem(.flexible())]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                column("正经事 · main", .wk(mon, "serious"))
                column("轻松一点 · light", .wk(mon, "light"))
            }
            Hint("第一栏 **/** = 已开始 · 第二栏 **X** = 完成，**>** = 移到下周（点格子切换）")
            HStack(spacing: 6) {
                Button("未完成 → 下周") { store.migrateAll([.wk(mon, "serious"), .wk(mon, "light")]) }.buttonStyle(.pill)
                Button("本周打卡页 →") { store.go(.habits) }.buttonStyle(.pill)
            }
            .padding(.top, 6)
            SectionTitle("保持追踪 · keep track")
            BulletList(ref: .wk(mon, "track"), placeholder: "不用我做，但要盯着的事…")
        }
    }

    private func column(_ title: String, _ ref: ListRef) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.ui(12.5, .semibold)).foregroundStyle(C.ink2)
            BulletList(ref: ref, two: true, placeholder: "任务")
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
