import AppCore
import AppKit
import DocumentKit
import SwiftUI

/// 시나리오 → 대본 형식 내보내기 (텍스트 / A4 PDF).
/// 페이지 에디터의 PageExport와 같은 측정→그리디 페이지 채우기→ImageRenderer 방식.
enum ScenarioExport {
    // MARK: 텍스트 (무대 대본 형식)

    @MainActor
    static func text(title: String, content: ScenarioContent, blocks: [ScenarioBlock]) -> String {
        var lines: [String] = [title, ""]

        if !content.cast.isEmpty {
            lines.append(Localizer.shared.t(.characters))
            for member in content.cast {
                let role = member.roleLine.isEmpty ? "" : " — \(member.roleLine)"
                lines.append("  \(member.name)\(role)")
            }
            lines.append("")
            lines.append(String(repeating: "─", count: 24))
            lines.append("")
        }

        for block in blocks {
            switch block.kind {
            case .line:
                let names = speakerNames(of: block, in: content)
                if !names.isEmpty {
                    lines.append(names)
                }
                lines.append("    \(block.text)")
                lines.append("")
            case .instruction:
                lines.append("(\(block.text))")
                lines.append("")
            case .divider:
                lines.append(String(repeating: "─", count: 24))
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func speakerNames(of block: ScenarioBlock, in content: ScenarioContent) -> String {
        block.speakerIDs
            .compactMap { id in content.cast.first { $0.id == id }?.name }
            .joined(separator: " · ")
    }

    // MARK: PDF

    @MainActor
    static func pdf(title: String, content: ScenarioContent, blocks: [ScenarioBlock]) -> Data? {
        let pageSize = CGSize(width: 595.2, height: 841.8) // A4 (pt)
        let margin: CGFloat = 56
        let contentWidth = pageSize.width - margin * 2
        let contentHeight = pageSize.height - margin * 2
        let spacing: CGFloat = 12

        func measure(_ view: some View) -> CGFloat {
            let controller = NSHostingController(rootView: view.frame(width: contentWidth))
            return controller.sizeThatFits(
                in: CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            ).height
        }

        let header = ScriptHeaderView(title: title, cast: content.cast)
        let headerHeight = measure(header)
        let rows: [ScriptRow] = blocks.map { block in
            ScriptRow(block: block, speakers: speakerNames(of: block, in: content))
        }
        let rowHeights = rows.map { measure(ScriptRowView(row: $0)) }

        // 그리디 페이지 채우기 — 첫 페이지 상단은 헤더(제목+등장인물)가 차지한다
        var pages: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = headerHeight + spacing
        for (index, height) in rowHeights.enumerated() {
            if used > 0, used + spacing + height > contentHeight {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(index)
            used += used > 0 ? spacing + height : height
        }
        pages.append(current)

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        for (pageIndex, indices) in pages.enumerated() {
            let renderer = ImageRenderer(content: ScriptPageView(
                header: pageIndex == 0 ? header : nil,
                rows: indices.map { rows[$0] },
                pageNumber: pageIndex + 1,
                pageCount: pages.count,
                pageSize: pageSize,
                margin: margin
            ))
            renderer.proposedSize = ProposedViewSize(pageSize)
            context.beginPDFPage(nil)
            renderer.render { _, render in render(context) }
            context.endPDFPage()
        }
        context.closePDF()
        return data.length > 0 ? data as Data : nil
    }
}

// MARK: - 대본 렌더링 뷰

private struct ScriptRow: Identifiable {
    let id = UUID()
    let block: ScenarioBlock
    let speakers: String
}

private struct ScriptHeaderView: View {
    let title: String
    let cast: [CastMember]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
            if !cast.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Localizer.shared.t(.characters))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.gray)
                    ForEach(cast) { member in
                        Text(member.roleLine.isEmpty ? member.name : "\(member.name) — \(member.roleLine)")
                            .font(.system(size: 11))
                    }
                }
            }
            Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 1)
        }
        .foregroundStyle(Color.black)
    }
}

private struct ScriptRowView: View {
    let row: ScriptRow

    var body: some View {
        Group {
            switch row.block.kind {
            case .line:
                VStack(alignment: .leading, spacing: 2) {
                    if !row.speakers.isEmpty {
                        Text(row.speakers)
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(row.block.text)
                        .font(.system(size: 12))
                        .padding(.leading, 20)
                }
            case .instruction:
                Text(row.block.text)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundStyle(Color.gray)
            case .divider:
                Text("✳︎ ✳︎ ✳︎")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.gray)
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScriptPageView: View {
    let header: ScriptHeaderView?
    let rows: [ScriptRow]
    let pageNumber: Int
    let pageCount: Int
    let pageSize: CGSize
    let margin: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let header {
                header
            }
            ForEach(rows) { row in
                ScriptRowView(row: row)
            }
            Spacer(minLength: 0)
        }
        .frame(
            width: pageSize.width - margin * 2,
            height: pageSize.height - margin * 2,
            alignment: .topLeading
        )
        .padding(margin)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            if pageCount > 1 {
                Text("\(pageNumber) / \(pageCount)")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.gray)
                    .padding(.bottom, margin / 2)
            }
        }
        .environment(\.colorScheme, .light)
    }
}
