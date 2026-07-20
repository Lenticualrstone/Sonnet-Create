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

    /// 모션 스펙 — 곡선과 역할 (디자인 브리프 1a).
    public enum Motion {
        /// Rise — 진입. 홈 계단식 등장, 카드·리스트. y+14→0 + fade, 스태거 45ms.
        public static let rise = Animation.timingCurve(0.22, 0.9, 0.24, 1, duration: 0.36)
        /// Rise 스태거 간격 (초)
        public static let riseStagger: Double = 0.045
        /// Glass pop — 패널 진입. ⌘K·AI 패널·팝오버. scale .94→1, 오버슈트 6%.
        public static let glassPop = Animation.timingCurve(0.34, 1.26, 0.4, 1, duration: 0.28)
        /// Glass pop 닫힘 — 180ms ease-in.
        public static let glassPopOut = Animation.easeIn(duration: 0.18)
        /// Press — 버튼 피드백. scale .96, 복귀는 스프링.
        public static let press = Animation.easeOut(duration: 0.12)
        /// Press 복귀 스프링 (response .3 · damping .7)
        public static let pressRelease = Animation.spring(response: 0.3, dampingFraction: 0.7)
        /// Ink flow — 진행 바. 초반 가속·말미 감속.
        public static let inkFlow = Animation.timingCurve(0.4, 0.1, 0.3, 1, duration: 0.6)

        // 레거시 별칭 — 기존 호출부를 새 곡선으로 흘려보낸다.
        public static let snappy = glassPop
        public static let gentle = rise
        public static let arrival = rise
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

private struct PageFocusModeKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PageTypewriterModeKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MindmapAutoOpenInspectorKey: EnvironmentKey {
    static let defaultValue = true
}

private struct MotionReducedKey: EnvironmentKey {
    static let defaultValue = false
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

    /// 설정 > 페이지: 포커스 모드 — 편집 중 블록 외 디밍
    var pageFocusMode: Bool {
        get { self[PageFocusModeKey.self] }
        set { self[PageFocusModeKey.self] = newValue }
    }

    /// 설정 > 페이지: 타자기 모드 — 편집 중 블록을 화면 중앙에 유지
    var pageTypewriterMode: Bool {
        get { self[PageTypewriterModeKey.self] }
        set { self[PageTypewriterModeKey.self] = newValue }
    }

    /// 설정 > 마인드맵: 노드 선택 시 인스펙터 자동 표시
    var mindmapAutoOpenInspector: Bool {
        get { self[MindmapAutoOpenInspectorKey.self] }
        set { self[MindmapAutoOpenInspectorKey.self] = newValue }
    }

    /// 모션 줄이기 실효값 — 시스템 손쉬운 사용(동작 줄이기) 또는 앱 설정이 켜지면 참 (6단계).
    /// 스플래시·디더·타자기·성운·rise 등 장식 모션이 즉시 표시/정적 페이드로 대체된다.
    var motionReduced: Bool {
        get { self[MotionReducedKey.self] }
        set { self[MotionReducedKey.self] = newValue }
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
/// 유리 강도(설정 4c)는 글래스 아래 깔리는 시트 워시의 불투명도로 반영된다 —
/// 강도가 낮을수록 뒤 캔버스가 더 비친다.
private struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let quality: RenderQuality

    @Environment(\.liquidGlassDisabled) private var glassDisabled
    @Environment(\.interfaceTheme) private var theme
    @Environment(\.glassIntensity) private var glassIntensity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        // 시스템 '투명도 줄이기'는 글래스 끄기와 동일하게 불투명 표면 + 테두리로 (6단계)
        if glassDisabled || reduceTransparency {
            // 레트로 미니멀: 불투명 표면 + 얇은 잉크 테두리
            content
                .background(shape.fill(flatFill))
                .overlay(shape.strokeBorder(borderColor, lineWidth: 1))
        } else if quality == .low {
            content.background(shape.fill(.regularMaterial))
        } else {
            content
                .glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
                .background(shape.fill(SonnetPalette.surface.opacity(0.5 * glassIntensity)))
        }
    }

    private var flatFill: Color {
        if let tint { return tint.opacity(0.16) }
        return theme.isBranded ? SonnetPalette.surface : Color.primary.opacity(0.05)
    }

    private var borderColor: Color {
        theme.isBranded ? SonnetPalette.ink.opacity(0.16) : Color.primary.opacity(0.12)
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
        // 미저장은 Dirty/Warning 골드 — 버밀리온(Primary Action)과 의미를 분리 (2단계)
        case .unsaved: SonnetPalette.warning
        case .saving, .savedAuto: SonnetPalette.inkMuted
        case .savedManual: SonnetPalette.success
        case .error: Color(hex: "#D28E2E")
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

/// 저장 실패 사유 — DocumentSession이 주입하고 SaveStatusBadge 툴팁이 읽는다.
/// 에디터 3종의 시그니처를 건드리지 않고 배지까지 내려보내기 위한 환경값.
private struct SaveErrorDetailKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    var saveErrorDetail: String? {
        get { self[SaveErrorDetailKey.self] }
        set { self[SaveErrorDetailKey.self] = newValue }
    }
}

public struct SaveStatusBadge: View {
    let state: SaveState
    let label: String
    let action: () -> Void

    @Environment(\.resolvedAccent) private var accent
    @Environment(\.saveErrorDetail) private var saveErrorDetail

    /// 저장 중/자동 저장의 고정 파랑은 앤티크 페이퍼 톤에서 유일하게 튀는 색이라
    /// 테마 액센트를 따르게 한다. 나머지 상태는 신호색(빨강/초록/노랑) 유지.
    private var displayColor: Color {
        switch state {
        case .saving, .savedAuto: accent
        default: state.color
        }
    }

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
                    .fill(displayColor)
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulse ? 1.7 : 1)
                    .shadow(color: displayColor.opacity(0.8), radius: 3)
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
        // 오류 상태에서는 왜 실패했는지 툴팁으로 — 클릭은 원래부터 수동 저장(=재시도)이다
        .help(state == .error ? (saveErrorDetail.map { "\(label) — \($0)" } ?? label) : label)
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

// MARK: - 로딩 인디케이터

/// 세 개의 점이 순차로 부풀며 숨쉬는 로딩 인디케이터 — AI 생성/네트워크 대기 공용.
/// (GitHub/Figma의 typing indicator 문법)
public struct PulseDotsIndicator: View {
    var dotSize: CGFloat
    var color: Color

    public init(dotSize: CGFloat = 5, color: Color = .secondary) {
        self.dotSize = dotSize
        self.color = color
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: dotSize * 0.9) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = t * 2.4 - Double(index) * 0.28
                    let wave = (sin(phase * .pi) + 1) / 2 // 0...1
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(0.65 + 0.45 * wave)
                        .opacity(0.35 + 0.6 * wave)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 로딩 플레이스홀더 위를 스치는 시머(광택) 오버레이.
private struct ShimmerModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    GeometryReader { geo in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let progress = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.35), .clear],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: geo.size.width * (progress * 2.2 - 1.1))
                        .blendMode(.plusLighter)
                    }
                }
                .allowsHitTesting(false)
                .clipped()
            }
        } else {
            content
        }
    }
}

