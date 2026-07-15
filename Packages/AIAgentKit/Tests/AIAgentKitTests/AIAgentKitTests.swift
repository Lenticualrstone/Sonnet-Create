import DocumentKit
import Foundation
import Testing
@testable import AIAgentKit

// MARK: - 테스트용 스텁 제공자

/// 고정 응답을 돌려주는 스텁 — 프로토콜 계약과 파서를 네트워크 없이 검증한다.
private struct StubProvider: AIProvider {
    let kind: AIProviderKind = .offline
    var reply: String
    /// 스트림 델타를 여러 조각으로 쪼개 방출할지 (스트림 누적 검증용)
    var chunkSize: Int = .max

    func availability() async -> AIAvailability { .available }

    func generate(system: String, prompt: String) async throws -> String { reply }

    func chatStream(history: [AIChatMessage], system: String) -> AsyncThrowingStream<String, Error> {
        let text = reply
        let size = chunkSize
        return AsyncThrowingStream { continuation in
            var index = text.startIndex
            while index < text.endIndex {
                let end = text.index(index, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
                continuation.yield(String(text[index..<end]))
                index = end
            }
            continuation.finish()
        }
    }
}

// MARK: - 프로토콜 디스패치

/// draftScenario는 프로토콜 요구사항이어야 한다. extension 전용이면 `any AIProvider`
/// 경유 호출이 정적 디스패치로 기본 구현에 묶여, 제공자의 재정의가 조용히 무시된다
/// (오프라인 모드의 시나리오 이어쓰기가 안내 문구 한 줄만 뱉던 실제 버그).
@Test func providerOverrideOfDraftScenarioIsDynamicallyDispatched() async throws {
    let provider: any AIProvider = OfflineDraftProvider()
    let context = AIScenarioContext(
        castNames: ["아린", "카이"],
        recentBlocks: [(speaker: "아린", text: "왜 돌아왔지?", isInstruction: false)]
    )
    let blocks = try await provider.draftScenario(context: context, maxBlocks: 10)

    #expect(blocks.count > 1, "재정의된 뼈대 생성기가 아니라 generate 기반 기본 구현이 불렸다")
    #expect(blocks.contains { $0.speakerName == "카이" }, "다음 화자로 순환해야 한다")
}

@Test func scenarioAutoWriterRespectsMaxBlocks() async throws {
    let context = AIScenarioContext(
        castNames: ["아린", "카이"],
        recentBlocks: [(speaker: "아린", text: "왜 돌아왔지?", isInstruction: false)]
    )
    let blocks = try await ScenarioAutoWriter(provider: OfflineDraftProvider(), maxBlocks: 2)
        .draft(context: context)
    #expect(blocks.count <= 2)
}

@Test func unavailableProviderThrowsBeforeCalling() async throws {
    let writer = ScenarioAutoWriter(provider: AnthropicProvider(apiKey: ""))
    await #expect(throws: (any Error).self) {
        try await writer.draft(context: AIScenarioContext(castNames: [], recentBlocks: []))
    }
}

// MARK: - 페르소나

@Test func personaMergesNameAndInstructionsIntoSystemPrompt() {
    let persona = AIAgentPersona(name: "테스터", instructionsMarkdown: "## 규칙\n- 짧게 답한다.")
    let prompt = persona.systemPrompt()
    #expect(prompt.contains("'테스터'"))
    #expect(prompt.contains("짧게 답한다"))
}

@Test func emptyPersonaProducesNoDanglingQuotes() {
    let prompt = AIAgentPersona().systemPrompt()
    #expect(!prompt.contains("''"))
    #expect(!prompt.contains("행동지침"))
}

// MARK: - 제공자 메타데이터

@Test func cloudProvidersDeclareDistinctKeychainAccounts() {
    let cloud = AIProviderKind.allCases.filter(\.requiresAPIKey)
    let accounts = cloud.map(\.keychainKey)
    #expect(cloud.count == 4)
    #expect(Set(accounts).count == accounts.count, "제공자별 키가 서로 덮어쓰면 안 된다")
    #expect(!accounts.contains(""))
    #expect(cloud.allSatisfy { !$0.defaultModel.isEmpty })
}

