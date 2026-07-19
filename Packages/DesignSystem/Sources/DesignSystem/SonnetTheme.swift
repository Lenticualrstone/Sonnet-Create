import AppCore
import AppKit
import CoreText
import SwiftUI

// MARK: - 인터페이스 테마

/// 앱 전반의 시각 스타일 — v2.0 "인장(印) & 원고" 단일 테마.
/// 웜 페이퍼 캔버스 위에 먹빛 잉크로 쓰고, 행동(생성·확정·AI)에만 버밀리온 인장을 찍는다.
/// enum 케이스는 저장분 디코딩 호환을 위해 유지하되, 어떤 케이스든 같은 팔레트를 반환한다.
public enum InterfaceTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, sonnet, pilgrimage

    public var id: String { rawValue }

    /// 테마 일원화 이후 모든 케이스가 브랜드 팔레트를 쓴다.
    public var isBranded: Bool { true }

    /// 메인 캔버스색 — 케이스와 무관하게 통합 팔레트.
    public var canvasColor: Color { SonnetPalette.canvas }

    /// 액센트색 — 케이스와 무관하게 통합 팔레트.
    public var accentColor: Color { SonnetPalette.accent }
}

/// 라이트/다크에 자동 대응하는 다이나믹 컬러 헬퍼.
private func dynamicColor(light: String, dark: String) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(hexString: isDark ? dark : light)
    })
}

private extension NSColor {
    convenience init(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: value).scanHexInt64(&rgb)
        self.init(
            srgbRed: CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >> 8) / 255,
            blue: CGFloat(rgb & 0x0000FF) / 255,
            alpha: 1
        )
    }
}

/// 통합 테마 팔레트 v4 — "인장(印) & 원고" Brand v2.
/// 라이트: 웜 페이퍼(#F6F4EF) 캔버스 + 먹(#191713) 잉크 + 버밀리온 인장(#B23A21) 액센트.
/// 다크: 먹지에 가까운 웜 블랙 캔버스 + 상아빛 잉크 + 밝힌 버밀리온.
public enum SonnetPalette {
    /// 메인 캔버스 — Paper (라이트: 웜 페이퍼 / 다크: 웜 블랙)
    public static let canvas = dynamicColor(light: "#F6F4EF", dark: "#12100D")
    /// 떠 있는 표면 — Sheet (카드/패널; 종이 위의 새 종이)
    public static let surface = dynamicColor(light: "#FFFFFF", dark: "#1C1915")
    /// 가라앉은 표면 — 헤더 밴드/입력 필드/사이드 레일
    public static let sunken = dynamicColor(light: "#ECE8E0", dark: "#0C0A08")
    /// 본문 잉크 — 먹
    public static let ink = dynamicColor(light: "#191713", dark: "#F6F4EF")
    /// 보조 잉크 — Muted
    public static let inkMuted = dynamicColor(light: "#7A7264", dark: "#B8B2A6")
    /// 부드러운 잉크 — 비활성 크롬 텍스트 (먹과 Muted 사이)
    public static let inkSoft = dynamicColor(light: "#443E33", dark: "#D8D2C6")
    /// 브랜드 액센트 — 인장 Seal (행동: 생성·확정·AI에만 사용)
    public static let accent = dynamicColor(light: "#B23A21", dark: "#E8695A")
    /// 인장 호버/프레스 — 더 깊은 버밀리온
    public static let accentDeep = dynamicColor(light: "#8E2D18", dark: "#C2482D")
    /// 인장 틴트 — Seal tint (액센트 배경 워시)
    public static let accentTint = dynamicColor(light: "#F3E4DE", dark: "#33201A")
    /// 먹록 Pine — 보조 의미색 (마인드맵·연결)
    public static let pine = dynamicColor(light: "#3E5C50", dark: "#8FB3A2")
    /// 골드 — 페이지(.scpa) 유형색
    public static let gold = dynamicColor(light: "#8A6D2F", dark: "#D4A854")
    /// 슬레이트 — 첨부/기타 유형색
    public static let slate = dynamicColor(light: "#5F6B7C", dark: "#9AA7B8")
    /// 세이지 — 저장 성공 신호색
    public static let sage = dynamicColor(light: "#5B8A4C", dark: "#8AB77C")
    /// 배경 도트 기본색 (도트 격자·장식)
    public static let dot = dynamicColor(light: "#443E33", dark: "#8C8579")

    // MARK: 파일 유형 컬러