public extension View {
    /// 로딩 중 시머 광택.
    func shimmer(active: Bool = true) -> some View {
        modifier(ShimmerModifier(active: active))
    }
}

// MARK: - 등장 애니메이션

/// 아래에서 살짝 떠오르며 페이드인하는 등장 연출 — delay를 계단식으로 주면
/// 리스트/카드가 순차 등장한다 (HIG의 hierarchy-revealing motion).
private struct FadeUpOnAppear: ViewModifier {
    let delay: Double
    let distance: CGFloat
    @State private var shown = false
    @Environment(\.motionReduced) private var motionReduced

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            // 모션 줄이기 — 이동 없이 120ms opacity만 (6단계)
            .offset(y: shown || motionReduced ? 0 : distance)
            .onAppear {
                withAnimation(
                    motionReduced
                        ? .easeOut(duration: 0.12)
                        : DesignTokens.Motion.arrival.delay(delay)
                ) { shown = true }
            }
    }
}

public extension View {
    /// 등장 시 아래→위 페이드 (delay로 스태거).
    func fadeUpOnAppear(delay: Double = 0, distance: CGFloat = 14) -> some View {
        modifier(FadeUpOnAppear(delay: delay, distance: distance))
    }
}

/// 아이콘 버튼용 꾹 눌리는 스프링 — LiftButtonStyle보다 작은 요소에 맞는 미세 반동.
public struct PressBounceButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
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
    /// 외부 ⌘F 등에서 포커스를 넣어줄 수 있는 선택적 바인딩.
    let focusBinding: FocusState<Bool>.Binding?

    public init(
        text: Binding<String>,
        placeholder: String,
        quality: RenderQuality = .standard,
        focusBinding: FocusState<Bool>.Binding? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.quality = quality
        self.focusBinding = focusBinding
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            searchField
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

    @ViewBuilder
    private var searchField: some View {
        if let focusBinding {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
                .focused(focusBinding)
        } else {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.callout)
        }
    }
}

