import AppCore
import AppKit
import DesignSystem
import DocumentKit
import SwiftUI

/// 사용자 프로필 페이지 — 이름 설정, 워크스페이스 통계, GitHub식 기여도 그래프.
struct ProfileView: View {
    @Environment(AppState.self) private var app
    @Environment(\.renderQuality) private var quality
    @Environment(\.resolvedAccent) private var accent

    @State private var nameDraft = ""

    var body: some View {
        let l10n = Localizer.shared
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                // 헤더 — 아바타 + 이름(즉시 저장)
                HStack(spacing: DesignTokens.Spacing.l) {
                    profileAvatar

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(l10n.t(.profile), text: $nameDraft)
                            .textFieldStyle(.plain)
                            .font(.system(size: 26, weight: .bold))
                            .onSubmit(commitName)
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption)
                            Text(app.workspace.rootURL.path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.secondary)
                        if nameDraft != app.settings.applied.authorName {
                            Button(l10n.t(.save), action: commitName)
                                .controlSize(.small)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }

                // 워크스페이스 통계
                statsRow(l10n)

                // 집필 목표 — 오늘 쓴 글자 수 / 목표, 연속 일수
                writingGoalCard(l10n)

                // 주간 집필 리포트 — 최근 7일 막대 + 합계/최고/지난주 대비
                weeklyReportCard(l10n)

                // 기여도 그래프 (GitHub식)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    Label(l10n.t(.contributions), systemImage: "square.grid.4x3.fill")
                        .font(.headline)
                    ContributionGraph()
                    if app.stats.activity.isEmpty {
                        Text(l10n.t(.activityEmpty))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(DesignTokens.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                        .fill(SonnetPalette.surface)
                )
            }
            .padding(DesignTokens.Spacing.l)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear { nameDraft = app.settings.applied.authorName }
    }

    private func commitName() {
        app.settings.draft.authorName = nameDraft
        app.settings.save()
    }

