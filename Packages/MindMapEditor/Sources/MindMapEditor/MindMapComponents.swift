import AppCore
import AppKit
import DesignSystem
import DocumentKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 노드 뷰 (Liquid Glass 틴트 카드)

struct MindMapNodeView: View {
    @Bindable var store: MindMapStore
    let node: DocumentKit.MindMapNode
    let zoom: Double
    let screenPosition: CGPoint
    let toCanvas: (CGPoint) -> CGPoint
    /// 포트 드래그 진행 (캔버스 뷰 좌표)
    let onPortDrag: (CGPoint) -> Void
    /// 포트 드롭 → 근접 노드 연결 확정
    let onPortDrop: (CGPoint) -> Void

    @State private var dragOrigin: CGPoint?
    @State private var hovering = false
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent
    @Environment(\.interfaceTheme) private var theme

    private var isSelected: Bool { store.selectedNodeID == node.id }
    private var tint: Color? { node.colorHex.map { Color(hex: $0) } }

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.caption)
                    .foregroundStyle(tint ?? Color.secondary)
                Text(node.title.isEmpty ? l10n.t(.untitled) : node.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
            }
            if !node.detail.isEmpty {
                Text(node.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if node.kind == .image, let path = node.resourcePath,
               let url = store.resourceResolver?(path),
               let image = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 264) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 132, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous))
            }
        }
        .padding(10)
        .frame(minWidth: 96, maxWidth: 180, alignment: .leading)
        .glassSurface(cornerRadius: DesignTokens.Radius.medium, tint: tint, quality: quality)
        // 글래스 표면은 반투명이라 아래에 그려진 연결선이 노드를 관통해 비쳤다 —
        // 캔버스색 불투명 베이스를 글래스 '뒤'에 깔아 선이 노드 밑에서 끊겨 보이게 한다.
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                .fill(theme.isBranded ? theme.canvasColor : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                .strokeBorder(
                    isSelected ? accent : (store.connectingFromID == node.id ? accent.opacity(0.6) : .clear),
                    lineWidth: 2
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 10 : 5, y: 3)
        .overlay(alignment: .trailing) { connectionPort }
        .scaleEffect(zoom, anchor: .center)
        .position(screenPosition)
        .onHover { hovering = $0 }
        .onTapGesture {
            if store.connectingFromID != nil {
                store.completeConnection(to: node.id)
            } else {
                store.selectedNodeID = node.id
            }
        }
        .gesture(dragGesture)
        .contextMenu {
            Button("연결선 시작") { store.beginConnecting(from: node.id) }
            Divider()
            Button(l10n.t(.delete), role: .destructive) { store.deleteNode(node.id) }
        }
        .animation(DesignTokens.Motion.snappy, value: isSelected)
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }

    /// 우측 연결 포트 — 호버/선택 시 노출, 드래그하면 프리뷰 라인과 함께 연결.
    private var connectionPort: some View {
        let visible = hovering || isSelected || store.connectingFromID == node.id
        return Circle()
            .fill(accent)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .padding(6) // 히트 영역 확장
            .contentShape(Circle())
            .offset(x: 14)
            .opacity(visible ? 1 : 0)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("mindmapCanvas"))
                    .onChanged { value in
                        onPortDrag(value.location)
                    }
                    .onEnded { value in
                        onPortDrop(value.location)
                    }
            )
            .help("드래그해서 다른 노드와 연결")
    }

    private var symbolName: String {
        switch node.kind {
        case .text: "textformat"
        case .page: "doc.richtext"
        case .image: "photo"
        case .file: "paperclip"
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragOrigin == nil {
                    dragOrigin = CGPoint(x: node.x, y: node.y)
                    store.selectedNodeID = node.id
                }
                let canvasPoint = toCanvas(value.location)
                store.liveMoveNode(id: node.id, to: canvasPoint)
            }
            .onEnded { _ in
                if let origin = dragOrigin {
                    store.commitMove(id: node.id, from: origin)
                }
                dragOrigin = nil
            }
    }
}

// MARK: - 노드 인스펙터 (우측)

struct MindMapInspectorView: View {
    @Bindable var store: MindMapStore
    let onOpenDocument: (UUID) -> Void

    private let palette = ["#5AC8FA", "#B18CFF", "#FF6482", "#FFB340", "#63E6B6"]

