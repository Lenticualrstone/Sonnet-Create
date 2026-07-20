import AppCore
import AppKit
import SwiftUI

// MARK: - 밀도

/// 성운 스피어의 가루 입자 밀도 — 설정에서 선택. 입자 수 배율로 작용한다.
public enum AISphereDensity: String, CaseIterable, Sendable, Identifiable {
    case sparse, normal, dense

    public var id: String { rawValue }

    public var labelKey: L10nKey {
        switch self {
        case .sparse: .sphereDensitySparse
        case .normal: .sphereDensityNormal
        case .dense: .sphereDensityDense
        }
    }

    /// 큰 스피어(≥44pt)의 입자 수.
    var largeCount: Int {
        switch self {
        case .sparse: 500
        case .normal: 850
        case .dense: 1300
        }
    }

    /// 작은 스피어(<44pt, 아이콘/헤더)의 입자 수 — 성능·가독 균형.
    var smallCount: Int {
        switch self {
        case .sparse: 100
        case .normal: 150
        case .dense: 230
        }
    }
}

private struct AISphereDensityKey: EnvironmentKey {
    static let defaultValue: AISphereDensity = .normal
}

public extension EnvironmentValues {
    /// 앱 전역 가루 입자 밀도 (설정 주입).
    var aiSphereDensity: AISphereDensity {
        get { self[AISphereDensityKey.self] }
        set { self[AISphereDensityKey.self] = newValue }
    }
}

// MARK: - 성운 가루 필드

/// 구각(球殼)을 따라 대류하는 가루 입자들 — 모션 스펙 10의 난류 유동장.
/// 입자 위치가 프레임 간 누적되는 상태 기반 시뮬레이션이라 참조 타입으로 둔다.
private final class NebulaDustField {
    struct Particle {
        var x = 0.0, y = 0.0, z = 0.0
        var life = 0.0, maxLife = 1.0
        var size = 0.55
        var warm = 0.0
    }

    private(set) var particles: [Particle] = []
    private var lastTime: TimeInterval?

    func ensure(count: Int) {
        guard particles.count != count else { return }
        particles = (0..<count).map { _ in
            var particle = Self.spawned()
            particle.life = Double.random(in: 0..<particle.maxLife)
            return particle
        }
        lastTime = nil
    }

    private static func spawned() -> Particle {
        var particle = Particle()
        respawn(&particle)
        return particle
    }

    private static func respawn(_ particle: inout Particle) {
        // 구각 반경 0.68~1.18에 균일 분포 — 스펙의 spawn과 동일
        let u = Double.random(in: -1...1)
        let theta = Double.random(in: 0..<(2 * .pi))
        let ring = (1 - u * u).squareRoot()
        let radius = 0.68 + Double.random(in: 0..<0.5)
        particle.x = ring * cos(theta) * radius
        particle.y = u * radius
        particle.z = ring * sin(theta) * radius
        particle.life = 0
        particle.maxLife = 2.5 + Double.random(in: 0..<4.5)
        let roll = Double.random(in: 0..<1)
        particle.size = roll < 0.1 ? 1.5 : (roll < 0.5 ? 0.8 : 0.55)
        particle.warm = Double.random(in: 0..<1)
    }

    /// 난류 유동장 한 스텝 — 회전류(+적도 제트) + 의사 컬 노이즈 + 구각 복원력.
    func step(to time: TimeInterval, speed: Double, turbulence: Double, jet: Double, pulse: Double) {
        let dt = min(time - (lastTime ?? time), 0.05)
        lastTime = time
        guard dt > 0 else { return }

        let tk = time * 0.9
        let target = 0.92 + pulse * sin(time * 2.6)
        for index in particles.indices {
            var p = particles[index]
            let n1 = sin(2.3 * p.y + tk * 0.7) + cos(1.7 * p.z - tk * 0.5)
            let n2 = sin(2.1 * p.z + tk * 0.6) + cos(1.9 * p.x + tk * 0.4)
            let n3 = sin(2.5 * p.x - tk * 0.55) + cos(2.2 * p.y + tk * 0.65)
            let jetFlow = jet * (1 - abs(p.y)) * 0.9
            let vx = -p.z * (0.4 + jetFlow) + turbulence * n1 * 0.45
            let vy = turbulence * n2 * 0.4
            let vz = p.x * (0.4 + jetFlow) + turbulence * n3 * 0.45
            p.x += vx * dt * speed
            p.y += vy * dt * speed
            p.z += vz * dt * speed

            let radius = max((p.x * p.x + p.y * p.y + p.z * p.z).squareRoot(), 1e-4)
            let pull = (target - radius) * 1.1 * dt
            p.x += p.x / radius * pull
            p.y += p.y / radius * pull
            p.z += p.z / radius * pull

            p.life += dt
            if p.life > p.maxLife { Self.respawn(&p) }
            particles[index] = p
        }
    }
}

