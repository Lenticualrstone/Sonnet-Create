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

            // 2) 메시 코어
            MeshGradient(width: 3, height: 3, points: meshPoints(t), colors: palette)
                .clipShape(Circle())
                .overlay(
                    // 구체의 어두운 가장자리 — 평면 그라디언트에 볼륨감 부여
                    Circle().strokeBorder(
                        RadialGradient(
                            colors: [.clear, Color.black.opacity(0.18)],
                            center: .center,
                            startRadius: size * 0.30,
                            endRadius: size * 0.52
                        ),
                        lineWidth: size * 0.10
                    )
                )

            // 3) 스펙큘러 하이라이트
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.75), .clear],
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

    /// 3×3 제어점 — 모서리는 고정, 가장자리 중점과 중앙만 물결치게 해 원형 마스크
    /// 안에서 색면이 유영하는 느낌을 만든다.
    private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func wave(_ base: Double, _ amp: Double, _ phase: Double) -> Float {
            Float(base + amp * sin(t * 0.8 + phase))
        }
        return [
            [0, 0], [wave(0.5, 0.18, 0.0), 0], [1, 0],
            [0, wave(0.5, 0.18, 1.7)],
            [wave(0.48, 0.22, 3.1), wave(0.52, 0.22, 4.2)],
            [1, wave(0.5, 0.18, 5.3)],
            [0, 1], [wave(0.5, 0.18, 2.4), 1], [1, 1],
        ]
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

    /// vividBase에서 파생한 9색 팔레트 — hue를 좌우로 돌리고, 중앙은 화이트 코어로 빛난다.
    private var palette: [Color] {
        let base = vividBase
        return [
            base.hueShifted(-0.06, brightness: 1.2), base.hueShifted(0.04, brightness: 1.05), base.hueShifted(0.10, brightness: 0.9),
            base.hueShifted(-0.10, brightness: 1.1), base.mixedWithWhite(0.55), base.hueShifted(0.07, brightness: 0.85),
            base.hueShifted(-0.04, brightness: 0.7), base.hueShifted(0.05, brightness: 0.95), base.hueShifted(0.12, brightness: 0.6),
        ]
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
