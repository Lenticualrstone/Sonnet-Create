import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

// MARK: - 플롯 궤도 (구조 보기)
// 시나리오의 장면들을 하나의 연속된 획으로 압축해 보여준다.
// 대사량이 획의 높이가 되고, 분기는 본선에서 실제로 갈라져 나간다.
// 드래그로 궤도를 돌리고, 하단 스크럽으로 장면 사이를 훑는다.
//
// 브랜드 번안: 원본 레퍼런스의 네온 발광 대신 '종이 위에 그은 먹선 + 버밀리온 인장 점'.
// 다크 모드에서만 은은한 발광을 얹는다.

struct PlotOrbitView: View {
    @Bindable var store: ScenarioStore
    let onJump: (UUID) -> Void

    @Environment(\.resolvedAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.motionReduced) private var motionReduced

    /// 궤도 회전 (드래그) — yaw는 좌우, pitch는 상하 기울기
    @State private var yaw: Double = -0.5
    @State private var pitch: Double = 0.42
    @State private var dragBase: (yaw: Double, pitch: Double)?
    /// 스크럽 위치 (0...1) — 획 위를 훑는 인장 점
    @State private var progress: Double = 1

    /// 궤도의 마디 하나 — 장면(구분선으로 나눈 구간)이 기본이지만,
    /// 장면을 나누지 않은 문서에서는 대사/지침 블록이 마디가 된다.
    struct OrbitNode: Identifiable {
        let id: UUID
        let title: String
        /// 획의 높이를 정하는 무게 (장면=대사 수, 블록=글자 수)
        let weight: Int
        let branchCount: Int
        let jumpTargetID: UUID
    }

    /// 장면이 2개 이상이면 장면 궤도, 아니면 블록 흐름을 궤도로 그린다.
    private var nodes: [OrbitNode] {
        let scenes = store.plotScenes
        if scenes.count >= 2 {
            return scenes.map {
                OrbitNode(
                    id: $0.id,
                    title: $0.title,
                    weight: $0.lineCount,
                    branchCount: $0.branchIDs.count,
                    jumpTargetID: $0.jumpTargetID
                )
            }
        }
        // 폴백 — 블록 하나가 마디. 구분선은 장면 제목으로 읽는다.
        return store.visibleBlocks.filter { $0.kind != .divider || !$0.text.isEmpty }.map { block in
            OrbitNode(
                id: block.id,
                title: block.text.isEmpty ? "…" : String(block.text.prefix(28)),
                weight: max(block.text.count, 1),
                branchCount: 0,
                jumpTargetID: block.id
            )
        }
    }

    /// 스크럽 위치에 해당하는 장면 인덱스
    private var focusedIndex: Int {
        let nodes = nodes
        guard nodes.count > 1 else { return 0 }
        return min(nodes.count - 1, max(0, Int((progress * Double(nodes.count - 1)).rounded())))
    }

