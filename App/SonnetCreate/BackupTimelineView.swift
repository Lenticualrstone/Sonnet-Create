import AppCore
import BackupKit
import DesignSystem
import SwiftUI

/// 타임라인 백업 목록 + 복원 (설정 > 기본 탭에 포함).
struct BackupTimelineView: View {
    @Environment(AppState.self) private var app

    @State private var records: [BackupRecord] = []
    @State private var confirmRestore: BackupRecord?
    /// 백업별 용량/문서 수 — 전체 파일 순회라 백그라운드에서 채운다.
    @State private var details: [String: BackupManager.BackupDetail] = [:]

    private var isBusy: Bool { app.isBackingUp || app.isRestoringBackup }

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(spacing: 8) {
                Button(l10n.t(.backupNow)) {
                    app.backupNow { refresh() }
                }
                .controlSize(.small)
                .disabled(isBusy)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.t(app.isRestoringBackup ? .restoreRunning : .backupRunning))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if records.isEmpty {
                Text("—")
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(records.prefix(8)) { record in
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(record.date, format: .dateTime.month().day().hour().minute())
                            .font(.callout)
                        if let detail = details[record.id] {
                            let size = ByteCountFormatter.string(fromByteCount: detail.byteSize, countStyle: .file)
                            Text("\(detail.documentCount) · \(size)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(l10n.t(.restoreBackup)) {
                            confirmRestore = record
                        }
                        .controlSize(.small)
                        .disabled(isBusy)
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog(
            l10n.t(.restoreBackup),
            isPresented: Binding(
                get: { confirmRestore != nil },
                set: { if !$0 { confirmRestore = nil } }
            )
        ) {
            Button(l10n.t(.restoreBackup), role: .destructive) {
                if let record = confirmRestore {
                    app.restoreBackup(record) { refresh() }
                }
            }
            Button(l10n.t(.cancel), role: .cancel) {}
        } message: {
            // 복원은 열린 문서 탭을 모두 닫는다 — 세션이 복원 전 내용을 도로 저장하는 사고 방지
            Text(l10n.t(.restoreClosesTabsMessage))
        }
    }

    private func refresh() {
        records = app.backupManager.timeline()
        let manager = app.backupManager
        let visible = Array(records.prefix(8))
        Task {
            let computed = await Task.detached(priority: .utility) {
                var result: [String: BackupManager.BackupDetail] = [:]
                for record in visible {
                    result[record.id] = manager.detail(of: record)
                }
                return result
            }.value
            details = computed
        }
    }
}
