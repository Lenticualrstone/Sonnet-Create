import AppCore
import AppKit
import SwiftUI

// MARK: - 스타일

/// AI 스피어 디자인 바리에이션 — 설정 > 모양에서 프리뷰를 보며 선택한다.
public enum AISphereStyle: String, CaseIterable, Sendable, Identifiable {
    /// 파티클 — 입자로 이루어진 구 (기본). 평소엔 부드럽게 회전하고,
    /// 커서가 스치면 입자가 밀려나 흩어졌다 돌아오며, 생성 중엔 전체가 요동친다.
    case particle
    /// 리퀴드 글래스 — 유리구슬 안에서 색 블롭이 유영 (metasidd/Orb 레이어링 참고)
    case glass
    /// 홀로그래픽 — 진주광택 박막 간섭 무지개 (Metal)
    case holographic
    /// 잉크 — 종이 위 먹물 번짐, 앤티크 페이퍼 무드 (모노톤)
    case ink
    /// 플라즈마 — fbm 노이즈 밴드가 흐르는 발광체 (Metal)
    case plasma

    public var id: String { rawValue }

    public var labelKey: L10nKey {
        switch self {
        case .particle: .sphereStyleParticle
        case .glass: .sphereStyleGlass
        case .holographic: .sphereStyleHolographic
        case .ink: .sphereStyleInk
        case .plasma: .sphereStylePlasma
        }
    }
}

/// 파티클 스피어의 입자 밀도 — 설정에서 선택. 입자 수 배율로 작용한다.
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
        case .sparse: 80
        case .normal: 140
        case .dense: 240
        }
    }

    /// 작은 스피어(<44pt, 아이콘/헤더)의 입자 수 — 성능·가독 균형.
    var smallCount: Int {
        switch self {
        case .sparse: 44
        case .normal: 64
        case .dense: 96
        }
    }
}

private struct AISphereStyleKey: EnvironmentKey {
    static let defaultValue: AISphereStyle = .particle
}

private struct AISphereDensityKey: EnvironmentKey {
    static let defaultValue: AISphereDensity = .normal
}

public extension EnvironmentValues {
    /// 앱 전역 AI 스피어 스타일 (설정 주입) — AISphere가 style 파라미터 생략 시 사용.
    var aiSphereStyle: AISphereStyle {
        get { self[AISphereStyleKey.self] }
        set { self[AISphereStyleKey.self] = newValue }
    }

    /// 앱 전역 파티클 밀도 (설정 주입).
    var aiSphereDensity: AISphereDensity {
        get { self[AISphereDensityKey.self] }
        set { self[AISphereDensityKey.self] = newValue }
    }
}

// MARK: - 스피어

/// Sonnet AI의 아이덴티티 오브 — 스타일 바리에이션 + 호버 인터랙션.
/// 마우스를 올리면 하이라이트/블롭이 커서를 따라 기울고, `thinking`이면 더 빠르게 요동친다.
public struct AISphere: View {
    /// 스피어의 활동 상태 — idle(평온) < typing(사용자 입력 중, 미세 동요) < thinking(생성 중, 요동).
    public enum Activity: Sendable {
        case idle, typing, thinking

        /// 회전/흐름 속도 배율 — 모션 스펙 10: 대기 0.45× · 사고 1.7×.
        var speed: Double {
            switch self {
            case .idle: 0.45
            case .typing: 1.0
            case .thinking: 1.7
            }
        }

        /// 입자 반경 요동의 세기 (평온=0, 사고 중 난류 완전 발달).
        var agitation: Double {
            switch self {
            case .idle: 0.0
            case .typing: 0.5
            case .thinking: 1.6
            }
        }

        /// 코어 글로우/반경 맥동 진폭 — 생성 중 6% (모션 스펙 10c).
        var pulse: Double {
            switch self {
            case .idle: 0.0
            case .typing: 0.02
            case .thinking: 0.06
            }
        }
    }

    let size: CGFloat
    let activity: Activity
    let styleOverride: AISphereStyle?

    @Environment(\.resolvedAccent) private var accent
    @Environment(\.renderQuality) private var quality
    @Environment(\.aiSphereStyle) private var environmentStyle
    @Environment(\.aiSphereDensity) private var density

    /// 호버 위치 (정규화 -1...1, nil = 비호버) — 필드 인터랙션용
    @State private var hover: CGPoint?

