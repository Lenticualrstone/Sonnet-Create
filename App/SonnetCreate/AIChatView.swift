import AIAgentKit
import AppCore
import DesignSystem
import SwiftUI

/// AI 에이전트 채팅 — 전용 탭과 플로팅 패널(compact)이 공유하는 본체.
struct AIChatView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.contentFontFamily) private var fontFamily
    @Environment(\.resolvedAccent) private var accent

    /// 플로팅 패널 모드 — 히어로를 줄이고 여백을 좁힌다.
    var compact = false

    @FocusState private var inputFocused: Bool
    @State private var confirmClear = false
    /// 현재 제공자의 연결 상태 문제 (nil = 정상)
    @State private var availabilityIssue: String?

    /// 진행 중 응답/도구 영역의 스크롤 앵커 — 메시지 ID가 아직 없는 구간을 따라가기 위한 것.
    private static let streamingAnchor = "streaming-anchor"

    var body: some View {
        let l10n = Localizer.shared
        let chat = app.aiChat
        VStack(spacing: 0) {
            header(l10n)
            Divider().opacity(0.4)

            if let issue = availabilityIssue {
                providerBanner(l10n, issue: issue)
            }

            messageList(l10n, chat: chat)
            inputBar(l10n, chat: chat)
        }
        .onAppear { inputFocused = true }
        // 제공자를 바꾸거나 화면에 들어올 때 연결 상태를 확인해 미리 알려준다 —
        // 보내고 나서야 실패를 아는 것보다 낫다.
        .task(id: app.settings.applied.aiProviderRaw) {
            let provider = app.currentProvider()
            if case .unavailable(let reason) = await provider.availability() {
                availabilityIssue = reason
            } else {
                availabilityIssue = nil
            }
        }
        // 파괴적 작업은 실행 전에 멈춰 서서 묻는다 — 에이전트가 조용히 지우는 일은 없다.
        .sheet(item: Binding(
            get: { app.aiChat.pendingConfirmation },
            set: { if $0 == nil { app.aiChat.answerConfirmation(approved: false) } }
        )) { pending in
            ToolConfirmationSheet(pending: pending) { approved in
                app.aiChat.answerConfirmation(approved: approved)
            }
        }
        .confirmationDialog(l10n.t(.clearChat), isPresented: $confirmClear) {
            Button(l10n.t(.clearChat), role: .destructive) { app.aiChat.clear() }
            Button(l10n.t(.cancel), role: .cancel) {}
        } message: {
            Text(l10n.t(.clearChatConfirm))
        }
    }

    // MARK: 헤더 — 정체성 + 작업 문서 칩 + 모델 선택

    private func header(_ l10n: Localizer) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            AISphere(size: 18, activity: sphereActivity)
            Text(agentDisplayName)
                .font(.headline)

            // 에이전트가 "지금 어느 문서를 대상으로 일하는지" — 암묵이 아니라 화면에 명시한다.
            if let session = app.chatContextSession {
                HStack(spacing: 4) {
                    Image(systemName: session.document.envelope.kind.symbolName)
                        .font(.caption2)
                    Text(session.title.isEmpty ? l10n.t(.untitled) : session.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(accent.opacity(0.1)))
                .help("\(l10n.t(.agentWorkingDoc)): \(session.title) — '이 문서'가 가리키는 대상")
            }

            Spacer()

            providerMenu(l10n)

            if !app.aiChat.displayMessages.isEmpty {
                Button(l10n.t(.clearChat)) { confirmClear = true }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
    }

    private var agentDisplayName: String {
        let name = app.settings.applied.agentName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? Localizer.shared.t(.sonnetAI) : name
    }

    /// 대화 중 프로바이더/모델 즉시 전환 — 설정 창을 오갈 필요가 없다.
    private func providerMenu(_ l10n: Localizer) -> some View {
        let current = AIProviderKind(rawValue: app.settings.applied.aiProviderRaw) ?? .offline
        return Menu {
            Section(l10n.t(.aiProvider)) {
                providerButton(.offline, l10n.t(.aiProviderMock), current: current)
                providerButton(.appleOnDevice, l10n.t(.aiProviderApple), current: current)
                Divider()
                ForEach([AIProviderKind.anthropic, .openai, .gemini, .grok]) { kind in
                    providerButton(kind, kind.displayName, current: current)
                }
            }
            if current.requiresAPIKey {
                Section(l10n.t(.aiModel)) {
                    modelButton("", label: "\(l10n.t(.aiModelDefault)) (\(current.defaultModel))", current: current)
                    ForEach(current.suggestedModels, id: \.self) { model in
                        modelButton(model, label: model, current: current)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(availabilityIssue == nil ? SonnetPalette.sage : Color.orange)
                    .frame(width: 6, height: 6)
                Text(currentModelLabel(current))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(l10n.t(.aiProvider))
    }

    private func currentModelLabel(_ kind: AIProviderKind) -> String {
        guard kind.requiresAPIKey else { return kind.displayName }
        let model = currentModel(of: kind)
        return model.isEmpty ? "\(kind.displayName) · \(kind.defaultModel)" : "\(kind.displayName) · \(model)"
    }

    private func currentModel(of kind: AIProviderKind) -> String {
        let applied = app.settings.applied
        return switch kind {
        case .anthropic: applied.anthropicModel
        case .openai: applied.openaiModel
        case .gemini: applied.geminiModel
        case .grok: applied.grokModel
        case .appleOnDevice, .offline: ""
        }
    }

    private func providerButton(_ kind: AIProviderKind, _ label: String, current: AIProviderKind) -> some View {
        Button {
            // draft 저장 절차 없이 즉시 적용 — 대화 흐름을 끊지 않는다.
            app.settings.applyField { $0.aiProviderRaw = kind.rawValue }
        } label: {
            if kind == current {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    private func modelButton(_ model: String, label: String, current: AIProviderKind) -> some View {
        Button {
            app.settings.applyField { settings in
                switch current {
                case .anthropic: settings.anthropicModel = model
                case .openai: settings.openaiModel = model
                case .gemini: settings.geminiModel = model
                case .grok: settings.grokModel = model
                case .appleOnDevice, .offline: break
                }
            }
        } label: {
            if currentModel(of: current) == model {
                Label(label, systemImage: "checkmark")
            } else {
                Text(label)
            }
        }
    }

    /// 미연결 안내 — 신규 사용자가 "왜 답이 이상하지"를 반복하기 전에 알려준다.
    private func providerBanner(_ l10n: Localizer, issue: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "bolt.slash")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t(.aiNotConnected))
                    .font(.caption.weight(.semibold))
                Text(issue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(l10n.t(.openSettings)) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: 메시지 목록

    private func messageList(_ l10n: Localizer, chat: AIChatStore) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.m) {
                    if chat.displayMessages.isEmpty, !chat.isBusy {
                        emptyHint(l10n)
                    }
                    ForEach(chat.displayMessages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            ChatBubble(message: message, fontFamily: fontFamily)
                            // 그 턴에 실행한 도구 — 히스토리에서 파생하므로 대화가 끝나도 남는다.
                            let history = chat.activities(for: message.id)
                            if !history.isEmpty {
                                toolChips(history)
                            }
                        }
                        .id(message.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    // 진행 중인 턴: 도구 호출 '이전'에 끝난 말 조각들 (별도 말풍선)
                    ForEach(Array(chat.streamingSegments.enumerated()), id: \.offset) { _, segment in
                        ChatBubble(
                            message: AIChatMessage(role: .assistant, text: segment),
                            fontFamily: fontFamily
                        )
                    }

                    // 이번 턴에 실행 중인/실행된 앱 기능
                    if !chat.toolActivity.isEmpty {
                        toolChips(chat.toolActivity)
                            .padding(.horizontal, DesignTokens.Spacing.l)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // 진행 중인 응답 — 완료되면 messages로 흡수된다
                    if !chat.streamingText.isEmpty {
                        ChatBubble(
                            message: AIChatMessage(role: .assistant, text: chat.streamingText),
                            fontFamily: fontFamily
                        )
                        .id(Self.streamingAnchor)
                    }

                    if (chat.isBusy && chat.streamingText.isEmpty) || app.isComposingDocument {
                        HStack(spacing: 8) {
                            AISphere(size: 22, activity: .thinking)
                            Text(l10n.t(app.isComposingDocument ? .aiComposeCreating : .aiSuggesting))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            PulseDotsIndicator(dotSize: 4)
                            Spacer()
                        }
                        .padding(.horizontal, DesignTokens.Spacing.l)
                        .id(Self.streamingAnchor)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.m)
                .frame(maxWidth: compact ? .infinity : 680)
                .frame(maxWidth: .infinity)
                .animation(DesignTokens.Motion.arrival, value: chat.displayMessages.count)
                .animation(DesignTokens.Motion.snappy, value: chat.toolActivity)
            }
            .onChange(of: chat.displayMessages.count) {
                if let last = chat.displayMessages.last {
                    withAnimation(DesignTokens.Motion.arrival) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            // 응답이 자라는 동안, 도구가 실행되는 동안 하단을 계속 따라간다
            .onChange(of: chat.streamingText) { proxy.scrollTo(Self.streamingAnchor, anchor: .bottom) }
            .onChange(of: chat.toolActivity) { proxy.scrollTo(Self.streamingAnchor, anchor: .bottom) }
        }
    }

    private func toolChips(_ activities: [ToolActivity]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(activities) { activity in
                ToolActivityChip(activity: activity)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, DesignTokens.Spacing.l)
    }

    // MARK: 입력

    private func inputBar(_ l10n: Localizer, chat: AIChatStore) -> some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            // 에이전트 액션 — 입력한 브리프로 문서를 통째로 생성한다.
            Menu {
                Section(l10n.t(.aiComposePrompt)) {
                    composeButton(.page, l10n.t(.aiComposeDocument), symbol: "doc.richtext")
                    composeButton(.character, l10n.t(.aiComposeCharacter), symbol: "person.crop.circle.badge.plus")
                    composeButton(.mindmap, l10n.t(.aiComposeMindmap), symbol: "point.3.connected.trianglepath.dotted")
                    composeButton(.scenario, l10n.t(.aiComposeScenario), symbol: "text.bubble")
                }
            } label: {
                Image(systemName: app.isComposingDocument ? "hourglass" : "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(canCompose ? accent : Color.secondary.opacity(0.5))
                    .symbolEffect(.pulse, isActive: app.isComposingDocument)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!canCompose)
            .help(l10n.t(.aiComposePrompt))

            TextField(l10n.t(.askAnything), text: bindingInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    send()
                    return .handled
                }

            if chat.isBusy {
                // 진행 중엔 전송 대신 중단 — 8회 도구 루프를 하염없이 기다리지 않아도 된다.
                Button {
                    chat.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.orange))
                }
                .buttonStyle(.plain)
                .help(l10n.t(.stopGenerating))
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(accent.opacity(canSend ? 1 : 0.3)))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, 10)
        .glassSurface(cornerRadius: DesignTokens.Radius.large, interactive: true, quality: quality)
        .frame(maxWidth: compact ? .infinity : 680)
        .padding(.horizontal, compact ? DesignTokens.Spacing.s : DesignTokens.Spacing.l)
        .padding(.bottom, compact ? DesignTokens.Spacing.s : DesignTokens.Spacing.m)
    }

    private var bindingInput: Binding<String> {
        Binding(
            get: { app.aiChat.input },
            set: { app.aiChat.input = $0 }
        )
    }

    private var canSend: Bool {
        !app.aiChat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !app.aiChat.isBusy
            && !app.isComposingDocument // 컴포즈 결과 note가 진행 중 턴에 덮이지 않게 상호배제
    }

    private var canCompose: Bool {
        !app.aiChat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !app.isComposingDocument
            && !app.aiChat.isBusy // 채팅 턴 종료 시 messages 교체가 컴포즈 기록을 지우지 않게
    }

    /// 컴포즈 메뉴 항목 — 현재 입력을 브리프로 소비해 문서를 생성한다.
    private func composeButton(_ kind: AIComposeKind, _ title: String, symbol: String) -> some View {
        Button {
            let brief = app.aiChat.input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !brief.isEmpty else { return }
            app.aiChat.input = ""
            app.aiChat.note(role: .user, text: "\(title): \(brief)")
            Task {
                if let failure = await app.composeDocument(kind: kind, brief: brief) {
                    app.aiChat.note(role: .assistant, text: "⚠️ \(failure)")
                }
            }
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    /// 스피어 활동 — 생성 중 > 입력 중(포커스+내용) > 평온.
    private var sphereActivity: AISphere.Activity {
        if app.aiChat.isBusy || app.isComposingDocument { return .thinking }
        if inputFocused, !app.aiChat.input.isEmpty { return .typing }
        return .idle
    }

    private func send() {
        guard canSend else { return }
        app.aiChat.submit(using: app.makeAgentRunner())
    }

    private func emptyHint(_ l10n: Localizer) -> some View {
        VStack(spacing: DesignTokens.Spacing.l) {
            // 대화가 비었을 때의 히어로 — 유영하는 AI 스피어 (입력 시작하면 동요)
            AISphere(size: compact ? 56 : 116, activity: sphereActivity)
            Text(l10n.t(.askAnything))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, compact ? 24 : 70)
    }
}

/// 파괴적 작업 승인 시트 — 무엇이 사라지는지 먼저 보여주고 묻는다.
struct ToolConfirmationSheet: View {
    let pending: AIChatStore.PendingConfirmation
    let respond: (Bool) -> Void

    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("에이전트가 이 작업을 하려고 합니다")
                    .font(.headline)
            }

            Text(pending.summary)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

            HStack {
                Spacer()
                Button("취소") { respond(false) }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("실행") { respond(true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.l)
        .frame(width: 380)
    }
}

/// 에이전트가 앱 기능을 실행 중임을 보여주는 칩 — 무슨 일이 일어나는지 감추지 않는다.
/// 클릭하면 실행 결과/실패 사유가 펼쳐진다.
struct ToolActivityChip: View {
    let activity: ToolActivity

    @Environment(\.resolvedAccent) private var accent
    @State private var expanded = false

    /// 도구 이름을 사용자 표현으로 — 모르는 이름은 그대로 노출한다 (새 도구가 붙어도 깨지지 않게).
    private var label: String {
        switch activity.name {
        case "list_projects": "프로젝트 목록 확인"
        case "list_documents": "문서 목록 확인"
        case "search_documents": "문서 검색"
        case "read_document": "문서 읽기"
        case "get_open_document": "열린 문서 확인"
        case "create_project": "프로젝트 생성"
        case "create_page": "문서 작성"
        case "create_character": "캐릭터 문서 작성"
        case "create_mindmap": "마인드맵 작성"
        case "create_scenario": "시나리오 작성"
        case "append_to_page": "문서에 이어 쓰기"
        case "rename_document": "문서 이름 변경"
        case "add_scenario_blocks": "시나리오에 블록 추가"
        case "update_scenario_block": "대사 수정"
        case "add_mindmap_nodes": "마인드맵에 노드 추가"
        case "update_mindmap_node": "노드 수정"
        case "update_character_profile": "캐릭터 프로필 수정"
        case "trash_document": "문서 휴지통으로 이동"
        case "delete_scenario_blocks": "시나리오 블록 삭제"
        case "delete_mindmap_nodes": "마인드맵 노드 삭제"
        case "replace_page": "문서 본문 교체"
        default: activity.name
        }
    }

    /// 되돌리기 어려운 작업은 칩에서도 다르게 보이게 한다.
    private var isDestructive: Bool {
        ["trash_document", "delete_scenario_blocks", "delete_mindmap_nodes", "replace_page"]
            .contains(activity.name)
    }

    private var symbol: String {
        if activity.isRunning { return isDestructive ? "exclamationmark.triangle" : "gearshape.2" }
        return activity.isError ? "exclamationmark.triangle" : "checkmark.circle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard !activity.detail.isEmpty else { return }
                withAnimation(DesignTokens.Motion.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(activity.isError ? Color.orange : SonnetPalette.pine)
                        .symbolEffect(.rotate, isActive: activity.isRunning)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(activity.isError ? Color.orange : SonnetPalette.pine)
                    if activity.isRunning {
                        PulseDotsIndicator(dotSize: 3)
                    } else if !activity.detail.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    // 도구 칩은 먹록(Pine) — 인장은 행동 버튼에만 아낀다 (4d)
                    Capsule().fill(activity.isError ? Color.orange.opacity(0.1) : SonnetPalette.pine.opacity(0.12))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(activity.detail.isEmpty ? label : activity.detail)

            // 결과/실패 사유 — 최종 답변 텍스트에 의존하지 않고 직접 확인할 수 있다.
            if expanded, !activity.detail.isEmpty {
                Text(activity.detail)
                    .font(.caption2)
                    .foregroundStyle(activity.isError ? Color.orange : Color.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

/// 채팅 말풍선 — 사용자: 우측 액센트 / 보조: 좌측 표면 / 오류: 주황 톤.
struct ChatBubble: View {
    let message: AIChatMessage
    let fontFamily: FontFamily

    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    /// 오류 안내("⚠️ …")는 일반 응답과 시각적으로 구분한다.
    private var isErrorNote: Bool {
        message.role == .assistant && message.text.hasPrefix("⚠️")
    }

    /// 말풍선 모양 — 사용자는 우하단, 보조는 좌하단 꼬리각 (4d).
    private var bubbleShape: UnevenRoundedRectangle {
        message.role == .user
            ? UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 14,
                bottomTrailingRadius: 4, topTrailingRadius: 14, style: .continuous
            )
            : UnevenRoundedRectangle(
                topLeadingRadius: 14, bottomLeadingRadius: 4,
                bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous
            )
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            Text(markdownText)
                .font(DSFonts.font(size: 13, family: fontFamily))
                .lineSpacing(4)
                .foregroundStyle(
                    message.role == .user && !isErrorNote
                        ? SonnetPalette.canvas
                        : SonnetPalette.ink
                )
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleShape.fill(bubbleFill))
                .overlay {
                    if isErrorNote {
                        bubbleShape.strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    } else if message.role == .assistant {
                        bubbleShape.strokeBorder(SonnetPalette.ink.opacity(0.08), lineWidth: 1)
                    }
                }
                .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
    }

    private var bubbleFill: AnyShapeStyle {
        if isErrorNote { return AnyShapeStyle(Color.orange.opacity(0.08)) }
        return message.role == .user
            ? AnyShapeStyle(SonnetPalette.ink)
            : AnyShapeStyle(SonnetPalette.surface)
    }

    private var markdownText: AttributedString {
        (try? AttributedString(
            markdown: message.text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
    }
}

/// 사이드패널 미니 챗 — 최근 대화 + 빠른 입력 + 탭으로 확장.
struct SidebarAIChatSection: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent
    var maxMessages = 3

    var body: some View {
        let l10n = Localizer.shared
        let chat = app.aiChat
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                AISphere(size: 14, activity: chat.isBusy ? .thinking : (chat.input.isEmpty ? .idle : .typing))
                Text(l10n.t(.sonnetAI))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    app.openAIChatTab()
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(l10n.t(.openAsTab))
            }

            ForEach(chat.displayMessages.suffix(maxMessages)) { message in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                        .font(.system(size: 8))
                        .foregroundStyle(message.role == .user ? Color.secondary : accent)
                        .padding(.top, 2)
                    Text(message.text)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(message.role == .user ? .secondary : .primary)
                }
            }
            // 실행 중인 도구가 있으면 사이드바에서도 보이게
            if let running = chat.toolActivity.last(where: \.isRunning) {
                ToolActivityChip(activity: running)
            }

            HStack(spacing: 4) {
                TextField(l10n.t(.askAnything), text: Binding(
                    get: { chat.input },
                    set: { chat.input = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.caption)
                .onSubmit {
                    chat.submit(using: app.makeAgentRunner())
                }
                if chat.isBusy {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }
}
