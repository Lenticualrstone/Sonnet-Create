import DocumentKit
import QuickLookUI
import UniformTypeIdentifiers

/// Finder 스페이스바(Quick Look)용 데이터 기반 프리뷰 — 문서 번들을 읽어
/// 가벼운 HTML로 렌더링한다. 앱을 열지 않고 내용을 훑는 용도.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let document = try DocumentPackageIO.read(from: request.fileURL)
        let html = PreviewHTML.render(document)
        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 640, height: 800)
        ) { _ in
            Data(html.utf8)
        }
        reply.title = document.envelope.title
        reply.stringEncoding = .utf8
        return reply
    }
}