@Test func localProvidersNeedNoAPIKey() {
    #expect(!AIProviderKind.offline.requiresAPIKey)
    #expect(!AIProviderKind.appleOnDevice.requiresAPIKey)
}

// MARK: - 시나리오 응답 파서

@Test func parserSplitsLinesAndInstructions() {
    let text = """
    [지침] 비 오는 밤, 창고.
    아린: 왜 돌아왔지?
    (짧은 사이)
    카이: 끝내려고.
    """
    let blocks = ScenarioResponseParser.parse(text, castNames: ["아린", "카이"])
    #expect(blocks.count == 4)
    #expect(blocks[0].isInstruction)
    #expect(blocks[1].speakerName == "아린")
    #expect(blocks[2].isInstruction, "괄호 표기도 지침으로 취급")
    #expect(blocks[3].text == "끝내려고.")
}

@Test func parserMatchesCastNameCaseInsensitively() {
    let blocks = ScenarioResponseParser.parse("arin: hello", castNames: ["Arin"])
    #expect(blocks.first?.speakerName == "Arin", "캐스트의 표기를 정본으로 삼아야 한다")
}

@Test func parserTreatsLongPrefixAsInstructionNotSpeaker() {
    // 콜론이 있어도 이름이라기엔 너무 길면(24자 초과) 화자로 오인하면 안 된다 —
    // 서술문이 화자로 파싱되면 컴포저가 그 문장을 캐스트로 만들어버린다.
    let text = "이것은 화자 이름이 아니라 아주 긴 서술문이며 콜론을 포함합니다: 내용"
    let blocks = ScenarioResponseParser.parse(text, castNames: ["아린"])
    #expect(blocks.first?.isInstruction == true)
}

// MARK: - 컴포저 파싱 (실제 LLM 출력의 지저분함에 대한 내성)

@Test func composerExtractsJSONWrappedInCodeFence() {
    let raw = """
    좋습니다, 요청하신 캐릭터입니다:
    ```json
    {"name": "서연화", "role": "은퇴한 검사"}
    ```
    추가 설명이 필요하면 말씀해 주세요.
    """
    let json = AIAgentComposer.extractJSONObject(from: raw)
    #expect(json?["name"] as? String == "서연화")
}

@Test func composerReturnsNilForNonJSON() {
    #expect(AIAgentComposer.extractJSONObject(from: "죄송하지만 만들 수 없습니다.") == nil)
}

@Test func composerSplitsExplicitTitleLine() {
    let (title, body) = AIAgentComposer.splitTitle(from: "제목: 마법 체계\n\n## 개요\n본문", fallback: "brief")
    #expect(title == "마법 체계")
    #expect(!body.contains("제목:"))
    #expect(body.contains("## 개요"))
}

@Test func composerFallsBackToLeadingHeading() {
    let (title, _) = AIAgentComposer.splitTitle(from: "# 마법 체계\n본문", fallback: "brief")
    #expect(title == "마법 체계")
}

@Test func composerFallsBackToBriefWhenTitleMissing() {
    let (title, body) = AIAgentComposer.splitTitle(from: "제목 없는 본문", fallback: "브리프")
    #expect(title == "브리프")
    #expect(body == "제목 없는 본문")
}

// MARK: - 컴포저 통합 (스텁 제공자 경유)

@Test func composesMindMapWithRadialLayout() async throws {
    let reply = """
    {"title": "플롯", "nodes": [
      {"id": "a", "title": "중심"}, {"id": "b", "title": "발단"}, {"id": "c", "title": "전개"}
    ], "edges": [{"from": "a", "to": "b"}, {"from": "a", "to": "c"}]}
    """
    let composer = AIAgentComposer(provider: StubProvider(reply: reply), persona: AIAgentPersona())
    let doc = try await composer.compose(kind: .mindmap, brief: "테스트")

    #expect(doc.title == "플롯")
    guard case .mindmap(let content) = doc.content else {
        Issue.record("마인드맵 콘텐츠가 아님")
        return
    }
    #expect(content.nodes.count == 3)
    #expect(content.edges.count == 2)
    #expect(content.nodes[0].x == 0 && content.nodes[0].y == 0, "중심 노드는 원점")
    #expect(content.nodes.dropFirst().allSatisfy { $0.x != 0 || $0.y != 0 }, "나머지는 방사 배치")
    let ids = Set(content.nodes.map(\.id))
    #expect(content.edges.allSatisfy { ids.contains($0.fromID) && ids.contains($0.toID) })
}