/// 툴바 아이콘 버튼 (호버 하이라이팅).
/// 강조색을 따르는 세그먼트 컨트롤 — macOS의 시스템 세그먼트 픽커는 `.tint`를 무시하고
/// 항상 시스템 강조색으로 선택 칸을 칠해서, 앱의 강조 색상 설정과 어긋나 보인다.
/// 설정처럼 눈에 띄는 곳은 이 컨트롤로 대체한다 (사이드바 탭 픽커와 같은 문법).
public struct DSSegmentedPicker<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    @Environment(\.resolvedAccent) private var accent
    @Namespace private var highlight

    public init(selection: Binding<Value>, options: [(value: Value, label: String)]) {
        _selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(DesignTokens.Motion.snappy) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.callout)
                        .lineLimit(1)
                        .foregroundStyle(selection == option.value ? accent : Color.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(accent.opacity(0.14))
                                    .matchedGeometryEffect(id: "dsSegHighlight", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

public struct ToolbarIconButton: View {
    let systemName: String
    let help: String
    var isActive: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.resolvedAccent) private var accent

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
                .foregroundStyle(isActive ? accent : (hovering ? accent : .secondary))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(isActive ? accent.opacity(0.14) : (hovering ? accent.opacity(0.1) : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous))
                .scaleEffect(hovering ? 1.07 : 1)
        }
        .buttonStyle(PressBounceButtonStyle())
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.snappy, value: hovering)
        .help(help)
        // 텍스트 없는 아이콘 버튼 — VoiceOver가 도움말 문구를 이름으로 읽는다 (2단계 4)
        .accessibilityLabel(help)
    }
}

/// 읽기 전용 뷰어 모드 토글 — 호스트가 `\.readOnlyMode` 바인딩을 주입한 경우에만
/// 렌더링된다. 세 에디터 툴바가 공유한다.
public struct ReadOnlyToggle: View {
    @Environment(\.readOnlyMode) private var readOnlyMode

    public init() {}

    public var body: some View {
        if let readOnlyMode {
            let l10n = Localizer.shared
            let isOn = readOnlyMode.wrappedValue
            ToolbarIconButton(
                isOn ? "lock.fill" : "lock.open",
                help: l10n.t(isOn ? .readOnlyOff : .readOnlyOn) + " (⇧⌘L)",
                isActive: isOn
            ) {
                withAnimation(DesignTokens.Motion.gentle) {
                    readOnlyMode.wrappedValue.toggle()
                }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

/// 읽기 전용 상태 캡슐 배지 — 툴바에서 토글 옆에 표시해 현재 모드를 명확히 한다.
public struct ReadOnlyBadge: View {
    @Environment(\.readOnlyMode) private var readOnlyMode
    @Environment(\.resolvedAccent) private var accent

    public init() {}

    public var body: some View {
        if readOnlyMode?.wrappedValue == true {
            // 색상만이 아니라 잠금 아이콘 + 도움말로 상태를 전달한다 (지시서 1단계 2)
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text(Localizer.shared.t(.readOnlyMode))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(accent.opacity(0.12)))
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .help(Localizer.shared.t(.readOnlyCanvasHint))
            .accessibilityLabel(Localizer.shared.t(.readOnlyMode))
        }
    }
}
