import AppCore
import SwiftUI

/// ASCII 웨이브 필드 — 삼각함수 간섭장을 글자 램프(밝기 → 문자)에 매핑해
/// 터미널 감성의 물결 애니메이션을 그린다. 홈 히어로의 픽셀 디밍 필드를 대체.
/// (참고: waves-ascii 시뮬레이터의 행·열 위상 이동 기법 — 행마다 살짝 어긋난
/// 사인파가 겹치며 문자들이 리듬감 있게 떠오르고 가라앉는다.)
public struct ASCIIWaveField: View {
    let columns: Int
    let rows: Int
    let fontSize: CGFloat
    let color: Color
    let quality: RenderQuality
    let speed: Double

    /// 어두움 → 밝음 순의 글자 램프. 공백이 "꺼짐"이라 필드 가장자리가 자연히 사라진다.
    private static let ramp: [Character] = Array(" ·:∗+✳#@")

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
                    canvas(time: context.date.timeIntervalSinceReferenceDate * speed)
                }
            }
        }
        .frame(height: CGFloat(rows) * fontSize * 1.25)
        .accessibilityHidden(true)
    }

    private func canvas(time: TimeInterval) -> some View {
        Canvas { context, size in
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
            for row in 0..<rows {
                for col in 0..<columns {
                    let value = fieldValue(col: col, row: row, time: time)
                    let index = min(Self.ramp.count - 1, max(0, Int(value * Double(Self.ramp.count))))
                    guard index > 0 else { continue } // 공백은 그리지 않는다
                    let point = CGPoint(
                        x: (CGFloat(col) + 0.5) * cellWidth,
                        y: (CGFloat(row) + 0.5) * cellHeight
                    )
                    context.draw(glyphs[index], at: point)
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
