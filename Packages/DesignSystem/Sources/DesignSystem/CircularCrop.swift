import AppCore
import AppKit
import SwiftUI

// MARK: - 원형 크롭

/// 원형으로 크롭된 이미지 — 줌과 정규화(지름 대비 비율) 오프셋을 적용해 그린다.
/// 캐릭터 아바타와 작가 프로필 사진이 같은 파라미터 체계를 쓴다.
public struct CroppedCircleImage: View {
    let image: NSImage
    let zoom: Double
    let offsetX: Double
    let offsetY: Double
    let size: CGFloat

    public init(image: NSImage, zoom: Double = 1, offsetX: Double = 0, offsetY: Double = 0, size: CGFloat) {
        self.image = image
        self.zoom = zoom
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.size = size
    }

    public var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fill)
            .scaleEffect(zoom)
            .offset(x: offsetX * size, y: offsetY * size)
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

/// 원형 크롭 편집기 — 드래그로 팬, 슬라이더로 줌. 원 밖 영역은 고스트로 비쳐
/// 어디가 잘리는지 보여준다. 오프셋은 지름 대비 비율로 바인딩한다.
public struct CircularCropEditor: View {
    let image: NSImage
    @Binding var zoom: Double
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    let diameter: CGFloat
    let onCommit: () -> Void

    @State private var dragBase: CGSize?

    public init(
        image: NSImage,
        zoom: Binding<Double>,
        offsetX: Binding<Double>,
        offsetY: Binding<Double>,
        diameter: CGFloat = 200,
        onCommit: @escaping () -> Void = {}
    ) {
        self.image = image
        _zoom = zoom
        _offsetX = offsetX
        _offsetY = offsetY
        self.diameter = diameter
        self.onCommit = onCommit
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            ZStack {
                preview.opacity(0.25)
                preview.clipShape(Circle())
                Circle()
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragBase == nil {
                            dragBase = CGSize(width: offsetX * diameter, height: offsetY * diameter)
                        }
                        guard let base = dragBase else { return }
                        offsetX = (base.width + value.translation.width) / diameter
                        offsetY = (base.height + value.translation.height) / diameter
                    }
                    .onEnded { _ in
                        dragBase = nil
                        onCommit()
                    }
            )

            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $zoom, in: 1...3) { editing in
                    if !editing { onCommit() }
                }
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            }
            .frame(width: diameter)
        }
    }

    /// 클립 없는 프리뷰 — 고스트 레이어는 그대로, 본 레이어는 호출부에서 원형 클립.
    private var preview: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .aspectRatio(contentMode: .fill)
            .scaleEffect(zoom)
            .offset(x: offsetX * diameter, y: offsetY * diameter)
            .frame(width: diameter, height: diameter)
    }
}
