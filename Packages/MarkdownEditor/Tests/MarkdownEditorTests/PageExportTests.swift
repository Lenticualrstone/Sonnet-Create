import DocumentKit
import PDFKit
import Testing
@testable import MarkdownEditor

@MainActor
struct PageExportTests {
    @Test func pdfSplitsLongDocumentIntoMultiplePages() throws {
        let blocks = (1...120).map { index in
            PageBlock(kind: .paragraph, text: "블록 \(index) — 페이지네이션 검증용 본문 문단입니다.")
        }
        let data = try #require(PageExport.pdf(title: "분할 테스트", blocks: blocks, resolver: nil))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1)

        // 모든 페이지가 A4 규격이어야 한다
        for pageIndex in 0..<document.pageCount {
            let bounds = try #require(document.page(at: pageIndex)).bounds(for: .mediaBox)
            #expect(abs(bounds.width - 595.2) < 1)
            #expect(abs(bounds.height - 841.8) < 1)
        }
    }

    @Test func pdfShortDocumentStaysSinglePage() throws {
        let blocks = [PageBlock(kind: .paragraph, text: "짧은 문서")]
        let data = try #require(PageExport.pdf(title: "한 장", blocks: blocks, resolver: nil))
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
    }
}
