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

    var body: some View {
        let l10n = Localizer.shared
        let chat = app.aiChat
        VStack(spacing: 0) {
            // 헤더 — 살아 있는 미니 스피어가 Sonnet AI의 아이덴티티 (생성 중엔 더 빠르게 요동)
            HStack(spacing: DesignTokens.Spacing.s) {
                AISphere(size: 18, activity: chat.isBusy ? .thinking : .idle)
                Text(l10n.t(.aiAgent))
                    .font(.headline)
                Spacer()
                if !chat.messages.isEmpty {
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
                        if chat.messages.isEmpty {
                            emptyHint(l10n)
                        }
                        ForEach(chat.messages) { message in
                            ChatBubble(message: message, fontFamily: fontFamily)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        if chat.isBusy {
                            HStack(spacing: 8) {
                                AISphere(size: 22, activity: .thinking)
                                Text(l10n.t(.aiSuggesting))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, DesignTokens.Spacing.l)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.vertical, DesignTokens.Spacing.m)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                    .animation(DesignTokens.Motion.arrival, value: chat.messages.count)
                }
                .onChange(of: chat.messages.count) {
                    if let last = chat.messages.last {
                        withAnimation(DesignTokens.Motion.arrival) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // 입력
            HStack(spacing: DesignTokens.Spacing.s) {
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

    private func send() {
        guard canSend else { return }
        let provider = app.currentProvider()
        Task { await app.aiChat.send(using: provider) }
    }

    private func emptyHint(_ l10n: Localizer) -> some View {
        VStack(spacing: DesignTokens.Spacing.l) {
            // 대화가 비었을 때의 히어로 — 유영하는 AI 스피어
            AISphere(size: 116)
            Text(l10n.t(.askAnything))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 70)
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
            HStack {
                Label(l10n.t(.aiAgent), systemImage: "sparkles")
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

            ForEach(chat.messages.suffix(maxMessages)) { message in
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

            HStack(spacing: 4) {
                TextField(l10n.t(.askAnything), text: Binding(
                    get: { chat.input },
                    set: { chat.input = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.caption)
                .onSubmit {
                    let provider = app.currentProvider()
                    Task { await chat.send(using: provider) }
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