    /// .scen 시나리오 — 버밀리온
    public static let typeScenario = accent
    /// .scno 마인드맵 — 파인
    public static let typeMindmap = pine
    /// .scpa 페이지 — 골드
    public static let typePage = gold
    /// .scpa·character 캐릭터 — 테라코타 (인장과 골드 사이)
    public static let typeCharacter = dynamicColor(light: "#9E5A3C", dark: "#D08B66")
    /// 기타 첨부 — 슬레이트
    public static let typeAttachment = slate
}

/// (구) Pilgrimage 팔레트 — v1.3 테마 일원화 이후 통합 팔레트의 별칭으로만 남는다.
public enum PilgrimagePalette {
    public static let canvas = SonnetPalette.canvas
    public static let accent = SonnetPalette.accent
}

// MARK: - 글꼴 팩

/// Notion처럼 고를 수 있는 글꼴 패밀리. 기본은 Pretendard.
public enum FontFamily: String, Codable, CaseIterable, Sendable, Identifiable {
    case pretendard, system, serif, mono

    public var id: String { rawValue }
}

public enum DSFonts {
    private nonisolated(unsafe) static var registered = false

    /// 번들된 Pretendard Variable을 프로세스에 등록. 앱 시작 시 1회 호출.
    public static func registerBundledFonts() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.module.url(forResource: "Fonts/PretendardVariable", withExtension: "ttf")
            ?? Bundle.module.url(forResource: "PretendardVariable", withExtension: "ttf", subdirectory: "Fonts")
        else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// 글꼴 팩 인지형 폰트 생성.
    public static func font(size: CGFloat, weight: Font.Weight = .regular, family: FontFamily) -> Font {
        switch family {
        case .pretendard:
            return Font.custom("Pretendard Variable", size: size).weight(weight)
        case .system:
            return .system(size: size, weight: weight)
        case .serif:
            return .system(size: size, weight: weight, design: .serif)
        case .mono:
            return .system(size: size, weight: weight, design: .monospaced)
        }
    }

    /// 설치된 한글 세리프 패밀리 탐색 결과 (Noto Serif KR > 나눔명조 > AppleMyungjo).
    private nonisolated(unsafe) static var resolvedSerifName: String? = {
        for name in ["Noto Serif KR", "NanumMyeongjo", "AppleMyungjo"] {
            if NSFont(name: name, size: 15) != nil { return name }
        }
        return nil
    }()

