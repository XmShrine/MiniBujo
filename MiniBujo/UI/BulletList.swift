import SwiftUI

let NEW_PH = "写点什么… (o 开头=事件 · - 开头=备注 · ! 开头=重要)"

/// 子弹列表：点符号切换状态，⋯ 菜单改类型 / 标重要 / 迁移 / 取消 / 删除，回车新增一行。
/// two = 周视图 overview 的两栏模式（/ = 已开始，X = 完成，> = 移到下周）
struct BulletList: View {
    @Environment(BujoStore.self) private var store
    let ref: ListRef
    var two = false
    var compact = false
    var placeholder = NEW_PH

    enum Field: Hashable { case item(String), new }
    @FocusState private var focus: Field?
    @State private var draft = ""

    private var fs: CGFloat { compact ? 13 : 15 }
    private var lineH: CGFloat { compact ? 20 : 24 }

    var body: some View {
        let items = store.items(ref)
        VStack(alignment: .leading, spacing: compact ? 0 : 1) {
            if two {
                HStack(spacing: 4) {
                    Spacer()
                    Text("/").frame(width: 22)
                    Text("X").frame(width: 22)
                }
                .font(.hand(15)).foregroundStyle(C.ink3)
            }
            ForEach(items) { row($0) }
            newRow
        }
        .onChange(of: focus) { old, new in
            // 编辑过的行清空后离开 = 删掉这一行（网页版是空行按退格）
            if case let .item(id) = old, new != old,
               let it = store.items(ref).first(where: { $0.id == id }),
               it.x.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.deleteItem(ref, id)
            }
            // 新输入框里写了字但没按回车就离开：也记下来
            if old == .new, new != .new { commit(keepFocus: false) }
        }
    }

    // MARK: rows

    private func row(_ it: Item) -> some View {
        let focused = focus == .item(it.id)
        return HStack(alignment: .top, spacing: two ? 4 : 6) {
            if !two {
                SymView(item: it, sym: store.doc.settings.sym, compact: compact)
                    .contentShape(Rectangle())
                    .onTapGesture { store.editItem(ref, it.id) { $0.cycle() } }
                    .help("点击切换状态")
            }
            if it.pri {
                Text("★").font(.ui(compact ? 11 : 13)).foregroundStyle(C.red).frame(height: lineH)
            }
            TextField("", text: textBinding(it), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.ui(fs, it.pri ? .semibold : .regular))
                .foregroundStyle(textColor(it))
                .strikethrough(it.state == "cancelled" || (two && it.state == "done"), color: C.ink3)
                .padding(.vertical, compact ? 1 : 2)
                .frame(minHeight: lineH)
                .focused($focus, equals: .item(it.id))
                .onSubmit { focus = .new }
            ItemMenu(ref: ref, item: it, compact: compact)
            if two { cells(it) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 3).fill(focused ? C.yellow.opacity(0.14) : .clear))
    }

    private func textColor(_ it: Item) -> Color {
        switch it.state {
        case "done": C.ink2
        case "cancelled", "migrated": C.ink3
        default: C.ink
        }
    }

    private func textBinding(_ it: Item) -> Binding<String> {
        Binding(
            get: { store.items(ref).first { $0.id == it.id }?.x ?? it.x },
            set: { v in
                if v.contains("\n") {
                    store.editItem(ref, it.id) { $0.x = v.replacingOccurrences(of: "\n", with: "") }
                    focus = .new
                } else {
                    store.editItem(ref, it.id) { $0.x = v }
                }
            })
    }

    @ViewBuilder private func cells(_ it: Item) -> some View {
        cell(it.st == true ? "/" : "", help: "已开始") {
            store.editItem(ref, it.id) { $0.st = !($0.st ?? false) }
        }
        cell(it.state == "done" ? "X" : it.state == "migrated" ? ">" : "", help: "X 完成 / > 移到下周") {
            store.editItem(ref, it.id) { $0.s = $0.state == "done" ? "migrated" : $0.state == "migrated" ? "open" : "done" }
        }
    }

    private func cell(_ text: String, help: String = "", action: (() -> Void)? = nil) -> some View {
        Text(text)
            .font(.hand(20)).foregroundStyle(C.ink)
            .frame(width: 22).frame(minHeight: 26, maxHeight: .infinity)
            .overlay(alignment: .leading) { Rectangle().fill(C.ink).frame(width: 1.5) }
            .contentShape(Rectangle())
            .onTapGesture { action?() }
            .help(help)
    }

    // MARK: new row

    private var newRow: some View {
        HStack(alignment: .top, spacing: two ? 4 : 6) {
            Text("+").font(.ui(15)).foregroundStyle(C.ink3).frame(width: compact ? 16 : 20, height: lineH)
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.ui(fs))
                .foregroundStyle(C.ink)
                .padding(.vertical, compact ? 1 : 2)
                .frame(minHeight: lineH)
                .focused($focus, equals: .new)
                .onSubmit { commit(keepFocus: true) }
                .onChange(of: draft) { _, v in if v.contains("\n") { commit(keepFocus: true) } }
            if two { cell(""); cell("") }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func commit(keepFocus: Bool) {
        let v = draft.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !v.isEmpty else { return }
        store.addItem(ref, v)
        if keepFocus { focus = .new }
    }
}

