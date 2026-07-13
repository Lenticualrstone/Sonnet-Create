import AppCore
import SwiftUI

/// ASCII 웨이브 필드 — 삼각함수 간섭장을 글자 램프(밝기 → 문자)에 매핑해
/// 터미널 감성의 물결 애니메이션을 그린다. 홈 히어로의 픽셀 디밍 필드를 대체.
///
/// 인터랙션: 커서가 지나간 궤적을 교란점 트레일로 기록하고, 근처 글자들이
/// 교란점에서 **밀려나 흩어졌다가**(변위 + 흐려짐) 시간이 지나면 제자리로
/// 돌아온다 — 위상만 바꾸는 리플이 아니라 실제 분산 느낌을 준다.
public struct ASCIIWaveField: View {
    let columns: Int
    let rows: Int
    let fontSize: CGFloat
    let color: Color
    let quality: RenderQuality
    let speed: Double

    /// 어두움 → 밝음 순의 글자 램프. 공백이 "꺼짐"이라 필드 가장자리가 자연히 사라진다.
    private static let ramp: [Character] = Array(" ·:∗+✳#@")

    /// 커서 궤적의 교란점 하나 — 시간이 지나며 힘이 사그라든다.
    private struct Disturbance {
        let point: CGPoint
        let time: TimeInterval
    }

    @State private var disturbances: [Disturbance] = []

    public init(
        columns: Int = 44,
        rows: Int = 6,
        fontSize: CGFloat = 11,
        color: Color,
        quality: RenderQuality = .standard,
        speed: Double = 1
    ) {
        self.columns = columns
        self.rows = rows
        self.fontSize = fontSize
        self.color = color
        self.quality = quality
        self.speed = speed
    }

    public var body: some View {
        Group {
            if quality == .low {
                // 저품질: 애니메이션 없이 한 프레임만
                canvas(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / (quality == .high ? 24.0 : 15.0))) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(height: CGFloat(rows) * fontSize * 1.25)
        .onContinuousHover { phase in
            guard case .active(let point) = phase else { return }
            recordDisturbance(at: point)
        }
        .accessibilityHidden(true)
    }

    /// 커서 이동을 교란점으로 기록 — 너무 촘촘히 쌓이지 않게 최소 이동 거리로 걸러낸다.
    private func recordDisturbance(at point: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        if let last = disturbances.last {
            let dx = point.x - last.point.x
            let dy = point.y - last.point.y
            guard dx * dx + dy * dy > 36 || now - last.time > 0.08 else { return }
        }
        disturbances.append(Disturbance(point: point, time: now))
        if disturbances.count > 14 {
            disturbances.removeFirst(disturbances.count - 14)
        }
    }

    private func canvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            // columns/rows가 1 이하이거나 크기가 0이면 나눗셈이 NaN을 만든다 — 방어적으로 중단
            guard columns > 1, rows > 0, size.width > 0, size.height > 0 else { return }
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows)
            // 램프 글자를 프레임당 1회씩만 리졸브 — 셀마다 리졸브하면 프레임 비용이 급증한다
            let glyphs = Self.ramp.map { char in
                context.resolve(
                    Text(String(char))
                        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                        .foregroundStyle(color.opacity(0.62))
                )
            }

            // 살아 있는 교란점만 (1.1초 감쇠) — 프레임 시계 기준
            let now = Date().timeIntervalSinceReferenceDate
            let active = disturbances.filter { now - $0.time < 1.1 }
            let scatterRadius = cellWidth * 5.5 // 교란 영향 반경

            for row in 0..<rows {
                for col in 0..<columns {
                    let value = fieldValue(col: col, row: row, time: time * speed)
                    var point = CGPoint(
                        x: (CGFloat(col) + 0.5) * cellWidth,
                        y: (CGFloat(row) + 0.5) * cellHeight
                    )

                    // 교란점들로부터 밀려나는 변위 — 가까울수록·최근일수록 강하게,
                    // 감쇠가 끝나면 부드럽게 제자리로 돌아온다.
                    var pushX: CGFloat = 0
                    var pushY: CGFloat = 0
                    var scatterEnergy: CGFloat = 0
                    for disturbance in active {
                        let age = CGFloat(now - disturbance.time)
                        let decay = exp(-age * 3.2) // 시간 감쇠
                        let dx = point.x - disturbance.point.x
                        let dy = point.y - disturbance.point.y
                        let distance = max(4, (dx * dx + dy * dy).squareRoot())
                        guard distance < scatterRadius else { continue }
                        let falloff = 1 - distance / scatterRadius // 거리 감쇠 (0...1)
                        let strength = decay * falloff * falloff
                        let magnitude = strength * cellWidth * 2.6
                        pushX += dx / distance * magnitude
                        pushY += dy / distance * magnitude
                        scatterEnergy = max(scatterEnergy, strength)
                    }
                    point.x += pushX
                    point.y += pushY

                    // 흩어진 글자는 흐려진다 — 밀도가 빠져나간 느낌
                    let effective = value * Double(1 - scatterEnergy * 0.75)
                    let index = min(Self.ramp.count - 1, max(0, Int(effective * Double(Self.ramp.count))))
                    guard index > 0 else { continue }
                    if scatterEnergy > 0.02 {
                        var scattered = context
                        scattered.opacity = Double(1 - scatterEnergy * 0.45)
                        scattered.draw(glyphs[index], at: point)
                    } else {
                        context.draw(glyphs[index], at: point)
                    }
                }
            }
        }
    }

    /// 세 사인파의 간섭 + 가장자리 페이드 → 0...1 밝기.
    private func fieldValue(col: Int, row: Int, time: Double) -> Double {
        let x = Double(col)
        let y = Double(row)
        let wave = (
            sin(x * 0.42 + time * 1.5)
                + sin(x * 0.23 + y * 0.9 - time * 1.05)
                + sin(y * 1.35 + time * 0.65)
        ) / 3.0 // -1...1
        let normalized = 0.5 + 0.5 * wave

        // 가로 가장자리로 갈수록 사라지게 (히어로 중앙 강조)
        let centerDistance = abs(x / Double(columns - 1) - 0.5) * 2 // 0(중앙)...1(가장자리)
        let fade = max(0, 1 - pow(centerDistance, 2.2))
        return normalized * fade
    }
}