    /// 디스플레이 세리프 — 홈 히어로·문서 제목·브랜드 워드마크용.
    /// 한글 세리프가 설치돼 있으면 그것을, 없으면 시스템 세리프 디자인을 쓴다.
    public static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if let name = resolvedSerifName {
            return Font.custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - 타이포 토큰 (인장 & 원고)

/// 역할별 타이포 토큰 — 디자인 브리프 1a의 TYPE 스펙.
public enum DSType {
    /// 디스플레이 — 세리프 600 (히어로·워드마크·챕터 제목)
    public static func displayLarge() -> Font { DSFonts.display(size: 26, weight: .bold) }
    public static func display() -> Font { DSFonts.display(size: 20, weight: .semibold) }
    /// UI 타이틀 — Pretendard 600 · 15
    public static func title() -> Font { DSFonts.font(size: 15, weight: .semibold, family: .pretendard) }
    /// UI 서브타이틀 — Pretendard 600 · 13
    public static func subtitle() -> Font { DSFonts.font(size: 13, weight: .semibold, family: .pretendard) }
    /// 본문 — Pretendard 400 · 14 (줄간 1.7은 .dsBodyLineSpacing()으로)
    public static func body() -> Font { DSFonts.font(size: 14, family: .pretendard) }
    /// 캡션 — 11.5
    public static func caption() -> Font { DSFonts.font(size: 11.5, family: .pretendard) }
    /// 메타·확장자 — Mono 12 (.scen .scno .scpa)
    public static func mono(size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

public extension View {
    /// 본문 14pt 기준 줄간 1.7 (14 × 0.7 ≈ 10pt 추가 간격).
    func dsBodyLineSpacing() -> some View { lineSpacing(9.8) }
}

// MARK: - 픽셀 브리딩 필드

/// 픽셀 격자가 저마다의 위상/속도/크기로 무작위 디밍·브리딩하는 장식 요소.
/// 열/행/픽셀 크기를 조절해 사이드바(소형)와 메인 화면(대형)에 함께 쓴다.
public struct PixelBreathField: View {
    let columns: Int
    let rows: Int
    let baseSize: CGFloat
    /// 픽셀별 크기 편차 (0 = 균일)
    let sizeVariance: CGFloat
    let spacing: CGFloat
    let color: Color
    let quality: RenderQuality

    public init(
        columns: Int = 12,
        rows: Int = 3,
        baseSize: CGFloat = 3.5,
        sizeVariance: CGFloat = 0,
        spacing: CGFloat = 2.5,
        color: Color = .accentColor,
        quality: RenderQuality = .standard
    ) {
        self.columns = columns
        self.rows = rows
        self.baseSize = baseSize
        self.sizeVariance = sizeVariance
        self.spacing = spacing
        self.color = color
        self.quality = quality
    }

    // 결정적 의사난수 (실행마다 동일 패턴)
    private func unit(_ index: Int, salt: Int) -> Double {
        let hash: Int = (index &* 2_654_435_761 &+ salt &* 97) % 1000
        return Double(abs(hash)) / 1000.0
    }

    public var body: some View {
        Group {
            if quality == .low {
                grid(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    grid(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    private func grid(time: TimeInterval) -> some View {
        // 크기가 달라도 기준선이 흔들리지 않도록 셀을 고정 크기로 잡는다
        let cell = baseSize + sizeVariance
        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = row * columns + col
                        let phase = unit(index, salt: 1) * 2.0 * Double.pi
                        let speed = 1.2 + unit(index, salt: 2) * 2.6
                        let size = baseSize + sizeVariance * CGFloat(unit(index, salt: 3))
                        let breath = 0.5 + 0.5 * sin(time * speed + phase)
                        Rectangle()
                            .fill(color)
                            .frame(width: size, height: size)
                            .opacity(0.10 + 0.65 * breath)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 그레인 텍스처

/// 앤티크 페이퍼 무드를 강화하는 미세 그레인 오버레이. 정적(비애니메이션), 결정적 패턴.
public struct GrainOverlay: View {
    let color: Color
    let opacity: Double
    let density: Int

    public init(color: Color = .black, opacity: Double = 0.05, density: Int = 700) {
        self.color = color
        self.opacity = opacity
        self.density = density
    }

    private func unit(_ index: Int, salt: Int) -> Double {
        let hash: Int = (index &* 2_654_435_761 &+ salt &* 97) % 1000
        return Double(abs(hash)) / 1000.0
    }

    public var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            for i in 0..<density {
                let x = unit(i, salt: 1) * size.width
                let y = unit(i, salt: 2) * size.height
                let a = 0.15 + unit(i, salt: 3) * 0.7
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(color.opacity(a * opacity))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ContentFontFamilyKey: EnvironmentKey {
    static let defaultValue: FontFamily = .pretendard
}

private struct InterfaceThemeKey: EnvironmentKey {
    static let defaultValue: InterfaceTheme = .sonnet
}

private struct LiquidGlassDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ResolvedAccentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

private struct ReadOnlyModeKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

public extension EnvironmentValues {
    var contentFontFamily: FontFamily {
        get { self[ContentFontFamilyKey.self] }
        set { self[ContentFontFamilyKey.self] = newValue }
    }

    var interfaceTheme: InterfaceTheme {
        get { self[InterfaceThemeKey.self] }
        set { self[InterfaceThemeKey.self] = newValue }
    }

    /// 베타: Liquid Glass를 끄고 평면(레트로 미니멀) 표면으로 대체
    var liquidGlassDisabled: Bool {
        get { self[LiquidGlassDisabledKey.self] }
        set { self[LiquidGlassDisabledKey.self] = newValue }
    }

    /// AppState.resolvedAccent — 테마+강조색상 설정을 조합한 실효 강조색.
    /// `.tint()`는 표준 컨트롤에만 영향을 주므로, 아이콘/Canvas 등 리터럴
    /// `Color.accentColor` 참조는 이 환경값을 직접 구독해야 한다.
    var resolvedAccent: Color {
        get { self[ResolvedAccentKey.self] }
        set { self[ResolvedAccentKey.self] = newValue }
    }

    /// 읽기 전용 뷰어 모드 — 문서 세션이 바인딩을 주입하면 에디터가 툴바 토글을
    /// 노출하고 편집 표면을 잠근다. nil이면 이 기능을 지원하지 않는 호스트.
    var readOnlyMode: Binding<Bool>? {
        get { self[ReadOnlyModeKey.self] }
        set { self[ReadOnlyModeKey.self] = newValue }
    }
}
