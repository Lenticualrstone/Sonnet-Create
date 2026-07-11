import AVFoundation
import SwiftUI

/// "살아있는 느낌"의 눈금-렌즈 슬라이더 (@uxmateja 리디자인 이식).
/// 캡슐 트랙 왼쪽에 값, 가운데에 세로 눈금 필드 — 채워진 눈금은 액센트,
/// 빈 눈금은 흐리게. 현재 위치의 유리 렌즈가 반경 내 눈금을 확대해 보여주고
/// (중앙 최대 1.7배 폭·1.9배 높이), 누르면 렌즈가 0.90으로 눌리며,
/// 조절 중에는 값 팝업이 14px 떠올랐다 650ms 뒤 사라진다.
/// 눈금을 넘어갈 때마다 520Hz 사인 틱이 26ms 스로틀로 울린다.
public struct BarSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let height: CGFloat
    let format: (Double) -> String
    let onCommit: () -> Void

    @State private var dragging = false
    @State private var hovering = false
    @State private var showPopup = false
    @State private var popupFadeTask: Task<Void, Never>?
    @State private var lastTickIndex = -1
    @Environment(\.resolvedAccent) private var accent
    @Environment(\.renderQuality) private var quality

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        height: CGFloat = 26,
        format: @escaping (Double) -> String = { String(format: "%.2f", $0) },
        onCommit: @escaping () -> Void = {}
    ) {
        _value = value
        self.range = range
        self.step = step
        self.height = height
        self.format = format
        self.onCommit = onCommit
    }

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    /// 렌즈 지름 — 원본 비율(트랙 24px : 구체 72px)은 폼 안에서 과해서 절반 수준으로.
    private var lensDiameter: CGFloat { height * 1.5 }
    /// 확대 반경 — 원본 33/72 비율 유지.
    private var magnifyRadius: CGFloat { lensDiameter * 0.46 }

    public var body: some View {
        GeometryReader { geo in
            let valueWidth: CGFloat = 44
            let fieldWidth = geo.size.width - valueWidth - 12
            let lensX = valueWidth + fieldWidth * CGFloat(fraction)

            ZStack(alignment: .leading) {
                // 트랙 — 유리 캡슐
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(hovering || dragging ? 0.08 : 0.055))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                    )

                // 값 (왼쪽 고정)
                Text(format(value))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(width: valueWidth, alignment: .center)
                    .allowsHitTesting(false)

                // 눈금 필드 + 렌즈
                TickField(
                    fraction: fraction,
                    lensCenterX: fieldWidth * CGFloat(fraction),
                    magnifyRadius: magnifyRadius,
                    accent: accent,
                    height: height
                )
                .frame(width: max(0, fieldWidth), height: height)
                .offset(x: valueWidth)
                .allowsHitTesting(false)

                lens
                    .position(x: lensX, y: geo.size.height / 2)
                    .allowsHitTesting(false)

                // 조절 중 떠오르는 값 팝업
                if showPopup {
                    Text(format(value))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .glassCapsule(quality: quality)
                        .position(x: lensX, y: -height * 0.55)
                        .transition(
                            .scale(scale: 0.92)
                                .combined(with: .offset(y: 14))
                                .combined(with: .opacity)
                        )
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        presentPopup()
                        setValue(fromX: gesture.location.x - valueWidth, width: fieldWidth)
                    }
                    .onEnded { _ in
                        dragging = false
                        schedulePopupFade()
                        onCommit()
                    }
            )
        }
        .frame(height: height)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: dragging)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement()
        .accessibilityValue(Text(format(value)))
        .accessibilityAdjustableAction { direction in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            @unknown default: break
            }
        }
    }

    /// 유리 구체 렌즈 — 0.5px 흰 테두리, 눌림 시 0.90 스케일 (원본 스펙).
    private var lens: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                // 구체감 — 상단 하이라이트
                Circle().fill(
                    RadialGradient(
                        colors: [.white.opacity(0.32), .white.opacity(0.04), .clear],
                        center: .init(x: 0.35, y: 0.25),
                        startRadius: 0,
                        endRadius: lensDiameter * 0.75
                    )
                )
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: dragging ? 5 : 3, y: 1.5)
            .frame(width: lensDiameter, height: lensDiameter)
            .scaleEffect(dragging ? 0.90 : 1)
    }

    private func setValue(fromX x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let targetFraction = min(1, max(0, x / width))
        var next = range.lowerBound + Double(targetFraction) * (range.upperBound - range.lowerBound)
        if let step, step > 0 {
            next = (next / step).rounded() * step
        }
        next = min(range.upperBound, max(range.lowerBound, next))
        guard next != value else { return }
        value = next

        // 눈금을 넘어갈 때마다 틱 — 26ms 스로틀은 플레이어가 처리
        let tickIndex = Int((next - range.lowerBound) / tickStride)
        if tickIndex != lastTickIndex {
            lastTickIndex = tickIndex
            SliderTickSound.shared.tick()
        }
    }

    private var tickStride: Double {
        step ?? (range.upperBound - range.lowerBound) / 40
    }

    private func presentPopup() {
        popupFadeTask?.cancel()
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)) {
            showPopup = true
        }
    }

    private func schedulePopupFade() {
        popupFadeTask?.cancel()
        popupFadeTask = Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showPopup = false }
        }
    }
}

