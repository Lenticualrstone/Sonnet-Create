import AppCore
import AppKit
import DesignSystem
import DocumentKit
import SwiftUI

/// 블록 트리 → HTML / PDF 내보내기.
enum PageExport {
    // MARK: HTML

    // swiftlint:disable line_length
    /// 로컬 이미지는 base64로 임베드해 단일 파일로 만든다.
    static func html(title: String, blocks: [PageBlock], resolver: ((String) -> URL?)?) -> String {
        var body: [String] = []
        var listStack: String? // "ul" | "ol"

        func closeList() {
            if let tag = listStack {
                body.append("</\(tag)>")
                listStack = nil
            }
        }

        func openList(_ tag: String) {
            if listStack != tag {
                closeList()
                body.append("<\(tag)>")
                listStack = tag
            }
        }

        for block in blocks {
            let text = escape(block.text)
            switch block.kind {
            case .heading1: closeList()
                body.append("<h1>\(text)</h1>")
            case .heading2: closeList()
                body.append("<h2>\(text)</h2>")
            case .heading3: closeList()
                body.append("<h3>\(text)</h3>")
            case .paragraph: closeList()
                body.append("<p>\(text)</p>")
            case .bulleted: openList("ul")
                body.append("<li>\(text)</li>")
            case .numbered: openList("ol")
                body.append("<li>\(text)</li>")
            case .task:
                openList("ul")
                let checked = block.isChecked ? " checked" : ""
                body.append("<li class=\"task\"><input type=\"checkbox\" disabled\(checked)> \(text)</li>")
            case .toggle:
                closeList()
                body.append("<details open><summary>\(text)</summary></details>")
            case .quote: closeList()
                body.append("<blockquote>\(text)</blockquote>")
            case .callout: closeList()
                body.append("<div class=\"callout\">💡 \(text)</div>")
            case .code: closeList()
                body.append("<pre><code>\(text)</code></pre>")
            case .divider: closeList()
                body.append("<hr>")
            case .image:
                closeList()
                if let src = imageSource(block, resolver: resolver) {
                    body.append("<figure><img src=\"\(src)\" alt=\"\(text)\"></figure>")
                }
            case .table:
                closeList()
                guard let rows = block.tableData, let header = rows.first else { break }
                var table = "<table><thead><tr>"
                table += header.map { "<th>\(escape($0))</th>" }.joined()
                table += "</tr></thead><tbody>"
                for row in rows.dropFirst() {
                    table += "<tr>" + row.map { "<td>\(escape($0))</td>" }.joined() + "</tr>"
                }
                table += "</tbody></table>"
                body.append(table)
            }
        }
        closeList()

        return """
        <!doctype html>
        <html lang="ko">
        <head>
        <meta charset="utf-8">
        <title>\(escape(title))</title>
        <style>
        body { font-family: -apple-system, "Pretendard", sans-serif; max-width: 720px; margin: 48px auto; padding: 0 24px; line-height: 1.65; color: #1d1d1f; }
        @media (prefers-color-scheme: dark) { body { background: #1e1e20; color: #eee; } .callout { background: #2c2c30; } pre { background: #2c2c30; } td, th { border-color: #444; } }
        h1 { font-size: 2em; } blockquote { border-left: 3px solid #999; margin-left: 0; padding-left: 16px; color: #666; }
        .callout { background: #f2f2f4; border-radius: 10px; padding: 12px 16px; }
        pre { background: #f5f5f7; border-radius: 10px; padding: 14px; overflow-x: auto; }
        img { max-width: 100%; border-radius: 10px; }
        table { border-collapse: collapse; width: 100%; } td, th { border: 1px solid #ccc; padding: 6px 10px; text-align: left; }
        li.task { list-style: none; margin-left: -20px; }
        hr { border: none; border-top: 1px solid #ccc; }
        </style>
        </head>
        <body>
        <h1>\(escape(title))</h1>
        \(body.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    // swiftlint:enable line_length

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func imageSource(_ block: PageBlock, resolver: ((String) -> URL?)?) -> String? {
        guard let path = block.resourcePath else { return nil }
        if path.hasPrefix("http") { return path }
        guard let url = resolver?(path), let data = try? Data(contentsOf: url) else { return nil }
        let mime = url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    // MARK: PDF

    /// A4 다중 페이지 PDF — 블록별 높이를 측정해 그리디로 페이지를 채운다.
    /// 단일 블록이 페이지 콘텐츠 높이를 넘으면 그 블록만 실은 페이지에서 잘린다
    /// (본문 블록은 Enter 분할 단위라 실사용에서는 이미지/표 정도만 해당).
    @MainActor
    static func pdf(title: String, blocks: [PageBlock], resolver: ((String) -> URL?)?) -> Data? {
        let pageSize = CGSize(width: 595.2, height: 841.8) // A4 (pt)
        let margin: CGFloat = 48
        let contentWidth = pageSize.width - margin * 2
        let contentHeight = pageSize.height - margin * 2
        let spacing: CGFloat = 10

        func measure(_ view: some View) -> CGFloat {
            let controller = NSHostingController(rootView: view.frame(width: contentWidth))
            return controller.sizeThatFits(
                in: CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
            ).height
        }

        // 1) 측정 — 제목은 첫 페이지 상단에 고정
        let titleHeight = measure(ExportTitleView(title: title))
        let blockHeights = blocks.map { measure(ExportBlockView(block: $0, resolver: resolver)) }

        // 2) 그리디 페이지 채우기
        var pages: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = titleHeight
        for (index, height) in blockHeights.enumerated() {
            if used > 0, used + spacing + height > contentHeight {
                pages.append(current)
                current = []
                used = 0
            }
            current.append(index)
            used += used > 0 ? spacing + height : height
        }
        pages.append(current)

        // 3) 페이지 단위 렌더링
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return nil }

        for (pageIndex, indices) in pages.enumerated() {
            let renderer = ImageRenderer(content: ExportPageView(
                title: pageIndex == 0 ? title : nil,
                blocks: indices.map { blocks[$0] },
                resolver: resolver,
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

/// PDF 페이지 한 장 — 여백을 포함한 A4 전체를 그린다 (TextField 없이 Text만).
private struct ExportPageView: View {
    let title: String?
    let blocks: [PageBlock]
    let resolver: ((String) -> URL?)?
    let pageNumber: Int
    let pageCount: Int
    let pageSize: CGSize
    let margin: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                ExportTitleView(title: title)
            }
            ForEach(blocks) { block in
                ExportBlockView(block: block, resolver: resolver)
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
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
    }
}

private struct ExportTitleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.bottom, 8)
    }
}

/// 블록 하나의 정적 렌더링 — 페이지 채우기 측정과 실제 그리기가 같은 뷰를 쓴다.
private struct ExportBlockView: View {
    let block: PageBlock
    let resolver: ((String) -> URL?)?

    var body: some View {
        blockView(block)
            .foregroundStyle(Color.black)
    }

    @ViewBuilder
    private func blockView(_ block: PageBlock) -> some View {
        let indent = CGFloat(block.indent) * 20
        switch block.kind {
        case .heading1:
            Text(block.text).font(.system(size: 22, weight: .bold))
        case .heading2:
            Text(block.text).font(.system(size: 18, weight: .bold))
        case .heading3:
            Text(block.text).font(.system(size: 15, weight: .semibold))
        case .paragraph:
            Text(block.text).font(.system(size: 12)).padding(.leading, indent)
        case .bulleted:
            Text("•  " + block.text).font(.system(size: 12)).padding(.leading, indent)
        case .numbered:
            Text("·  " + block.text).font(.system(size: 12)).padding(.leading, indent)
        case .task:
            Text((block.isChecked ? "☑ " : "☐ ") + block.text)
                .font(.system(size: 12)).padding(.leading, indent)
        case .toggle:
            Text("▸ " + block.text).font(.system(size: 12, weight: .medium)).padding(.leading, indent)
        case .quote:
            HStack(spacing: 8) {
                Rectangle().fill(Color.gray).frame(width: 3)
                Text(block.text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .callout:
            Text("💡 " + block.text)
                .font(.system(size: 12))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
        case .code:
            Text(block.text)
                .font(.system(size: 11, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))
        case .divider:
            Rectangle().fill(Color.gray.opacity(0.4)).frame(height: 1)
        case .image:
            if let path = block.resourcePath, !path.hasPrefix("http"),
               let url = resolver?(path), let image = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 640) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let path = block.resourcePath {
                Text("🖼 " + path).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        case .table:
            if let rows = block.tableData {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(rows.indices, id: \.self) { r in
                        GridRow {
                            ForEach(rows[r].indices, id: \.self) { c in
                                Text(rows[r][c])
                                    .font(.system(size: 11, weight: r == 0 ? .semibold : .regular))
                                    .padding(5)
                                    .frame(minWidth: 70, alignment: .leading)
                                    .border(Color.gray.opacity(0.5), width: 0.5)
                            }
                        }
                    }
                }
            }
        }
    }
}