    public init(size: CGFloat = 96, activity: Activity = .idle, style: AISphereStyle? = nil) {
        self.size = size
        self.activity = activity
        styleOverride = style
    }

    private var style: AISphereStyle { styleOverride ?? environmentStyle }
    private var speed: Double { activity.speed }

    public var body: some View {
        Group {
            if quality == .low {
                sphere(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    sphere(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                hover = CGPoint(
                    x: (point.x / size) * 2 - 1,
                    y: (point.y / size) * 2 - 1
                )
            case .ended:
                hover = nil
            }
        }
    }

    @ViewBuilder
    private func sphere(time: TimeInterval) -> some View {
        let t = time * speed
        let breathe = 1 + activity.pulse * sin(t * 2.6)
        Group {
            switch style {
            case .particle: particleSphere(t)
            case .glass: glassSphere(t)
            case .holographic: shaderSphere(function: "aiSphereHolo", time: time)
            case .ink: inkSphere(t)
            case .plasma: shaderSphere(function: "aiSpherePlasma", time: time)
            }
        }
        .compositingGroup()
        .frame(width: size, height: size)
        .scaleEffect(breathe)
        .animation(DesignTokens.Motion.gentle, value: hover == nil)
    }

    // MARK: 파티클 — 입자 구 (기본)

    /// 피보나치 나선으로 구면에 고르게 뿌린 단위 방향 벡터들.
    private static func fibonacciDirections(count: Int) -> [SIMD3<Double>] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { index in
            let y = 1 - (Double(index) + 0.5) / Double(count) * 2 // 1 → -1
            let ringRadius = (1 - y * y).squareRoot()
            let theta = golden * Double(index)
            return SIMD3(cos(theta) * ringRadius, y, sin(theta) * ringRadius)
        }
    }

    /// 밀도 3종 × 대/소 6개 방향 세트를 미리 계산 (매 프레임 재계산 방지, 불변이라 동시성 안전).
    private static let directionSets: [String: [SIMD3<Double>]] = {
        var sets: [String: [SIMD3<Double>]] = [:]
        for density in AISphereDensity.allCases {
            sets["\(density.rawValue)-L"] = fibonacciDirections(count: density.largeCount)
            sets["\(density.rawValue)-S"] = fibonacciDirections(count: density.smallCount)
        }
        return sets
    }()

    private func directions() -> [SIMD3<Double>] {
        let key = "\(density.rawValue)-\(size < 44 ? "S" : "L")"
        // 키는 항상 존재하지만(전 밀도 사전 계산), 방어적으로 폴백을 둔다.
        return Self.directionSets[key] ?? Self.directionSets["normal-L"] ?? Self.fibonacciDirections(count: 140)
    }

    @ViewBuilder
    private func particleSphere(_ t: Double) -> some View {
        let base = vividBase
        ZStack {
            // 은은한 후광 — 입자 사이로 배어 나오는 빛 (활동이 높을수록 밝아진다)
            Circle()
                .fill(base.opacity(0.16 + 0.14 * activity.agitation))
                .blur(radius: size * 0.13)
                .scaleEffect(0.95)

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let sphereRadius = min(canvasSize.width, canvasSize.height) * 0.42
                let directions = directions()

                // 느린 2축 회전 — 살아 있는 느낌의 핵심
                let yaw = t * 0.4
                let pitch = 0.4 + sin(t * 0.19) * 0.22
                let cosYaw = cos(yaw)
                let sinYaw = sin(yaw)
                let cosPitch = cos(pitch)
                let sinPitch = sin(pitch)

                // 호버 지점 (뷰 좌표) — 입자들이 이 점에서 밀려난다
                let hoverPoint: CGPoint? = hover.map {
                    CGPoint(
                        x: ($0.x * 0.5 + 0.5) * canvasSize.width,
                        y: ($0.y * 0.5 + 0.5) * canvasSize.height
                    )
                }
                let disperseRadius = sphereRadius * 0.85
                let agitationLevel = activity.agitation

                // 투영 후 깊이순 정렬 (뒤 → 앞) — 앞 입자가 위에 그려진다.
                // rest는 요동/분산 전 원위치, position은 분산 후 최종 위치 (둘 사이가 잔상 트레일).
                var projected: [(position: CGPoint, rest: CGPoint, depth: Double, scatter: Double)] = []
                projected.reserveCapacity(directions.count)
                for (index, direction) in directions.enumerated() {
                    // yaw(수직축) 회전
                    let x1 = direction.x * cosYaw + direction.z * sinYaw
                    let z1 = -direction.x * sinYaw + direction.z * cosYaw
                    // pitch(수평축) 회전
                    let y2 = direction.y * cosPitch - z1 * sinPitch
                    let z2 = direction.y * sinPitch + z1 * cosPitch

                    // 반경 요동 — 평소엔 잔잔한 숨, 입력/생성 중엔 입자가 흩날린다
                    let phase = Double(index) * 2.399963
                    let calm = 0.03 * sin(t * 1.3 + phase)
                    let energetic = 0.18 * sin(t * 3.6 + phase) + 0.06 * sin(t * 7.1 + phase * 1.7)
                    let agitation = calm + agitationLevel * (energetic - calm)
                    let particleRadius = sphereRadius * (1 + agitation)

                    let rest = CGPoint(
                        x: center.x + x1 * particleRadius,
                        y: center.y + y2 * particleRadius
                    )
                    var position = rest
                    var scatter = 0.0

                    // 커서 분산 — 가까운 입자일수록 강하게 밀려난다 (가우시안 감쇠)
                    if let hoverPoint {
                        let dx = position.x - hoverPoint.x
                        let dy = position.y - hoverPoint.y
                        let distance = max(2, (dx * dx + dy * dy).squareRoot())
                        let influence = exp(-(distance * distance) / (disperseRadius * disperseRadius * 0.5))
                        scatter = influence
                        let push = influence * sphereRadius * 0.55
                        position.x += dx / distance * push
                        position.y += dy / distance * push
                    }

                    projected.append((position: position, rest: rest, depth: (z2 + 1) / 2, scatter: scatter))
                }
                projected.sort { $0.depth < $1.depth }

                for particle in projected {
                    let depth = particle.depth
                    let dotRadius = sphereRadius * 0.045 * (0.55 + 0.85 * depth)
                    let tone = base.mixedWithWhite(0.12 + 0.5 * depth)

                    // 분산된 입자는 원위치까지 옅은 잔상 꼬리를 남긴다 (밀려난 궤적)
                    if particle.scatter > 0.04 {
                        var trail = Path()
                        trail.move(to: particle.rest)
                        trail.addLine(to: particle.position)
                        context.stroke(
                            trail,
                            with: .color(tone.opacity(0.10 + 0.28 * depth * particle.scatter)),
                            style: StrokeStyle(lineWidth: dotRadius * 0.9, lineCap: .round)
                        )
                    }
                    let rect = CGRect(
                        x: particle.position.x - dotRadius,
                        y: particle.position.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(tone.opacity(0.28 + 0.62 * depth))
                    )
                }
            }
        }
    }