    var body: some View {
        let l10n = Localizer.shared
        ScrollView {
            if let node = store.selectedNode {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    Text(l10n.t(.inspector))
                        .font(.headline)

                    // 제목/설명
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(l10n.t(.untitled), text: binding(node) { $0.title } set: { $0.title = $1 })
                            .textFieldStyle(.roundedBorder)
                        TextField(
                            l10n.t(.characterSummary),
                            text: binding(node) { $0.detail } set: { $0.detail = $1 },
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                    }

                    // 컬러 피커 (Liquid Glass 틴트)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n.t(.accentColor)).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            ForEach(palette, id: \.self) { hex in
                                Button {
                                    var updated = node
                                    updated.colorHex = hex
                                    store.updateNode(updated)
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Circle().strokeBorder(
                                                node.colorHex == hex ? Color.primary : .clear,
                                                lineWidth: 2
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                var updated = node
                                updated.colorHex = nil
                                store.updateNode(updated)
                            } label: {
                                Image(systemName: "slash.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // 유형별 부가 기능
                    kindSection(node, l10n: l10n)

                    // 연결선 캡션
                    let edges = store.edges(of: node.id)
                    if !edges.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(l10n.t(.edgeCaption)).font(.caption).foregroundStyle(.secondary)
                            ForEach(edges) { edge in
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    TextField(
                                        otherNodeTitle(edge: edge, current: node.id),
                                        text: Binding(
                                            get: { edge.caption },
                                            set: { store.updateEdgeCaption(edge.id, caption: $0) }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    Button {
                                        store.deleteEdge(edge.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Divider()
                    Button(role: .destructive) {
                        store.deleteNode(node.id)
                    } label: {
                        Label(l10n.t(.delete), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(DesignTokens.Spacing.m)
            }
        }
    }

    @ViewBuilder
    private func kindSection(_ node: DocumentKit.MindMapNode, l10n: Localizer) -> some View {
        switch node.kind {
        case .page:
            VStack(alignment: .leading, spacing: 6) {
                let catalog = store.documentCatalog?() ?? []
                Menu {
                    ForEach(catalog, id: \.id) { entry in
                        Button(entry.title.isEmpty ? l10n.t(.untitled) : entry.title) {
                            var updated = node
                            updated.linkedDocumentID = entry.id
                            if updated.title.isEmpty || updated.title == l10n.t(.nodePage) {
                                updated.title = entry.title
                            }
                            store.updateNode(updated)
                        }
                    }
                    if node.linkedDocumentID != nil {
                        Divider()
                        Button(l10n.t(.delete), role: .destructive) {
                            var updated = node
                            updated.linkedDocumentID = nil
                            store.updateNode(updated)
                        }
                    }
                } label: {
                    Label(
                        linkedTitle(node, catalog: catalog) ?? "문서 연결…",
                        systemImage: "link"
                    )
                    .frame(maxWidth: .infinity)
                }

                if let docID = node.linkedDocumentID {
                    Button {
                        onOpenDocument(docID)
                    } label: {
                        Label(l10n.t(.open), systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        case .image, .file:
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    importResource(into: node)
                } label: {
                    Label(l10n.t(.choose), systemImage: node.kind == .image ? "photo.badge.plus" : "paperclip")
                        .frame(maxWidth: .infinity)
                }
                if node.kind == .image, let path = node.resourcePath,
                   let url = store.resourceResolver?(path),
                   let image = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 600) {
                    // 확대 뷰어
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous))
                } else if let path = node.resourcePath {
                    Text(path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        case .text:
            EmptyView()
        }
    }

    private func linkedTitle(_ node: DocumentKit.MindMapNode, catalog: [(id: UUID, title: String)]) -> String? {
        guard let docID = node.linkedDocumentID else { return nil }
        return catalog.first { $0.id == docID }?.title ?? "…"
    }

    private func otherNodeTitle(edge: MindMapEdge, current: UUID) -> String {
        let otherID = edge.fromID == current ? edge.toID : edge.fromID
        return store.node(id: otherID)?.title ?? "…"
    }

    private func importResource(into node: DocumentKit.MindMapNode) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if node.kind == .image {
            panel.allowedContentTypes = [.image]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = node
        updated.resourcePath = store.resourceImporter?(url) ?? url.path
        if updated.title.isEmpty || updated.title == Localizer.shared.t(.nodeImage) || updated.title == Localizer.shared.t(.nodeFile) {
            updated.title = url.deletingPathExtension().lastPathComponent
        }
        store.updateNode(updated)
    }

    /// 노드 필드 바인딩 헬퍼 (변경 즉시 store 반영)
    private func binding(
        _ node: DocumentKit.MindMapNode,
        get: @escaping (DocumentKit.MindMapNode) -> String,
        set: @escaping (inout DocumentKit.MindMapNode, String) -> Void
    ) -> Binding<String> {
        Binding(
            get: { store.node(id: node.id).map(get) ?? "" },
            set: { newValue in
                guard var current = store.node(id: node.id) else { return }
                set(&current, newValue)
                store.updateNode(current)
            }
        )
    }
}
