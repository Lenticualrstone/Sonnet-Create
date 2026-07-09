import AppCore
import AppKit
import CoreText
import SwiftUI

// MARK: - 인터페이스 테마

/// 앱 전반의 시각 스타일. Sonnet = 본(#C8C0B0) 캔버스 + 적갈색 액센트의 모던-레트로 테마.
/// Pilgrimage = 같은 본톤 캔버스에 짙은 네이비 액센트를 얹은 변형.
public enum InterfaceTheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, sonnet, pilgrimage

    public var id: String { rawValue }

    /// 고유 브랜드 팔레트(캔버스/표면/액센트 등)를 쓰는 테마인지 — system은 플랫폼 기본 소재를 쓴다.
    public var isBranded: Bool { self != .system }

    /// 테마별 메인 캔버스색. 브랜드 팔레트가 아닌 테마에서는 호출부가 쓰지 않지만
    /// (isBranded로 먼저 분기) 안전하게 Sonnet 값을 기본으로 반환한다.
    public var canvasColor: Color {
        self == .pilgrimage ? PilgrimagePalette.canvas : SonnetPalette.canvas
    }

    /// 테마별 액센트색.
    public var accentColor: Color {
        self == .pilgrimage ? PilgrimagePalette.accent : SonnetPalette.accent
    }
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

/// Sonnet 테마 팔레트 v2 — 앤티크 페이퍼 캔버스 위의 적갈색 액센트. 부드러운 레트로 미니멀리즘.
public enum SonnetPalette {
    /// 메인 캔버스 (라이트: 연베이지 백색 / 다크: 웜 브라운 블랙)
    public static let canvas = dynamicColor(light: "#F6F1E7", dark: "#221E19")
    /// 살짝 떠 있는 표면 (카드/패널)
    public static let surface = dynamicColor(light: "#FCF9F2", dark: "#2C2620")
    /// 가라앉은 표면 (사이드바/탭바/입력 필드) — 본톤 기운
    public static let sunken = dynamicColor(light: "#EAE3D3", dark: "#1A1613")
    /// 본문 잉크
    public static let ink = dynamicColor(light: "#33291E", dark: "#E7E0D0")
    /// 보조 잉크
    public static let inkMuted = dynamicColor(light: "#867B67", dark: "#9E9585")
    /// 적갈색 액센트 (Claude 오렌지보다 어둡고 붉은 쪽)
    public static let accent = dynamicColor(light: "#9C4A2E", dark: "#C4714F")
    /// 배경 도트 기본색 (테마 추종 모드)
    public static let dot = dynamicColor(light: "#5C5344", dark: "#C8C0B0")
}

/// Pilgrimage 테마 팔레트 — Sonnet과 같은 본톤 캔버스 가족이되 살짝 더 백색에 가깝게,
/// 적갈색 대신 짙은 네이비 액센트. 표면/잉크/도트 등 나머지 톤은 Sonnet과 동일하게 공유한다.
public enum PilgrimagePalette {
    /// 메인 캔버스 — Sonnet보다 살짝 더 흰 쪽으로 (다크는 Sonnet과 동일)
    public static let canvas = dynamicColor(light: "#F9F7F2", dark: "#221E19")
    /// 짙은 네이비 액센트 — 라이트/다크 공통 고정 값
    public static let accent = dynamicColor(light: "#031C35", dark: "#031C35")
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
}
