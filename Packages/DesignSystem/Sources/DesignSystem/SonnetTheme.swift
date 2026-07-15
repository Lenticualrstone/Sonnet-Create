import AppCore
import AppKit
import CoreText
import SwiftUI

// MARK: - 인터페이스 테마

/// 앱 전반의 시각 스타일 — v1.3에서 백색 캔버스 + 딥네이비(#031C35) 단일 테마로 일원화.
/// enum 케이스는 저장분 디코딩 호환을 위해 유지하되, 어떤 케이스든 같은 팔레트를 반환한다.
public enum InterfaceTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, sonnet, pilgrimage

    public var id: String { rawValue }

    /// v1.3 일원화 이후 모든 케이스가 브랜드 팔레트를 쓴다.
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

/// 통합 테마 팔레트 v3 — 백색 캔버스 + 딥네이비(#031C35) 액센트.
/// 다크모드는 네이비 기운의 어두운 캔버스 + 가시성을 위해 밝힌 네이비 액센트를 쓴다.
public enum SonnetPalette {
    /// 메인 캔버스 (라이트: 순백 / 다크: 네이비 블랙)
    public static let canvas = dynamicColor(light: "#FFFFFF", dark: "#0C1420")
    /// 살짝 떠 있는 표면 (카드/패널)
    public static let surface = dynamicColor(light: "#F6F8FB", dark: "#16202E")
    /// 가라앉은 표면 (사이드바/탭바/입력 필드)
    public static let sunken = dynamicColor(light: "#ECF0F5", dark: "#080E17")
    /// 본문 잉크 — 라이트에서는 브랜드 네이비에 가깝게
    public static let ink = dynamicColor(light: "#0E1B2C", dark: "#E6ECF4")
    /// 보조 잉크
    public static let inkMuted = dynamicColor(light: "#5F6B7C", dark: "#8E9BAD")
    /// 브랜드 액센트 — 라이트 #031C35 / 다크는 가시성을 위해 밝힌 네이비 블루
    public static let accent = dynamicColor(light: "#031C35", dark: "#7FA6D4")
    /// 배경 도트 기본색 (테마 추종 모드)
    public static let dot = dynamicColor(light: "#33465E", dark: "#93A7BF")
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