// MARK: - 스피어

/// Sonnet AI의 아이덴티티 오브 — 미세 가루 입자가 일렁이는 성운 (모션 스펙 10).
/// 라이트에서는 먹가루 성운(10b), 다크에서는 버밀리온 성운(10a),
/// 다크에서 생성 중일 때는 적도 제트가 흐르는 금사 와류(10c)로 나타난다.
public struct AISphere: View {
    /// 스피어의 활동 상태 — idle(대기) < typing(사용자 입력 중) < thinking(생성 중).
    public enum Activity: Sendable {
        case idle, typing, thinking

        /// 스펙 10의 상태 파라미터 — 대기 {rot .1, spd .45, turb .5},
        /// 사고/생성 {rot .22, spd 1.7, turb 1.6} + 코어 펄스.
        var rotation: Double {
            switch self {
            case .idle: 0.1
            case .typing: 0.16
            case .thinking: 0.22
            }
        }

        var speed: Double {
            switch self {
            case .idle: 0.45
            case .typing: 1.0
            case .thinking: 1.7
            }
        }

        var turbulence: Double {
            switch self {
            case .idle: 0.5
            case .typing: 1.0
            case .thinking: 1.6
            }
        }

        var glow: Double {
            switch self {
            case .idle: 0.85
            case .typing: 0.95
            case .thinking: 1.15
            }
        }

        /// 코어 글로우/구각 반경 맥동 진폭 — 생성 중 6% (모션 스펙 10c).
        var pulse: Double {
            switch self {
            case .idle: 0.0
            case .typing: 0.02
            case .thinking: 0.06
            }
        }
    }

    /// 색 램프 바리에이션 — 컨텍스트(라이트/다크·생성 중)가 자동 결정한다.
    private enum Variant {
        /// 10a 버밀리온 성운 — 다크 기본. 주홍→살구→상아 3단 램프 + 가산 발광.
        case vermilion
        /// 10b 먹가루 성운 — 라이트 임베드. 먹 + 버밀리온 14%, 발광 없이 종이 위 침전.
        case inkDust
        /// 10c 금사 와류 — 다크에서 생성 중. 적도 제트 + 금박 35%.
        case goldJet
    }

    let size: CGFloat
    let activity: Activity

