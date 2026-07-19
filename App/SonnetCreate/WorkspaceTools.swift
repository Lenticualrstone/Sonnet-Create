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
    /// 설정 > Sonnet AI의 컨텍스트 범위를 에이전트 도구에 강제한다.
    /// 탐색/읽기 도구는 전부 이 집합만 본다 — 설정 화면의 "컨텍스트는 선택한 범위를
    /// 벗어나 전송되지 않습니다"라는 약속을 지키는 지점.
    private func agentScopedDocuments() throws -> [DocumentListItem] {
        switch settings.applied.aiContextScope {
        case .workspace:
            return workspace.visibleDocuments
        case .project:
            guard let projectID = chatContextSession?.document.envelope.projectID else {
                throw ToolFailure(
                    "컨텍스트 범위가 '현재 프로젝트'로 설정돼 있는데 지금 프로젝트 소속 문서가 열려 있지 않습니다. "
                        + "사용자에게 문서를 열거나 설정 > Sonnet AI에서 범위를 넓혀 달라고 안내하세요."
                )
            }
            return workspace.visibleDocuments.filter { $0.envelope.projectID == projectID }
        case .document:
            guard let session = chatContextSession else {
                throw ToolFailure(
                    "컨텍스트 범위가 '현재 문서'로 설정돼 있는데 지금 열린 문서가 없습니다. "
                        + "사용자에게 문서를 열거나 설정 > Sonnet AI에서 범위를 넓혀 달라고 안내하세요."
                )
            }
            return workspace.visibleDocuments.filter { $0.id == session.id }
        }
    }

    /// 범위 안의 문서인지 검사 — 읽기 도구가 범위 밖 id를 받았을 때 명확히 거절한다.
    private func assertInAgentScope(_ id: UUID) throws {
        // 현재 컨텍스트 문서는 (미저장이라 스캔에 아직 없더라도) 항상 허용.
        if chatContextSession?.id == id { return }
        let allowed = try agentScopedDocuments()
        guard allowed.contains(where: { $0.id == id }) else {
            throw ToolFailure("이 문서는 설정된 컨텍스트 범위 밖입니다. 설정 > Sonnet AI에서 범위를 조정할 수 있습니다.")
        }
    }

    func makeAgentToolbox() -> AIToolbox {
        AIToolbox(
            discoveryTools + authoringTools + editingTools + scenarioTools
                + mindMapTools + characterTools + destructiveTools,
            confirmationHandler: { [weak self] request in
                guard let self else { return false }
                return await aiChat.requestConfirmation(request)
            }
        )
    }

    // MARK: 탐색 · 읽기

    private var discoveryTools: [AIToolHandler] {
        [
            AIToolHandler(AITool(
                name: "list_projects",
                description: "프로젝트 목록과 각 프로젝트의 문서 수를 반환한다. 문서를 만들 프로젝트를 고르기 전에 쓴다."
            )) { [weak self] _ in
                guard let self else { return ToolError.appGone }
                return try await MainActor.run {
                    let scoped = try self.agentScopedDocuments()
                    // 범위 안에 문서가 있는 프로젝트만 노출 (워크스페이스 범위 = 전체)
                    let visibleProjectIDs = Set(scoped.compactMap(\.envelope.projectID))
                    let projects = self.settings.applied.aiContextScope == .workspace
                        ? self.workspace.projects
                        : self.workspace.projects.filter { visibleProjectIDs.contains($0.id) }
                    guard !projects.isEmpty else { return "프로젝트가 없습니다. create_project로 만들 수 있습니다." }
                    return projects.map { project in
                        let count = scoped.count { $0.envelope.projectID == project.id }
                        return "- \(project.manifest.name) (id: \(project.id.uuidString), 문서 \(count)개)"
                    }.joined(separator: "\n")
                }
            },

            AIToolHandler(AITool(
                name: "list_documents",
                description: "문서 목록을 반환한다. 프로젝트나 종류로 좁힐 수 있다.",
                properties: [
                    "project_id": .string("이 프로젝트의 문서만. 생략하면 전체."),
                    "kind": .string("문서 종류로 좁히기", enumValues: ["scenario", "mindmap", "page", "character"]),
                ]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let projectID = arguments.optionalString("project_id").flatMap(UUID.init(uuidString:))
                let kind = arguments.optionalString("kind")
                return try await MainActor.run {
                    var items = try self.agentScopedDocuments()
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
                let results = await workspace.deepSearch(query)
                // 딥서치는 전체 색인을 뒤지므로, 반환 전에 범위로 거른다.
                let allowed = try await MainActor.run { Set(try self.agentScopedDocuments().map(\.id)) }
                let scoped = results.filter { allowed.contains($0.id) }
                guard !scoped.isEmpty else { return "'\(query)'에 대한 검색 결과가 없습니다." }
                return scoped.prefix(30).map(Self.describe).joined(separator: "\n")
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
                    try self.assertInAgentScope(id)
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
                description: "사용자가 지금 작업 중인 문서를 반환한다. '이거', '이 문서', '여기' 같은 지시어가 나오면 먼저 쓴다. 채팅 화면에 있어도 마지막으로 편집하던 문서를 기억한다."
            )) { [weak self] _ in
                guard let self else { return ToolError.appGone }
                return await MainActor.run {
                    guard let session = self.chatContextSession else {
                        return "지금 작업 중인 문서가 없습니다. 문서 탭을 연 적이 없거나 모두 닫혔습니다."
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
                        title: title, content: content, in: self.workspace.project(id: projectID),
                        activate: false
                    )
                    self.notify(symbol: "doc.richtext", message: "AI 생성: \(title)")
                    return "문서 '\(title)'을 만들어 탭에 열어뒀습니다 (id: \(id.uuidString))"
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
                        in: self.workspace.project(id: projectID),
                        activate: false
                    )
                    self.notify(symbol: "person.crop.circle.badge.plus", message: "AI 생성: \(name)")
                    return "캐릭터 '\(name)'을 만들어 탭에 열어뒀습니다 (id: \(id.uuidString))"
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
                        title: title, content: content, in: self.workspace.project(id: projectID),
                        activate: false
                    )
                    self.notify(symbol: "point.3.connected.trianglepath.dotted", message: "AI 생성: \(title)")
                    var report = "마인드맵 '\(title)'을 만들어 탭에 열어뒀습니다 — 노드 \(nodes.count)개, 연결 \(edges.count)개 (id: \(id.uuidString))"
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
                        title: title, content: content, in: self.workspace.project(id: projectID),
                        activate: false
                    )
                    self.notify(symbol: "text.bubble", message: "AI 생성: \(title)")
                    return "시나리오 '\(title)'을 만들어 탭에 열어뒀습니다 — 블록 \(blocks.count)개, 등장인물 \(cast.count)명 (id: \(id.uuidString))"
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

    // MARK: 시나리오 부분 편집

    private var scenarioTools: [AIToolHandler] {
        [
            AIToolHandler(AITool(
                name: "add_scenario_blocks",
                description: "기존 시나리오에 대사/지침 블록을 추가한다. 없는 화자는 캐스트에 자동 추가된다.",
                properties: [
                    "document_id": .string("시나리오 문서 ID"),
                    "blocks": .array("추가할 블록", of: .object("블록", properties: [
                        "type": .string("line=대사, instruction=지침", enumValues: ["line", "instruction"]),
                        "speaker": .string("화자 이름 (type=line일 때)"),
                        "text": .string("내용"),
                    ], required: ["type", "text"])),
                    "after_block": .string("이 블록 핸들 바로 뒤에 삽입. 생략하면 맨 끝."),
                ],
                required: ["document_id", "blocks"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let specs = arguments.objects("blocks")
                guard !specs.isEmpty else { throw ToolFailure("블록이 최소 1개는 필요합니다.") }
                let afterHandle = arguments.optionalString("after_block")

                return try await MainActor.run {
                    try self.mutateDocument(id: id) { content in
                        guard case .scenario(var scenario) = content else {
                            throw ToolFailure("이 문서는 시나리오가 아닙니다.")
                        }
                        var added: [ScenarioBlock] = []
                        var newCast = 0
                        for spec in specs {
                            guard let text = try? spec.string("text") else { continue }
                            if spec.string("type", or: "line") == "instruction" {
                                added.append(ScenarioBlock(kind: .instruction, text: text))
                            } else {
                                var speakerIDs: [UUID] = []
                                if let name = spec.optionalString("speaker") {
                                    if let existing = scenario.cast.first(where: { $0.name == name }) {
                                        speakerIDs = [existing.id]
                                    } else {
                                        let member = Self.makeCastMember(name: name, index: scenario.cast.count)
                                        scenario.cast.append(member)
                                        speakerIDs = [member.id]
                                        newCast += 1
                                    }
                                }
                                added.append(ScenarioBlock(kind: .line, speakerIDs: speakerIDs, text: text))
                            }
                        }
                        guard !added.isEmpty else { throw ToolFailure("블록에 text가 필요합니다.") }

                        if let afterHandle {
                            let target = try Self.resolve(
                                handle: afterHandle, in: scenario.blocks, id: \.id, label: "블록"
                            )
                            let index = scenario.blocks.firstIndex { $0.id == target.id } ?? scenario.blocks.count - 1
                            scenario.blocks.insert(contentsOf: added, at: index + 1)
                        } else {
                            scenario.blocks += added
                        }
                        content = .scenario(scenario)
                        var report = "'\(self.documentTitle(id: id))'에 블록 \(added.count)개를 추가했습니다."
                        if newCast > 0 { report += " 새 등장인물 \(newCast)명이 캐스트에 추가됐습니다." }
                        return report
                    }
                }
            },

            AIToolHandler(AITool(
                name: "update_scenario_block",
                description: "시나리오 블록 하나의 대사 내용이나 화자를 고친다. read_document의 [핸들]로 지목한다.",
                properties: [
                    "document_id": .string("시나리오 문서 ID"),
                    "block": .string("블록 핸들 (read_document가 대괄호로 알려준 값)"),
                    "text": .string("새 내용. 생략하면 그대로."),
                    "speaker": .string("새 화자 이름. 생략하면 그대로."),
                ],
                required: ["document_id", "block"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let blockHandle = try arguments.string("block")
                let newText = arguments.optionalString("text")
                let newSpeaker = arguments.optionalString("speaker")
                guard newText != nil || newSpeaker != nil else {
                    throw ToolFailure("text나 speaker 중 하나는 지정해야 합니다.")
                }

                return try await MainActor.run {
                    try self.mutateDocument(id: id) { content in
                        guard case .scenario(var scenario) = content else {
                            throw ToolFailure("이 문서는 시나리오가 아닙니다.")
                        }
                        let target = try Self.resolve(
                            handle: blockHandle, in: scenario.blocks, id: \.id, label: "블록"
                        )
                        guard let index = scenario.blocks.firstIndex(where: { $0.id == target.id }) else {
                            throw ToolFailure("블록을 찾을 수 없습니다.")
                        }
                        if let newText { scenario.blocks[index].text = newText }
                        if let newSpeaker {
                            if let existing = scenario.cast.first(where: { $0.name == newSpeaker }) {
                                scenario.blocks[index].speakerIDs = [existing.id]
                            } else {
                                let member = Self.makeCastMember(name: newSpeaker, index: scenario.cast.count)
                                scenario.cast.append(member)
                                scenario.blocks[index].speakerIDs = [member.id]
                            }
                            scenario.blocks[index].kind = .line
                        }
                        content = .scenario(scenario)
                        return "블록 [\(Self.handle(target.id))]을 수정했습니다."
                    }
                }
            },
        ]
    }

    // MARK: 마인드맵 부분 편집

    private var mindMapTools: [AIToolHandler] {
        [
            AIToolHandler(AITool(
                name: "add_mindmap_nodes",
                description: "기존 마인드맵에 노드와 연결을 추가한다. 새 노드는 자동 배치된다.",
                properties: [
                    "document_id": .string("마인드맵 문서 ID"),
                    "nodes": .array("추가할 노드", of: .object("노드", properties: [
                        "id": .string("이 요청 안에서만 쓰는 임시 id (연결에서 참조)"),
                        "title": .string("노드 제목"),
                        "detail": .string("부연"),
                    ], required: ["id", "title"])),
                    "edges": .array("연결. from/to에는 새 노드의 임시 id 또는 기존 노드 핸들을 쓴다.",
                                    of: .object("연결", properties: [
                                        "from": .string("출발"),
                                        "to": .string("도착"),
                                        "caption": .string("관계 라벨"),
                                    ], required: ["from", "to"])),
                ],
                required: ["document_id", "nodes"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let nodeSpecs = arguments.objects("nodes")
                let edgeSpecs = arguments.objects("edges")
                guard !nodeSpecs.isEmpty else { throw ToolFailure("노드가 최소 1개는 필요합니다.") }

                return try await MainActor.run {
                    try self.mutateDocument(id: id) { content in
                        guard case .mindmap(var map) = content else {
                            throw ToolFailure("이 문서는 마인드맵이 아닙니다.")
                        }
                        let existingCount = map.nodes.count
                        var keyToID: [String: UUID] = [:]
                        for (offset, spec) in nodeSpecs.enumerated() {
                            guard let key = try? spec.string("id"),
                                  let title = try? spec.string("title") else { continue }
                            // 기존 노드 뒤에 이어 붙는 위치로 배치
                            let position = MindMapLayout.radial(
                                index: existingCount + offset,
                                total: existingCount + nodeSpecs.count
                            )
                            let node = MindMapNode(
                                title: title, detail: spec.string("detail", or: ""),
                                x: position.x, y: position.y
                            )
                            keyToID[key] = node.id
                            map.nodes.append(node)
                        }
                        guard !keyToID.isEmpty else { throw ToolFailure("노드에 id와 title이 필요합니다.") }

                        /// 임시 id 우선, 없으면 기존 노드 핸들로 해석
                        func resolveNode(_ key: String) -> UUID? {
                            if let id = keyToID[key] { return id }
                            return try? Self.resolve(handle: key, in: map.nodes, id: \.id, label: "노드").id
                        }
                        var addedEdges = 0
                        var dangling = 0
                        for spec in edgeSpecs {
                            guard let fromKey = try? spec.string("from"),
                                  let toKey = try? spec.string("to") else { continue }
                            guard let from = resolveNode(fromKey), let to = resolveNode(toKey) else {
                                dangling += 1
                                continue
                            }
                            map.edges.append(MindMapEdge(
                                fromID: from, toID: to, caption: spec.string("caption", or: "")
                            ))
                            addedEdges += 1
                        }
                        content = .mindmap(map)
                        var report = "노드 \(keyToID.count)개, 연결 \(addedEdges)개를 추가했습니다."
                        if dangling > 0 { report += " 대상을 못 찾은 연결 \(dangling)개는 무시했습니다." }
                        return report
                    }
                }
            },

            AIToolHandler(AITool(
                name: "update_mindmap_node",
                description: "마인드맵 노드 하나의 제목/부연을 고친다.",
                properties: [
                    "document_id": .string("마인드맵 문서 ID"),
                    "node": .string("노드 핸들"),
                    "title": .string("새 제목. 생략하면 그대로."),
                    "detail": .string("새 부연. 생략하면 그대로."),
                ],
                required: ["document_id", "node"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let nodeHandle = try arguments.string("node")
                let newTitle = arguments.optionalString("title")
                let newDetail = arguments.optionalString("detail")
                guard newTitle != nil || newDetail != nil else {
                    throw ToolFailure("title이나 detail 중 하나는 지정해야 합니다.")
                }

                return try await MainActor.run {
                    try self.mutateDocument(id: id) { content in
                        guard case .mindmap(var map) = content else {
                            throw ToolFailure("이 문서는 마인드맵이 아닙니다.")
                        }
                        let target = try Self.resolve(handle: nodeHandle, in: map.nodes, id: \.id, label: "노드")
                        guard let index = map.nodes.firstIndex(where: { $0.id == target.id }) else {
                            throw ToolFailure("노드를 찾을 수 없습니다.")
                        }
                        if let newTitle { map.nodes[index].title = newTitle }
                        if let newDetail { map.nodes[index].detail = newDetail }
                        content = .mindmap(map)
                        return "노드 [\(Self.handle(target.id))]을 수정했습니다."
                    }
                }
            },
        ]
    }

    // MARK: 캐릭터 프로필 편집

    private var characterTools: [AIToolHandler] {
        [
            AIToolHandler(AITool(
                name: "update_character_profile",
                description: "캐릭터 문서의 프로필을 고친다. 지정한 항목만 바뀌고 나머지는 유지된다. 필드는 같은 이름이면 덮어쓰고 없으면 추가한다.",
                properties: [
                    "document_id": .string("캐릭터 문서 ID"),
                    "role": .string("새 역할"),
                    "summary": .string("새 요약"),
                    "fields": .array("추가/수정할 필드", of: .object("필드", properties: [
                        "name": .string("항목 이름"),
                        "value": .string("값"),
                    ], required: ["name", "value"])),
                    "voice_tone": .string("새 말투"),
                    "voice_taboo": .string("새 금기"),
                    "voice_samples": .array("예시 대사 (지정하면 기존 목록을 대체)", of: .string("대사")),
                ],
                required: ["document_id"]
            )) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let role = arguments.optionalString("role")
                let summary = arguments.optionalString("summary")
                let fieldSpecs = arguments.objects("fields")
                let tone = arguments.optionalString("voice_tone")
                let taboo = arguments.optionalString("voice_taboo")
                let samples = arguments.stringArray("voice_samples")

                return try await MainActor.run {
                    try self.mutateDocument(id: id) { content in
                        guard case .page(var page) = content, var profile = page.profile else {
                            throw ToolFailure("이 문서는 캐릭터 문서가 아닙니다.")
                        }
                        var changes: [String] = []
                        if let role { profile.role = role
                            changes.append("역할")
                        }
                        if let summary { profile.summary = summary
                            changes.append("요약")
                        }

                        if !fieldSpecs.isEmpty {
                            var fields = profile.fields ?? []
                            for spec in fieldSpecs {
                                guard let name = try? spec.string("name") else { continue }
                                let value = spec.string("value", or: "")
                                if let index = fields.firstIndex(where: { $0.name == name }) {
                                    fields[index].value = value
                                } else {
                                    fields.append(CharacterField(name: name, value: value))
                                }
                            }
                            profile.fields = fields
                            changes.append("필드 \(fieldSpecs.count)개")
                        }

                        if tone != nil || taboo != nil || !samples.isEmpty {
                            var voice = profile.voice ?? CharacterVoice()
                            if let tone { voice.tone = tone }
                            if let taboo { voice.taboo = taboo }
                            if !samples.isEmpty { voice.samples = samples }
                            profile.voice = voice
                            changes.append("보이스 카드")
                        }

                        guard !changes.isEmpty else { throw ToolFailure("바꿀 항목을 하나 이상 지정하세요.") }
                        page.profile = profile
                        content = .page(page)
                        return "'\(self.documentTitle(id: id))'의 \(changes.joined(separator: ", "))을(를) 수정했습니다."
                    }
                }
            },
        ]
    }

    // MARK: 파괴적 작업 (전부 사용자 확인을 거친다)

    private var destructiveTools: [AIToolHandler] {
        [
            AIToolHandler(
                AITool(
                    name: "trash_document",
                    description: "문서를 휴지통으로 옮긴다. 사용자 확인을 거친다.",
                    properties: ["document_id": .string("문서 ID")],
                    required: ["document_id"]
                ),
                confirmationSummary: { [weak self] arguments in
                    guard let self else { return ToolError.appGone }
                    let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                    return await MainActor.run {
                        "'\(self.documentTitle(id: id))'을(를) 휴지통으로 옮깁니다."
                    }
                }
            ) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                return try await MainActor.run {
                    guard let item = self.workspace.item(id: id) else {
                        throw ToolFailure("문서를 찾을 수 없습니다: \(id.uuidString)")
                    }
                    let title = item.envelope.title
                    // 열려 있으면 탭부터 닫는다 (세션이 자동저장으로 되살리지 않도록)
                    if let tab = self.tabs.first(where: { $0.content == .document(id) }) {
                        self.closeTab(tab)
                    }
                    self.workspace.moveToTrash(item)
                    self.notify(symbol: "trash", message: "AI: '\(title)' 휴지통으로 이동")
                    return "'\(title)'을(를) 휴지통으로 옮겼습니다. 파일 아카이브의 휴지통에서 되돌릴 수 있습니다."
                }
            },

            AIToolHandler(
                AITool(
                    name: "delete_scenario_blocks",
                    description: "시나리오에서 블록을 지운다. 사용자 확인을 거친다.",
                    properties: [
                        "document_id": .string("시나리오 문서 ID"),
                        "blocks": .array("지울 블록 핸들", of: .string("핸들")),
                    ],
                    required: ["document_id", "blocks"]
                ),
                confirmationSummary: { [weak self] arguments in
                    guard let self else { return ToolError.appGone }
                    let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                    let handles = arguments.stringArray("blocks")
                    return try await MainActor.run {
                        guard case .scenario(let scenario) = try self.currentContent(id: id) else {
                            throw ToolFailure("이 문서는 시나리오가 아닙니다.")
                        }
                        // 무엇이 지워지는지 실제 대사를 보여준다 — 핸들만 보고는 판단할 수 없다.
                        let previews = handles.compactMap { text -> String? in
                            guard let block = try? Self.resolve(
                                handle: text, in: scenario.blocks, id: \.id, label: "블록"
                            ) else { return nil }
                            return "· " + block.text.prefix(40)
                        }
                        guard !previews.isEmpty else { throw ToolFailure("지울 블록을 찾을 수 없습니다.") }
                        return "'\(self.documentTitle(id: id))'에서 블록 \(previews.count)개를 지웁니다:\n"
                            + previews.joined(separator: "\n")
                    }
                }
            ) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let handles = arguments.stringArray("blocks")
                return try await MainActor.run {
                    try self.mutateDocument(id: id) { content in
                        guard case .scenario(var scenario) = content else {
                            throw ToolFailure("이 문서는 시나리오가 아닙니다.")
                        }
                        var targets: Set<UUID> = []
                        for text in handles {
                            let block = try Self.resolve(
                                handle: text, in: scenario.blocks, id: \.id, label: "블록"
                            )
                            targets.insert(block.id)
                        }
                        scenario.blocks.removeAll { targets.contains($0.id) }
                        content = .scenario(scenario)
                        return "블록 \(targets.count)개를 지웠습니다. (⌘Z로 되돌릴 수 있습니다)"
                    }
                }
            },

            AIToolHandler(
                AITool(
                    name: "delete_mindmap_nodes",
                    description: "마인드맵에서 노드를 지운다. 그 노드에 붙은 연결도 함께 사라진다. 사용자 확인을 거친다.",
                    properties: [
                        "document_id": .string("마인드맵 문서 ID"),
                        "nodes": .array("지울 노드 핸들", of: .string("핸들")),
                    ],
                    required: ["document_id", "nodes"]
                ),
                confirmationSummary: { [weak self] arguments in
                    guard let self else { return ToolError.appGone }
                    let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                    let handles = arguments.stringArray("nodes")
                    return try await MainActor.run {
                        guard case .mindmap(let map) = try self.currentContent(id: id) else {
                            throw ToolFailure("이 문서는 마인드맵이 아닙니다.")
                        }
                        let targets = handles.compactMap {
                            try? Self.resolve(handle: $0, in: map.nodes, id: \.id, label: "노드")
                        }
                        guard !targets.isEmpty else { throw ToolFailure("지울 노드를 찾을 수 없습니다.") }
                        let ids = Set(targets.map(\.id))
                        let edgeCount = map.edges.count { ids.contains($0.fromID) || ids.contains($0.toID) }
                        var summary = "'\(self.documentTitle(id: id))'에서 노드 \(targets.count)개를 지웁니다:\n"
                            + targets.map { "· \($0.title)" }.joined(separator: "\n")
                        if edgeCount > 0 { summary += "\n연결 \(edgeCount)개도 함께 사라집니다." }
                        return summary
                    }
                }
            ) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let handles = arguments.stringArray("nodes")
                return try await MainActor.run {
                    try self.mutateDocument(id: id) { content in
                        guard case .mindmap(var map) = content else {
                            throw ToolFailure("이 문서는 마인드맵이 아닙니다.")
                        }
                        var targets: Set<UUID> = []
                        for text in handles {
                            let node = try Self.resolve(handle: text, in: map.nodes, id: \.id, label: "노드")
                            targets.insert(node.id)
                        }
                        map.nodes.removeAll { targets.contains($0.id) }
                        // 매달린 연결을 남기면 에디터가 허공을 가리킨다
                        let removedEdges = map.edges.count { targets.contains($0.fromID) || targets.contains($0.toID) }
                        map.edges.removeAll { targets.contains($0.fromID) || targets.contains($0.toID) }
                        content = .mindmap(map)
                        return "노드 \(targets.count)개와 연결 \(removedEdges)개를 지웠습니다. (⌘Z로 되돌릴 수 있습니다)"
                    }
                }
            },

            AIToolHandler(
                AITool(
                    name: "replace_page",
                    description: "일반/캐릭터 문서의 본문을 통째로 새 마크다운으로 갈아엎는다. 기존 본문은 사라진다. 이어 쓰기가 목적이면 append_to_page를 써라. 사용자 확인을 거친다.",
                    properties: [
                        "document_id": .string("문서 ID"),
                        "markdown": .string("새 본문 (기존 본문을 대체)"),
                    ],
                    required: ["document_id", "markdown"]
                ),
                confirmationSummary: { [weak self] arguments in
                    guard let self else { return ToolError.appGone }
                    let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                    return try await MainActor.run {
                        guard case .page(let page) = try self.currentContent(id: id) else {
                            throw ToolFailure("이 문서는 페이지가 아닙니다.")
                        }
                        let existing = page.blocks.count { !$0.text.isEmpty }
                        return "'\(self.documentTitle(id: id))'의 본문을 통째로 교체합니다. 기존 블록 \(existing)개가 사라집니다."
                    }
                }
            ) { [weak self] arguments in
                guard let self else { return ToolError.appGone }
                let id = try Self.parseUUID(arguments.string("document_id"), key: "document_id")
                let markdown = try arguments.string("markdown")
                let blocks = PageMarkdown.import(markdown)
                guard !blocks.isEmpty else { throw ToolFailure("새 본문이 비어 있습니다.") }

                return try await MainActor.run {
                    try self.mutateDocument(id: id) { content in
                        guard case .page(var page) = content else {
                            throw ToolFailure("이 문서는 페이지가 아닙니다.")
                        }
                        page.blocks = blocks // 프로필(캐릭터)은 유지된다
                        content = .page(page)
                        return "'\(self.documentTitle(id: id))'의 본문을 블록 \(blocks.count)개로 교체했습니다. (⌘Z로 되돌릴 수 있습니다)"
                    }
                }
            },
        ]
    }

    // MARK: 헬퍼
    // 순수 함수들 — 도구 핸들러가 MainActor 밖에서도 부르므로 nonisolated로 둔다.

    nonisolated private static func makeCastMember(name: String, index: Int) -> CastMember {
        let palette = ["#5AC8FA", "#FF6482", "#63E6B6", "#FFB340", "#B18CFF", "#8E8E93"]
        return CastMember(name: name, accentHex: palette[index % palette.count])
    }

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

    /// UUID의 앞 8자 — 편집 도구가 블록/노드를 지목할 짧은 핸들.
    /// 전체 UUID를 노출하면 블록마다 36자씩 토큰을 먹는다.
    nonisolated private static func handle(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).lowercased()
    }

    /// 짧은 핸들(또는 전체 UUID)로 대상을 찾는다. 모호하면 오류 — 조용히 엉뚱한 걸
    /// 고치는 것보다 모델에게 되묻게 하는 편이 안전하다.
    nonisolated private static func resolve<T>(
        handle text: String, in items: [T], id: (T) -> UUID, label: String
    ) throws -> T {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = items.filter { id($0).uuidString.lowercased().hasPrefix(needle) }
        guard let first = matches.first else {
            throw ToolFailure("\(label) '\(text)'를 찾을 수 없습니다. read_document로 현재 핸들을 다시 확인하세요.")
        }
        guard matches.count == 1 else {
            throw ToolFailure("\(label) '\(text)'가 \(matches.count)개와 일치합니다. 더 긴 핸들을 쓰세요.")
        }
        return first
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
            // 대괄호 핸들은 편집 도구가 블록/캐스트를 지목하는 주소다.
            var lines: [String] = []
            if !scenario.cast.isEmpty {
                lines.append("등장인물: " + scenario.cast.map { "\($0.name) [\(handle($0.id))]" }
                    .joined(separator: ", "))
                lines.append("")
            }
            for block in scenario.blocks {
                let tag = "[\(handle(block.id))]"
                switch block.kind {
                case .instruction:
                    lines.append("\(tag) [지침] \(block.text)")
                case .divider:
                    lines.append("\(tag) ---")
                case .line:
                    let speaker = block.speakerIDs.first.flatMap { id in
                        scenario.cast.first { $0.id == id }?.name
                    } ?? "?"
                    lines.append("\(tag) \(speaker): \(block.text)")
                }
            }
            for branch in scenario.branches {
                lines.append("")
                lines.append("[분기: \(branch.name)] (분기는 편집 도구로 수정할 수 없습니다)")
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
                lines.append("- [\(handle(node.id))] \(node.title)"
                    + (node.detail.isEmpty ? "" : " — \(node.detail)"))
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

    // MARK: 문서 수정 공용 경로

    /// 문서를 열려 있으면 세션 경유(되돌리기 스택 + 자동저장)로, 닫혀 있으면 디스크에서
    /// 직접 수정한다. 편집 도구 전부가 이 경로를 지난다.
    private func mutateDocument(
        id: UUID,
        _ transform: (inout DocumentContent) throws -> String
    ) throws -> String {
        if let session = sessions[id] {
            var content = session.document.content
            let report = try transform(&content)
            switch (session.editor, content) {
            case (.page(let store), .page(let page)):
                store.replaceContent(page)
            case (.scenario(let store), .scenario(let scenario)):
                store.replaceContent(scenario)
            case (.mindmap(let store), .mindmap(let map)):
                store.replaceContent(map)
            default:
                throw ToolFailure("문서 종류가 맞지 않습니다.")
            }
            return report
        }

        guard let item = workspace.item(id: id) else {
            throw ToolFailure("문서를 찾을 수 없습니다: \(id.uuidString)")
        }
        guard let loaded = try? DocumentPackageIO.read(from: item.url) else {
            throw ToolFailure("문서를 읽지 못했습니다: \(item.envelope.title)")
        }
        var content = loaded.content
        let report = try transform(&content)
        let updated = LoadedDocument(
            envelope: loaded.envelope, content: content, refs: loaded.refs, url: loaded.url
        )
        do {
            _ = try DocumentPackageIO.write(updated)
        } catch {
            throw ToolFailure("저장하지 못했습니다: \(error.localizedDescription)")
        }
        workspace.scanSoon()
        return report
    }

    /// 편집 대상 문서의 현재 콘텐츠 (열려 있으면 미저장분 포함).
    private func currentContent(id: UUID) throws -> DocumentContent {
        if let session = sessions[id] { return session.document.content }
        guard let item = workspace.item(id: id) else {
            throw ToolFailure("문서를 찾을 수 없습니다: \(id.uuidString)")
        }
        guard let loaded = try? DocumentPackageIO.read(from: item.url) else {
            throw ToolFailure("문서를 읽지 못했습니다: \(item.envelope.title)")
        }
        return loaded.content
    }

    private func documentTitle(id: UUID) -> String {
        sessions[id]?.title ?? workspace.item(id: id)?.envelope.title ?? "문서"
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
