import AppCore
import SwiftUI

/// Wavy Dot Field 배경 파라미터.
public struct WavyDotFieldConfiguration: Sendable, Equatable {
    public var speed: Double
    /// 화면 긴 변 기준 도트 개수
    public var density: Double
    public var amplitude: Double
    public var vignette: Double
    public var blurRadius: Double
    /// 도트 크기 배율 (설정 연동)
    public var dotScale: Double
    /// 시점 각도 — 1.0 정면, 낮을수록 기울어진 평면 (설정 연동)
    public var pitch: Double

    public init(
        speed: Double = 0.6,
        density: Double = 34,
        amplitude: Double = 1.0,
        vignette: Double = 0.75,
        blurRadius: Double = 0,
        dotScale: Double = 1.0,
        pitch: Double = 1.0
    ) {
        self.speed = speed
        self.density = density
        self.amplitude = amplitude
        self.vignette = vignette
        self.blurRadius = blurRadius
        self.dotScale = dotScale
        self.pitch = pitch
    }
}

/// 시그니처 배경 — 도트가 물결치는 Metal 애니메이션.
/// 메인 화면에서는 그대로, 그 외 화면에서는 blurRadius를 올려 사용한다.
/// Low 품질에서는 애니메이션이 정지된 단일 프레임을 그린다.
public struct WavyDotFieldView: View {
    let configuration: WavyDotFieldConfiguration
    let tint: Color
    let quality: RenderQuality

    public init(
        configuration: WavyDotFieldConfiguration = WavyDotFieldConfiguration(),
        tint: Color,
        quality: RenderQuality = .standard
    ) {
        self.configuration = configuration
        self.tint = tint
        self.quality = quality
    }

    private static let shaderAvailable: Bool =
        Bundle.module.url(forResource: "default", withExtension: "metallib") != nil

    private var animated: Bool { quality != .low }

    public var body: some View {
        Group {
            if animated {
                TimelineView(.animation) { context in
                    field(time: context.date.timeIntervalSinceReferenceDate * configuration.speed)
                }
            } else {
                field(time: 0)
            }
        }
        .blur(radius: configuration.blurRadius)
        .allowsHitTesting(false)
        .drawingGroup()
    }

    @ViewBuilder
    private func field(time: TimeInterval) -> some View {
        if Self.shaderAvailable {
            Rectangle()
                .fill(Color.white)
                .colorEffect(
                    ShaderLibrary.bundle(.module).wavyDotField(
                        .boundingRect,
                        .float(Float(time.truncatingRemainder(dividingBy: 100_000))),
                        .float(Float(configuration.density)),
                        .float(Float(configuration.amplitude)),
                        .color(tint),
                        .float(Float(configuration.vignette)),
                        .float(Float(configuration.dotScale)),
                        .float(Float(configuration.pitch))
                    )
                )
        } else {
            canvasFallback(time: time)
        }
    }

    /// 셰이더를 쓸 수 없을 때의 Canvas 폴백 (동일한 물결 수식).
    private func canvasFallback(time: TimeInterval) -> some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            let pitch = max(configuration.pitch, 0.3)
            let cell = max(size.width, size.height) / max(configuration.density, 4)
            let cellY = cell * pitch
            let cols = Int(size.width / cell) + 2
            let rows = Int(size.height / cellY) + 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxDistance = hypot(center.x, center.y)

            for row in 0..<rows {
                for col in 0..<cols {
                    let ix = Double(col)
                    let iy = Double(row)
                    let waveA = sin(ix * 0.55 + iy * 0.35 + time)
                    let waveB = cos(ix * 0.32 - iy * 0.47 + time * 0.8)
                    let lift = sin((ix + iy) * 0.4 + time * 1.25)

                    let x = (ix + 0.5) * cell + waveA * cell * 0.22 * configuration.amplitude
                    let y = ((iy + 0.5) * cell + waveB * cell * 0.22 * configuration.amplitude) * pitch
                    let radius = cell * (0.085 + 0.055 * (0.5 + 0.5 * lift) * configuration.amplitude)
                        * max(configuration.dotScale, 0.2)

                    let distanceRatio = hypot(x - center.x, y - center.y) / maxDistance
                    let vig = 1.0 - min(1, max(0, (distanceRatio - 0.3) / 0.42)) * configuration.vignette
                    let brightness = 0.55 + 0.45 * (0.5 + 0.5 * lift)

                    let rect = CGRect(
                        x: x - radius, y: y - radius * pitch,
                        width: radius * 2, height: radius * 2 * pitch
                    )
                    context.opacity = vig * brightness
                    context.fill(Path(ellipseIn: rect), with: .color(tint))
                }
            }
        }
    }
}
