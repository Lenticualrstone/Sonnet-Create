import AppKit

/// 멀티라인 TextField(axis: .vertical)가 포커스될 때 NSTextView 필드 에디터가
/// 불투명 백색 배경을 그려 Sonnet 캔버스와 충돌하는 문제의 전역 해결.
extension NSTextView {
    // frame 갱신 시점 보정만으로는 필드 에디터가 백색을 그리는 경우가 남아,
    // drawsBackground 자체를 항상 false로 강제한다.
    open override var drawsBackground: Bool {
        get { false }
        set {}
    }

    open override var frame: CGRect {
        didSet {
            backgroundColor = .clear
        }
    }
}
