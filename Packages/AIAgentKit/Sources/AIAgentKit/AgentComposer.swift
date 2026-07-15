import DocumentKit
import Foundation

// MARK: - 마인드맵 자동 배치

/// 모델은 노드/연결만 주고 좌표는 앱이 정한다 — 컴포저와 에이전트 도구가 공유한다.
public enum MindMapLayout {
    /// 첫 노드는 중심(0,0), 이후 노드는 링을 이루며 방사형으로 퍼진다.
    public static func radial(index: Int, total: Int) -> (x: Double, y: Double) {
        guard index > 0 else { return (0, 0) }
        let ringCapacity = 8
        let ring = (index - 1) / ringCapacity
        let slot = (index - 1) % ringCapacity
        let inRing = min(ringCapacity, max(1, total - 1 - ring * ringCapacity))
        let angle = (Double(slot) / Double(inRing)) * 2 * Double.pi - Double.pi / 2
        let radius = 220.0 + Double(ring) * 190.0
        return (cos(angle) * radius, sin(angle) * radius)
    }
}

// MARK: - 에이전트 문서 생성

/// 에이전트가 생성할 수 있는 문서 작업 종류 (채팅 외 액션).
public enum AIComposeKind: String, CaseIterable, Sendable, Identifiable {
    case page // 일반 문서 (마크다운 → 블록)
    case character // 캐릭터 문서 (프로필 + 본문)
    case mindmap // 마인드맵 (노드/엣지 JSON)
    case scenario // 시나리오 (대사/지침 블록)

    public var id: String { rawValue }
}

/// 생성 결과 — 제목 + 에디터에 바로 꽂을 수 있는 콘텐츠.
public struct AIComposedDocument: Sendable {
    public var title: String
    public var content: DocumentContent

    public init(title: String, content: DocumentContent) {
        self.title = title
        self.content = content
    }
}

/// 연결된 AI 제공자로 문서를 통째로 생성하는 컴포저.
/// 모든 프롬프트는 "어떤 제공자든" 파싱 가능한 출력 형식(마크다운/JSON/시나리오 형식)을 강제한다.
public struct AIAgentComposer: Sendable {
    let provider: any AIProvider
    let persona: AIAgentPersona

    public init(provider: any AIProvider, persona: AIAgentPersona) {
        self.provider = provider
        self.persona = persona
    }

    public func compose(kind: AIComposeKind, brief: String, projectContext: String? = nil) async throws -> AIComposedDocument {
        if case .unavailable(let reason) = await provider.availability() {
            throw AIProviderError.make(30, reason)
        }
        switch kind {
        case .page: return try await composePage(brief: brief, projectContext: projectContext)
        case .character: return try await composeCharacter(brief: brief, projectContext: projectContext)
        case .mindmap: return try await composeMindMap(brief: brief, projectContext: projectContext)
        case .scenario: return try await composeScenario(brief: brief, projectContext: projectContext)
        }
    }

    // MARK: 페이지 (마크다운)

    private func composePage(brief: String, projectContext: String?) async throws -> AIComposedDocument {
        let prompt = """
        다음 요청에 맞는 창작 보조 문서를 작성하세요.
        \(contextLine(projectContext))
        출력 형식: 첫 줄은 '제목: <문서 제목>' 한 줄, 그 다음 줄부터 마크다운 본문.
        제목/구분선/리스트/인용/표 등 표준 마크다운을 활용하고, 코드펜스로 전체를 감싸지 마세요.

        요청: \(brief)
        """
        let raw = try await provider.generate(system: persona.systemPrompt(), prompt: prompt)
        let (title, body) = Self.splitTitle(from: raw, fallback: brief)
        let blocks = PageMarkdown.import(body)
        return AIComposedDocument(title: title, content: .page(PageContent(blocks: blocks)))
    }

    // MARK: 캐릭터 문서 (JSON 프로필 + 마크다운 본문)

