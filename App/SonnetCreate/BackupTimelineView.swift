import AppCore
import BackupKit
import DesignSystem
import SwiftUI

/// 타임라인 백업 목록 + 복원 (설정 > 기본 탭에 포함).
struct BackupTimelineView: View {
    @Environment(AppState.self) private var app

    @State private var records: [BackupRecord] = []
    @State private var confirmRestore: BackupRecord?

    var body: some View {
        let l10n = Localizer.shared
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack {
                Button(l10n.t(.backupNow)) {
                    app.backupNow()
                    refresh()
                }
                .controlSize(.small)
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
                        Spacer()
                        Button(l10n.t(.restoreBackup)) {
                            confirmRestore = record
                        }
                        .controlSize(.small)
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
                    restore(record)
                }
            }
            Button(l10n.t(.cancel), role: .cancel) {}
        }
    }

    private func refresh() {
        records = app.backupManager.timeline()
    }

    private func restore(_ record: BackupRecord) {
        app.flushAllSessions()
        try? app.backupManager.restore(record)
        app.workspace.scan()
        app.notify(symbol: "clock.arrow.circlepath", message: Localizer.shared.t(.eventRestored))
        refresh()
    }
}
