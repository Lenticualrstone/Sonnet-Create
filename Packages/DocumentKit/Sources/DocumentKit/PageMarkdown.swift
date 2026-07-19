import Foundation

/// 블록 트리 ↔ Markdown 변환 (경량 자체 구현, 오프라인 동작 보장).
public enum PageMarkdown {
    // MARK: Export

    public static func export(_ blocks: [PageBlock]) -> String {
        var lines: [String] = []
        var numberedCounter = 0
        for block in blocks {
            if block.kind != .numbered { numberedCounter = 0 }
            let indent = String(repeating: "  ", count: max(0, block.indent))
            switch block.kind {
            case .paragraph:
                lines.append(indent + block.text)
            case .heading1:
                lines.append("# " + block.text)
            case .heading2:
                lines.append("## " + block.text)
            case .heading3:
                lines.append("### " + block.text)
            case .bulleted:
                lines.append(indent + "- " + block.text)
            case .numbered:
                numberedCounter += 1
                lines.append(indent + "\(numberedCounter). " + block.text)
            case .task:
                lines.append(indent + "- [\(block.isChecked ? "x" : " ")] " + block.text)
            case .toggle:
                lines.append(indent + "<details><summary>\(block.text)</summary></details>")
            case .quote:
                lines.append("> " + block.text)
            case .code:
                lines.append("```\n\(block.text)\n```")
            case .divider:
                lines.append("---")
            case .callout:
                lines.append("> 💡 " + block.text)
            case .image:
                lines.append("![\(block.text)](\(block.resourcePath ?? ""))")
            case .embed:
                // 임베드는 마크다운으로 표현할 수 없다 — 문서 참조 주석으로 남긴다
                lines.append("<!-- embed: \(block.embeddedDocumentID?.uuidString ?? "") -->")
            case .table:
                if let rows = block.tableData, let first = rows.first {
                    var tableLines: [String] = []
                    tableLines.append("| " + first.joined(separator: " | ") + " |")
                    tableLines.append("|" + Array(repeating: " --- |", count: first.count).joined())
                    for row in rows.dropFirst() {
                        tableLines.append("| " + row.joined(separator: " | ") + " |")
                    }
                    lines.append(tableLines.joined(separator: "\n"))
                }
            }
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: Import

    public static func `import`(_ markdown: String) -> [PageBlock] {
        var blocks: [PageBlock] = []
        var inCodeFence = false
        var codeBuffer: [String] = []
        var tableBuffer: [[String]] = []

        func flushTable() {
            guard !tableBuffer.isEmpty else { return }
            blocks.append(PageBlock(kind: .table, tableData: tableBuffer))
            tableBuffer = []
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // 표 행 수집 (| a | b |)
            if !inCodeFence, line.hasPrefix("|"), line.hasSuffix("|"), line.count > 1 {
                let cells = line.dropFirst().dropLast()
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                let isSeparator = cells.allSatisfy { $0.allSatisfy { "-: ".contains($0) } && !$0.isEmpty }
                if !isSeparator { tableBuffer.append(cells) }
                continue
            }
            flushTable()

            if line.hasPrefix("```") {
                if inCodeFence {
                    blocks.append(PageBlock(kind: .code, text: codeBuffer.joined(separator: "\n")))
                    codeBuffer = []
                    inCodeFence = false
                } else {
                    inCodeFence = true
                }
                continue
            }
            if inCodeFence {
                codeBuffer.append(rawLine)
                continue
            }
            if line.isEmpty { continue }

            let leadingSpaces = rawLine.prefix { $0 == " " }.count
            let indent = min(4, leadingSpaces / 2)

            if line.hasPrefix("### ") {
                blocks.append(PageBlock(kind: .heading3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                blocks.append(PageBlock(kind: .heading2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                blocks.append(PageBlock(kind: .heading1, text: String(line.dropFirst(2))))
            } else if line == "---" || line == "***" {
                blocks.append(PageBlock(kind: .divider))
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                blocks.append(PageBlock(kind: .task, text: String(line.dropFirst(6)), isChecked: true, indent: indent))
            } else if line.hasPrefix("- [ ] ") {
                blocks.append(PageBlock(kind: .task, text: String(line.dropFirst(6)), isChecked: false, indent: indent))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                blocks.append(PageBlock(kind: .bulleted, text: String(line.dropFirst(2)), indent: indent))
            } else if let range = line.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                blocks.append(PageBlock(kind: .numbered, text: String(line[range.upperBound...]), indent: indent))
            } else if line.hasPrefix("!["),
                      let bracketEnd = line.range(of: "]("),
                      line.hasSuffix(")") {
                let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<bracketEnd.lowerBound])
                let path = String(line[bracketEnd.upperBound..<line.index(before: line.endIndex)])
                blocks.append(PageBlock(kind: .image, text: alt, resourcePath: path.isEmpty ? nil : path))
            } else if line.hasPrefix("> 💡 ") {
                blocks.append(PageBlock(kind: .callout, text: String(line.dropFirst(5))))
            } else if line.hasPrefix("> ") {
                blocks.append(PageBlock(kind: .quote, text: String(line.dropFirst(2))))
            } else {
                blocks.append(PageBlock(kind: .paragraph, text: line, indent: indent))
            }
        }
        flushTable()
        if inCodeFence, !codeBuffer.isEmpty {
            blocks.append(PageBlock(kind: .code, text: codeBuffer.joined(separator: "\n")))
        }
        return blocks
    }
}
