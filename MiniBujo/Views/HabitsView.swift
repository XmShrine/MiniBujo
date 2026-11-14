import SwiftUI

struct HabitsLeft: View {
    @Environment(BujoStore.self) private var store
    @FocusState private var nameFocus: String?

    var body: some View {
        let mon = Dates.mondayOf(store.date), W = store.peekWeek(mon)
        let ti = Dates.mondayOf(Dates.today()) == mon ? Dates.wdIdx(Dates.today()) : -1
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("habits", sub: "week \(Dates.weekNo(mon)) · \(Dates.fmtMD(mon)) – \(Dates.fmtMD(Dates.addDays(mon, 6)))")

            GridTable(rows: W.habits.map(\.id), today: ti) { id in
                TextField("习惯名", text: habitName(mon, id)).focused($nameFocus, equals: id)
            } cell: { id, i in
                let v = W.habits.first { $0.id == id }?.marks[i] ?? ""
                Button {
                    store.editWeek(mon) { w in
                        if let k = w.habits.firstIndex(where: { $0.id == id }) {
                            w.habits[k].marks[i] = ["": "X", "X": "/", "/": ""][w.habits[k].marks[i]] ?? ""
                        }
                    }
                } label: {
                    Text(v).font(.hand(22)).foregroundStyle(C.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } onDelete: { id in
                store.editWeek(mon) { $0.habits.removeAll { $0.id == id } }
            }
            HStack(spacing: 8) {
                Button("+ 习惯") {
                    let h = Habit()
                    store.editWeek(mon) { $0.habits.append(h) }
                    nameFocus = h.id
                }
                .buttonStyle(.pill)
                Text("点格子：X 完成 → / 做了一点 → 空").font(.ui(12.5)).foregroundStyle(C.ink3)
            }
            .padding(.top, 14)

            SectionTitle("打分 1–7")
            GridTable(rows: W.scores.map(\.id), today: ti) { id in
                TextField("打分项", text: scoreBind(mon, id, nil)).focused($nameFocus, equals: id)
            } cell: { id, i in
                TextField("", text: scoreBind(mon, id, i))
                    .multilineTextAlignment(.center)
                    .font(.hand(20))
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            } onDelete: { id in
                store.editWeek(mon) { $0.scores.removeAll { $0.id == id } }
            }
            Button("+ 打分项") {
                let sc = Score()
                store.editWeek(mon) { $0.scores.append(sc) }
                nameFocus = sc.id
            }
            .buttonStyle(.pill)
            .padding(.top, 14)

            SectionTitle("SLEEP · 睡眠 & 体重")
            SleepTable(mon: mon)
            SleepChart(sleep: W.sleep)
        }
    }

    private func habitName(_ mon: String, _ id: String) -> Binding<String> {
        Binding(get: { store.peekWeek(mon).habits.first { $0.id == id }?.name ?? "" },
                set: { v in store.editWeek(mon) { w in if let k = w.habits.firstIndex(where: { $0.id == id }) { w.habits[k].name = v } } })
    }

    private func scoreBind(_ mon: String, _ id: String, _ i: Int?) -> Binding<String> {
        Binding(get: {
            let sc = store.peekWeek(mon).scores.first { $0.id == id }
            return i.map { sc?.vals[$0] ?? "" } ?? sc?.name ?? ""
        }, set: { v in
            store.editWeek(mon) { w in
                guard let k = w.scores.firstIndex(where: { $0.id == id }) else { return }
                if let i { w.scores[k].vals[i] = String(v.prefix(2)) } else { w.scores[k].name = v }
            }
        })
    }
}

/// 习惯 / 打分共用的表格：左边名字，中间 7 格（粗框），右边删除
struct GridTable<Name: View, Cell: View>: View {
    let rows: [String]
    let today: Int
    @ViewBuilder let name: (String) -> Name
    @ViewBuilder let cell: (String, Int) -> Cell
    let onDelete: (String) -> Void
    @Environment(\.layout) private var layout

    private var cw: CGFloat { layout.narrow ? 29 : 32 }
    private let ch: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(0..<7, id: \.self) { Text(Dates.WD[$0]).font(.hand(15)).foregroundStyle(C.ink2).frame(width: cw) }
                Color.clear.frame(width: 24, height: 1)
            }
            .padding(.bottom, 2)
            ForEach(Array(rows.enumerated()), id: \.element) { r, id in
                HStack(spacing: 0) {
                    name(id)
                        .textFieldStyle(.plain).font(.ui(13.5)).foregroundStyle(C.ink)
                        .padding(.trailing, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            cell(id, i)
                                .textFieldStyle(.plain)
                                .frame(width: cw, height: ch)
                                .background(i == today ? C.yellow.opacity(0.18) : .clear)
                                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(C.line).frame(width: 1) } }
                        }
                    }
                    .overlay(EdgeBorder(edges: [.leading, .trailing] + (r == 0 ? [.top] : []) + (r == rows.count - 1 ? [.bottom] : []))
                        .stroke(C.ink, lineWidth: 1.8))
                    XButton { onDelete(id) }.opacity(0.6).frame(width: 24)
                }
                .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
            }
        }
    }
}

