import AppCore
import AppKit
import SwiftUI

/// Siri식 AI 스피어 — 애니메이티드 메시 그라디언트를 다층 합성한 구체.
/// 구성 (참고: metasidd/Orb의 레이어링, 신형 Siri의 시간 기반 메시 변형):
///   1) 바깥 글로우 — 블러 처리한 액센트 원
///   2) 코어 — 3×3 MeshGradient, 중앙 제어점들이 시간에 따라 물결치고 팔레트는
///      실효 강조색에서 색상(hue)을 ±회전해 파생
///   3) 상단 스펙큘러 하이라이트 — 유리 구슬 반사광
/// `activity == .thinking`이면 더 빠르게 요동치고 살짝 숨쉰다 (응답 생성 중 표시).
public struct AISphere: View {
    public enum Activity: Sendable {
        case idle, thinking
    }

    let size: CGFloat
    let activity: Activity

    @Environment(\.resolvedAccent) private var accent
    @Environment(\.renderQuality) private var quality

    public init(size: CGFloat = 96, activity: Activity = .idle) {
        self.size = size
        self.activity = activity
    }

    public var body: some View {
        if quality == .low {
            sphere(time: 0)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                sphere(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private var speed: Double { activity == .thinking ? 2.6 : 1.0 }

    @ViewBuilder
    private func sphere(time: TimeInterval) -> some View {
        let t = time * speed
        let breathe = activity == .thinking ? 1 + 0.04 * sin(t * 3.1) : 1
        ZStack {
            // 1) 바깥 글로우
            Circle()
                .fill(vividBase.opacity(0.5))
                .blur(radius: size * 0.16)
                .scaleEffect(1.02 + 0.03 * sin(t * 0.9))

            // 2) Metal 플라즈마 코어 — fbm 노이즈 밴드가 구면을 따라 흐르는 셰이더.
            //    셰이더가 원형 알파와 구면 셰이딩까지 직접 계산한다.
            //    (colorEffect는 뷰의 픽셀을 변환하므로 캔버스는 불투명해야 한다 — 투명 뷰는 스킵됨)
            Rectangle()
                .fill(Color.white)
                .colorEffect(
                    ShaderLibrary.bundle(.module).aiSpherePlasma(
                        .boundingRect,
                        .float(Float(time)), // 속도는 셰이더의 thinking 파라미터가 처리
                        .float(Float(baseHue)),
                        .float(activity == .thinking ? 1 : 0)
                    )
                )

            // 3) 스펙큘러 하이라이트
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.7), .clear],
                        center: UnitPoint(x: 0.34, y: 0.26),
                        startRadius: 0,
                        endRadius: size * 0.34
                    )
                )
                .blendMode(.screen)
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .scaleEffect(breathe)
    }

    /// vividBase의 hue (0...1) — 셰이더의 무지갯빛 밴드 중심축.
    private var baseHue: CGFloat {
        guard let rgb = NSColor(vividBase).usingColorSpace(.deviceRGB) else { return 0.6 }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var value: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        return hue
    }

    /// 어두운/무채색 강조색도 스피어에서는 발광해야 한다 — 명도·채도 하한을 끌어올린 베이스.
    private var vividBase: Color {
        guard let rgb = NSColor(accent).usingColorSpace(.deviceRGB) else { return accent }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var value: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        return Color(hue: hue, saturation: max(saturation, 0.5), brightness: max(value, 0.78), opacity: 1)
    }
}

public extension Color {
    /// 다크 모드용 가독 보정 — 어두운 강조색(커스텀 네이비 등)은 다크 배경에서
    /// 대비를 잃는다. 명도가 낮으면 끌어올리고 채도를 살짝 눌러 발광감을 준다.
    /// 밝은 강조색은 그대로 통과한다.
    func adaptedForDarkMode() -> Color {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var value: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        guard value < 0.55 else { return self }
        return Color(hue: hue, saturation: min(saturation, 0.85) * 0.92, brightness: max(value, 0.7), opacity: alpha)
    }

    /// 흰색 방향으로 혼합한 파생색 — 스피어 화이트 코어처럼 발광하는 톤을 만든다.
    func mixedWithWhite(_ amount: CGFloat) -> Color {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        let clamped = min(1, max(0, amount))
        return Color(
            red: rgb.redComponent + (1 - rgb.redComponent) * clamped,
            green: rgb.greenComponent + (1 - rgb.greenComponent) * clamped,
            blue: rgb.blueComponent + (1 - rgb.blueComponent) * clamped
        )
    }

    /// hue를 회전하고 밝기를 배율 조정한 파생색 (AI 스피어 팔레트용).
    func hueShifted(_ delta: CGFloat, brightness scale: CGFloat = 1) -> Color {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var value: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        var shifted = hue + delta
        shifted -= floor(shifted) // 0..1 래핑
        return Color(
            hue: shifted,
            saturation: min(1, saturation * (scale > 1 ? 0.9 : 1.05)),
            brightness: min(1, max(0.1, value * scale)),
            opacity: alpha
        )
    }
}
