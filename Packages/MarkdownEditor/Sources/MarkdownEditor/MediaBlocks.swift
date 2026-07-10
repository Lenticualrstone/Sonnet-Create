import AppCore
import AppKit
import DesignSystem
import DocumentKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 이미지 블록

/// 파일 선택 · 드래그 앤 드롭 · URL 임베드, 비율 지정, 클릭 시 확대 오버레이.
struct ImageBlockView: View {
    @Bindable var store: PageStore
    let block: PageBlock

    @State private var showViewer = false
    @State private var showURLField = false
    @State private var urlDraft = ""
    @State private var dropTargeted = false
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    /// 이 뷰는 LazyVStack/ForEach 블록 목록 안에서 재구성될 수 있다 — 탭/컨텍스트메뉴에서
    /// 바로 showViewer=true를 주면 앵커 뷰가 아직 윈도우 계층에서 확정되지 않아
    /// sheet/popover가 NSPopover 크래시를 일으킬 수 있다 (macOS 26). 한 틱 지연해서 연다.
    private func openViewer() {
        DispatchQueue.main.async { showViewer = true }
    }

    private var isRemote: Bool {
        block.resourcePath?.hasPrefix("http") ?? false
    }

    private var localImage: NSImage? {
        guard let path = block.resourcePath, !isRemote,
              let url = store.resourceResolver?(path)
        else { return nil }
        return ImageThumbnailCache.thumbnail(for: url, maxPointSize: 900)
    }

    var body: some View {
        let l10n = Localizer.shared
        Group {
            if block.resourcePath == nil {
                emptyPlaceholder(l10n)
            } else {
                VStack(alignment: captionAlignment, spacing: 4) {
                    imageContent
                        .frame(maxHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous))
                        .onTapGesture { openViewer() }
                    // 캡션 (block.text)
                    TextField(
                        l10n.t(.captionLabel),
                        text: Binding(
                            get: { store.block(id: block.id)?.text ?? "" },
                            set: { store.updateText(block.id, text: $0) }
                        )
                    )
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(textAlignment)
                }
                // 너비 비율 + 정렬
                .containerRelativeFrame(.horizontal, alignment: frameAlignment) { length, _ in
                    length * (block.widthFraction ?? 1.0)
                }
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .contextMenu {
                    Button(l10n.t(.enlarge)) { openViewer() }
                    Menu(l10n.t(.aspectOriginal)) {
                        Button(l10n.t(.aspectOriginal)) { setAspect(nil) }
                        Button("16:9") { setAspect(16.0 / 9.0) }
                        Button("4:3") { setAspect(4.0 / 3.0) }
                        Button("1:1") { setAspect(1) }
                    }
                    Menu(l10n.t(.imageWidth)) {
                        ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { fraction in
                            Button("\(Int(fraction * 100))%") {
                                var updated = block
                                updated.widthFraction = fraction == 1.0 ? nil : fraction
                                store.updateBlock(updated)
                            }
                        }
                    }
                    Menu(l10n.t(.imageAlign)) {
                        Button(l10n.t(.alignLeft)) { setAlign("left") }
                        Button(l10n.t(.alignCenter)) { setAlign(nil) }
                        Button(l10n.t(.alignRight)) { setAlign("right") }
                    }
                    Button(l10n.t(.chooseImage)) { pickImage() }
                    Divider()
                    Button(l10n.t(.delete), role: .destructive) {
                        var updated = block
                        updated.resourcePath = nil
                        store.updateBlock(updated)
                    }
                }
                .sheet(isPresented: $showViewer) { viewerOverlay }
            }
        }
    }

    private var frameAlignment: Alignment {
        switch block.alignRaw {
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }

    private var captionAlignment: HorizontalAlignment {
        switch block.alignRaw {
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }

    private var textAlignment: TextAlignment {
        switch block.alignRaw {
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }

    private func setAlign(_ raw: String?) {
        var updated = block
        updated.alignRaw = raw
        store.updateBlock(updated)
    }

    @ViewBuilder
    private var imageContent: some View {
        if isRemote, let path = block.resourcePath, let url = URL(string: path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): fitted(image)
                case .failure: brokenPlaceholder
                default: ProgressView().frame(height: 120)
                }
            }
        } else if let nsImage = localImage {
            fitted(Image(nsImage: nsImage))
        } else {
            brokenPlaceholder
        }
    }

    private func fitted(_ image: Image) -> some View {
        let resizable = image.resizable().interpolation(.high).antialiased(true)
        return Group {
            if let aspect = block.aspect {
                resizable.aspectRatio(aspect, contentMode: .fill)
            } else {
                resizable.aspectRatio(contentMode: .fit)
            }
        }
    }

    private var brokenPlaceholder: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo.badge.exclamationmark")
            Text(block.resourcePath ?? "")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.secondary)
        .padding(DesignTokens.Spacing.m)
    }

    private func emptyPlaceholder(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Button {
                pickImage()
            } label: {
                Label(l10n.t(.chooseImage), systemImage: "photo.badge.plus")
            }
            Button {
                if showURLField {
                    showURLField = false
                } else {
                    DispatchQueue.main.async { showURLField = true }
                }
            } label: {
                Label(l10n.t(.embedURL), systemImage: "link")
            }
            Button {
                pasteFromClipboard()
            } label: {
                Label(l10n.t(.pasteImage), systemImage: "doc.on.clipboard")
            }
            Text(l10n.t(.dropHere))
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(DesignTokens.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                .strokeBorder(
                    dropTargeted ? accent : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [5, 4])
                )
        )
        .popover(isPresented: $showURLField, arrowEdge: .bottom) {
            HStack(spacing: 6) {
                TextField("https://…", text: $urlDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(commitURL)
                Button(l10n.t(.done), action: commitURL)
                    .controlSize(.small)
            }
            .padding(10)
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func setAspect(_ aspect: Double?) {
        var updated = block
        updated.aspect = aspect
        store.updateBlock(updated)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyLocalFile(url)
    }

    /// 클립보드의 이미지를 번들 리소스로 저장해 삽입.
    private func pasteFromClipboard() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pasted-\(UUID().uuidString.prefix(8)).png")
        do {
            try png.write(to: temp)
            applyLocalFile(temp)
            try? FileManager.default.removeItem(at: temp)
        } catch {}
    }

    private func applyLocalFile(_ url: URL) {
        guard let relative = store.resourceImporter?(url) else { return }
        var updated = block
        updated.resourcePath = relative
        store.updateBlock(updated)
    }

    private func commitURL() {
        let trimmed = urlDraft.trimmingCharacters(in: .whitespaces)
        showURLField = false
        guard trimmed.hasPrefix("http"), URL(string: trimmed) != nil else { return }
        var updated = block
        updated.resourcePath = trimmed
        store.updateBlock(updated)
        urlDraft = ""
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            Task { @MainActor in
                applyLocalFile(url)
            }
        }
        return true
    }

    /// 클릭 시 확대/전체 보기 오버레이.
    private var viewerOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    showViewer = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(DesignTokens.Spacing.s)

            Group {
                if isRemote, let path = block.resourcePath, let url = URL(string: path) {
                    AsyncImage(url: url) { image in
                        image.resizable().interpolation(.high).antialiased(true).aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                } else if let nsImage = localImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .padding([.horizontal, .bottom], DesignTokens.Spacing.m)
        }
        .frame(minWidth: 480, minHeight: 360)
        .frame(maxWidth: 900, maxHeight: 700)
    }
}

