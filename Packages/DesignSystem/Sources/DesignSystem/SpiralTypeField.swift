import SwiftUI

// MARK: - 나선 타이포그래피

/// 글자들이 소용돌이를 그리며 배치되는 활자 필드.
/// 레퍼런스의 kinetic typography를 '인장 & 원고'로 번안한 것 —
/// 네온 대신 먹 활자가 종이 위에서 소용돌이치는 결.
///
/// 시동 스플래시(문서 제목이 모여드는 인트로)와 프로젝트 표지(정적 장식)가 공유한다.
public struct SpiralTypeField: View {
    /// 나선에 새길 문구들 — 안쪽에서 바깥으로 반복 배치된다.
    let words: [String]
    /// 회전 속도 (0이면 정지 — 정적 장식/모션 줄이기)
    var speed: Double
    /// 전체 불투명도 상한 (장식이므로 낮게)
    var maxOpacity: Double
    var color: Color

    @Environment(\.motionReduced) private var motionReduced
    @Environment(\.decorAnimationsPaused) private var animationsPaused

    public init(
        words: [String],
        speed: Double = 0.06,
        maxOpacity: Double = 0.5,
        color: Color = SonnetPalette.ink
    ) {
        self.words = words.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        self.speed = speed
        self.maxOpacity = maxOpacity
        self.color = color
    }

    public var body: some View {
        Group {
            if motionReduced || animationsPaused || speed == 0 {
                // 정지 프레임 — 나선 형태는 그대로, 회전만 멈춘다
                field(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                    field(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 아르키메데스 나선 위에 글자를 한 자씩 앉힌다 — 바깥으로 갈수록 커지고 옅어진다.
    private func field(time: TimeInterval) -> some View {
        Canvas { context, size in
            guard !words.isEmpty else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) * 0.62
            let rotation = time * speed

            // 안쪽에서 바깥으로 감기는 나선을 따라 글자를 흘린다
            var angle = 0.0
            var wordIndex = 0
            var charIndex = 0
            while true {
                // 아르키메데스 나선: r = a·θ
                let radius = 5.0 + angle * 5.4
                guard radius < maxRadius else { break }

                let word = words[wordIndex % words.count]
                let chars = Array(word)
                let char = chars[charIndex % chars.count]

                let theta = angle + rotation
                let position = CGPoint(
                    x: center.x + cos(theta) * radius,
                    y: center.y + sin(theta) * radius
                )
                // 바깥일수록 크고 옅게 — 깊이감
                let t = radius / maxRadius
                let fontSize = 6.0 + t * 13.0
                let opacity = maxOpacity * (0.15 + 0.85 * t) * 0.9

                var resolved = context.resolve(
                    Text(String(char))
                        .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color.opacity(opacity))
                )
                resolved.shading = .color(color.opacity(opacity))

                // 글자를 나선의 접선 방향으로 눕힌다
                context.drawLayer { layer in
                    layer.translateBy(x: position.x, y: position.y)
                    layer.rotate(by: .radians(theta + .pi / 2))
                    layer.draw(resolved, at: .zero, anchor: .center)
                }

                // 글자 간격이 반지름에 비례해 벌어지도록 각도 증분을 조절
                angle += max(0.12, 1.1 / max(radius / 6.5, 1))
                charIndex += 1
                if charIndex % max(chars.count, 1) == 0 {
                    wordIndex += 1
                    charIndex = 0
                    angle += 0.16 // 낱말 사이 여백
                }
                if angle > 220 { break } // 안전 상한
            }
        }
    }
}
