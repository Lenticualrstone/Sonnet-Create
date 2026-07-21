import DocumentKit
import Foundation

/// 문서 종류별 Quick Look HTML — Sonnet 앤티크 페이퍼 톤, 다크 모드 대응.
/// 이미지는 임베드하지 않고 플레이스홀더로 표시한다 (프리뷰는 훑는 용도).
enum PreviewHTML {
    /// 프리뷰에 싣는 블록 수 상한 — 긴 문서도 즉시 뜨게 한다.
    private static let blockCap = 60

    static func render(_ document: LoadedDocument) -> String {
        let title = escape(document.envelope.title.isEmpty ? "제목 없음" : document.envelope.title)
        let body: String
        switch document.content {
        case .scenario(let content):
            body = scenarioBody(content)
        case .mindmap(let content):
            body = mindmapBody(content)
        case .page(let content):
            body = pageBody(content)
        }
        return """
        <!doctype html>
        <html lang="ko">
        <head>
        <meta charset="utf-8">
        <style>
        body { font-family: -apple-system, "Pretendard", sans-serif; margin: 28px 32px; line-height: 1.6;
               background: #F5F1E8; color: #2A241C; }
        h1 { font-size: 1.45em; margin: 0 0 4px; }
        .meta { font-size: 0.8em; color: #8A8070; margin-bottom: 18px; }
        .cast { margin: 0 0 14px; }
        .cast span { display: inline-block; font-size: 0.8em; padding: 2px 9px; margin: 0 4px 4px 0;
                     border-radius: 999px; background: rgba(3,28,53,0.08); color: #031C35; }
        .line { margin: 7px 0; }
        .speaker { font-weight: 600; font-size: 0.85em; color: #031C35; }
        .instruction { color: #6E6558; font-style: italic; border-left: 2px solid #C8C0B0;
                       padding-left: 10px; margin: 8px 0; }
        .divider { border: none; border-top: 1px solid #C8C0B0; margin: 14px 0; }
        .callout { background: rgba(3,28,53,0.06); border-radius: 8px; padding: 8px 12px; margin: 8px 0; }
        pre { background: rgba(3,28,53,0.06); border-radius: 8px; padding: 10px; overflow-x: auto; }
        blockquote { border-left: 3px solid #C8C0B0; margin-left: 0; padding-left: 12px; color: #6E6558; }
        .placeholder { color: #8A8070; font-size: 0.85em; }
        .node { margin: 4px 0; }
        .truncated { margin-top: 16px; color: #8A8070; font-size: 0.85em; }
        table { border-collapse: collapse; } td, th { border: 1px solid #C8C0B0; padding: 4px 8px; font-size: 0.85em; }
        @media (prefers-color-scheme: dark) {
          body { background: #221E19; color: #E8E2D6; }
          .speaker, .cast span { color: #B8CBE0; }
          .cast span, .callout, pre { background: rgba(184,203,224,0.12); }
          .meta, .placeholder, .truncated { color: #97907F; }
        }
        </style>
        </head>
        <body>
        <h1>\(title)</h1>
        \(body)
        </body>
        </html>
        """
    }

    // MARK: 시나리오 — 캐스트 칩 + 채팅형 대사

    private static func scenarioBody(_ content: ScenarioContent) -> String {
        var parts: [String] = []
        parts.append("<div class=\"meta\">시나리오 · 블록 \(content.blocks.count)개 · 등장인물 \(content.cast.count)명</div>")
        if !content.cast.isEmpty {
            let chips = content.cast.map { "<span>\(escape($0.name))</span>" }.joined()
            parts.append("<div class=\"cast\">\(chips)</div>")
        }
        let names = Dictionary(uniqueKeysWithValues: content.cast.map { ($0.id, $0.name) })
        for block in content.blocks.prefix(blockCap) {
            switch block.kind {
            case .line:
                let speaker = block.speakerIDs.compactMap { names[$0] }.joined(separator: ", ")
                let label = speaker.isEmpty ? "?" : speaker
                parts.append("<div class=\"line\"><span class=\"speaker\">\(escape(label))</span><br>\(escape(block.text))</div>")
            case .instruction:
                parts.append("<div class=\"instruction\">\(escape(block.text))</div>")
            case .divider:
                parts.append("<hr class=\"divider\">")
            }
        }
        appendTruncationNote(&parts, total: content.blocks.count)
        return parts.joined(separator: "\n")
    }

    // MARK: 마인드맵 — 노드 개요

    private static func mindmapBody(_ content: MindMapContent) -> String {
        var parts: [String] = []
        parts.append("<div class=\"meta\">마인드맵 · 노드 \(content.nodes.count)개 · 연결 \(content.edges.count)개</div>")
        for node in content.nodes.prefix(blockCap) {
            let detail = node.detail.isEmpty ? "" : " <span class=\"placeholder\">— \(escape(node.detail))</span>"
            parts.append("<div class=\"node\">• \(escape(node.title))\(detail)</div>")
        }
        appendTruncationNote(&parts, total: content.nodes.count)
        return parts.joined(separator: "\n")
    }

    // MARK: 페이지 — 블록 간이 렌더링

    private static func pageBody(_ content: PageContent) -> String {
        var parts: [String] = []
        parts.append("<div class=\"meta\">페이지 · 블록 \(content.blocks.count)개</div>")
        for block in content.blocks.prefix(blockCap) {
            let text = escape(block.text)
            switch block.kind {
            case .heading1: parts.append("<h2>\(text)</h2>")
            case .heading2: parts.append("<h3>\(text)</h3>")
            case .heading3: parts.append("<h4>\(text)</h4>")
            case .paragraph: parts.append("<p>\(text)</p>")
            case .bulleted: parts.append("<div>• \(text)</div>")
            case .numbered: parts.append("<div>· \(text)</div>")
            case .task: parts.append("<div>\(block.isChecked ? "☑" : "☐") \(text)</div>")
            case .toggle: parts.append("<div>▸ \(text)</div>")
            case .quote: parts.append("<blockquote>\(text)</blockquote>")
            case .callout: parts.append("<div class=\"callout\">💡 \(text)</div>")
            case .code: parts.append("<pre>\(text)</pre>")
            case .divider: parts.append("<hr class=\"divider\">")
            case .image: parts.append("<div class=\"placeholder\">🖼 이미지</div>")
            case .embed: parts.append("<div class=\"placeholder\">📄 문서 임베드</div>")
            case .table:
                guard let rows = block.tableData, !rows.isEmpty else { break }
                var table = "<table>"
                for (rowIndex, row) in rows.enumerated() {
                    let tag = rowIndex == 0 ? "th" : "td"
                    table += "<tr>" + row.map { "<\(tag)>\(escape($0))</\(tag)>" }.joined() + "</tr>"
                }
                table += "</table>"
                parts.append(table)
            }
        }
        appendTruncationNote(&parts, total: content.blocks.count)
        return parts.joined(separator: "\n")
    }

    private static func appendTruncationNote(_ parts: inout [String], total: Int) {
        if total > blockCap {
            parts.append("<div class=\"truncated\">… 외 \(total - blockCap)개 블록</div>")
        }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
