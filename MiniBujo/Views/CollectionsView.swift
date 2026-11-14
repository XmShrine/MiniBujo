import SwiftUI

struct ColsLeft: View {
    @Environment(BujoStore.self) private var store

    var body: some View {
        let cur = store.currentCol
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("collections", sub: "长期跟踪页")
            Hint("有些事不是某一周必须做完的，而是要连着跟几周（等回复的邮件、要跟进的事…），单独拎出来放这里，贴个绿标签方便找。")
            VStack(spacing: 6) {
                if store.doc.cols.isEmpty {
                    Text("还没有跟踪页").font(.ui(13.5)).foregroundStyle(C.ink3).frame(maxWidth: .infinity).padding(.vertical, 30)
                }
                ForEach(store.doc.cols) { c in
                    let open = c.items.filter { !$0.isClosed && $0.t != "note" }.count, on = c.id == cur?.id
                    Button { store.colID = c.id } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(C.green).frame(width: 6)
                            Text(c.title.isEmpty ? "未命名" : c.title).font(.ui(15)).foregroundStyle(C.ink)
                            Spacer(minLength: 0)
                            Text("\(open) 项进行中").font(.ui(12)).foregroundStyle(C.ink3)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 6).fill(C.paper))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? C.ink : C.line, lineWidth: on ? 2 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("+ 新建跟踪页") {
                let c = Col(title: store.doc.cols.isEmpty ? "open emails 待回复" : "")
                store.mutate { $0.cols.append(c) }
                store.colID = c.id
            }
            .buttonStyle(.pill)
            .padding(.top, 14)
        }
    }
}

struct ColsRight: View {
    @Environment(BujoStore.self) private var store

    var body: some View {
        if let cur = store.currentCol {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    TextField("标题，比如 open emails", text: Binding(
                        get: { store.doc.cols.first { $0.id == cur.id }?.title ?? "" },
                        set: { v in store.mutate { d in if let i = d.cols.firstIndex(where: { $0.id == cur.id }) { d.cols[i].title = v } } }))
                        .textFieldStyle(.plain).font(.hand(34)).foregroundStyle(C.ink)
                    XButton(help: "删除这一页") {
                        store.confirm = ConfirmRequest(title: "删除跟踪页「\(cur.title.isEmpty ? "未命名" : cur.title)」？") {
                            store.mutate { $0.cols.removeAll { $0.id == cur.id } }
                            store.colID = nil
                        }
                    }
                }
                .padding(.bottom, 14)
                BulletList(ref: .col(cur.id), placeholder: "要跟进的事")
                Hint("方框：空 = 未开始 · 半格 = 进行中 / 等回复 · 满格 = 搞定")
            }
            .id(cur.id)
        } else {
            Text("点左边「新建跟踪页」开始").font(.ui(13.5)).foregroundStyle(C.ink3)
                .frame(maxWidth: .infinity).padding(.vertical, 30)
        }
    }
}

extension BujoStore {
    var currentCol: Col? { doc.cols.first { $0.id == colID } ?? doc.cols.first }
}
