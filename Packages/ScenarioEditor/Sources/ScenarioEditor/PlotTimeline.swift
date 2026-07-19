import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

/// 플롯 타임라인 (2a) — 장면 = 카드, 분기 = 장면 뒤 레인 칩.
/// 카드 클릭 = 해당 장면으로 점프, 드래그 = 장면 재배열(본문 블록 순서 반영),
/// 분기 칩 클릭 = 그 분기로 전환/복귀.
struct PlotTimelineView: View {
    @Bindable var store: ScenarioStore
    let isReadOnly: Bool
    let onJump: (UUID) -> Void

    @Environment(\.resolvedAccent) private var accent
    /// 드래그 중인 장면 id (라이브 리오더)
    @State private var draggingSceneID: UUID?

    var body: some View {
        let l10n = Localizer.shared
        let scenes = store.plotScenes
        HStack(spacing: 10) {
            Text(l10n.t(.plotLabel))
                .font(DSFonts.font(size: 10.5, weight: .semibold, family: .pretendard))
                .kerning(1)
                .foregroundStyle(SonnetPalette.inkMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                        SceneCard(
                            scene: scene,
                            number: index + 1,
                            isCurrent: isCurrent(scene, index: index, total: scenes.count),
                            isDimmed: draggingSceneID != nil && draggingSceneID != scene.id
                        ) {
                            store.currentSceneID = scene.id
                            onJump(scene.jumpTargetID)
                        }
                        .onDrag {
                            guard !isReadOnly else { return NSItemProvider() }
                            store.beginSceneDrag()
                            draggingSceneID = scene.id
                            return NSItemProvider(object: scene.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text], delegate: SceneReorderDropDelegate(
                            targetID: scene.id,
                            store: store,
                            draggingSceneID: $draggingSceneID
                        ))

                        // 이 장면에서 갈라진 분기 — ⑂ 레인
                        if !scene.branchIDs.isEmpty {
                            Text("⑂")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: "#C2482D"))
                            ForEach(scene.branchIDs, id: \.self) { branchID in
                                if let branch = store.content.branches.first(where: { $0.id == branchID }) {
                                    branchChip(branch)
                                }
                            }
                        }
                    }

                    if !isReadOnly {
                        addSceneCard(l10n)
                    }
                }
                .padding(.vertical, 2)
            }

            Text(l10n.t(.plotDragHint))
                .font(DSFonts.font(size: 10.5, family: .pretendard))
                .foregroundStyle(SonnetPalette.inkMuted)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SonnetPalette.canvas.opacity(0.01)) // 히트 영역 확보
        .animation(DesignTokens.Motion.glassPop, value: store.content.blocks.map(\.id))
        .animation(DesignTokens.Motion.glassPop, value: store.activeBranchID)
    }

    /// 현재 장면 — 마지막으로 선택한 장면, 선택 이력이 없으면 마지막 장면(집필 지점).
    private func isCurrent(_ scene: ScenarioStore.PlotScene, index: Int, total: Int) -> Bool {
        if let currentID = store.currentSceneID {
            return scene.id == currentID
        }
        return index == total - 1
    }

    /// 분기 칩 — 인장 틴트 대시 캡슐. 활성 분기는 채움 강조.
    private func branchChip(_ branch: ScenarioBranch) -> some View {
        let isActive = store.activeBranchID == branch.id
        return Button {
            withAnimation(DesignTokens.Motion.glassPop) {
                store.switchBranch(isActive ? nil : branch.id)
            }
        } label: {
            Text("\(branch.name) · \(branch.blocks.count)")
                .font(DSFonts.font(size: 10.5, weight: .semibold, family: .pretendard))
                .foregroundStyle(isActive ? Color(hex: "#F6F4EF") : accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isActive ? AnyShapeStyle(accent) : AnyShapeStyle(SonnetPalette.accentTint))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            Color(hex: "#C2482D"),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])
                        )
                        .opacity(isActive ? 0 : 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(branch.name)
    }

    /// ＋ 장면 — 본편 끝에 장면 경계 추가.
    private func addSceneCard(_ l10n: Localizer) -> some View {
        Button {
            let id = store.addScene(title: "")
            onJump(id)
        } label: {
            Text("＋ \(l10n.t(.sceneBlock))")
                .font(DSFonts.font(size: 11, family: .pretendard))
                .foregroundStyle(SonnetPalette.inkMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            SonnetPalette.ink.opacity(0.2),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(l10n.t(.composerPlaceholderScene))
    }
}

/// 장면 카드 한 칸.
private struct SceneCard: View {
    let scene: ScenarioStore.PlotScene
    let number: Int
    let isCurrent: Bool
    let isDimmed: Bool
    let onTap: () -> Void

    @Environment(\.resolvedAccent) private var accent
    @State private var hovering = false

    private var titleLine: String {
        let prefix = "S#\(number)"
        return scene.title.isEmpty ? prefix : "\(prefix) · \(scene.title)"
    }

    private var metaLine: String {
        var parts = ["대사 \(scene.lineCount)"]
        if !scene.branchIDs.isEmpty { parts.append("분기 \(scene.branchIDs.count)") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleLine)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isCurrent ? accent : SonnetPalette.inkMuted)
                    .lineLimit(1)
                Text(metaLine)
                    .font(DSFonts.font(size: 10, family: .pretendard))
                    .foregroundStyle(SonnetPalette.inkMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 96, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SonnetPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isCurrent ? accent : SonnetPalette.ink.opacity(0.1),
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
            .background(
                // 현재 장면 강조 링 (0 0 0 3px rgba(seal,.08))
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent.opacity(isCurrent ? 0.08 : 0))
                    .padding(-3)
            )
            .opacity(isDimmed ? 0.45 : (isCurrent || hovering ? 1 : 0.85))
            .offset(y: hovering && !isCurrent ? -1 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.press, value: hovering)
    }
}

/// 장면 드래그 리오더 — 다른 카드 위로 들어오는 순간 자리를 바꾸고(라이브),
/// 드롭 시 단일 undo 항목으로 확정한다.
private struct SceneReorderDropDelegate: DropDelegate {
    let targetID: UUID
    let store: ScenarioStore
    @Binding var draggingSceneID: UUID?

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let draggedID = draggingSceneID, draggedID != targetID else { return }
            withAnimation(DesignTokens.Motion.glassPop) {
                store.moveSceneLive(draggedID: draggedID, over: targetID)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            store.endSceneDrag()
            draggingSceneID = nil
        }
        return true
    }
}
