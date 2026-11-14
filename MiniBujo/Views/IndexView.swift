import SwiftUI

struct IndexLeft: View {
    @Environment(BujoStore.self) private var store
    @Environment(\.layout) private var layout

    var body: some View {
        @Bindable var store = store
        let cards = store.doc.days.flatMap { d, o in o.cards.filter(\.tag).map { (d, $0) } }.sorted { $0.0 > $1.0 }
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("index", sub: "搜索整本手帐")
            TextField("搜点什么…", text: $store.query)
                .textFieldStyle(.plain).font(.ui(15)).foregroundStyle(C.ink)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(C.paper))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(C.ink, lineWidth: 1.8))
                .autocorrectionDisabled()
            let q = store.query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                let hits = store.search(q)
                VStack(spacing: 0) {
                    if hits.isEmpty { empty("没找到") }
                    ForEach(hits) { h in
                        row(where_: h.where_, what: highlight(snippet(h.text, q), q)) { store.open(h.target) }
                    }
                }
                .padding(.top, 10)
            }
            SectionTitle("黄色标签 · 卡片")
            VStack(spacing: 0) {
                if cards.isEmpty { empty("日视图里「+ 卡片」并贴黄标签的内容（菜谱、清单…）会出现在这里") }
                ForEach(cards, id: \.1.id) { d, c in
                    let title = !c.title.isEmpty ? c.title : !c.body.isEmpty ? String(c.body.prefix(40)) : "（空卡片）"
                    row(where_: d, what: AttributedString(title), tag: true) { store.go(.day, d) }
                }
            }
        }
    }

    private func empty(_ s: String) -> some View {
        Text(s).font(.ui(13.5)).foregroundStyle(C.ink3).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    private func row(where_: String, what: AttributedString, tag: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(where_).font(.ui(12)).foregroundStyle(C.ink3).lineLimit(1)
                    .frame(width: layout.narrow ? 92 : 128, alignment: .leading)
                HStack(spacing: 6) {
                    if tag { UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2).fill(C.yellow).frame(width: 8, height: 12) }
                    Text(what).font(.ui(14)).foregroundStyle(C.ink).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7).padding(.horizontal, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func snippet(_ t: String, _ q: String) -> String {
        let s = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let r = s.range(of: q, options: .caseInsensitive) else { return String(s.prefix(100)) }
        let start = s.index(r.lowerBound, offsetBy: -20, limitedBy: s.startIndex) ?? s.startIndex
        let end = s.index(r.lowerBound, offsetBy: 80, limitedBy: s.endIndex) ?? s.endIndex
        return String(s[start..<end])
    }

    private func highlight(_ s: String, _ q: String) -> AttributedString {
        var a = AttributedString(s)
        var from = a.startIndex
        while let r = a[from...].range(of: q, options: .caseInsensitive) {
            a[r].backgroundColor = C.yellow.opacity(0.55)
            from = r.upperBound
        }
        return a
    }
}

struct IndexRight: View {
    @Environment(BujoStore.self) private var store

    var body: some View {
        let sym = store.doc.settings.sym
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("key", sub: "符号说明 · 设置")
            HStack(spacing: 10) {
                Text("任务符号").font(.ui(12)).foregroundStyle(C.ink3)
                Picker("", selection: Binding(get: { sym }, set: { v in store.mutate { $0.settings.sym = v } })) {
                    Text("方框 ☐").tag("box")
                    Text("圆点 •").tag("dot")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                if sym == "box" {
                    key(AnyView(BoxSym(state: "open")), "任务 task")
                    key(AnyView(BoxSym(state: "started")), "进行中 started")
                    key(AnyView(BoxSym(state: "done")), "完成 done")
                } else {
                    key(hand("•"), "任务 task")
                    key(hand("/"), "进行中 started")
                    key(hand("×"), "完成 done")
                }
                key(hand(">"), "迁移 migrated（⋯ 菜单 → 迁移到明天 / 下周）")
                key(AnyView(Circle().stroke(C.ink, lineWidth: 1.7).frame(width: 11, height: 11)), "事件 event（输入时用 o 开头）")
                key(hand("–"), "备注 note（输入时用 - 开头）")
                key(AnyView(Text("★").font(.ui(13)).foregroundStyle(C.red)), "重要（输入时用 ! 开头）")
                key(AnyView(Text("abc").strikethrough().foregroundStyle(C.ink3)), "取消 cancelled")
                key(AnyView(Circle().fill(C.red).frame(width: 10, height: 10)), "红圆点：这天有重要安排")
                key(AnyView(Circle().fill(C.blue).frame(width: 10, height: 10)), "蓝圆点：这天有不太重要的预约")
            }
            Hint("点符号切换状态；每行右侧 ⋯ 可以改类型、标重要、迁移、取消、删除。回车新增一行，清空一行再离开就会删掉它。")

            SectionTitle("提醒 · reminders")
            ReminderSettings()

            SectionTitle("数据 · iCloud")
            DataSettings()
        }
    }

    private func hand(_ s: String) -> AnyView { AnyView(Text(s).font(.hand(22)).foregroundStyle(C.ink)) }

    private func key(_ sym: AnyView, _ text: String) -> some View {
        HStack(spacing: 0) {
            sym.frame(width: 40, alignment: .leading)
            Text(text).font(.ui(13.5)).foregroundStyle(C.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
    }
}

// MARK: - reminders

private struct ReminderSettings: View {
    @Environment(ReminderCenter.self) private var rc

    var body: some View {
        @Bindable var rc = rc
        VStack(alignment: .leading, spacing: 8) {
            Toggle("开启提醒（只影响这台设备）", isOn: $rc.prefs.enabled)
                .font(.ui(14, .medium))
            if rc.authorized == false {
                Text("系统里关掉了 Mini Bujo 的通知，到「设置 → 通知」里打开后才会响。")
                    .font(.ui(12.5)).foregroundStyle(C.red)
            }
            if rc.prefs.enabled {
                Group {
                    toggleRow("红点 / 蓝点日", "红点：前一晚和当天早上各提醒一次；蓝点：当天早上", $rc.prefs.dotDays) {
                        timePick("前一晚", $rc.prefs.eveMin)
                        timePick("当天早上", $rc.prefs.morningMin)
                    }
                    toggleRow("时间轴", "日视图时间轴里写了内容的整点", $rc.prefs.timeline) { EmptyView() }
                    toggleRow("文字里的时间", "月记、任务、事件里写的「15:30 牙医」这类时间", $rc.prefs.textTimes) { EmptyView() }
                    if rc.prefs.timeline || rc.prefs.textTimes {
                        HStack {
                            Text("提前").font(.ui(13)).foregroundStyle(C.ink2)
                            Picker("", selection: $rc.prefs.leadMin) {
                                ForEach([0, 5, 10, 15, 30, 60], id: \.self) { Text($0 == 0 ? "准时" : "\($0) 分钟").tag($0) }
                            }
                            .labelsHidden().fixedSize()
                        }
                        .padding(.leading, 4)
                    }
                    toggleRow("每晚打卡", "提醒还没打卡的习惯、没记的心情、没做完要迁移的任务", $rc.prefs.checkin) {
                        timePick("时间", $rc.prefs.checkinMin)
                    }
                    toggleRow("周日小结", "提醒把本周没完成的迁到下周、写本周小结", $rc.prefs.weekly) {
                        timePick("时间", $rc.prefs.weeklyMin)
                    }
                }
                HStack(spacing: 8) {
                    Button("发一条试试") { rc.sendTest() }.buttonStyle(.pill)
                    Text("接下来 2 周已排好 \(rc.pendingCount) 条提醒").font(.ui(12)).foregroundStyle(C.ink3)
                }
                .padding(.top, 4)
            }
        }
        .toggleStyle(.switch)
        .tint(C.green)
        .foregroundStyle(C.ink)
    }

    private func toggleRow<Extra: View>(_ title: String, _ sub: String, _ on: Binding<Bool>, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: on) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.ui(14))
                    Text(sub).font(.ui(12)).foregroundStyle(C.ink3).fixedSize(horizontal: false, vertical: true)
                }
            }
            if on.wrappedValue {
                HStack(spacing: 14) { extra() }.padding(.leading, 4)
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(C.line).frame(height: 1) }
    }

    private func timePick(_ label: String, _ minutes: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.ui(13)).foregroundStyle(C.ink2)
            DatePicker("", selection: Binding(
                get: { Dates.cal.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date())! },
                set: { let c = Dates.cal.dateComponents([.hour, .minute], from: $0); minutes.wrappedValue = c.hour! * 60 + c.minute! }),
                       displayedComponents: .hourAndMinute)
                .labelsHidden().controlSize(.small).fixedSize()
        }
    }
}

