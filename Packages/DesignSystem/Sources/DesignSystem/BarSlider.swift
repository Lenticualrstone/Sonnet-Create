import SwiftUI

/// 굵은 채움형 슬라이더 — 썸(손잡이) 없이 트랙 전체가 값만큼 채워지고,
/// 값이 바 안에 표시되며, 바 어디를 잡아도 드래그·클릭으로 조절된다.
/// (iOS 제어센터/@uxmateja 슬라이더 리디자인 계열)
public struct BarSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    let height: CGFloat
    let format: (Double) -> String
    let onCommit: () -> Void

    @State private var dragging = false
    @State private var hovering = false
    @Environment(\.resolvedAccent) private var accent

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        height: CGFloat = 24,
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

    public var body: some View {
        GeometryReader { geo in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let shape = RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
            ZStack(alignment: .leading) {
                shape.fill(Color.primary.opacity(hovering || dragging ? 0.10 : 0.06))
                shape
                    .fill(accent.opacity(dragging ? 0.55 : 0.42))
                    .frame(width: max(height * 0.5, geo.size.width * fraction))
            }
            .overlay(alignment: .trailing) {
                Text(format(value))
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        dragging = true
                        setValue(fromX: gesture.location.x, width: geo.size.width)
                    }
                    .onEnded { _ in
                        dragging = false
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

    private func setValue(fromX x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let fraction = min(1, max(0, x / width))
        var next = range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound)
        if let step, step > 0 {
            next = (next / step).rounded() * step
        }
        value = min(range.upperBound, max(range.lowerBound, next))
    }
}
