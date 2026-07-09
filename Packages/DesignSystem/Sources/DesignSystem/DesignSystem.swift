import AppCore
import SwiftUI

// MARK: - 토큰

/// GoldenGate/Tahoe Liquid Glass 디자인 언어의 단일 토큰 소스.
public enum DesignTokens {
    /// 8pt 그리드
    public enum Spacing {
        public static let unit: CGFloat = 8
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 40
    }

    public enum Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 14
        public static let large: CGFloat = 22
        public static let capsule: CGFloat = 999
    }

    /// 짧은 스프링 모션
    public enum Motion {
        public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)
        public static let gentle = Animation.spring(response: 0.45, dampingFraction: 0.86)
        public static let arrival = Animation.spring(response: 0.38, dampingFraction: 0.72)
    }
}

// MARK: - 테마

public enum ThemeMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 강조 색상: 브랜드 5종 + 시스템 + 사용자 지정.
public enum AccentChoice: Codable, Sendable, Equatable, Hashable {
    case system
    case sky, lavender, rose, amber, mint
    case custom(hex: String)

    public static let brandCases: [AccentChoice] = [.sky, .lavender, .rose, .amber, .mint]

    public var color: Color {
        switch self {
        case .system: .accentColor
        case .sky: Color(hex: "#5AC8FA")
        case .lavender: Color(hex: "#B18CFF")
        case .rose: Color(hex: "#FF6482")
        case .amber: Color(hex: "#FFB340")
        case .mint: Color(hex: "#63E6B6")
        case .custom(let hex): Color(hex: hex)
        }
    }
}

// MARK: - 색상 유틸

public extension Color {
    /// "#RRGGBB" / "RRGGBB" / "#RRGGBBAA"
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgba: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgba)
        let r, g, b, a: Double
        switch value.count {
        case 8:
            r = Double((rgba & 0xFF00_0000) >> 24) / 255
            g = Double((rgba & 0x00FF_0000) >> 16) / 255
            b = Double((rgba & 0x0000_FF00) >> 8) / 255
            a = Double(rgba & 0x0000_00FF) / 255
        default:
            r = Double((rgba & 0xFF0000) >> 16) / 255
            g = Double((rgba & 0x00FF00) >> 8) / 255
            b = Double(rgba & 0x0000FF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - 품질 환경

private struct RenderQualityKey: EnvironmentKey {
    static let defaultValue: RenderQuality = .standard
}

private struct ContentFontScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

private struct ContentLineSpacingKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

private struct ContentBlockSpacingKey: EnvironmentKey {
    static let defaultValue: Double = 7.0
}

private struct DialogueDisplayStyleKey: EnvironmentKey {
    static let defaultValue: String = "avatarAndName"
}

private struct DialogueAvatarSizeKey: EnvironmentKey {
    static let defaultValue: Double = 34.0
}

public extension EnvironmentValues {
    var renderQuality: RenderQuality {
        get { self[RenderQualityKey.self] }
        set { self[RenderQualityKey.self] = newValue }
    }

    /// 설정 > 텍스트의 글자 크기 배율 (에디터 본문에 적용)
    var contentFontScale: Double {
        get { self[ContentFontScaleKey.self] }
        set { self[ContentFontScaleKey.self] = newValue }
    }

    /// 설정 > 텍스트의 줄 간격 배율
    var contentLineSpacing: Double {
        get { self[ContentLineSpacingKey.self] }
        set { self[ContentLineSpacingKey.self] = newValue }
    }

    /// 설정 > 텍스트의 블록 간 간격 (pt) — 페이지·시나리오 에디터 공용
    var contentBlockSpacing: Double {
        get { self[ContentBlockSpacingKey.self] }
        set { self[ContentBlockSpacingKey.self] = newValue }
    }

    /// 설정 > 에디터의 시나리오 대사 블록 캐릭터 표시 방식
    /// "avatarAndName" | "avatarOnly" | "nameOnly" | "hidden"
    var dialogueDisplayStyle: String {
        get { self[DialogueDisplayStyleKey.self] }
        set { self[DialogueDisplayStyleKey.self] = newValue }
    }

    /// 설정 > 에디터의 시나리오 대사 블록 캐릭터 프로필(아바타) 크기 (pt)
    var dialogueAvatarSize: Double {
        get { self[DialogueAvatarSizeKey.self] }
        set { self[DialogueAvatarSizeKey.self] = newValue }
    }
}

public extension View {
    /// 줄 간격 배율(1.0 = 기본)을 포인트 간격으로 변환해 적용.
    func contentLineSpacing(_ scale: Double) -> some View {
        lineSpacing(max(0, (scale - 1.0) * 9))
    }
}

// MARK: - Liquid Glass 표면

private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass: Glass = .regular
    if let tint { glass = glass.tint(tint.opacity(0.35)) }
    if interactive { glass = glass.interactive() }
    return glass
}

/// 품질/테마 인지형 표면. Low 품질 또는 'Liquid Glass 끄기(베타)'에서는 평면 표면으로 대체.
private struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let quality: RenderQuality

    @Environment(\.liquidGlassDisabled) private var glassDisabled
    @Environment(\.interfaceTheme) private var theme

    func body(content: Content) -> some View {
        if glassDisabled {
            // 레트로 미니멀: 불투명 표면 + 얇은 잉크 테두리
            content
                .background(shape.fill(flatFill))
                .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
        } else if quality == .low {
            content.background(shape.fill(.regularMaterial))
        } else {
            content.glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        }
    }

    private var flatFill: Color {
        if let tint { return tint.opacity(0.16) }
        return theme == .sonnet ? SonnetPalette.surface : Color.primary.opacity(0.05)
    }

    private var borderColor: Color {
        theme == .sonnet ? SonnetPalette.ink.opacity(0.16) : Color.primary.opacity(0.12)
    }
}