// MARK: - 표 블록

/// 편집 가능한 그리드 + 행/열 추가·삭제.
struct TableBlockView: View {
    @Bindable var store: PageStore
    let block: PageBlock

    @State private var hovering = false

    private var rows: [[String]] {
        block.tableData ?? [["", ""], ["", ""]]
    }

    var body: some View {
        let l10n = Localizer.shared
        let data = rows
        let columnCount = data.first?.count ?? 0

        VStack(alignment: .leading, spacing: 4) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(data.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { colIndex in
                            TextField(
                                "",
                                text: Binding(
                                    get: {
                                        let current = rows
                                        guard current.indices.contains(rowIndex),
                                              current[rowIndex].indices.contains(colIndex)
                                        else { return "" }
                                        return current[rowIndex][colIndex]
                                    },
                                    set: { newValue in
                                        var current = rows
                                        guard current.indices.contains(rowIndex),
                                              current[rowIndex].indices.contains(colIndex)
                                        else { return }
                                        current[rowIndex][colIndex] = newValue
                                        var updated = block
                                        updated.tableData = current
                                        store.updateBlock(updated)
                                    }
                                )
                            )
                            .textFieldStyle(.plain)
                            .font(rowIndex == 0 ? .callout.weight(.semibold) : .callout)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(minWidth: 90, alignment: .leading)
                            .background(rowIndex == 0 ? Color.primary.opacity(0.05) : .clear)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
                            )
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            )

            if hovering {
                HStack(spacing: DesignTokens.Spacing.s) {
                    Button {
                        mutateTable { $0.append(Array(repeating: "", count: columnCount)) }
                    } label: {
                        Label(l10n.t(.addRow), systemImage: "plus")
                    }
                    Button {
                        mutateTable { table in
                            for i in table.indices { table[i].append("") }
                        }
                    } label: {
                        Label(l10n.t(.addColumn), systemImage: "plus.square.on.square")
                    }
                    if data.count > 2 {
                        Button {
                            mutateTable { _ = $0.popLast() }
                        } label: {
                            Image(systemName: "rectangle.badge.minus")
                        }
                        .help(l10n.t(.addRow) + " −")
                    }
                    if columnCount > 1 {
                        Button {
                            mutateTable { table in
                                for i in table.indices where !table[i].isEmpty {
                                    table[i].removeLast()
                                }
                            }
                        } label: {
                            Image(systemName: "rectangle.portrait.badge.minus")
                        }
                        .help(l10n.t(.addColumn) + " −")
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption)
            }
        }
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.snappy, value: hovering)
    }

    private func mutateTable(_ transform: (inout [[String]]) -> Void) {
        var current = rows
        transform(&current)
        var updated = block
        updated.tableData = current
        store.updateBlock(updated)
    }
}