// MARK: - data

private struct DataSettings: View {
    @Environment(BujoStore.self) private var store
    @Environment(FileSync.self) private var sync
    @Environment(FileActions.self) private var files

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(store.doc.days.values.filter { !$0.isEmpty }.count) 天 · \(store.doc.weeks.count) 周 · \(store.doc.cols.count) 个跟踪页")
                .font(.ui(12)).foregroundStyle(C.ink3)
            let st = sync.statusText
            Text(st.text).font(.ui(12.5)).foregroundStyle(st.warn ? C.red : C.ink2)
            HStack(spacing: 6) {
                Button(sync.isLinked ? "更换 iCloud 文件夹…" : "关联 iCloud 文件夹…") { files.importing = .folder }
                    .buttonStyle(.pill(sync.isLinked ? .normal : .primary))
                Button("导入 .json…") { files.importing = .json }.buttonStyle(.pill)
                Button("导出 .json…") { files.exporting = true }.buttonStyle(.pill)
            }
            if sync.isLinked {
                Button("取消关联（之后只存本机）") { sync.unlink() }.buttonStyle(.pill(.danger))
            }
            Hint("iCloud 里的 my-bujo.json 和网页版的数据格式完全一样：网页版「保存」下载的 .json 可以在这里「导入」；网页版也能「打开」iCloud 里的这个文件。")
        }
    }
}