@Test func mindMapDropsEdgesReferencingUnknownNodes() async throws {
    let reply = """
    {"title": "T", "nodes": [{"id": "a", "title": "A"}],
     "edges": [{"from": "a", "to": "ghost"}]}
    """
    let composer = AIAgentComposer(provider: StubProvider(reply: reply), persona: AIAgentPersona())
    let doc = try await composer.compose(kind: .mindmap, brief: "테스트")
    guard case .mindmap(let content) = doc.content else {
        Issue.record("마인드맵 콘텐츠가 아님")
        return
    }
    #expect(content.edges.isEmpty, "존재하지 않는 노드를 가리키는 엣지는 버려야 한다")
}

@Test func composesScenarioLinkingSpeakersToCast() async throws {
    let reply = """
    제목: 깨진 맹세
    캐릭터: 이서진, 한도윤
    [지침] 비 오는 밤, 창고.
    이서진: 왔구나.
    한도윤: 도망칠 이유가 없어.
    """
    let composer = AIAgentComposer(provider: StubProvider(reply: reply), persona: AIAgentPersona())
    let doc = try await composer.compose(kind: .scenario, brief: "테스트")

    #expect(doc.title == "깨진 맹세")
    guard case .scenario(let content) = doc.content else {
        Issue.record("시나리오 콘텐츠가 아님")
        return
    }
    #expect(content.cast.count == 2)
    let castIDs = Set(content.cast.map(\.id))
    let lines = content.blocks.filter { $0.kind == .line }
    #expect(lines.count == 2)
    #expect(lines.allSatisfy { $0.speakerIDs.allSatisfy { castIDs.contains($0) } },
            "화자는 캐스트에 연결돼야 한다 — 안 그러면 에디터에서 물음표로 뜬다")
    #expect(content.cast.allSatisfy { !$0.accentHex.isEmpty })
}

@Test func composesCharacterWithProfileAndVoice() async throws {
    let reply = """
    {"name": "서연화", "role": "은퇴한 검사", "summary": "칼을 내려놓은 검객.",
     "fields": [{"name": "나이", "value": "43"}],
     "voice": {"tone": "건조하다", "taboo": "복수", "samples": ["칼은 내려놨다."]},
     "body_markdown": "## 배경\\n왕립 검무사단 출신."}
    """
    let composer = AIAgentComposer(provider: StubProvider(reply: reply), persona: AIAgentPersona())
    let doc = try await composer.compose(kind: .character, brief: "테스트")

    #expect(doc.title == "서연화")
    guard case .page(let content) = doc.content, let profile = content.profile else {
        Issue.record("캐릭터 프로필이 없음")
        return
    }
    #expect(profile.role == "은퇴한 검사")
    #expect(profile.fields?.count == 1)
    #expect(profile.voice?.tone == "건조하다")
    #expect(profile.voice?.samples == ["칼은 내려놨다."])
    #expect(content.blocks.contains { $0.kind == .heading2 && $0.text == "배경" })
}

@Test func composerSurfacesUnparseableResponseAsError() async throws {
    let composer = AIAgentComposer(provider: StubProvider(reply: "만들 수 없습니다."), persona: AIAgentPersona())
    await #expect(throws: (any Error).self) {
        try await composer.compose(kind: .character, brief: "테스트")
    }
}

@Test func composerRefusesWhenProviderUnavailable() async throws {
    let composer = AIAgentComposer(provider: GeminiProvider(apiKey: ""), persona: AIAgentPersona())
    await #expect(throws: (any Error).self) {
        try await composer.compose(kind: .page, brief: "테스트")
    }
}

// MARK: - 스트림 누적

@Test func chatAccumulatesStreamDeltasInOrder() async throws {
    let provider = StubProvider(reply: "가나다라마바사", chunkSize: 2)
    let full = try await provider.chat(history: [AIChatMessage(role: .user, text: "hi")])
    #expect(full == "가나다라마바사", "델타가 순서대로 이어붙어야 한다")
}