    private func composeCharacter(brief: String, projectContext: String?) async throws -> AIComposedDocument {
        let prompt = """
        다음 요청에 맞는 캐릭터 설정 문서를 작성하세요.
        \(contextLine(projectContext))
        출력 형식은 JSON 하나만 — 설명·코드펜스 없이 아래 스키마를 정확히 지키세요:
        {
          "name": "캐릭터 이름",
          "role": "한 줄 역할 (예: 주인공, 조력자)",
          "summary": "2~3문장 요약",
          "fields": [{"name": "나이", "value": "..."}, {"name": "소속", "value": "..."}],
          "voice": {"tone": "말투 묘사", "taboo": "쓰지 않는 말", "samples": ["예시 대사 1", "예시 대사 2"]},
          "body_markdown": "## 배경\\n... (마크다운 본문: 배경/성격/목표/약점 등)"
        }

        요청: \(brief)
        """
        let raw = try await provider.generate(system: persona.systemPrompt(), prompt: prompt)
        guard let json = Self.extractJSONObject(from: raw) else {
            throw AIProviderError.make(40, "캐릭터 생성 응답을 해석하지 못했습니다.")
        }
        var profile = CharacterProfile(
            role: json["role"] as? String ?? "",
            summary: json["summary"] as? String ?? ""
        )
        if let fields = json["fields"] as? [[String: Any]] {
            profile.fields = fields.compactMap { field in
                guard let name = field["name"] as? String else { return nil }
                return CharacterField(name: name, value: field["value"] as? String ?? "")
            }
        }
        if let voice = json["voice"] as? [String: Any] {
            profile.voice = CharacterVoice(
                tone: voice["tone"] as? String ?? "",
                taboo: voice["taboo"] as? String ?? "",
                samples: (voice["samples"] as? [String]) ?? []
            )
        }
        let body = json["body_markdown"] as? String ?? ""
        let blocks = PageMarkdown.import(body)
        let title = (json["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return AIComposedDocument(
            title: title.isEmpty ? brief : title,
            content: .page(PageContent(blocks: blocks, profile: profile))
        )
    }

    // MARK: 마인드맵 (JSON 노드/엣지)

    private func composeMindMap(brief: String, projectContext: String?) async throws -> AIComposedDocument {
        let prompt = """
        다음 요청에 맞는 마인드맵을 설계하세요.
        \(contextLine(projectContext))
        출력 형식은 JSON 하나만 — 설명·코드펜스 없이 아래 스키마를 정확히 지키세요:
        {
          "title": "마인드맵 제목",
          "nodes": [{"id": "n1", "title": "중심 주제", "detail": "부연 (없으면 빈 문자열)"}, ...],
          "edges": [{"from": "n1", "to": "n2", "caption": "관계 라벨 (없으면 빈 문자열)"}, ...]
        }
        노드는 6~16개, 중심 주제 1개에서 가지가 뻗는 구조로. id는 짧은 고유 문자열.

        요청: \(brief)
        """
        let raw = try await provider.generate(system: persona.systemPrompt(), prompt: prompt)
        guard
            let json = Self.extractJSONObject(from: raw),
            let nodeList = json["nodes"] as? [[String: Any]], !nodeList.isEmpty
        else {
            throw AIProviderError.make(41, "마인드맵 생성 응답을 해석하지 못했습니다.")
        }

        // 방사형 자동 배치 — 첫 노드를 중심에, 나머지를 링 형태로.
        var idMap: [String: UUID] = [:]
        var nodes: [MindMapNode] = []
        let count = nodeList.count
        for (index, entry) in nodeList.enumerated() {
            guard let key = entry["id"] as? String ?? entry["title"] as? String else { continue }
            let title = entry["title"] as? String ?? key
            let position = MindMapLayout.radial(index: index, total: count)
            let node = MindMapNode(
                title: title,
                detail: entry["detail"] as? String ?? "",
                x: position.x,
                y: position.y
            )
            idMap[key] = node.id
            nodes.append(node)
        }
        var edges: [MindMapEdge] = []
        if let edgeList = json["edges"] as? [[String: Any]] {
            for entry in edgeList {
                guard
                    let fromKey = entry["from"] as? String, let from = idMap[fromKey],
                    let toKey = entry["to"] as? String, let to = idMap[toKey]
                else { continue }
                edges.append(MindMapEdge(fromID: from, toID: to, caption: entry["caption"] as? String ?? ""))
            }
        }
        let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return AIComposedDocument(
            title: title.isEmpty ? brief : title,
            content: .mindmap(MindMapContent(nodes: nodes, edges: edges))
        )
    }

    // MARK: 시나리오

    private func composeScenario(brief: String, projectContext: String?) async throws -> AIComposedDocument {
        let prompt = """
        다음 요청에 맞는 시나리오 장면을 작성하세요.
        \(contextLine(projectContext))
        출력 형식:
        첫 줄은 '제목: <시나리오 제목>'.
        둘째 줄은 '캐릭터: 이름1, 이름2, ...' (등장 인물 목록).
        그 다음 줄부터 본문 — 대사는 '이름: 내용', 무대 지침은 '[지침] 내용'. 다른 형식/설명/번호는 금지.
        20~40개 블록 분량으로.

        요청: \(brief)
        """
        let raw = try await provider.generate(system: persona.systemPrompt(), prompt: prompt)
        var lines = raw.components(separatedBy: .newlines)

        var title = brief
        var castNames: [String] = []
        // 헤더 두 줄 소비 (순서 무관, 앞쪽 4줄 안에서 탐색)
        var consumed = 0
        for line in lines.prefix(4) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("제목:") {
                title = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                consumed += 1
            } else if trimmed.hasPrefix("캐릭터:") {
                castNames = String(trimmed.dropFirst(4))
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                consumed += 1
            } else if trimmed.isEmpty, consumed > 0 {
                consumed += 1
            } else if consumed > 0 {
                break
            }
        }
        lines.removeFirst(min(consumed, lines.count))

        let suggested = ScenarioResponseParser.parse(lines.joined(separator: "\n"), castNames: castNames)
        guard !suggested.isEmpty else {
            throw AIProviderError.make(42, "시나리오 생성 응답을 해석하지 못했습니다.")
        }

        // 캐스트 구성 — 파싱된 화자 이름을 합류시킨다.
        var cast: [CastMember] = []
        var castByName: [String: UUID] = [:]
        func castID(for name: String) -> UUID {
            if let existing = castByName[name] { return existing }
            let palette = ["#5AC8FA", "#FF6482", "#63E6B6", "#FFB340", "#B18CFF", "#8E8E93"]
            let member = CastMember(name: name, accentHex: palette[cast.count % palette.count])
            cast.append(member)
            castByName[name] = member.id
            return member.id
        }
        for name in castNames { _ = castID(for: name) }

        let blocks: [ScenarioBlock] = suggested.map { block in
            if block.isInstruction {
                return ScenarioBlock(kind: .instruction, text: block.text)
            }
            let speakerIDs = block.speakerName.map { [castID(for: $0)] } ?? []
            return ScenarioBlock(kind: .line, speakerIDs: speakerIDs, text: block.text)
        }
        return AIComposedDocument(
            title: title.isEmpty ? brief : title,
            content: .scenario(ScenarioContent(cast: cast, blocks: blocks))
        )
    }