    @Environment(\.renderQuality) private var quality
    @Environment(\.aiSphereDensity) private var density
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.decorAnimationsPaused) private var animationsPaused
    @Environment(\.motionReduced) private var motionReduced

    @State private var field = NebulaDustField()

    public init(size: CGFloat = 96, activity: Activity = .idle) {
        self.size = size
        self.activity = activity
    }

    private var variant: Variant {
        guard colorScheme == .dark else { return .inkDust }
        return activity == .thinking ? .goldJet : .vermilion
    }

    public var body: some View {
        Group {
            if quality == .low || animationsPaused || motionReduced {
                // 저사양/앱 비활성/모션 줄이기 — 정지 프레임
                sphere(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    sphere(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }

    @ViewBuilder
    private func sphere(time: TimeInterval) -> some View {
        let variant = variant
        Canvas { context, canvasSize in
            field.ensure(count: size < 44 ? density.smallCount : density.largeCount)
            field.step(
                to: time,
                speed: activity.speed,
                turbulence: activity.turbulence,
                jet: variant == .goldJet ? 1 : 0,
                pulse: activity.pulse
            )

            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let sphereRadius = min(canvasSize.width, canvasSize.height) * 0.42
            let glow = activity.glow

            // 코어 글로우 — 가산 변형(10a·10c)만. 생성 중엔 맥동한다.
            if let core = coreColor(variant) {
                let glowPulse = 0.5 + (activity.pulse > 0 ? 0.35 * (0.5 + 0.5 * sin(time * 2.6)) : 0)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - sphereRadius * 1.1,
                        y: center.y - sphereRadius * 1.1,
                        width: sphereRadius * 2.2,
                        height: sphereRadius * 2.2
                    )),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: core.opacity(0.16 * glow * glowPulse), location: 0),
                            .init(color: core.opacity(0.05 * glow * glowPulse), location: 0.55),
                            .init(color: core.opacity(0), location: 1),
                        ]),
                        center: center,
                        startRadius: 0,
                        endRadius: sphereRadius * 1.1
                    )
                )
                context.blendMode = .plusLighter
            }

            // 회전 투영 — yaw는 상태별 속도로 진행, pitch는 스펙 고정값 0.42
            let yaw = time * activity.rotation * 2
            let pitch = 0.42
            let cosYaw = cos(yaw)
            let sinYaw = sin(yaw)
            let cosPitch = cos(pitch)
            let sinPitch = sin(pitch)
            let dotScale = max(0.9, sphereRadius / 118)

            for particle in field.particles {
                let x1 = particle.x * cosYaw + particle.z * sinYaw
                let z1 = particle.z * cosYaw - particle.x * sinYaw
                let y1 = particle.y * cosPitch - z1 * sinPitch
                let z2 = particle.y * sinPitch + z1 * cosPitch
                let depth = (z2 + 1.4) / 2.8

                let envelope = min(particle.life * 1.2, (particle.maxLife - particle.life) * 1.2, 1)
                let alpha = envelope * (0.1 + depth * 0.55) * glow
                guard alpha > 0.01 else { continue }

                let dot = particle.size * dotScale * (0.55 + depth * 0.85)
                context.fill(
                    Path(CGRect(
                        x: center.x + x1 * sphereRadius - dot / 2,
                        y: center.y + y1 * sphereRadius - dot / 2,
                        width: dot,
                        height: dot
                    )),
                    with: .color(dustColor(variant, warm: particle.warm, alpha: alpha))
                )
            }
        }
        .frame(width: size, height: size)
    }

    /// 가산 발광 변형의 코어 색 — 먹가루(라이트)는 발광하지 않는다.
    private func coreColor(_ variant: Variant) -> Color? {
        switch variant {
        case .vermilion: Color(red: 194 / 255, green: 72 / 255, blue: 45 / 255)
        case .goldJet: Color(red: 226 / 255, green: 120 / 255, blue: 50 / 255)
        case .inkDust: nil
        }
    }

    /// 스펙 10의 색 램프 — warm 값이 입자마다 고정돼 가루의 결이 유지된다.
    private func dustColor(_ variant: Variant, warm: Double, alpha: Double) -> Color {
        let clamped = min(alpha, 1)
        switch variant {
        case .vermilion:
            if warm < 0.45 { return Color(red: 226 / 255, green: 88 / 255, blue: 58 / 255, opacity: clamped) }
            if warm < 0.85 { return Color(red: 242 / 255, green: 152 / 255, blue: 104 / 255, opacity: clamped) }
            return Color(red: 255 / 255, green: 232 / 255, blue: 204 / 255, opacity: min(clamped * 1.15, 1))
        case .inkDust:
            if warm < 0.14 { return Color(red: 178 / 255, green: 58 / 255, blue: 33 / 255, opacity: min(clamped * 1.3, 1)) }
            return Color(red: 25 / 255, green: 23 / 255, blue: 19 / 255, opacity: min(clamped * 1.05, 1))
        case .goldJet:
            if warm < 0.35 { return Color(red: 212 / 255, green: 168 / 255, blue: 84 / 255, opacity: clamped) }
            if warm < 0.8 { return Color(red: 226 / 255, green: 88 / 255, blue: 58 / 255, opacity: clamped) }
            return Color(red: 255 / 255, green: 224 / 255, blue: 190 / 255, opacity: min(clamped * 1.1, 1))
        }
    }
}

// MARK: - 색상 유틸

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

    /// 흰색 방향으로 혼합한 파생색 — 발광하는 톤을 만든다.
    func mixedWithWhite(_ amount: CGFloat) -> Color {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return self }
        let clamped = min(1, max(0, amount))
        return Color(
            red: rgb.redComponent + (1 - rgb.redComponent) * clamped,
            green: rgb.greenComponent + (1 - rgb.greenComponent) * clamped,
            blue: rgb.blueComponent + (1 - rgb.blueComponent) * clamped
        )
    }

    /// hue를 회전하고 밝기를 배율 조정한 파생색.
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
