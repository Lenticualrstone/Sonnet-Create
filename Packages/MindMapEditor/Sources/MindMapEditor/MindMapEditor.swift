import AppCore
import DesignSystem
import DocumentKit
import RenderingKit
import SwiftUI

/// 노드 연결형 마인드맵 뷰어/에디터 — 무한 확장 캔버스.
public struct MindMapEditorView: View {
    @Bindable var store: MindMapStore
    let breadcrumb: [String]
    let saveState: SaveState
    let onManualSave: () -> Void
    let onOpenDocument: (UUID) -> Void

    @State private var zoom: Double = 1
    @State private var offset: CGSize = .zero
    @State private var gestureBaseZoom: Double?
    @State private var gestureBaseOffset: CGSize?
    @State private var showInspector = true

    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent
    @Environment(\.readOnlyMode) private var readOnlyMode
    @Environment(\.mindmapAutoOpenInspector) private var autoOpenInspector

    private var isReadOnly: Bool { readOnlyMode?.wrappedValue == true }

    public init(
        store: MindMapStore,
        breadcrumb: [String],
        saveState: SaveState,
        onManualSave: @escaping () -> Void,
        onOpenDocument: @escaping (UUID) -> Void = { _ in }
    ) {
        self.store = store
        self.breadcrumb = breadcrumb
        self.saveState = saveState
        self.onManualSave = onManualSave
        self.onOpenDocument = onOpenDocument
        _zoom = State(initialValue: store.content.zoom)
        _offset = State(initialValue: CGSize(width: store.content.offsetX, height: store.content.offsetY))
    }

