import AIAgentKit
import AppCore
import DesignSystem
import SwiftUI

/// AI 에이전트 채팅 — 전용 탭 뷰.
struct AIChatView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.contentFontFamily) private var fontFamily
    @Environment(\.resolvedAccent) private var accent

    @FocusState private var inputFocused: Bool

    /// 진행 중 응답/도구 영역의 스크롤 앵커 — 메시지 ID가 아직 없는 구간을 따라가기 위한 것.
    private static let streamingAnchor = "streaming-anchor"

    var body: some View {
        let l10n = Localizer.shared
        let chat = app.aiChat
        VStack(spacing: 0) {
            // 헤더 — 살아 있는 미니 스피어가 Sonnet AI의 아이덴티티.
            // 입력 중엔 미세 동요(typing), 생성 중엔 크게 요동(thinking).
            HStack(spacing: DesignTokens.Spacing.s) {
                AISphere(size: 18, activity: sphereActivity)
                Text(l10n.t(.aiAgent))
                    .font(.headline)
                Spacer()
                if !chat.displayMessages.isEmpty {
                    Button(l10n.t(.clearChat)) { chat.clear() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, DesignTokens.Spacing.s)
            Divider().opacity(0.4)

            // 메시지
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.m) {
                        if chat.displayMessages.isEmpty, !chat.isBusy {
                            emptyHint(l10n)
                        }
                        ForEach(chat.displayMessages) { message in
                            ChatBubble(message: message, fontFamily: fontFamily)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        // 이번 턴에 에이전트가 실행 중인/실행한 앱 기능
                        if !chat.toolActivity.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(chat.toolActivity) { activity in
                                    ToolActivityChip(activity: activity)
                                }
                            }
                            .frame(maxWidth: 520, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .frame(maxWidth: 680)
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

            // 입력
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
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: DesignTokens.Radius.large, interactive: true, quality: quality)
            .frame(maxWidth: 680)
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.bottom, DesignTokens.Spacing.m)
        }
        .onAppear { inputFocused = true }
    }

    private var bindingInput: Binding<String> {
        Binding(
            get: { app.aiChat.input },
            set: { app.aiChat.input = $0 }
        )
    }

    private var canSend: Bool {
        !app.aiChat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !app.aiChat.isBusy
    }

    private var canCompose: Bool {
        !app.aiChat.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !app.isComposingDocument
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
        let runner = app.makeAgentRunner()
        Task { await app.aiChat.send(using: runner) }
    }

    private func emptyHint(_ l10n: Localizer) -> some View {
        VStack(spacing: DesignTokens.Spacing.l) {
            // 대화가 비었을 때의 히어로 — 유영하는 AI 스피어 (입력 시작하면 동요)
            AISphere(size: 116, activity: sphereActivity)
            Text(l10n.t(.askAnything))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 70)
    }
}

/// 에이전트가 앱 기능을 실행 중임을 보여주는 칩 — 무슨 일이 일어나는지 감추지 않는다.
struct ToolActivityChip: View {
    let activity: ToolActivity

    @Environment(\.resolvedAccent) private var accent

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
        default: activity.name
        }
    }

    private var symbol: String {
        if activity.isRunning { return "gearshape.2" }
        return activity.isError ? "exclamationmark.triangle" : "checkmark.circle"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(activity.isError ? Color.orange : accent)
                .symbolEffect(.rotate, isActive: activity.isRunning)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            if activity.isRunning {
                PulseDotsIndicator(dotSize: 3)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(activity.isError ? Color.orange.opacity(0.1) : accent.opacity(0.08))
        )
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

/// 채팅 말풍선 — 사용자: 우측 액센트 / 보조: 좌측 표면.
struct ChatBubble: View {
    let message: AIChatMessage
    let fontFamily: FontFamily

    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            Text(markdownText)
                .font(DSFonts.font(size: 13, family: fontFamily))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                        .fill(
                            message.role == .user
                                ? AnyShapeStyle(accent.opacity(0.16))
                                : AnyShapeStyle(SonnetPalette.surface)
                        )
                )
                .frame(maxWidth: 520, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
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
                Text(l10n.t(.aiAgent))
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
                    let runner = app.makeAgentRunner()
                    Task { await chat.send(using: runner) }
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