    // MARK: 글래스 — 유리구슬 속 색 블롭

    @ViewBuilder
    private func glassSphere(_ t: Double) -> some View {
        let base = vividBase
        let hoverX = hover?.x ?? 0
        let hoverY = hover?.y ?? 0
        ZStack {
            // 은은한 후광 — 호버 시 살짝 밝아진다
            Circle()
                .fill(base.opacity(hover == nil ? 0.22 : 0.34))
                .blur(radius: size * 0.14)
                .scaleEffect(1.08)

            // 유리 바탕 — 위에서 빛이 드는 밝은 구
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            base.mixedWithWhite(0.72).opacity(0.85),
                            base.mixedWithWhite(0.4).opacity(0.75),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 유영하는 색 블롭 두 개 — 서로 반대로 공전, 호버 방향으로 패럴랙스
            glassBlob(color: base.opacity(0.55), t: t, direction: 1, phase: 0)
                .offset(x: hoverX * size * 0.05, y: hoverY * size * 0.05)
            glassBlob(color: base.hueShifted(0.09, brightness: 1.1).opacity(0.42), t: t, direction: -1, phase: 2.3)
                .offset(x: hoverX * size * 0.09, y: hoverY * size * 0.09)

            // 바닥 깊이 — 아래쪽이 살짝 가라앉는 내부 그림자
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.clear, base.opacity(0.28)],
                        center: UnitPoint(x: 0.5, y: 0.25),
                        startRadius: size * 0.30,
                        endRadius: size * 0.62
                    )
                )

            // 상단 광택 — 호버하면 커서를 따라온다
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.85), .clear],
                        center: UnitPoint(x: 0.35 + hoverX * 0.18, y: 0.24 + hoverY * 0.18),
                        startRadius: 0,
                        endRadius: size * 0.36
                    )
                )
                .blendMode(.screen)

            // 유리 테두리 — 위는 빛나고 아래로 사라진다
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color.white.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(1, size * 0.014)
                )
        }
        .clipShape(Circle())
    }

    /// 글래스 내부의 블롭 한 장 — 블러 처리된 타원이 중심 주위를 공전한다.
    private func glassBlob(color: Color, t: Double, direction: Double, phase: Double) -> some View {
        Ellipse()
            .fill(
                RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: size * 0.42)
            )
            .frame(width: size * 0.95, height: size * 0.7)
            .offset(y: size * 0.16)
            .rotationEffect(.radians(t * 0.45 * direction + phase))
            .blur(radius: size * 0.07)
    }

    // MARK: 잉크 — 종이 위 먹물 번짐 (앤티크 모노)

    @ViewBuilder
    private func inkSphere(_ t: Double) -> some View {
        let ink = accent
        let hoverX = hover?.x ?? 0
        let hoverY = hover?.y ?? 0
        ZStack {
            // 종이 바탕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [ink.mixedWithWhite(0.94), ink.mixedWithWhite(0.78)],
                        center: UnitPoint(x: 0.42, y: 0.36),
                        startRadius: 0,
                        endRadius: size * 0.62
                    )
                )

            // 먹물 세 획 — 느리게 각자 다른 속도로 맴돈다, 호버 방향으로 쏠림
            inkWisp(t: t, speedFactor: 0.30, phase: 0.0, opacity: 0.34)
            inkWisp(t: t, speedFactor: -0.22, phase: 2.4, opacity: 0.26)
            inkWisp(t: t, speedFactor: 0.16, phase: 4.5, opacity: 0.20)

            // 종이 그레인 — 앤티크 페이퍼 질감
            GrainOverlay(color: ink, opacity: 0.05, density: 320)
                .clipShape(Circle())

            // 가는 먹선 테두리
            Circle()
                .strokeBorder(ink.opacity(0.45), lineWidth: max(1, size * 0.012))
        }
        .offset(x: hoverX * size * 0.02, y: hoverY * size * 0.02)
        .clipShape(Circle())
    }

    /// 먹물 한 획 — 블러된 캡슐이 중심 주위를 돈다.
    private func inkWisp(t: Double, speedFactor: Double, phase: Double, opacity: Double) -> some View {
        Capsule()
            .fill(accent.opacity(opacity))
            .frame(width: size * 0.78, height: size * 0.3)
            .offset(x: size * 0.1, y: (hover?.y ?? 0) * size * 0.06)
            .rotationEffect(.radians(t * speedFactor + phase))
            .blur(radius: size * 0.11)
    }

    // MARK: Metal 셰이더 스타일 (홀로그래픽/플라즈마)

    @ViewBuilder
    private func shaderSphere(function: String, time: TimeInterval) -> some View {
        ZStack {
            Circle()
                .fill(vividBase.opacity(style == .holographic ? 0.28 : 0.5))
                .blur(radius: size * 0.16)
                .scaleEffect(1.02 + 0.03 * sin(time * speed * 0.9))

            // colorEffect는 뷰의 픽셀을 변환하므로 캔버스는 불투명해야 한다 (투명 뷰는 스킵됨)
            Rectangle()
                .fill(Color.white)
                .colorEffect(
                    ShaderLibrary.bundle(.module)[dynamicMember: function](
                        .boundingRect,
                        .float(Float(time)),
                        .float(Float(baseHue)),
                        .float(Float(activity.agitation)),
                        .float2(Float(hover?.x ?? 0), Float(hover?.y ?? 0))
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.7), .clear],
                        center: UnitPoint(x: 0.34 + (hover?.x ?? 0) * 0.15, y: 0.26 + (hover?.y ?? 0) * 0.15),
                        startRadius: 0,
                        endRadius: size * 0.34
                    )
                )
                .blendMode(.screen)
        }
    }

    /// vividBase의 hue (0...1) — 셰이더 색상축.
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