private struct SleepTable: View {
    @Environment(BujoStore.self) private var store
    let mon: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 38, height: 1)
                ForEach(["入睡", "起床", "体重"], id: \.self) {
                    Text($0).font(.ui(12, .medium)).foregroundStyle(C.ink3).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 2)
            ForEach(0..<7, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(Dates.WD[i]).font(.hand(17)).foregroundStyle(C.ink).lineLimit(1).fixedSize().frame(width: 38, alignment: .leading)
                    TimeCell(value: bind(\.bed, i), fallback: "23:00").frame(maxWidth: .infinity, alignment: .leading)
                    TimeCell(value: bind(\.wake, i), fallback: "07:00").frame(maxWidth: .infinity, alignment: .leading)
                    TextField("—", text: bind(\.wt, i))
                        .textFieldStyle(.plain).font(.ui(13)).foregroundStyle(C.ink)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 30)
                .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
            }
        }
    }

    private func bind(_ kp: WritableKeyPath<Sleep, [String]>, _ i: Int) -> Binding<String> {
        Binding(get: { store.peekWeek(mon).sleep[keyPath: kp][i] },
                set: { v in store.editWeek(mon) { $0.sleep[keyPath: kp][i] = v } })
    }
}

/// 网页版的 <input type=time>：空着显示「—」，点一下填默认时间，之后用时间选择器改
private struct TimeCell: View {
    @Binding var value: String
    let fallback: String

    var body: some View {
        if value.isEmpty {
            Button { value = fallback } label: {
                Text("—").font(.ui(13)).foregroundStyle(C.ink3).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 2) {
                DatePicker("", selection: Binding(get: { date(from: value) }, set: { value = Dates.hhmm($0) }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                Button { value = "" } label: {
                    Text("×").font(.ui(13)).foregroundStyle(C.ink3).frame(width: 18, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("清除")
            }
        }
    }

    private func date(from s: String) -> Date {
        let p = s.split(separator: ":").compactMap { Int($0) }
        return Dates.cal.date(bySettingHour: p.first ?? 0, minute: p.count > 1 ? p[1] : 0, second: 0, of: Date()) ?? Date()
    }
}

struct HabitsRight: View {
    @Environment(BujoStore.self) private var store
    @FocusState private var titleFocus: String?

    var body: some View {
        let mon = Dates.mondayOf(store.date), W = store.peekWeek(mon)
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("lists", sub: "每周可以换；没做完的条目会自动带到下周")
            ForEach(W.lists) { l in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("清单名", text: listTitle(mon, l.id))
                            .textFieldStyle(.plain).font(.hand(22)).foregroundStyle(C.ink)
                            .focused($titleFocus, equals: l.id)
                        XButton(help: "删除清单") {
                            let del = { store.editWeek(mon) { $0.lists.removeAll { $0.id == l.id } } }
                            if l.items.isEmpty { del() }
                            else { store.confirm = ConfirmRequest(title: "删除清单「\(l.title.isEmpty ? "未命名" : l.title)」？", action: del) }
                        }
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(C.ink).frame(height: 1.8) }
                    BulletList(ref: .wl(mon, l.id), placeholder: "")
                }
                .padding(.bottom, 14)
            }
            Button("+ 清单") {
                let l = WList()
                store.editWeek(mon) { $0.lists.append(l) }
                titleFocus = l.id
            }
            .buttonStyle(.pill)
            SectionTitle("thoughts & summary · 本周小结")
            GrowingEditor(text: Binding(get: { store.peekWeek(mon).thoughts }, set: { v in store.editWeek(mon) { $0.thoughts = v } }),
                          placeholder: "（可选）这周怎么样…", minHeight: 90, ruled: true)
        }
    }

    private func listTitle(_ mon: String, _ id: String) -> Binding<String> {
        Binding(get: { store.peekWeek(mon).lists.first { $0.id == id }?.title ?? "" },
                set: { v in store.editWeek(mon) { w in if let k = w.lists.firstIndex(where: { $0.id == id }) { w.lists[k].title = v } } })
    }
}