    var body: some View {
        let l10n = Localizer.shared
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    canvas(size: geo.size)
                    // 사건 칩 — 지금 훑고 있는 장면만 (모두 띄우면 난잡해진다)
                    let nodes = nodes
                    if nodes.indices.contains(focusedIndex) {
                        sceneChip(nodes[focusedIndex], size: geo.size, l10n: l10n)
                    }
                }
                .contentShape(Rectangle())
                .gesture(orbitGesture)
            }
            .frame(height: 148)

            // 스크럽 — 획을 따라 장면 사이를 훑는다
            scrubBar(l10n)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
        .onAppear {
            // 현재 보고 있는 장면이 있으면 그 위치로 스크럽을 맞춘다
            if let currentID = store.currentSceneID,
               let index = nodes.firstIndex(where: { $0.id == currentID }),
               nodes.count > 1 {
                progress = Double(index) / Double(nodes.count - 1)
            }
        }
    }

    // MARK: 획 그리기

    /// 장면 i의 3D 좌표 — x는 시간축, y는 대사량(높이), z는 분기 깊이.
    private func point(for index: Int, in nodes: [OrbitNode]) -> SIMD3<Double> {
        let count = max(nodes.count - 1, 1)
        let t = Double(index) / Double(count)
        let maxWeight = max(nodes.map(\.weight).max() ?? 1, 1)
        let height = Double(nodes[index].weight) / Double(maxWeight)
        // 시간축을 가로지르며 완만하게 흔들리는 획 — 직선보다 '여정'처럼 읽힌다
        return SIMD3(
            (t - 0.5) * 2.0,
            -(height - 0.4) * 0.9,
            sin(t * .pi * 1.6) * 0.35
        )
    }

    /// 3D → 2D 투영 (AI 성운 스피어와 동일한 회전·투영 기법).
    private func project(_ p: SIMD3<Double>, in size: CGSize) -> (point: CGPoint, depth: Double) {
        let cy = cos(yaw), sy = sin(yaw)
        let cp = cos(pitch), sp = sin(pitch)
        let x1 = p.x * cy + p.z * sy
        let z1 = p.z * cy - p.x * sy
        let y1 = p.y * cp - z1 * sp
        let z2 = p.y * sp + z1 * cp
        let depth = (z2 + 1.6) / 3.2
        let scale = min(size.width, size.height * 2.1) * 0.34
        return (
            CGPoint(x: size.width / 2 + x1 * scale, y: size.height / 2 + y1 * scale * 0.9),
            depth
        )
    }

    private func canvas(size: CGSize) -> some View {
        let nodes = nodes
        return Canvas { context, canvasSize in
            guard nodes.count >= 2 else { return }
            let inkColor = colorScheme == .dark ? SonnetPalette.inkMuted : SonnetPalette.ink
            let projected = nodes.indices.map { project(point(for: $0, in: nodes), in: canvasSize) }

            // 본선 — 장면을 잇는 하나의 획 (곡선 보간)
            var path = Path()
            path.move(to: projected[0].point)
            for i in 1..<projected.count {
                let previous = projected[i - 1].point
                let current = projected[i].point
                let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: current, control: CGPoint(x: mid.x, y: previous.y))
            }
            // 다크에서는 획 아래 은은한 발광 (라이트는 종이 위 먹선 그대로)
            if colorScheme == .dark {
                context.stroke(
                    path,
                    with: .color(accent.opacity(0.22)),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                )
            }
            context.stroke(
                path,
                with: .color(inkColor.opacity(0.85)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            // 분기 — 본선에서 갈라져 나가는 가는 획 (점선)
            for (index, node) in nodes.enumerated() where node.branchCount > 0 {
                let origin = projected[index]
                for branchIndex in 0..<node.branchCount {
                    let spread = Double(branchIndex + 1) * 0.5
                    let target = project(
                        SIMD3(
                            point(for: index, in: nodes).x + 0.22,
                            point(for: index, in: nodes).y - 0.45 * spread,
                            point(for: index, in: nodes).z + 0.4 * spread
                        ),
                        in: canvasSize
                    )
                    var branch = Path()
                    branch.move(to: origin.point)
                    branch.addQuadCurve(
                        to: target.point,
                        control: CGPoint(x: origin.point.x + 14, y: (origin.point.y + target.point.y) / 2)
                    )
                    context.stroke(
                        branch,
                        with: .color(accent.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 3])
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: target.point.x - 2.5, y: target.point.y - 2.5, width: 5, height: 5)),
                        with: .color(accent.opacity(0.7))
                    )
                }
            }

            // 장면 마디 — 깊이에 따라 크기가 달라지는 먹점
            for (index, item) in projected.enumerated() {
                let radius = 2.0 + item.depth * 1.6
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: item.point.x - radius, y: item.point.y - radius,
                        width: radius * 2, height: radius * 2
                    )),
                    with: .color(inkColor.opacity(0.35 + 0.4 * item.depth))
                )
                _ = index
            }

            // 스크럽 인장 — 지금 훑고 있는 지점 (버밀리온 원점 + 후광)
            if projected.indices.contains(focusedIndex) {
                let focus = projected[focusedIndex].point
                context.fill(
                    Path(ellipseIn: CGRect(x: focus.x - 9, y: focus.y - 9, width: 18, height: 18)),
                    with: .color(accent.opacity(0.18))
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: focus.x - 4, y: focus.y - 4, width: 8, height: 8)),
                    with: .color(accent)
                )
            }
        }
    }

    // MARK: 사건 칩 · 스크럽

    /// 지금 훑고 있는 장면의 요약 칩 — 클릭하면 그 장면으로 점프.
    private func sceneChip(_ scene: OrbitNode, size: CGSize, l10n: Localizer) -> some View {
        Button {
            store.currentSceneID = scene.id
            onJump(scene.jumpTargetID)
        } label: {
            HStack(spacing: 6) {
                Text("S#\(focusedIndex + 1)")
                    .font(DSType.mono(size: 9.5, weight: .semibold))
                    .foregroundStyle(accent)
                Text(scene.title.isEmpty ? l10n.t(.untitled) : scene.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SonnetPalette.ink)
                    .lineLimit(1)
                Text(String(format: l10n.t(.linesCountFormat), scene.weight))
                    .font(.caption2)
                    .foregroundStyle(SonnetPalette.inkMuted)
                if scene.branchCount > 0 {
                    Text("⑂\(scene.branchCount)")
                        .font(DSType.mono(size: 9.5, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(SonnetPalette.surface)
                    .shadow(color: SonnetPalette.ink.opacity(0.12), radius: 5, y: 2)
            )
            .overlay(Capsule().strokeBorder(SonnetPalette.ink.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.leading, 10)
        .padding(.top, 6)
    }

    private func scrubBar(_ l10n: Localizer) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Slider(value: $progress, in: 0...1)
                .controlSize(.mini)
                .tint(accent)
            Text("\(focusedIndex + 1)/\(max(nodes.count, 1))")
                .font(DSType.mono(size: 10))
                .foregroundStyle(SonnetPalette.inkMuted)
                .frame(width: 42, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(l10n.t(.plotOrbit))
    }

    /// 드래그 = 궤도 회전. 모션 줄이기에서는 회전을 막지 않되 관성 없이 즉시 반영된다.
    private var orbitGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragBase == nil { dragBase = (yaw, pitch) }
                guard let base = dragBase else { return }
                yaw = base.yaw + Double(value.translation.width) * 0.006
                pitch = min(1.1, max(-0.2, base.pitch - Double(value.translation.height) * 0.004))
            }
            .onEnded { _ in dragBase = nil }
    }
}
