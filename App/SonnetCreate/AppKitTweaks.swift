import AppKit
import SwiftUI

/// 시스템 타이틀바 드래그 차단 — hiddenTitleBar 윈도우도 상단 영역은 여전히
/// 시스템이 "타이틀바"로 취급해 마우스 다운+이동이 창을 끌고 간다. 탭 칩을
/// 드래그해 순서를 바꿀 때 창까지 따라오던 원인. 이 뷰를 컨트롤 밑에 깔면
/// 해당 영역에서 시스템 창 이동이 꺼진다 (창 이동은 명시적 WindowDragGesture 영역 전담).
struct BlockWindowDrag: NSViewRepresentable {
    final class Blocker: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }

    func makeNSView(context: Context) -> Blocker { Blocker() }
    func updateNSView(_ nsView: Blocker, context: Context) {}
}

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