// MARK: - 눈금 필드

/// 세로 눈금 열 — 렌즈 반경 안의 눈금은 중앙에 가까울수록
/// 최대 1.7배 넓고 1.9배 높게 그려진다 (돋보기 효과).
private struct TickField: View {
    let fraction: Double
    let lensCenterX: CGFloat
    let magnifyRadius: CGFloat
    let accent: Color
    let height: CGFloat

    private let pitch: CGFloat = 5 // 눈금 간격

    var body: some View {
        Canvas { context, size in
            let count = max(2, Int(size.width / pitch))
            let baseHeight = height * 0.42
            let filledUpTo = Int((Double(count - 1) * fraction).rounded())

            for index in 0..<count {
                let x = CGFloat(index) / CGFloat(count - 1) * (size.width - 2) + 1
                let distance = abs(x - lensCenterX)

                // 렌즈 확대 — 중앙 1.0 → 가장자리 0.0 (코사인 감쇠)
                var widthScale: CGFloat = 1
                var heightScale: CGFloat = 1
                if distance < magnifyRadius {
                    let t = cos((distance / magnifyRadius) * .pi / 2)
                    widthScale = 1 + 0.7 * t
                    heightScale = 1 + 0.9 * t
                }

                let tickWidth = 1.5 * widthScale
                let tickHeight = baseHeight * heightScale
                let rect = CGRect(
                    x: x - tickWidth / 2,
                    y: (size.height - tickHeight) / 2,
                    width: tickWidth,
                    height: tickHeight
                )
                let color = index <= filledUpTo
                    ? accent.opacity(0.9)
                    : Color.primary.opacity(0.18)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: tickWidth / 2),
                    with: .color(color)
                )
            }
        }
    }
}

// MARK: - 틱 사운드

/// 520Hz 사인파 틱 (5ms 어택, 45ms 디케이) — 원본의 Web Audio 레시피를
/// AVAudioEngine으로 이식. 26ms 스로틀, 생성 실패 시 조용히 무음.
@MainActor
final class SliderTickSound {
    static let shared = SliderTickSound()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var lastTick = Date.distantPast
    private var started = false

    func tick() {
        let now = Date()
        guard now.timeIntervalSince(lastTick) >= 0.026 else { return }
        lastTick = now
        startIfNeeded()
        guard started, let buffer else { return }
        player.scheduleBuffer(buffer, at: nil)
        if !player.isPlaying { player.play() }
    }

    private func startIfNeeded() {
        guard !started else { return }
        let sampleRate = 44100.0
        let duration = 0.06 // 5ms 어택 + 45ms 디케이 + 여유
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = pcm.floatChannelData?[0]
        else { return }
        pcm.frameLength = frames

        let attack = 0.005, decay = 0.045
        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            let envelope: Double = t < attack
                ? t / attack
                : max(0, 1 - (t - attack) / decay)
            // 1500Hz 저역통과 근사 — 순수 사인이라 사실상 원음 그대로
            channel[frame] = Float(sin(2 * .pi * 520 * t) * envelope * 0.12)
        }
        buffer = pcm

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }
}
