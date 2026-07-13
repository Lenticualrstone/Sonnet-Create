import DocumentKit
import Foundation
import Testing
@testable import ScenarioEditor

/// 대본 텍스트 내보내기 — 화자/대사/지침/구분선이 무대 대본 형식으로 배치되는지 확인.
@MainActor
@Test func scriptTextExportFormatsBlocks() {
    let aria = CastMember(name: "아리아", roleLine: "주인공")
    let kyle = CastMember(name: "카일")
    let content = ScenarioContent(
        cast: [aria, kyle],
        blocks: [
            ScenarioBlock(kind: .instruction, text: "성벽 바깥. 저녁 안개."),
            ScenarioBlock(kind: .line, speakerIDs: [aria.id], text: "이 문, 어떤 지도에도 없어."),
            ScenarioBlock(kind: .divider, text: ""),
            ScenarioBlock(kind: .line, speakerIDs: [aria.id, kyle.id], text: "같이 열어보자."),
        ]
    )
    let script = ScenarioExport.text(title: "1장", content: content, blocks: content.blocks)

    #expect(script.hasPrefix("1장\n"))
    #expect(script.contains("아리아 — 주인공")) // 등장인물 목록
    #expect(script.contains("(성벽 바깥. 저녁 안개.)")) // 지침은 괄호
    #expect(script.contains("아리아\n    이 문, 어떤 지도에도 없어.")) // 화자 다음 줄 들여쓴 대사
    #expect(script.contains("아리아 · 카일\n    같이 열어보자.")) // 다중 화자
    #expect(script.contains(String(repeating: "─", count: 24))) // 구분선
}

/// PDF 내보내기 — 유효한 PDF 데이터(헤더 %PDF)가 생성되는지 확인.
@MainActor
@Test func scriptPDFExportProducesValidData() {
    let aria = CastMember(name: "아리아")
    let content = ScenarioContent(
        cast: [aria],
        blocks: (0..<40).map { index in
            ScenarioBlock(kind: .line, speakerIDs: [aria.id], text: "대사 \(index) — 페이지가 넘어갈 만큼 충분히 긴 문장을 반복합니다.")
        }
    )
    let data = ScenarioExport.pdf(title: "PDF 테스트", content: content, blocks: content.blocks)
    #expect(data != nil)
    if let data {
        #expect(data.count > 500)
        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")
    }
}
