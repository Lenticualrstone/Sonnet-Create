import AppCore
import DesignSystem
import SwiftUI

/// 앱 시동 스플래시 (8a) — 잉크 스트로크가 획순으로 그어지고(300ms×3, 스태거 180ms),
/// 워드마크가 rise로 떠오르고, 잉크 바가 차오른 뒤 180ms 페이드아웃으로
/// 홈 계단식 등장에 인계한다. 저사양(Low)에서는 9a 도트 매트릭스 부트로 대체.
struct SplashView: View {
    @Environment(\.renderQuality) private var quality
    let onFinished: () -> Void

    @State private var strokeProgress: [Double] = [0, 0, 0]
    @State private var wordmarkShown = false
    @State private var barProgress: Double = 0
    @State private var chipShown = false
    @State private var fadingOut = false

    var body: some View {
        ZStack {
            SonnetPalette.canvas.ignoresSafeArea()

            VStack(spacing: 26) {
                if quality == .low {
                    DotMatrixBoot()
                        .frame(width: 96, height: 96)
                } else {
                    logoChip
                }

                VStack(spacing: 8) {
                    Text("Sonnet Create")
                        .font(DSFonts.display(size: 26, weight: .bold))
                        .foregroundStyle(SonnetPalette.ink)
                    // 서브카피는 타자기 리빌 (9e) — 시동 연출과 문법 통일.
                    // 정적 원문으로 자리를 잡아 리빌 중 레이아웃이 흔들리지 않게 한다.
                    ZStack {
                        Text("marks · scenes · worlds")
                            .font(DSFonts.font(size: 12, family: .pretendard))
                            .kerning(0.6)
                            .opacity(0)
                        if wordmarkShown {
                            TypewriterText(
                                "marks · scenes · worlds",
                                font: DSFonts.font(size: 12, family: .pretendard),
                                color: SonnetPalette.inkMuted,
                                speed: 2.4,
                                kerning: 0.6
                            )
                        }
                    }
                }
                .opacity(wordmarkShown ? 1 : 0)
                .offset(y: wordmarkShown ? 0 : 14)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SonnetPalette.ink.opacity(0.09))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#C2482D"), Color(hex: "#B23A21")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: 220 * barProgress)
                }
                .frame(width: 220, height: 2.5)
                .opacity(wordmarkShown ? 1 : 0)
            }
        }
        .opacity(fadingOut ? 0 : 1)
        .onAppear(perform: run)
        .accessibilityHidden(true)
    }

    /// 버밀리온 스쿼클 + 획순 드로우.
    private var logoChip: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#C2482D"), Color(hex: "#8E2D18")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: 96, height: 96)
            .overlay(strokeCanvas)
            .shadow(color: Color(hex: "#B23A21").opacity(0.3), radius: 16, y: 8)
            .scaleEffect(chipShown ? 1 : 0.88)
            .opacity(chipShown ? 1 : 0)
    }

    private var strokeCanvas: some View {
        Canvas { context, size in
            let s = size.width * 0.56 / 24
            let origin = size.width * 0.22
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin + x * s, y: origin + y * s)
            }
            let strokes: [(CGPoint, CGPoint, Double)] = [
                (pt(4.5, 20.5), pt(19.5, 4.5), 1.0),
                (pt(9.5, 15.5), pt(15, 10), 0.75),
                (pt(12.5, 18.5), pt(18, 13), 0.45),
            ]
            let style = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round)
            for (index, (from, to, opacity)) in strokes.enumerated() {
                let progress = strokeProgress[index]
                guard progress > 0 else { continue }
                var path = Path()
                path.move(to: from)
                path.addLine(
                    to: CGPoint(
                        x: from.x + (to.x - from.x) * progress,
                        y: from.y + (to.y - from.y) * progress
                    )
                )
                context.stroke(path, with: .color(Color(hex: "#F6F4EF").opacity(opacity)), style: style)
            }
        }
    }

    /// 시퀀스: 칩 팝 → 획 3개 스태거 드로우 → 워드마크 rise → 잉크 바 → 페이드아웃.
    private func run() {
        withAnimation(DesignTokens.Motion.glassPop) { chipShown = true }
        for index in 0..<3 {
            withAnimation(
                Animation.timingCurve(0.22, 0.9, 0.24, 1, duration: 0.3)
                    .delay(0.12 + Double(index) * 0.18)
            ) {
                strokeProgress[index] = 1
            }
        }
        withAnimation(DesignTokens.Motion.rise.delay(0.62)) { wordmarkShown = true }
        withAnimation(Animation.timingCurve(0.4, 0.1, 0.3, 1, duration: 0.7).delay(0.75)) {
            barProgress = 1
        }
        Task {
            try? await Task.sleep(for: .milliseconds(1620))
            withAnimation(.easeIn(duration: 0.18)) { fadingOut = true }
            try? await Task.sleep(for: .milliseconds(190))
            onFinished()
        }
    }
}

/// 9a 도트 매트릭스 부트 — 인장 도트 격자에 잉크가 대각선으로 번지는 물결 (저사양 기본).
private struct DotMatrixBoot: View {
    // 'S' 도트 패턴 (5×7)
    private static let pattern = [
        ".###.",
        "#...#",
        "#....",
        ".###.",
        "....#",
        "#...#",
        ".###.",
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Grid(horizontalSpacing: 5, verticalSpacing: 5) {
                ForEach(0..<7, id: \.self) { row in
                    GridRow {
                        ForEach(0..<5, id: \.self) { col in
                            let on = Self.pattern[row][Self.pattern[row].index(Self.pattern[row].startIndex, offsetBy: col)] == "#"
                            let phase = Double(row + col) * 0.09
                            let wave = 0.5 + 0.5 * sin((t / 2.2 - phase) * 2 * .pi)
                            Circle()
                                .fill(on ? Color(hex: "#C2482D") : SonnetPalette.ink.opacity(0.07))
                                .frame(width: 10, height: 10)
                                .opacity(on ? 0.25 + 0.75 * wave : 1)
                                .scaleEffect(on ? 0.65 + 0.35 * wave : 1)
                        }
                    }
                }
            }
        }
    }
}