    // MARK: 파싱 헬퍼

    private func contextLine(_ projectContext: String?) -> String {
        guard let context = projectContext, !context.isEmpty else { return "" }
        return "프로젝트 맥락: \(context)"
    }

    /// '제목: ...' 첫 줄을 분리. 없으면 첫 헤딩을 제목으로 쓴다.
    static func splitTitle(from raw: String, fallback: String) -> (title: String, body: String) {
        var lines = raw.components(separatedBy: .newlines)
        // 선행 빈 줄 제거
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        if let first = lines.first?.trimmingCharacters(in: .whitespaces) {
            if first.hasPrefix("제목:") {
                let title = String(first.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                lines.removeFirst()
                return (title.isEmpty ? fallback : title, lines.joined(separator: "\n"))
            }
            if first.hasPrefix("# ") {
                let title = String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                lines.removeFirst()
                return (title.isEmpty ? fallback : title, lines.joined(separator: "\n"))
            }
        }
        let trimmedFallback = String(fallback.prefix(40))
        return (trimmedFallback, lines.joined(separator: "\n"))
    }

    /// 응답에서 최상위 JSON 오브젝트를 추출 (코드펜스/부연 텍스트에 관대).
    static func extractJSONObject(from raw: String) -> [String: Any]? {
        // 1) 그대로 시도
        if let data = raw.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return json
        }
        // 2) 첫 '{'부터 마지막 '}'까지 잘라 시도 (코드펜스·설명문 제거)
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"), start < end else {
            return nil
        }
        let sliced = String(raw[start...end])
        guard let data = sliced.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
