import AIAgentKit
import AppCore
import DocumentKit
import FileManagerKit
import Foundation
import MarkdownEditor

// MARK: - 에이전트 도구 (앱 기능 노출)

/// 에이전트가 쓸 수 있는 앱 기능의 등록소.
///
/// **새 기능을 붙일 때**: 여기 배열에 `AIToolHandler` 하나를 더하면 끝이다 —
/// 4개 제공자 전부에 자동으로 노출되고(각 어댑터가 스키마를 번역한다), 프롬프트를
/// 손댈 필요가 없다. 도구 이름/설명이 곧 모델이 보는 사용 설명서다.
extension AppState {
    func makeAgentToolbox() -> AIToolbox {
        AIToolbox(discoveryTools + authoringTools + editingTools)
    }

    // MARK: 탐색 · 읽기

    private var discoveryTools: [AIToolHandler] {
        [
            AIToolHandler(AITool(
                name: "list_projects",
                description: "워크스페이스의 모든 프로젝트 목록과 각 프로젝트의 문서 수를 반환한다. 문서를 만들 프로젝트를 고르기 전에 쓴다."
            )) { [weak self] _ in
                guard let self else { return ToolError.appGone }
                return await MainActor.run {
                    let projects = self.workspace.projects
                    guard !projects.isEmpty else { return "프로젝트가 없습니다. create_project로 만들 수 있습니다." }
                    return projects.map { project in
                        let count = self.workspace.visibleDocuments.count { $0.envelope.projectID == project.id }
                        return "- \(project.manifest.name) (id: \(project.id.uuidString), 문서 \(count)개)"
                    }.joined(separator: "\n")
                }
            },

            AIToolHandler(AITool(
                name: "list_documents",
                description: "워크스페이스의 문서 목록을 반환한다. 프로젝트나 종류로 좁힐 수 있다.",
                properties: [
                    "project_id": .string("이 프로젝트의 문서만. 생략하면 전체."),
                    "kind": .string("문서 종류로 좁히기", enumValues: ["scenario", "mindmap", "page", "character"]),
                ]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let projectID = arguments.optionalString("project_id").flatMap(UUID.init(uuidString:))
                let kind = arguments.optionalString("kind")
                return await MainActor.run {
                    var items = self.workspace.visibleDocuments
                    if let projectID { items = items.filter { $0.envelope.projectID == projectID } }
                    if let kind { items = items.filter { Self.matches(kind: kind, $0.envelope) } }
                    guard !items.isEmpty else { return "조건에 맞는 문서가 없습니다." }
                    return items.prefix(60).map(Self.describe).joined(separator: "\n")
                }
            },

            AIToolHandler(AITool(
                name: "search_documents",
                description: "제목과 본문을 함께 검색해 관련 문서를 찾는다. 무엇을 참고할지 모를 때 먼저 쓴다.",
                properties: ["query": .string("검색어")],
                required: ["query"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let query = try arguments.string("query")
                let results = await self.workspace.deepSearch(query)
                guard !results.isEmpty else { return "'\(query)'에 대한 검색 결과가 없습니다." }
                return results.prefix(30).map(Self.describe).joined(separator: "\n")
            },

            AIToolHandler(AITool(
                name: "read_document",
                description: "문서 하나의 전체 내용을 텍스트로 읽는다. 기존 설정을 참고해 이어 쓸 때 쓴다.",
                properties: ["document_id": .string("문서 ID (list_documents/search_documents가 알려준 값)")],
                required: ["document_id"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                return try await MainActor.run {
                    // 열려 있으면 미저장 편집분까지 반영된 세션 쪽을 읽는다.
                    if let session = self.sessions[id] {
                        return Self.serialize(session.document.content, title: session.title)
                    }
                    guard let item = self.workspace.item(id: id) else {
                        throw ToolFailure("문서를 찾을 수 없습니다: \(id.uuidString)")
                    }
                    guard let loaded = try? DocumentPackageIO.read(from: item.url) else {
                        throw ToolFailure("문서를 읽지 못했습니다: \(item.envelope.title)")
                    }
                    return Self.serialize(loaded.content, title: loaded.envelope.title)
                }
            },

            AIToolHandler(AITool(
                name: "get_open_document",
                description: "사용자가 지금 보고 있는 문서를 반환한다. '이거', '지금 이 문서' 같은 지시어가 나오면 먼저 쓴다."
            )) { [weak self] _ in
                guard let self else { return ToolError.appGone }
                return await MainActor.run {
                    guard let tab = self.selectedTab, let session = self.session(for: tab) else {
                        return "지금 열린 문서가 없습니다 (홈/채팅 화면일 수 있습니다)."
                    }
                    let project = self.workspace.project(id: session.document.envelope.projectID)
                    return """
                    id: \(session.id.uuidString)
                    제목: \(session.title)
                    종류: \(Self.kindLabel(session.document.envelope))
                    프로젝트: \(project?.manifest.name ?? "(없음)")

                    \(Self.serialize(session.document.content, title: session.title))
                    """
                }
            },
        ]
    }

    // MARK: 생성

    private var authoringTools: [AIToolHandler] {
        [
            AIToolHandler(AITool(
                name: "create_project",
                description: "새 프로젝트(문서를 묶는 폴더)를 만든다.",
                properties: ["name": .string("프로젝트 이름")],
                required: ["name"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let name = try arguments.string("name")
                return try await MainActor.run {
                    do {
                        let project = try self.workspace.createProject(name: name)
                        return "프로젝트 '\(project.manifest.name)' 생성됨 (id: \(project.id.uuidString))"
                    } catch {
                        throw ToolFailure("프로젝트를 만들지 못했습니다: \(error.localizedDescription)")
                    }
                }
            },

            AIToolHandler(AITool(
                name: "create_page",
                description: "마크다운 본문으로 일반 문서(설정/세계관/메모 등)를 만들고 연다.",
                properties: [
                    "title": .string("문서 제목"),
                    "markdown": .string("마크다운 본문. 제목(#)·목록·인용·표를 쓸 수 있다."),
                    "project_id": .string("넣을 프로젝트 ID. 생략하면 최상위."),
                ],
                required: ["title", "markdown"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let title = try arguments.string("title")
                let markdown = try arguments.string("markdown")
                let projectID = arguments.optionalString("project_id").flatMap(UUID.init(uuidString:))
                return await MainActor.run {
                    let content = DocumentContent.page(PageContent(blocks: PageMarkdown.import(markdown)))
                    let id = self.createAndOpenDocument(
                        title: title, content: content, in: self.workspace.project(id: projectID)
                    )
                    self.notify(symbol: "doc.richtext", message: "AI 생성: \(title)")
                    return "문서 '\(title)' 생성 후 열었습니다 (id: \(id.uuidString))"
                }
            },

            AIToolHandler(AITool(
                name: "create_character",
                description: "캐릭터 설정 문서를 만들고 연다. 프로필·보이스 카드는 시나리오 자동작성에서 말투 유지에 쓰인다.",
                properties: [
                    "name": .string("캐릭터 이름"),
                    "role": .string("한 줄 역할 (예: 주인공, 조력자)"),
                    "summary": .string("2~3문장 요약"),
                    "fields": .array("나이·소속 등 구조화 필드", of: .object("필드", properties: [
                        "name": .string("항목 이름"),
                        "value": .string("값"),
                    ], required: ["name", "value"])),
                    "voice_tone": .string("말투 묘사"),
                    "voice_taboo": .string("이 인물이 쓰지 않는 말"),
                    "voice_samples": .array("예시 대사", of: .string("대사 한 줄")),
                    "body_markdown": .string("배경·성격·목표 등 본문 (마크다운)"),
                    "project_id": .string("넣을 프로젝트 ID. 생략하면 최상위."),
                ],
                required: ["name"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let name = try arguments.string("name")
                var profile = CharacterProfile(
                    role: arguments.string("role", or: ""),
                    summary: arguments.string("summary", or: "")
                )
                let fields = arguments.objects("fields").compactMap { field -> CharacterField? in
                    guard let fieldName = try? field.string("name") else { return nil }
                    return CharacterField(name: fieldName, value: field.string("value", or: ""))
                }
                if !fields.isEmpty { profile.fields = fields }
                let tone = arguments.string("voice_tone", or: "")
                let taboo = arguments.string("voice_taboo", or: "")
                let samples = arguments.stringArray("voice_samples")
                if !tone.isEmpty || !taboo.isEmpty || !samples.isEmpty {
                    profile.voice = CharacterVoice(tone: tone, taboo: taboo, samples: samples)
                }
                let body = arguments.string("body_markdown", or: "")
                let projectID = arguments.optionalString("project_id").flatMap(UUID.init(uuidString:))

                return await MainActor.run {
                    let content = DocumentContent.page(PageContent(
                        blocks: PageMarkdown.import(body), profile: profile
                    ))
                    let id = self.createAndOpenDocument(
                        title: name, content: content, pageRole: .character,
                        in: self.workspace.project(id: projectID)
                    )
                    self.notify(symbol: "person.crop.circle.badge.plus", message: "AI 생성: \(name)")
                    return "캐릭터 '\(name)' 생성 후 열었습니다 (id: \(id.uuidString))"
                }
            },

            AIToolHandler(AITool(
                name: "create_mindmap",
                description: "노드와 연결로 마인드맵을 만들고 연다. 배치는 앱이 방사형으로 자동 계산한다 (첫 노드가 중심).",
                properties: [
                    "title": .string("마인드맵 제목"),
                    "nodes": .array("노드 목록. 첫 번째가 중심 주제가 된다.", of: .object("노드", properties: [
                        "id": .string("이 요청 안에서만 쓰는 짧은 고유 id (연결에서 참조)"),
                        "title": .string("노드 제목"),
                        "detail": .string("부연 설명"),
                    ], required: ["id", "title"])),
                    "edges": .array("노드 간 연결", of: .object("연결", properties: [
                        "from": .string("출발 노드 id"),
                        "to": .string("도착 노드 id"),
                        "caption": .string("관계 라벨"),
                    ], required: ["from", "to"])),
                    "project_id": .string("넣을 프로젝트 ID. 생략하면 최상위."),
                ],
                required: ["title", "nodes"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let title = try arguments.string("title")
                let nodeSpecs = arguments.objects("nodes")
                guard !nodeSpecs.isEmpty else { throw ToolFailure("노드가 최소 1개는 필요합니다.") }

                var keyToID: [String: UUID] = [:]
                var nodes: [MindMapNode] = []
                for (index, spec) in nodeSpecs.enumerated() {
                    guard let key = try? spec.string("id"), let nodeTitle = try? spec.string("title") else { continue }
                    let position = MindMapLayout.radial(index: index, total: nodeSpecs.count)
                    let node = MindMapNode(
                        title: nodeTitle, detail: spec.string("detail", or: ""),
                        x: position.x, y: position.y
                    )
                    keyToID[key] = node.id
                    nodes.append(node)
                }
                guard !nodes.isEmpty else { throw ToolFailure("노드에 id와 title이 필요합니다.") }

                var edges: [MindMapEdge] = []
                var danglingEdges = 0
                for spec in arguments.objects("edges") {
                    guard let fromKey = try? spec.string("from"), let toKey = try? spec.string("to") else { continue }
                    guard let from = keyToID[fromKey], let to = keyToID[toKey] else {
                        danglingEdges += 1
                        continue
                    }
                    edges.append(MindMapEdge(fromID: from, toID: to, caption: spec.string("caption", or: "")))
                }
                let projectID = arguments.optionalString("project_id").flatMap(UUID.init(uuidString:))

                return await MainActor.run {
                    let content = DocumentContent.mindmap(MindMapContent(nodes: nodes, edges: edges))
                    let id = self.createAndOpenDocument(
                        title: title, content: content, in: self.workspace.project(id: projectID)
                    )
                    self.notify(symbol: "point.3.connected.trianglepath.dotted", message: "AI 생성: \(title)")
                    var report = "마인드맵 '\(title)' 생성 후 열었습니다 — 노드 \(nodes.count)개, 연결 \(edges.count)개 (id: \(id.uuidString))"
                    if danglingEdges > 0 {
                        report += "\n주의: 존재하지 않는 노드를 가리키는 연결 \(danglingEdges)개는 무시했습니다."
                    }
                    return report
                }
            },

            AIToolHandler(AITool(
                name: "create_scenario",
                description: "대사와 지침으로 시나리오를 만들고 연다. 등장인물은 blocks의 speaker에서 자동 수집된다.",
                properties: [
                    "title": .string("시나리오 제목"),
                    "blocks": .array("대사/지침 블록을 순서대로", of: .object("블록", properties: [
                        "type": .string("line=대사, instruction=무대 지침", enumValues: ["line", "instruction"]),
                        "speaker": .string("화자 이름 (type=line일 때 필수)"),
                        "text": .string("대사 또는 지침 내용"),
                    ], required: ["type", "text"])),
                    "project_id": .string("넣을 프로젝트 ID. 생략하면 최상위."),
                ],
                required: ["title", "blocks"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let title = try arguments.string("title")
                let specs = arguments.objects("blocks")
                guard !specs.isEmpty else { throw ToolFailure("블록이 최소 1개는 필요합니다.") }

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

                var blocks: [ScenarioBlock] = []
                for spec in specs {
                    guard let text = try? spec.string("text") else { continue }
                    if spec.string("type", or: "line") == "instruction" {
                        blocks.append(ScenarioBlock(kind: .instruction, text: text))
                    } else {
                        let speakerIDs = spec.optionalString("speaker").map { [castID(for: $0)] } ?? []
                        blocks.append(ScenarioBlock(kind: .line, speakerIDs: speakerIDs, text: text))
                    }
                }
                guard !blocks.isEmpty else { throw ToolFailure("블록에 text가 필요합니다.") }
                let projectID = arguments.optionalString("project_id").flatMap(UUID.init(uuidString:))

                return await MainActor.run {
                    let content = DocumentContent.scenario(ScenarioContent(cast: cast, blocks: blocks))
                    let id = self.createAndOpenDocument(
                        title: title, content: content, in: self.workspace.project(id: projectID)
                    )
                    self.notify(symbol: "text.bubble", message: "AI 생성: \(title)")
                    return "시나리오 '\(title)' 생성 후 열었습니다 — 블록 \(blocks.count)개, 등장인물 \(cast.count)명 (id: \(id.uuidString))"
                }
            },
        ]
    }

    // MARK: 편집

    private var editingTools: [AIToolHandler] {
        [
            AIToolHandler(AITool(
                name: "append_to_page",
                description: "기존 일반/캐릭터 문서 끝에 마크다운을 덧붙인다. 기존 내용은 지우지 않는다.",
                properties: [
                    "document_id": .string("대상 문서 ID"),
                    "markdown": .string("덧붙일 마크다운"),
                ],
                required: ["document_id", "markdown"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let markdown = try arguments.string("markdown")
                let newBlocks = PageMarkdown.import(markdown)
                guard !newBlocks.isEmpty else { throw ToolFailure("덧붙일 내용이 비어 있습니다.") }

                return try await MainActor.run {
                    // 열려 있으면 세션 경유 — 되돌리기 스택에 남고 자동저장이 처리한다.
                    if let session = self.sessions[id] {
                        guard case .page(let store) = session.editor else {
                            throw ToolFailure("이 문서는 페이지가 아닙니다. 시나리오/마인드맵에는 쓸 수 없습니다.")
                        }
                        var content = store.content
                        content.blocks += newBlocks
                        store.replaceContent(content)
                        return "'\(session.title)'에 블록 \(newBlocks.count)개를 덧붙였습니다."
                    }
                    // 닫혀 있으면 디스크에서 직접
                    guard let item = self.workspace.item(id: id) else {
                        throw ToolFailure("문서를 찾을 수 없습니다: \(id.uuidString)")
                    }
                    guard var loaded = try? DocumentPackageIO.read(from: item.url),
                          case .page(var content) = loaded.content
                    else {
                        throw ToolFailure("페이지 문서를 읽지 못했습니다: \(item.envelope.title)")
                    }
                    content.blocks += newBlocks
                    loaded = LoadedDocument(
                        envelope: loaded.envelope, content: .page(content),
                        refs: loaded.refs, url: loaded.url
                    )
                    do {
                        _ = try DocumentPackageIO.write(loaded)
                    } catch {
                        throw ToolFailure("저장하지 못했습니다: \(error.localizedDescription)")
                    }
                    self.workspace.scanSoon()
                    return "'\(item.envelope.title)'에 블록 \(newBlocks.count)개를 덧붙였습니다."
                }
            },

            AIToolHandler(AITool(
                name: "rename_document",
                description: "문서 제목을 바꾼다.",
                properties: [
                    "document_id": .string("대상 문서 ID"),
                    "title": .string("새 제목"),
                ],
                required: ["document_id", "title"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let title = try arguments.string("title")
                return try await MainActor.run {
                    guard let item = self.workspace.item(id: id) else {
                        throw ToolFailure("문서를 찾을 수 없습니다: \(id.uuidString)")
                    }
                    let old = item.envelope.title
                    self.renameDocument(item, to: title)
                    return "'\(old)' → '\(title)'로 이름을 바꿨습니다."
                }
            },
        ]
    }

    // MARK: 헬퍼
    // 순수 함수들 — 도구 핸들러가 MainActor 밖에서도 부르므로 nonisolated로 둔다.

    nonisolated private static func parseUUID(_ text: String, key: String) throws -> UUID {
        guard let id = UUID(uuidString: text) else {
            throw AIToolArgumentError(key: key, reason: "UUID 형식이 아닙니다: \(text)")
        }
        return id
    }

    nonisolated private static func matches(kind: String, _ envelope: DocumentEnvelope) -> Bool {
        switch kind {
        case "character": envelope.isCharacterPage
        case "page": envelope.kind == .page && !envelope.isCharacterPage
        case "scenario": envelope.kind == .scenario
        case "mindmap": envelope.kind == .mindmap
        default: true
        }
    }

    nonisolated private static func kindLabel(_ envelope: DocumentEnvelope) -> String {
        if envelope.isCharacterPage { return "character" }
        return envelope.kind.rawValue
    }

    nonisolated private static func describe(_ item: DocumentListItem) -> String {
        var line = "- \(item.envelope.title) [\(kindLabel(item.envelope))] id: \(item.id.uuidString)"
        if let project = item.projectName { line += " / 프로젝트: \(project)" }
        return line
    }

    /// 문서 콘텐츠를 모델이 읽을 수 있는 평문으로 직렬화.
    nonisolated private static func serialize(_ content: DocumentContent, title: String) -> String {
        switch content {
        case .page(let page):
            var parts: [String] = []
            if let profile = page.profile {
                var lines = ["# \(title)"]
                if !profile.role.isEmpty { lines.append("역할: \(profile.role)") }
                if !profile.summary.isEmpty { lines.append("요약: \(profile.summary)") }
                for field in profile.fields ?? [] {
                    lines.append("\(field.name): \(field.value)")
                }
                if let voice = profile.voice {
                    if !voice.tone.isEmpty { lines.append("말투: \(voice.tone)") }
                    if !voice.taboo.isEmpty { lines.append("금기: \(voice.taboo)") }
                    let samples = voice.samples.filter { !$0.isEmpty }
                    if !samples.isEmpty { lines.append("예시 대사: " + samples.joined(separator: " / ")) }
                }
                parts.append(lines.joined(separator: "\n"))
            }
            parts.append(PageMarkdown.export(page.blocks))
            return parts.joined(separator: "\n\n")

        case .scenario(let scenario):
            var lines: [String] = []
            if !scenario.cast.isEmpty {
                lines.append("등장인물: " + scenario.cast.map(\.name).joined(separator: ", "))
                lines.append("")
            }
            for block in scenario.blocks {
                switch block.kind {
                case .instruction:
                    lines.append("[지침] \(block.text)")
                case .divider:
                    lines.append("---")
                case .line:
                    let speaker = block.speakerIDs.first.flatMap { id in
                        scenario.cast.first { $0.id == id }?.name
                    } ?? "?"
                    lines.append("\(speaker): \(block.text)")
                }
            }
            for branch in scenario.branches {
                lines.append("")
                lines.append("[분기: \(branch.name)]")
                for block in branch.blocks {
                    let speaker = block.speakerIDs.first.flatMap { id in
                        scenario.cast.first { $0.id == id }?.name
                    } ?? "?"
                    lines.append(block.kind == .instruction ? "[지침] \(block.text)" : "\(speaker): \(block.text)")
                }
            }
            return lines.joined(separator: "\n")

        case .mindmap(let map):
            var lines = ["노드:"]
            for node in map.nodes {
                lines.append("- \(node.title)" + (node.detail.isEmpty ? "" : " — \(node.detail)"))
            }
            guard !map.edges.isEmpty else { return lines.joined(separator: "\n") }
            lines.append("")
            lines.append("연결:")
            for edge in map.edges {
                let from = map.nodes.first { $0.id == edge.fromID }?.title ?? "?"
                let to = map.nodes.first { $0.id == edge.toID }?.title ?? "?"
                lines.append("- \(from) → \(to)" + (edge.caption.isEmpty ? "" : " (\(edge.caption))"))
            }
            return lines.joined(separator: "\n")
        }
    }
}

/// 도구가 모델에게 돌려줄 실패 사유. 예외지만 루프를 끊지 않고 결과로 감싸여 전달된다.
struct ToolFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private enum ToolError {
    static let appGone = "앱 상태에 접근할 수 없습니다."
}