public extension View {
    /// 품질 단계 인지형 유리 표면. Low/글래스 끔에서는 평면 표면으로 대체된다.
    func glassSurface(
        cornerRadius: CGFloat = DesignTokens.Radius.medium,
        tint: Color? = nil,
        interactive: Bool = false,
        quality: RenderQuality = .standard
    ) -> some View {
        modifier(SurfaceModifier(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            tint: tint, interactive: interactive, quality: quality
        ))
    }

    /// 캡슐형 유리 표면.
    func glassCapsule(
        tint: Color? = nil,
        interactive: Bool = false,
        quality: RenderQuality = .standard
    ) -> some View {
        modifier(SurfaceModifier(
            shape: Capsule(), tint: tint, interactive: interactive, quality: quality
        ))
    }
}

// MARK: - 카드형 모션 (호버 리프트 + 눌림)

/// 카드형 버튼 공통 모션 — 호버 시 살짝 떠오르며 그림자, 클릭 시 눌림.
/// GitHub/Figma의 카드 인터랙션 패턴 참고: 정지 상태와 호버 상태의 차이를 그림자 깊이로 표현.
public struct LiftButtonStyle: ButtonStyle {
    var hoverScale: CGFloat
    var pressScale: CGFloat

    public init(hoverScale: CGFloat = 1.03, pressScale: CGFloat = 0.97) {
        self.hoverScale = hoverScale
        self.pressScale = pressScale
    }

    public func makeBody(configuration: Configuration) -> some View {
        LiftButtonBody(configuration: configuration, hoverScale: hoverScale, pressScale: pressScale)
    }

    private struct LiftButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let hoverScale: CGFloat
        let pressScale: CGFloat
        @State private var hovering = false

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? pressScale : (hovering ? hoverScale : 1))
                .shadow(
                    color: .black.opacity(hovering && !configuration.isPressed ? 0.14 : 0),
                    radius: hovering ? 10 : 0,
                    y: hovering ? 4 : 0
                )
                .onHover { hovering = $0 }
                .animation(DesignTokens.Motion.snappy, value: hovering)
                .animation(DesignTokens.Motion.snappy, value: configuration.isPressed)
        }
    }
}

// MARK: - 저장 상태 배지

/// 색상 배지 저장 버튼 상태 — 빨강 미저장 / 노랑 오류 / 하늘 저장중·자동 / 초록 수동 저장.
public enum SaveState: Sendable, Equatable {
    case unsaved
    case saving
    case savedAuto
    case savedManual
    case error

    public var color: Color {
        switch self {
        case .unsaved: Color(hex: "#FF5B5B")
        case .saving, .savedAuto: Color(hex: "#5AC8FA")
        case .savedManual: Color(hex: "#4CD97B")
        case .error: Color(hex: "#FFC53D")
        }
    }

    public var labelKey: L10nKey {
        switch self {
        case .unsaved: .saveStateUnsaved
        case .saving: .saveStateSaving
        case .savedAuto, .savedManual: .saveStateSaved
        case .error: .saveStateError
        }
    }
}

public struct SaveStatusBadge: View {
    let state: SaveState
    let label: String
    let action: () -> Void

    @State private var pulse = false

    public init(state: SaveState, label: String, action: @escaping () -> Void) {
        self.state = state
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(state.color)
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulse ? 1.7 : 1)
                    .shadow(color: state.color.opacity(0.8), radius: 3)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textStateSwap()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .textSelection(.disabled)
        .animation(DesignTokens.Motion.snappy, value: state)
        .help(label)
        .onChange(of: state) {
            // 상태가 바뀔 때마다 도트가 짧게 튀는 하이라이트 (GitHub 상태 배지 참고)
            withAnimation(DesignTokens.Motion.snappy) { pulse = true }
            Task {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(DesignTokens.Motion.snappy) { pulse = false }
            }
        }
    }
}

// MARK: - 모션 이펙트

/// Error State Shake — 빈 입력 전송 시도 등 오류 피드백.
public struct ShakeEffect: GeometryEffect {
    public var travel: CGFloat = 7
    public var shakesPerUnit: CGFloat = 3
    public var animatableData: CGFloat

    public init(animatableData: CGFloat) {
        self.animatableData = animatableData
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * shakesPerUnit * 2),
            y: 0
        ))
    }
}

public extension View {
    /// Text State Swap — 텍스트 변경 시 부드러운 전환.
    func textStateSwap() -> some View {
        contentTransition(.opacity)
    }
}

// MARK: - 공용 크롬 컴포넌트

/// 경로 브레드크럼.
public struct BreadcrumbView: View {
    let components: [String]

    public init(_ components: [String]) {
        self.components = components
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, name in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(name)
                    .font(.caption)
                    .foregroundStyle(index == components.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .textSelection(.disabled)
    }
}

/// 캡슐 검색 필드.
public struct SearchCapsule: View {
    @Binding var text: String
    let placeholder: String
    let quality: RenderQuality

    public init(text: Binding<String>, placeholder: String, quality: RenderQuality = .standard) {
        self._text = text
        self.placeholder = placeholder
        self.quality = quality
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassCapsule(quality: quality)
        .frame(maxWidth: 220)
    }
}

/// 툴바 아이콘 버튼 (호버 하이라이팅).
public struct ToolbarIconButton: View {
    let systemName: String
    let help: String
    var isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    public init(_ systemName: String, help: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : (hovering ? Color.accentColor : .secondary))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.14) : (hovering ? Color.accentColor.opacity(0.1) : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.snappy, value: hovering)
        .help(help)
    }
}