/// ⋯ 菜单
struct ItemMenu: View {
    @Environment(BujoStore.self) private var store
    let ref: ListRef
    let item: Item
    var compact = false

    var body: some View {
        Menu {
            Picker("类型", selection: Binding(get: { item.t }, set: { t in
                store.editItem(ref, item.id) { it in
                    it.t = t
                    if t != "task" && (it.state == "started" || it.state == "migrated") { it.s = "open" }
                }
            })) {
                Text("☐ 任务").tag("task")
                Text("○ 事件").tag("event")
                Text("– 备注").tag("note")
            }
            .pickerStyle(.inline)
            Button(item.pri ? "★ 取消重要" : "★ 标为重要") { store.editItem(ref, item.id) { $0.p = !($0.p ?? false) } }
            if let tg = ref.migrateTarget, item.t == "task" {
                Button("> 迁移到\(tg.label)") { store.migrate(ref, item.id) }
            }
            moveButton
            Button(item.state == "cancelled" ? "恢复" : "划掉（取消）") {
                store.editItem(ref, item.id) { $0.s = $0.state == "cancelled" ? "open" : "cancelled" }
            }
            Divider()
            Button("删除", role: .destructive) { store.deleteItem(ref, item.id) }
        } label: {
            Text("⋯").font(.ui(16)).foregroundStyle(C.ink3)
                .frame(width: compact ? 18 : 22, height: compact ? 20 : 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(0.6)
        .accessibilityLabel("更多操作")
    }

    @ViewBuilder private var moveButton: some View {
        switch ref {
        case let .day(_, b):
            Button(b == "main" ? "↓ 移到「轻松」" : "↑ 移到「重要」") { store.moveItem(ref, item.id, to: b == "main" ? "light" : "main") }
        case let .wk(_, b) where b != "track":
            Button(b == "serious" ? "→ 移到「轻松」栏" : "← 移到「正经事」栏") { store.moveItem(ref, item.id, to: b == "serious" ? "light" : "serious") }
        default:
            EmptyView()
        }
    }
}

/// 任务符号：方框 / 圆点、事件圆圈、备注横线、迁移 >
struct SymView: View {
    let item: Item
    let sym: String
    var compact = false

    var body: some View {
        Group {
            if item.t == "note" {
                Text("–").font(.hand(compact ? 18 : 22)).foregroundStyle(C.ink2)
            } else if item.t == "event" {
                let d: CGFloat = compact ? 9 : 11
                Circle().fill(item.state == "done" ? C.ink : .clear)
                    .overlay(Circle().stroke(C.ink, lineWidth: 1.7))
                    .frame(width: d, height: d)
            } else if item.state == "migrated" {
                Text(">").font(.hand(compact ? 18 : 22)).foregroundStyle(C.ink)
            } else if sym == "dot" {
                Text(["open": "•", "started": "/", "done": "×", "cancelled": "•"][item.state] ?? "•")
                    .font(.hand(compact ? 18 : 22)).foregroundStyle(C.ink)
            } else {
                BoxSym(state: item.state, size: compact ? 10 : 12)
            }
        }
        .frame(width: compact ? 16 : 20, height: compact ? 20 : 24)
    }
}

struct BoxSym: View {
    let state: String
    var size: CGFloat = 12
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2).fill(state == "done" ? C.ink : .clear)
            if state == "started" {
                Path { p in p.move(to: .zero); p.addLine(to: .init(x: size, y: 0)); p.addLine(to: .init(x: 0, y: size)); p.closeSubpath() }
                    .fill(C.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            RoundedRectangle(cornerRadius: 2).stroke(C.ink, lineWidth: 1.7)
        }
        .frame(width: size, height: size)
        .opacity(state == "cancelled" ? 0.45 : 1)
    }
}
