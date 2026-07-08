import AppCore
import AppKit
import DesignSystem
import DocumentKit
import SwiftUI

/// 블록 트리 → HTML / PDF 내보내기.
enum PageExport {
    // MARK: HTML

    /// 로컬 이미지는 base64로 임베드해 단일 파일로 만든다.
    static func html(title: String, blocks: [PageBlock], resolver: ((String) -> URL?)?) -> String {
        var body: [String] = []
        var listStack: String? = nil // "ul" | "ol"

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
            case .heading1: closeList(); body.append("<h1>\(text)</h1>")
            case .heading2: closeList(); body.append("<h2>\(text)</h2>")
            case .heading3: closeList(); body.append("<h3>\(text)</h3>")
            case .paragraph: closeList(); body.append("<p>\(text)</p>")
            case .bulleted: openList("ul"); body.append("<li>\(text)</li>")
            case .numbered: openList("ol"); body.append("<li>\(text)</li>")
            case .task:
                openList("ul")
                let checked = block.isChecked ? " checked" : ""
                body.append("<li class=\"task\"><input type=\"checkbox\" disabled\(checked)> \(text)</li>")
            case .toggle:
                closeList()
                body.append("<details open><summary>\(text)</summary></details>")
            case .quote: closeList(); body.append("<blockquote>\(text)</blockquote>")
            case .callout: closeList(); body.append("<div class=\"callout\">💡 \(text)</div>")
            case .code: closeList(); body.append("<pre><code>\(text)</code></pre>")
            case .divider: closeList(); body.append("<hr>")
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

    /// ImageRenderer 기반 PDF (v1: 한 장의 긴 페이지).
    @MainActor
    static func pdf(title: String, blocks: [PageBlock], resolver: ((String) -> URL?)?) -> Data? {
        let renderer = ImageRenderer(
            content: ExportRenderView(title: title, blocks: blocks, resolver: resolver)
                .frame(width: 700)
        )
        renderer.proposedSize = ProposedViewSize(width: 700, height: nil)

        let data = NSMutableData()
        renderer.render { size, render in
            var mediaBox = CGRect(origin: .zero, size: CGSize(width: size.width, height: max(size.height, 100)))
            guard let consumer = CGDataConsumer(data: data as CFMutableData),
                  let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
            else { return }
            context.beginPDFPage(nil)
            render(context)
            context.endPDFPage()
            context.closePDF()
        }
        return data.length > 0 ? data as Data : nil
    }
}

/// PDF 렌더링 전용의 단순 정적 뷰 (TextField 없이 Text만).
private struct ExportRenderView: View {
    let title: String
    let blocks: [PageBlock]
    let resolver: ((String) -> URL?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 8)
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .padding(36)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .environment(\.colorScheme, .light)
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
               let url = resolver?(path), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
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
