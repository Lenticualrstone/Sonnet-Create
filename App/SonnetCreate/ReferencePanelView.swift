import AppCore
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// 문서 우측 사이드 패널 — 속성 · 참조 · 백링크.
struct ReferencePanelView: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    @Bindable var session: DocumentSession

    @State private var backlinks: [DocumentListItem] = []

    var body: some View {
        let l10n = Localizer.shared
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                propertiesSection(l10n)
                referencesSection(l10n)
                backlinksSection(l10n)
            }
            .padding(DesignTokens.Spacing.m)
        }
        .task(id: session.id) {
            backlinks = app.workspace.backlinks(to: session.id)
        }
        .onChange(of: session.saveState) { _, newValue in
            // 저장 직후 백링크 갱신 (자동 참조 파생 반영)
            if newValue == .savedAuto || newValue == .savedManual {
                backlinks = app.workspace.backlinks(to: session.id)
            }
        }
    }

    // MARK: 속성

    private func propertiesSection(_ l10n: Localizer) -> some View {
        let envelope = session.document.envelope
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader(l10n.t(.properties), symbol: "info.circle")
            propertyRow(
                l10n.t(envelope.isCharacterPage ? .characterPage : kindKey(envelope.kind)),
                value: "." + envelope.kind.fileExtension
            )
            if let projectName = app.workspace.item(id: session.id)?.projectName {
                propertyRow(l10n.t(.project), value: projectName)
            }
            propertyRow(l10n.t(.createdAt), value: envelope.createdAt.formatted(date: .abbreviated, time: .shortened))
            propertyRow(l10n.t(.modifiedAt), value: envelope.modifiedAt.formatted(date: .abbreviated, time: .shortened))
        }
    }

    private func kindKey(_ kind: DocumentKind) -> L10nKey {
        switch kind {
        case .scenario: .scenario
        case .mindmap: .mindmap
        case .page: .page
        }
    }

    private func propertyRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
        }
    }

    // MARK: 참조 (나가는)

    private func referencesSection(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader(l10n.t(.references), symbol: "link")
                Spacer()
                addReferenceMenu(l10n)
            }
            let refs = session.document.refs.outgoing
            if refs.isEmpty {
                Text(l10n.t(.noReferences))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(refs) { ref in
                    referenceRow(ref, l10n: l10n)
                }
            }
        }
    }

    private func referenceRow(_ ref: ReferenceGraph.Reference, l10n: Localizer) -> some View {
        let item = app.workspace.item(id: ref.target)
        return HStack(spacing: 6) {
            Image(systemName: ref.kind == .character ? "person.crop.circle" : "doc")
                .font(.caption)
                .foregroundStyle(accent)
            Text(item?.envelope.title ?? "…")
                .font(.callout)
                .lineLimit(1)
            Spacer()
            Button {
                session.removeReference(ref.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(l10n.t(.delete))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if item != nil { app.openDocument(id: ref.target) }
        }
        .opacity(item == nil ? 0.5 : 1)
    }

    private func addReferenceMenu(_ l10n: Localizer) -> some View {
        Menu {
            let candidates = app.workspace.visibleDocuments.filter { candidate in
                candidate.id != session.id
                    && !session.document.refs.outgoing.contains { $0.target == candidate.id }
            }
            ForEach(candidates) { item in
                Button {
                    session.addReference(to: item.id)
                } label: {
                    Label(
                        item.envelope.title.isEmpty ? l10n.t(.untitled) : item.envelope.title,
                        systemImage: item.envelope.isCharacterPage ? "person.crop.circle" : item.envelope.kind.symbolName
                    )
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n.t(.addReference))
    }

    // MARK: 백링크 (들어오는)

    private func backlinksSection(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(l10n.t(.backlinks), symbol: "arrow.turn.up.left")
            if backlinks.isEmpty {
                Text(l10n.t(.noReferences))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(backlinks) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.envelope.kind.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.envelope.title)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { app.openDocument(item) }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