    public var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 0) {
            toolbar(l10n)
            Divider().opacity(0.4)
            HStack(spacing: 0) {
                canvas(l10n)
                if showInspector, store.selectedNode != nil, !isReadOnly {
                    Divider().opacity(0.4)
                    MindMapInspectorView(store: store, onOpenDocument: onOpenDocument)
                        .frame(width: 260)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .animation(DesignTokens.Motion.gentle, value: showInspector)
        .animation(DesignTokens.Motion.gentle, value: store.selectedNodeID)
        .onAppear { showInspector = autoOpenInspector }
    }

    // MARK: 좌표 변환

    private func toScreen(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x * zoom) + offset.width + size.width / 2,
            y: (point.y * zoom) + offset.height + size.height / 2
        )
    }

    private func toCanvas(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (point.x - offset.width - size.width / 2) / zoom,
            y: (point.y - offset.height - size.height / 2) / zoom
        )
    }

    private func persistViewport() {
        store.setViewport(zoom: zoom, offsetX: offset.width, offsetY: offset.height)
    }

    // MARK: 툴바

    private func toolbar(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            BreadcrumbView(breadcrumb)
            Spacer()

            ReadOnlyBadge()

            ToolbarIconButton("arrow.uturn.backward", help: l10n.t(.undo)) { store.undo() }
                .disabled(!store.canUndo || isReadOnly)
                .opacity(store.canUndo && !isReadOnly ? 1 : 0.35)
            ToolbarIconButton("arrow.uturn.forward", help: l10n.t(.redo)) { store.redo() }
                .disabled(!store.canRedo || isReadOnly)
                .opacity(store.canRedo && !isReadOnly ? 1 : 0.35)

            SaveStatusBadge(state: saveState, label: l10n.t(saveState.labelKey), action: onManualSave)

            ReadOnlyToggle()

            if !isReadOnly {
                Menu {
                    Button(l10n.t(.nodeText)) { addNodeAtCenter(.text) }
                    Button(l10n.t(.nodePage)) { addNodeAtCenter(.page) }
                    Button(l10n.t(.nodeImage)) { addNodeAtCenter(.image) }
                    Button(l10n.t(.nodeFile)) { addNodeAtCenter(.file) }
                } label: {
                    Label(l10n.t(.addNode), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 2) {
                ToolbarIconButton("minus.magnifyingglass", help: "-") { setZoom(zoom / 1.25) }
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
                ToolbarIconButton("plus.magnifyingglass", help: "+") { setZoom(zoom * 1.25) }
                ToolbarIconButton("arrow.counterclockwise", help: l10n.t(.zoomReset)) {
                    withAnimation(DesignTokens.Motion.gentle) {
                        zoom = 1
                        offset = .zero
                    }
                    persistViewport()
                }
            }

            ToolbarIconButton("sidebar.right", help: l10n.t(.inspector) + " (⌥⌘I)", isActive: showInspector) {
                showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    private func setZoom(_ value: Double) {
        withAnimation(DesignTokens.Motion.snappy) {
            zoom = min(3, max(0.25, value))
        }
        persistViewport()
    }

    private func addNodeAtCenter(_ kind: DocumentKit.MindMapNodeKind) {
        let l10n = Localizer.shared
        let title: String = switch kind {
        case .text: l10n.t(.nodeText)
        case .page: l10n.t(.nodePage)
        case .image: l10n.t(.nodeImage)
        case .file: l10n.t(.nodeFile)
        }
        // 화면 중앙 = 캔버스 좌표 (-offset)/zoom
        let point = CGPoint(x: -offset.width / zoom, y: -offset.height / zoom)
        store.addNode(kind: kind, title: title, at: point)
    }

    // MARK: 캔버스

    private func canvas(_ l10n: Localizer) -> some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // 배경: 단색 + 도트 패턴
                dotGrid(size: size)
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .gesture(doubleTapGesture(size: size))
                    .onTapGesture {
                        store.selectedNodeID = nil
                        store.cancelConnecting()
                    }

                // 연결선
                edgeLayer(size: size)

                // 포트 드래그 프리뷰 라인
                connectionPreview(size: size)

                // 노드 — 읽기 전용에서는 드래그/편집/선택을 모두 잠근다
                // (팬·줌은 배경 dotGrid 제스처와 simultaneousGesture라 계속 동작)
                ForEach(store.content.nodes) { node in
                    MindMapNodeView(
                        store: store,
                        node: node,
                        zoom: zoom,
                        screenPosition: toScreen(CGPoint(x: node.x, y: node.y), in: size),
                        toCanvas: { toCanvas($0, in: size) },
                        onPortDrag: { point in
                            store.connectingFromID = node.id
                            store.connectPreviewPoint = point
                        },
                        onPortDrop: { point in
                            resolveDrop(at: point, in: size)
                        }
                    )
                    .allowsHitTesting(!isReadOnly)
                }

                // 연결 모드 힌트 (컨텍스트 메뉴로 시작한 경우)
                if store.connectingFromID != nil, store.connectPreviewPoint == nil {
                    VStack {
                        Text("연결할 노드를 클릭하세요 — ESC로 취소")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .glassCapsule(quality: quality)
                        Spacer()
                    }
                    .padding(.top, DesignTokens.Spacing.m)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if store.content.nodes.isEmpty {
                    Text(l10n.t(.doubleClickToCreate))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "mindmapCanvas")
            .simultaneousGesture(magnifyGesture)
            .clipped()
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.escape) {
                store.cancelConnecting()
                return .handled
            }
            .onKeyPress(.delete) {
                guard let selected = store.selectedNodeID else { return .ignored }
                store.deleteNode(selected)
                return .handled
            }
        }
    }

    /// 포트 드롭 지점에서 가장 가까운 노드를 찾아 연결을 확정한다.
    private func resolveDrop(at point: CGPoint, in size: CGSize) {
        let threshold: CGFloat = 90
        var best: (id: UUID, distance: CGFloat)?
        for node in store.content.nodes where node.id != store.connectingFromID {
            let center = toScreen(CGPoint(x: node.x, y: node.y), in: size)
            let distance = hypot(center.x - point.x, center.y - point.y)
            if distance < threshold, distance < (best?.distance ?? .infinity) {
                best = (node.id, distance)
            }
        }
        if let best {
            store.completeConnection(to: best.id)
        } else {
            store.cancelConnecting()
        }
    }

    /// 드래그 중인 연결선 프리뷰 (점선 + 끝점 원).
    @ViewBuilder
    private func connectionPreview(size: CGSize) -> some View {
        if let fromID = store.connectingFromID,
           let fromNode = store.node(id: fromID),
           let preview = store.connectPreviewPoint {
            let p1 = toScreen(CGPoint(x: fromNode.x, y: fromNode.y), in: size)
            Canvas { context, _ in
                var path = Path()
                path.move(to: p1)
                path.addLine(to: preview)
                context.stroke(
                    path,
                    with: .color(accent),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4])
                )
                let endDot = CGRect(x: preview.x - 5, y: preview.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: endDot), with: .color(accent))
            }
            .allowsHitTesting(false)
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if gestureBaseOffset == nil { gestureBaseOffset = offset }
                guard let base = gestureBaseOffset else { return }
                offset = CGSize(
                    width: base.width + value.translation.width,
                    height: base.height + value.translation.height
                )
            }
            .onEnded { _ in
                gestureBaseOffset = nil
                persistViewport()
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if gestureBaseZoom == nil { gestureBaseZoom = zoom }
                guard let base = gestureBaseZoom else { return }
                zoom = min(3, max(0.25, base * value.magnification))
            }
            .onEnded { _ in
                gestureBaseZoom = nil
                persistViewport()
            }
    }

    private func doubleTapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard !isReadOnly else { return }
                let point = toCanvas(value.location, in: size)
                store.addNode(kind: .text, title: Localizer.shared.t(.nodeText), at: point)
            }
    }

    // MARK: 배경 도트

    private func dotGrid(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let spacing: CGFloat = 28 * zoom
            guard spacing > 6 else { return }
            let dotSize: CGFloat = max(1.2, 1.6 * zoom)
            let originX = (offset.width + canvasSize.width / 2).truncatingRemainder(dividingBy: spacing)
            let originY = (offset.height + canvasSize.height / 2).truncatingRemainder(dividingBy: spacing)
            var x = originX - spacing
            while x < canvasSize.width + spacing {
                var y = originY - spacing
                while y < canvasSize.height + spacing {
                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(0.09)))
                    y += spacing
                }
                x += spacing
            }
        }
        .background(Color.clear)
    }

    // MARK: 엣지 레이어

    private func edgeLayer(size: CGSize) -> some View {
        let highlighted = store.edgesTouching(store.selectedNodeID)
        return ZStack {
            Canvas { context, _ in
                for edge in store.content.edges {
                    guard
                        let from = store.node(id: edge.fromID),
                        let to = store.node(id: edge.toID)
                    else { continue }
                    let p1 = toScreen(CGPoint(x: from.x, y: from.y), in: size)
                    let p2 = toScreen(CGPoint(x: to.x, y: to.y), in: size)

                    var path = Path()
                    path.move(to: p1)
                    let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                    let bend = CGPoint(
                        x: mid.x + (p2.y - p1.y) * 0.08,
                        y: mid.y - (p2.x - p1.x) * 0.08
                    )
                    path.addQuadCurve(to: p2, control: bend)

                    let isHot = highlighted.contains(edge.id)
                    context.stroke(
                        path,
                        with: .color(isHot ? accent : Color.primary.opacity(0.28)),
                        style: StrokeStyle(lineWidth: isHot ? 2.5 : 1.5, lineCap: .round)
                    )
                }
            }
            .allowsHitTesting(false)

            // 캡션 (텍스트는 Canvas 밖에서 그려 폰트 처리 단순화)
            ForEach(store.content.edges.filter { !$0.caption.isEmpty }) { edge in
                if let from = store.node(id: edge.fromID), let to = store.node(id: edge.toID) {
                    let p1 = toScreen(CGPoint(x: from.x, y: from.y), in: size)
                    let p2 = toScreen(CGPoint(x: to.x, y: to.y), in: size)
                    Text(edge.caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassCapsule(quality: quality)
                        .position(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
