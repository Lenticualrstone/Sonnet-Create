import SwiftUI

// MARK: - 브랜드 마크 (6g 잉크 스트로크)

/// 잉크 스트로크 브랜드 마크 — 깃털을 45° 세 획으로 극단 추상화.
/// 획이 뒤로 갈수록 흐려지며 잉크가 마르는 잔상을 남긴다 (앱 아이콘 6g 확정안).
public struct InkStrokeMark: View {
    let size: CGFloat
    let color: Color

    public init(size: CGFloat = 20, color: Color = SonnetPalette.accent) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 24
            var main = Path()
            main.move(to: CGPoint(x: 4.5 * s, y: 20.5 * s))
            main.addLine(to: CGPoint(x: 19.5 * s, y: 4.5 * s))
            var second = Path()
            second.move(to: CGPoint(x: 9.5 * s, y: 15.5 * s))
            second.addLine(to: CGPoint(x: 15 * s, y: 10 * s))
            var third = Path()
            third.move(to: CGPoint(x: 12.5 * s, y: 18.5 * s))
            third.addLine(to: CGPoint(x: 18 * s, y: 13 * s))
            let style = StrokeStyle(lineWidth: 2.2 * s, lineCap: .round)
            context.stroke(main, with: .color(color), style: style)
            context.stroke(second, with: .color(color.opacity(0.75)), style: style)
            context.stroke(third, with: .color(color.opacity(0.45)), style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 버밀리온 스쿼클 위 잉크 스트로크 — 레일/스플래시용 풀컬러 로고 칩.
public struct InkStrokeLogoChip: View {
    let size: CGFloat

    public init(size: CGFloat = 38) {
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(hex: "#C2482D"), Color(hex: "#8E2D18")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(InkStrokeMark(size: size * 0.53, color: Color(hex: "#F6F4EF")))
            .shadow(color: Color(hex: "#B23A21").opacity(0.3), radius: size * 0.26, y: size * 0.08)
    }
}

// MARK: - 파일 유형 아이콘 (5a — 스트로크 1.6 · 직선/45° 문법)

/// 문서 유형 — DesignSystem이 DocumentKit에 의존하지 않도록 독립 enum.
public enum DSFileType: String, Sendable {
    case scenario, mindmap, page, character, attachment

    /// 유형 컬러 (버밀리온/파인/골드/테라코타/슬레이트)
    public var color: Color {
        switch self {
        case .scenario: SonnetPalette.typeScenario
        case .mindmap: SonnetPalette.typeMindmap
        case .page: SonnetPalette.typePage
        case .character: SonnetPalette.typeCharacter
        case .attachment: SonnetPalette.typeAttachment
        }
    }

    /// 확장자 표기 (.scen .scno .scpa)
    public var extensionLabel: String {
        switch self {
        case .scenario: ".scen"
        case .mindmap: ".scno"
        case .page: ".scpa"
        case .character: ".scpa ·인물"
        case .attachment: "첨부"
        }
    }
}

/// 파일 유형 아이콘 — 직선/45° 문법의 커스텀 글리프.
/// .scen 각진 말풍선+대사 행 / .scno 사각 노드 3 / .scpa 접힌 문서+블록 행 /
/// 캐릭터 다이아몬드 두상+사다리꼴 어깨 / 첨부 각진 산 능선.
public struct FileTypeIcon: View {
    let type: DSFileType
    let size: CGFloat
    var color: Color?

    public init(_ type: DSFileType, size: CGFloat = 14, color: Color? = nil) {
        self.type = type
        self.size = size
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width / 20
            let stroke = StrokeStyle(lineWidth: 1.6 * s, lineCap: .square, lineJoin: .miter)
            let tint = color ?? type.color
            for path in paths(scale: s) {
                context.stroke(path, with: .color(tint), style: stroke)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func paths(scale s: CGFloat) -> [Path] {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        switch type {
        case .scenario:
            // 각진 말풍선 + 대사 행
            var bubble = Path()
            bubble.move(to: pt(3, 4))
            bubble.addLine(to: pt(17, 4))
            bubble.addLine(to: pt(17, 13))
            bubble.addLine(to: pt(10, 13))
            bubble.addLine(to: pt(6, 17))
            bubble.addLine(to: pt(6, 13))
            bubble.addLine(to: pt(3, 13))
            bubble.closeSubpath()
            var lines = Path()
            lines.move(to: pt(6, 7.5)); lines.addLine(to: pt(14, 7.5))
            lines.move(to: pt(6, 10)); lines.addLine(to: pt(11, 10))
            return [bubble, lines]
        case .mindmap:
            // 사각 노드 3 + 연결선
            var nodes = Path()
            nodes.addRect(CGRect(x: 8 * s, y: 2.5 * s, width: 4 * s, height: 4 * s))
            nodes.addRect(CGRect(x: 2.5 * s, y: 13.5 * s, width: 4 * s, height: 4 * s))
            nodes.addRect(CGRect(x: 13.5 * s, y: 13.5 * s, width: 4 * s, height: 4 * s))
            var links = Path()
            links.move(to: pt(10, 6.5)); links.addLine(to: pt(10, 9.5))
            links.move(to: pt(10, 9.5)); links.addLine(to: pt(5.5, 13.5))
            links.move(to: pt(10, 9.5)); links.addLine(to: pt(14.5, 13.5))
            return [nodes, links]
        case .page:
            // 접힌 모서리 문서 + 블록 행
            var sheet = Path()
            sheet.move(to: pt(5, 2.5))
            sheet.addLine(to: pt(12, 2.5))
            sheet.addLine(to: pt(15.5, 6))
            sheet.addLine(to: pt(15.5, 17.5))
            sheet.addLine(to: pt(5, 17.5))
            sheet.closeSubpath()
            var fold = Path()
            fold.move(to: pt(12, 2.5))
            fold.addLine(to: pt(12, 6))
            fold.addLine(to: pt(15.5, 6))
            var rows = Path()
            rows.move(to: pt(7.5, 9.5)); rows.addLine(to: pt(13, 9.5))
            rows.move(to: pt(7.5, 12.5)); rows.addLine(to: pt(11, 12.5))
            return [sheet, fold, rows]
        case .character:
            // 다이아몬드 두상 + 사다리꼴 어깨
            var head = Path()
            head.move(to: pt(10, 3))
            head.addLine(to: pt(13, 6))
            head.addLine(to: pt(10, 9))
            head.addLine(to: pt(7, 6))
            head.closeSubpath()
            var shoulders = Path()
            shoulders.move(to: pt(4.5, 17))
            shoulders.addLine(to: pt(7, 11.5))
            shoulders.addLine(to: pt(13, 11.5))
            shoulders.addLine(to: pt(15.5, 17))
            shoulders.closeSubpath()
            return [head, shoulders]
        case .attachment:
            // 각진 산 능선 (이미지·스캔)
            var frame = Path()
            frame.addRect(CGRect(x: 3 * s, y: 4 * s, width: 14 * s, height: 12 * s))
            var ridge = Path()
            ridge.move(to: pt(4.5, 14))
            ridge.addLine(to: pt(8.5, 9.5))
            ridge.addLine(to: pt(11, 12))
            ridge.addLine(to: pt(13.5, 8.5))
            ridge.addLine(to: pt(15.5, 14))
            return [frame, ridge]
        }
    }
}

/// 유형 배지 (칩) — 아이콘 + 확장자를 함께 (5a: 텍스트 배지의 아이콘 배지 승격).
public struct FileTypeBadge: View {
    let type: DSFileType
    var showLabel: Bool

    public init(_ type: DSFileType, showLabel: Bool = true) {
        self.type = type
        self.showLabel = showLabel
    }

    public var body: some View {
        HStack(spacing: 4) {
            FileTypeIcon(type, size: 12)
            if showLabel {
                Text(type.extensionLabel)
                    .font(DSType.mono(size: 10.5, weight: .semibold))
            }
        }
        .foregroundStyle(type.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(type.color.opacity(0.1))
        )
    }
}
