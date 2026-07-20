import AppCore
import DesignSystem
import DocumentKit
import SwiftUI

/// 문서 스냅샷 패널 — 이름 붙여 찍고, 현재 상태와 비교하고, 복원한다.
/// Scrivener 스냅샷 패턴: 큰 수정 전에 찍어 두는 안전망.
struct SnapshotPanelView: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    @Bindable var session: DocumentSession

    @State private var draftName = ""
    @State private var comparing: DocumentSnapshot?
    @State private var pendingRestore: DocumentSnapshot?

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.t(.snapshots))
                .font(.headline)
                .padding(DesignTokens.Spacing.m)

            // 새 스냅샷
            HStack(spacing: 6) {
                TextField(l10n.t(.snapshotNamePlaceholder), text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .onSubmit(take)
                Button(action: take) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .help(l10n.t(.takeSnapshot))
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.bottom, DesignTokens.Spacing.s)

            Divider().opacity(0.4)

            if session.snapshots.isEmpty {
                Text(l10n.t(.noSnapshots))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(DesignTokens.Spacing.m)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(session.snapshots) { snapshot in
                            snapshotRow(snapshot, l10n: l10n)
                        }
                    }
                    .padding(DesignTokens.Spacing.s)
                }
            }
        }
        .task(id: session.id) { session.refreshSnapshots() }
        .sheet(item: $comparing) { snapshot in
            SnapshotDiffSheet(session: session, snapshot: snapshot)
        }
        .confirmationDialog(
            l10n.t(.restore),
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            presenting: pendingRestore
        ) { snapshot in
            Button("\(l10n.t(.restore)): \(snapshot.name)") {
                session.restoreSnapshot(snapshot)
            }
            Button(l10n.t(.cancel), role: .cancel) {}
        } message: { snapshot in
            // 복원 전에 규모를 알려준다 — 현재 상태와의 차이 건수 (4단계 스냅샷)
            let diffCount = SnapshotDiff.rows(
                current: session.document.content,
                snapshot: snapshot.content
            ).count
            Text(
                diffCount == 0
                    ? l10n.t(.restoreSnapshotConfirm)
                    : String(format: l10n.t(.restoreSnapshotDiffFormat), diffCount)
            )
        }
    }

    private func take() {
        session.takeSnapshot(named: draftName)
        draftName = ""
    }

    private func snapshotRow(_ snapshot: DocumentSnapshot, l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(snapshot.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if snapshot.isAutomatic {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .help(l10n.t(.autosave))
                }
            }
            HStack(spacing: 6) {
                Text(snapshot.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    // 스냅샷 목록 ForEach 안 — 시트는 한 틱 지연해 연다 (앵커 크래시 방지)
                    DispatchQueue.main.async { comparing = snapshot }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(l10n.t(.compare))

                Button {
                    DispatchQueue.main.async { pendingRestore = snapshot }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(l10n.t(.restore))
                // 읽기 전용 세션은 markDirty가 차단되어 복원이 저장되지 않으므로 금지
                .disabled(session.isReadOnly)

                Button(role: .destructive) {
                    session.deleteSnapshot(snapshot.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(l10n.t(.delete))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - 비교 시트

/// 스냅샷 ↔ 현재 상태의 블록 단위 diff.
private struct SnapshotDiffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: DocumentSession
    let snapshot: DocumentSnapshot

    var body: some View {
        let l10n = Localizer.shared
        let rows = SnapshotDiff.rows(
            current: session.document.content,
            snapshot: snapshot.content
        )
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(snapshot.name) → \(l10n.t(.modifiedAt))")
                        .font(.headline)
                    Text(snapshot.createdAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(l10n.t(.done)) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(DesignTokens.Spacing.m)

            Divider().opacity(0.4)

            if rows.isEmpty {
                Text(l10n.t(.noDifferences))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(rows) { row in
                            diffRow(row, l10n: l10n)
                        }
                    }
                    .padding(DesignTokens.Spacing.m)
                }
            }
        }
        .frame(width: 480, height: 440)
    }

    @ViewBuilder
    private func diffRow(_ row: SnapshotDiff.Row, l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(badgeText(row.kind, l10n: l10n))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(badgeColor(row.kind).opacity(0.16)))
                    .foregroundStyle(badgeColor(row.kind))
                if !row.label.isEmpty {
                    Text(row.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let old = row.oldText {
                Text(old)
                    .font(.callout)
                    .strikethrough()
                    .foregroundStyle(.secondary)
            }
            Text(row.text)
                .font(.callout)
                .strikethrough(row.kind == .removed)
                .foregroundStyle(row.kind == .removed ? .secondary : .primary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(badgeColor(row.kind).opacity(0.06))
        )
    }

    private func badgeText(_ kind: SnapshotDiff.Row.Kind, l10n: Localizer) -> String {
        switch kind {
        case .added: l10n.t(.diffAdded)
        case .removed: l10n.t(.diffRemoved)
        case .changed: l10n.t(.diffChanged)
        }
    }

    // 의미 토큰 정렬 (2단계) — 추가=success, 삭제=accent, 변경=warning
    private func badgeColor(_ kind: SnapshotDiff.Row.Kind) -> Color {
        switch kind {
        case .added: SonnetPalette.success
        case .removed: SonnetPalette.accent
        case .changed: SonnetPalette.warning
        }
    }
}

// MARK: - Diff 계산

enum SnapshotDiff {
    struct Row: Identifiable {
        enum Kind { case added, removed, changed }

        let id = UUID()
        let kind: Kind
        /// 화자·노드 등 주체 라벨 (없으면 빈 문자열)
        let label: String
        let text: String
        /// changed일 때 이전 본문
        var oldText: String?
    }

    /// 블록/노드를 ID로 대응시켜 추가·삭제·변경을 뽑는다.
    /// 현재 문서 순서대로 추가/변경을 나열하고, 삭제된 항목은 마지막에 모은다.
    static func rows(current: DocumentContent, snapshot: DocumentContent) -> [Row] {
        switch (current, snapshot) {
        case (.scenario(let cur), .scenario(let old)):
            return scenarioRows(current: cur, snapshot: old)
        case (.page(let cur), .page(let old)):
            return pageRows(current: cur, snapshot: old)
        case (.mindmap(let cur), .mindmap(let old)):
            return mindmapRows(current: cur, snapshot: old)
        default:
            return []
        }
    }

    private static func scenarioRows(current: ScenarioContent, snapshot: ScenarioContent) -> [Row] {
        let names = Dictionary(uniqueKeysWithValues: (current.cast + snapshot.cast).map { ($0.id, $0.name) })

        func label(_ block: ScenarioBlock) -> String {
            let speakers = block.speakerIDs.compactMap { names[$0] }.joined(separator: ", ")
            return block.kind == .line ? (speakers.isEmpty ? "?" : speakers) : ""
        }

        let oldByID = Dictionary(uniqueKeysWithValues: snapshot.blocks.map { ($0.id, $0) })
        let currentIDs = Set(current.blocks.map(\.id))
        var rows: [Row] = []
        for block in current.blocks {
            if let previous = oldByID[block.id] {
                if previous.text != block.text || previous.speakerIDs != block.speakerIDs {
                    rows.append(Row(kind: .changed, label: label(block), text: block.text, oldText: previous.text))
                }
            } else if block.kind != .divider {
                rows.append(Row(kind: .added, label: label(block), text: block.text))
            }
        }
        for block in snapshot.blocks where !currentIDs.contains(block.id) && block.kind != .divider {
            rows.append(Row(kind: .removed, label: label(block), text: block.text))
        }
        return rows
    }

    private static func pageRows(current: PageContent, snapshot: PageContent) -> [Row] {
        let oldByID = Dictionary(uniqueKeysWithValues: snapshot.blocks.map { ($0.id, $0) })
        let currentIDs = Set(current.blocks.map(\.id))
        var rows: [Row] = []
        for block in current.blocks {
            if let previous = oldByID[block.id] {
                if previous.text != block.text || previous.kind != block.kind {
                    rows.append(Row(kind: .changed, label: "", text: block.text, oldText: previous.text))
                }
            } else if !block.text.isEmpty {
                rows.append(Row(kind: .added, label: "", text: block.text))
            }
        }
        for block in snapshot.blocks where !currentIDs.contains(block.id) && !block.text.isEmpty {
            rows.append(Row(kind: .removed, label: "", text: block.text))
        }
        return rows
    }

    private static func mindmapRows(current: MindMapContent, snapshot: MindMapContent) -> [Row] {
        let oldByID = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0) })
        let currentIDs = Set(current.nodes.map(\.id))
        var rows: [Row] = []
        for node in current.nodes {
            if let previous = oldByID[node.id] {
                if previous.title != node.title || previous.detail != node.detail {
                    let old = previous.title == node.title ? previous.detail : previous.title
                    rows.append(Row(kind: .changed, label: previous.title, text: node.title, oldText: old))
                }
            } else {
                rows.append(Row(kind: .added, label: "", text: node.title))
            }
        }
        for node in snapshot.nodes where !currentIDs.contains(node.id) {
            rows.append(Row(kind: .removed, label: "", text: node.title))
        }
        if current.edges.count != snapshot.edges.count {
            rows.append(Row(
                kind: .changed,
                label: "—",
                text: "연결 \(snapshot.edges.count) → \(current.edges.count)"
            ))
        }
        return rows
    }
}