    /// 설정에 저장된 프로필 사진(authorPhotoPath)이 있으면 표시 — 사이드바 아바타와 동일한 소스.
    @ViewBuilder
    private var profileAvatar: some View {
        let path = app.settings.applied.authorPhotoPath
        if !path.isEmpty, let image = ImageThumbnailCache.thumbnail(for: URL(fileURLWithPath: path), maxPointSize: 96) {
            CroppedCircleImage(
                image: image,
                zoom: app.settings.applied.authorCropZoom,
                offsetX: app.settings.applied.authorCropOffsetX,
                offsetY: app.settings.applied.authorCropOffsetY,
                size: 96
            )
        } else {
            ZStack {
                Circle().fill(accent.opacity(0.16))
                Image(systemName: "person.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 96, height: 96)
        }
    }

    private func writingGoalCard(_ l10n: Localizer) -> some View {
        let today = app.stats.todayWriting
        let goal = max(1, Int(app.settings.applied.dailyWritingGoal))
        let progress = min(1.0, Double(today) / Double(goal))
        let streak = app.stats.writingStreak

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack {
                Label(l10n.t(.writingGoal), systemImage: "target")
                    .font(.headline)
                Spacer()
                if streak > 0 {
                    Label(String(format: l10n.t(.streakDays), streak), systemImage: "flame.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(today)")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("/ \(goal)\(l10n.t(.charsUnit))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if today >= goal {
                    Label(l10n.t(.goalReached), systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(accent)
                }
            }

            // 진행 바
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(accent.opacity(0.75))
                        .frame(width: max(6, geo.size.width * progress))
                }
            }
            .frame(height: 7)
            .animation(DesignTokens.Motion.gentle, value: progress)
        }
        .padding(DesignTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                .fill(SonnetPalette.surface)
        )
    }

    private func weeklyReportCard(_ l10n: Localizer) -> some View {
        let week = app.stats.recentWeekWriting
        let total = week.reduce(0) { $0 + $1.count }
        let best = week.max { $0.count < $1.count }
        let previous = app.stats.previousWeekTotal
        let maxCount = max(1, week.map(\.count).max() ?? 1)
        let goal = max(1, Int(app.settings.applied.dailyWritingGoal))

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack {
                Label(l10n.t(.weeklyReport), systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                if previous > 0 || total > 0 {
                    weeklyDelta(l10n, total: total, previous: previous)
                }
            }

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.l) {
                // 7일 미니 막대 — 목표 달성일은 액센트 풀톤
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(week, id: \.date) { day in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(day.count >= goal ? accent : accent.opacity(day.count >= 1 ? 0.45 : 0.12))
                                .frame(width: 18, height: max(4, 46 * CGFloat(day.count) / CGFloat(maxCount)))
                            Text(day.date, format: .dateTime.weekday(.narrow))
                                .font(.caption2)
                                .foregroundStyle(Calendar.current.isDateInToday(day.date) ? accent : Color.secondary)
                        }
                        .help("\(day.date.formatted(date: .abbreviated, time: .omitted)) — \(day.count)\(l10n.t(.charsUnit))")
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(total)")
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        Text(l10n.t(.weeklyTotal))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    // 튜플의 count 필드 — swiftformat isEmpty 규칙을 피하려고 >= 1 사용
                    if let best, best.count >= 1 {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(best.count)")
                                .font(.callout.weight(.semibold).monospacedDigit())
                            Text("\(l10n.t(.weeklyBestDay)) · \(best.date.formatted(.dateTime.weekday(.abbreviated)))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: .continuous)
                .fill(SonnetPalette.surface)
        )
    }

    /// 지난주(8~14일 전) 대비 증감 배지.
    @ViewBuilder
    private func weeklyDelta(_ l10n: Localizer, total: Int, previous: Int) -> some View {
        let delta = total - previous
        let symbol = delta > 0 ? "arrow.up.right" : (delta < 0 ? "arrow.down.right" : "minus")
        let color: Color = delta > 0 ? .green : (delta < 0 ? .orange : .secondary)
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(delta == 0 ? "±0" : (delta > 0 ? "+\(delta)" : "\(delta)"))
                .font(.caption.weight(.semibold).monospacedDigit())
            Text(l10n.t(.vsLastWeek))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(color)
    }

    private func statsRow(_ l10n: Localizer) -> some View {
        let docs = app.workspace.visibleDocuments
        let stats: [(key: L10nKey, symbol: String, count: Int)] = [
            (.project, "folder.fill", app.workspace.projects.count),
            (.scenario, "text.bubble", docs.filter { $0.envelope.kind == .scenario }.count),
            (.mindmap, "point.3.connected.trianglepath.dotted", docs.filter { $0.envelope.kind == .mindmap }.count),
            (.page, "doc.richtext", docs.filter { $0.envelope.kind == .page && !$0.envelope.isCharacterPage }.count),
            (.characterPage, "person.crop.circle", docs.filter { $0.envelope.isCharacterPage }.count),
        ]
        return HStack(spacing: DesignTokens.Spacing.s) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(spacing: 3) {
                    Image(systemName: stat.symbol)
                        .font(.callout)
                        .foregroundStyle(accent)
                    Text("\(stat.count)")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text(l10n.t(stat.key))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: .continuous)
                        .fill(SonnetPalette.surface)
                )
            }
        }
    }
}

/// GitHub식 기여도 히트맵 — 최근 20주, 열=주 / 행=요일, 액센트 5단계.
struct ContributionGraph: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent

    private let weeks = 20
    private let cell: CGFloat = 13
    private let spacing: CGFloat = 3

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // 이번 주 일요일로 정렬 (GitHub 관례: 일요일 시작)
        let weekday = calendar.component(.weekday, from: today) // 1 = 일
        let thisSunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let firstSunday = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisSunday) ?? thisSunday

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { day in
                            let date = calendar.date(byAdding: .day, value: week * 7 + day, to: firstSunday) ?? today
                            let isFuture = date > today
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color(for: isFuture ? -1 : app.stats.activityCount(on: date)))
                                .frame(width: cell, height: cell)
                                .help(isFuture ? "" : "\(formatted(date)) — \(app.stats.activityCount(on: date))")
                        }
                    }
                }
            }
            // 범례
            HStack(spacing: 4) {
                Spacer()
                Text("0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: level == 0 ? 0 : level * 2))
                        .frame(width: 9, height: 9)
                }
                Text("+")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func color(for count: Int) -> Color {
        switch count {
        case ..<0: .clear // 미래
        case 0: SonnetPalette.sunken.opacity(0.7) // 활동 없음
        case 1...2: accent.opacity(0.25)
        case 3...5: accent.opacity(0.45)
        case 6...9: accent.opacity(0.7)
        default: accent
        }
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
