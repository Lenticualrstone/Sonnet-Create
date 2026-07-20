import AppCore
import AppKit
import DesignSystem
import DocumentKit
import FileManagerKit
import SwiftUI

/// 홈 (1b) — 명령 중심 시작 화면.
/// 세리프 타이포 히어로 · ⌘K 검색 · 빠른 시작 · 이어서 쓰기 · 우측 집필/프로젝트/백업 열.
/// 카드들은 rise 계단식(45ms 스태거)으로 등장한다.
struct HomeView: View {
    @Environment(AppState.self) private var app
    @Environment(\.resolvedAccent) private var accent

    @State private var showBackupTimeline = false
    /// 인사말 타자기 리빌 재생 여부 — nil이면 아직 미결정(placeholder 표시).
    @State private var playGreetingReveal: Bool?
    /// 홈 실측 폭 — 좁은 창에서 우측 열을 본문 아래로 내린다 (4단계 홈).
    @State private var homeWidth: CGFloat = 1280
    /// 좁은 레이아웃 상태 — 경계 리사이즈 깜빡임 방지용 ±20pt 히스테리시스.
    @State private var narrowLayout = false

    var body: some View {
        let l10n = Localizer.shared
        ScrollView {
            // 좁은 창(<1020pt)에서는 우측 집필/프로젝트/백업 열이 본문 아래로 흐른다
            Group {
                if !narrowLayout {
                    HStack(alignment: .top, spacing: 40) {
                        mainColumn(l10n)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        sideColumn(l10n)
                            .frame(width: 300)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 34) {
                        mainColumn(l10n)
                        sideColumn(l10n)
                            .frame(maxWidth: 640, alignment: .leading)
                    }
                }
            }
            .padding(.top, 56)
            .padding(.leading, 64)
            .padding(.trailing, 44)
            .padding(.bottom, 96)
            .frame(maxWidth: 1280, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            homeWidth = width
            if width < 1000 { narrowLayout = true } else if width > 1040 { narrowLayout = false }
        }
        // 우하단 AI 플로팅 버튼 — 도트 매트릭스 웨이브 (1b)
        .overlay(alignment: .bottomTrailing) {
            aiFloatingButton
                .padding(.trailing, 28)
                .padding(.bottom, 28)
        }
        .sheet(isPresented: $showBackupTimeline) {
            BackupTimelineView()
                .environment(app)
                .frame(minWidth: 520, minHeight: 420)
        }
    }

    // MARK: 좌측 메인 열

    private func mainColumn(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 34) {
            hero(l10n)
                .fadeUpOnAppear(once: "home")

            searchTrigger(l10n)
                .fadeUpOnAppear(delay: 0.045, once: "home")

            quickStart(l10n)
                .fadeUpOnAppear(delay: 0.09, once: "home")

            continueSection(l10n)
                .fadeUpOnAppear(delay: 0.135, once: "home")
        }
    }

    /// 히어로 크기 — 창 폭에 따라 단계 축소 (2단계 3: 좁은 창에서 위압적이지 않게).
    private var heroSize: CGFloat {
        if homeWidth >= 1180 {
            34
        } else if homeWidth >= 1000 {
            30
        } else {
            26
        }
    }

    /// 세리프 타이포 히어로 — 날짜 캡션 + 2행 인사말.
    /// 앱 세션 첫 진입 1회만 인사말 첫 줄이 타자기 리빌(9e)로 새겨진다 (매번은 피로).
    private func hero(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date(), format: .dateTime.month().day().weekday(.wide))
                .font(DSFonts.font(size: 12.5, family: .pretendard))
                .foregroundStyle(SonnetPalette.inkMuted)
                .kerning(0.7)
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    // 정적 원문으로 자리를 잡아 리빌 중 아래 행이 밀리지 않게 한다
                    Text(greetingText).opacity(playGreetingReveal == nil ? 1 : 0)
                    if playGreetingReveal == true {
                        TypewriterText(
                            greetingText,
                            font: DSFonts.display(size: heroSize, weight: .semibold),
                            color: SonnetPalette.ink,
                            caretHeight: heroSize * 0.88
                        )
                    } else if playGreetingReveal == false {
                        Text(greetingText)
                    }
                }
                Text(l10n.t(.greetingFollowup))
            }
            .font(DSFonts.display(size: heroSize, weight: .semibold))
            .foregroundStyle(SonnetPalette.ink)
            .lineSpacing(6)
            .lineLimit(nil)
            // ko 로케일의 줄바꿈 전략에서 세리프 커스텀 폰트가 말줄임되는 문제 —
            // 세로 확장을 명시해 항상 줄바꿈되게 한다
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            guard playGreetingReveal == nil else { return }
            playGreetingReveal = !app.homeGreetingRevealPlayed
            app.homeGreetingRevealPlayed = true
        }
    }

    /// 검색 필드 모양의 ⌘K 트리거 — 딥서치·명령·문서 점프는 전부 팔레트가 담당.
    private func searchTrigger(_ l10n: Localizer) -> some View {
        Button {
            withAnimation(DesignTokens.Motion.glassPop) { app.showCommandPalette = true }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SonnetPalette.inkMuted)
                Text(l10n.t(.searchPlaceholder))
                    .font(DSFonts.font(size: 14.5, family: .pretendard))
                    .foregroundStyle(SonnetPalette.inkMuted)
                Spacer()
                Text("⌘K")
                    .font(DSType.mono(size: 11))
                    .foregroundStyle(SonnetPalette.inkMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(SonnetPalette.ink.opacity(0.16), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .frame(maxWidth: 640)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SonnetPalette.surface.opacity(0.85))
                    .shadow(color: SonnetPalette.ink.opacity(0.09), radius: 9, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(SonnetPalette.glassRim, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(LiftButtonStyle(hoverScale: 1.005, pressScale: 0.995))
    }

    // MARK: 빠른 시작 (5종)

    private func quickStart(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(l10n.t(.quickStart))
            // adaptive grid — 좁은 창에서 5장의 카드가 잘리는 대신 3+2 / 2열로 흐른다 (4단계 홈)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 148, maximum: 240), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                QuickStartCard(
                    type: .scenario,
                    title: l10n.t(.scenario),
                    subtitle: "대사·지침 블록, 분기"
                ) {
                    app.createAndOpen(kind: .scenario)
                }
                QuickStartCard(
                    type: .mindmap,
                    title: l10n.t(.mindmap),
                    subtitle: "무한 캔버스, 링크 노드"
                ) {
                    app.createAndOpen(kind: .mindmap)
                }
                QuickStartCard(
                    type: .page,
                    title: l10n.t(.page),
                    subtitle: "블록 편집, / 커맨드"
                ) {
                    app.createAndOpen(kind: .page)
                }
                QuickStartCard(
                    type: .character,
                    title: l10n.t(.characterPage),
                    subtitle: "프로필·관계·보이스"
                ) {
                    app.createAndOpen(kind: .page, pageRole: .character)
                }
                aiDraftCard(l10n)
            }
        }
    }

    /// AI로 초안 — 유일하게 인장(버밀리온 그라데이션)을 쓰는 행동 카드.
    private func aiDraftCard(_ l10n: Localizer) -> some View {
        Button {
            app.toggleAgentSurface()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .medium))
                    .padding(.bottom, 6)
                Text(l10n.t(.aiDraft))
                    .font(DSFonts.font(size: 14, weight: .semibold, family: .pretendard))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(l10n.t(.aiDraftSubtitle))
                    .font(DSFonts.font(size: 11.5, family: .pretendard))
                    .opacity(0.8)
                    .lineLimit(2)
            }
            .foregroundStyle(Color(hex: "#F6F4EF"))
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#B23A21"), Color(hex: "#8E2D18")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(LiftButtonStyle(hoverScale: 1.02, pressScale: 0.97))
    }

    // MARK: 이어서 쓰기

    @ViewBuilder
    private func continueSection(_ l10n: Localizer) -> some View {
        let items = Array(app.workspace.recentDocuments.prefix(3))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(l10n.t(.continueWriting))
                Spacer()
                Button {
                    app.openArchiveTab()
                } label: {
                    Text(l10n.t(.archiveAll))
                        .font(DSFonts.font(size: 12, family: .pretendard))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            if items.isEmpty {
                emptyWorkspaceHero(l10n)
            } else {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        ContinueCard(item: item) { app.openDocument(item) }
                    }
                    // 3칸 미만이어도 카드 폭 유지
                    ForEach(0..<max(0, 3 - items.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func emptyWorkspaceHero(_ l10n: Localizer) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text(l10n.t(.emptyWorkspaceTitle))
                .font(DSType.title())
            Text(l10n.t(.emptyWorkspaceBody))
                .font(DSType.body())
                .foregroundStyle(SonnetPalette.inkMuted)
            Button {
                _ = try? app.workspace.createProject(name: l10n.t(.newProject))
            } label: {
                Label(l10n.t(.createFirstProject), systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(homeCardBackground())
    }

    // MARK: 우측 열

    private func sideColumn(_ l10n: Localizer) -> some View {
        VStack(spacing: 14) {
            writingCard(l10n)
                .fadeUpOnAppear(delay: 0.09, once: "home")
            projectsCard(l10n)
                .fadeUpOnAppear(delay: 0.135, once: "home")
            backupCard(l10n)
                .fadeUpOnAppear(delay: 0.18, once: "home")
        }
    }

    /// 오늘의 집필 — 세리프 숫자 + 잉크 진행 바 + 주간 막대.
    private func writingCard(_ l10n: Localizer) -> some View {
        let today = app.stats.todayWriting
        let goal = max(1, Int(app.settings.applied.dailyWritingGoal))
        let progress = min(1, Double(today) / Double(goal))
        let week = app.stats.recentWeekWriting
        let peak = max(1, week.map(\.count).max() ?? 1)
        let streak = app.stats.writingStreak

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(l10n.t(.todayWriting))
                    .font(DSType.subtitle())
                Spacer()
                if streak > 0 {
                    Text(String(format: l10n.t(.streakDaysFormat), streak))
                        .font(DSFonts.font(size: 12, family: .pretendard))
                        .foregroundStyle(accent)
                }
            }
            .padding(.bottom, 14)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(today.formatted())")
                    .font(DSFonts.display(size: 30, weight: .bold))
                Text("/ \(goal.formatted())\(l10n.t(.dailyGoalChars))")
                    .font(DSFonts.font(size: 12, family: .pretendard))
                    .foregroundStyle(SonnetPalette.inkMuted)
            }
            .padding(.bottom, 12)

            // 잉크 진행 바 — 차오르는 잉크 (100%에서 인장 스탬프)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SonnetPalette.ink.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "#C2482D"), Color(hex: "#B23A21")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                        .animation(DesignTokens.Motion.inkFlow, value: progress)
                }
            }
            .frame(height: 6)
            .padding(.bottom, 14)

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                    let ratio = max(0.12, Double(day.count) / Double(peak))
                    let isToday = index == week.count - 1
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(count: day.count, isToday: isToday))
                        .frame(height: 34 * ratio)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 34, alignment: .bottom)
            .padding(.bottom, 6)

            HStack {
                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 10))
                        .foregroundStyle(SonnetPalette.inkMuted)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(20)
        .background(homeCardBackground())
    }

    private func barColor(count: Int, isToday: Bool) -> Color {
        if count == 0 { return SonnetPalette.ink.opacity(0.12) }
        if isToday { return Color(hex: "#E3B7AA") }
        return SonnetPalette.accent
    }

    /// 프로젝트 목록 — 유형색 사각 도트 + 문서 수.
    private func projectsCard(_ l10n: Localizer) -> some View {
        let dotColors: [Color] = [
            SonnetPalette.accent, SonnetPalette.pine, SonnetPalette.gold, SonnetPalette.slate,
        ]
        return VStack(alignment: .leading, spacing: 2) {
            Text(l10n.t(.project))
                .font(DSType.subtitle())
                .padding(.bottom, 10)
            ForEach(Array(app.workspace.projects.enumerated()), id: \.element.id) { index, project in
                HomeProjectRow(
                    project: project,
                    dotColor: dotColors[index % dotColors.count],
                    isActive: isActiveProject(project)
                ) {
                    app.openArchiveTab(category: .all, project: project.id)
                }
            }
            Button {
                _ = try? app.workspace.createProject(name: l10n.t(.newProject))
            } label: {
                HStack(spacing: 8) {
                    Text("＋")
                        .font(.system(size: 15))
                    Text(l10n.t(.newProject))
                        .font(DSFonts.font(size: 12.5, family: .pretendard))
                }
                .foregroundStyle(SonnetPalette.inkMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(SidebarLongButtonStyle())
        }
        .padding(20)
        .background(homeCardBackground())
    }

    private func isActiveProject(_ project: ProjectFolder) -> Bool {
        guard let tab = app.selectedTab, let session = app.session(for: tab) else { return false }
        return session.document.envelope.projectID == project.id
    }

    /// 자동 백업 상태 — 최근 스냅샷 + 타임라인 링크.
    private func backupCard(_ l10n: Localizer) -> some View {
        let latest = app.backupManager.timeline().first
        return HStack(spacing: 12) {
            Circle()
                .fill(latest == nil ? SonnetPalette.inkMuted : SonnetPalette.sage)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(l10n.t(.autoBackupDone))
                    .font(DSFonts.font(size: 12.5, weight: .semibold, family: .pretendard))
                if let latest {
                    Text(latest.date, format: .dateTime.month().day().hour().minute())
                        .font(DSFonts.font(size: 12, family: .pretendard))
                        .foregroundStyle(SonnetPalette.inkMuted)
                } else {
                    Text(l10n.t(.noRecents))
                        .font(DSFonts.font(size: 12, family: .pretendard))
                        .foregroundStyle(SonnetPalette.inkMuted)
                }
            }
            Spacer()
            Button {
                showBackupTimeline = true
            } label: {
                Text(l10n.t(.backupTimelineShort))
                    .font(DSFonts.font(size: 11.5, family: .pretendard))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(homeCardBackground())
    }

    // MARK: AI 플로팅 버튼

    /// 우하단 깃털 버튼 — 도트 매트릭스가 물결치는 글래스 원판. AI 패널을 연다.
    private var aiFloatingButton: some View {
        Button {
            withAnimation(DesignTokens.Motion.glassPop) { app.showFloatingChat.toggle() }
        } label: {
            DotMatrixWave(color: accent)
                .frame(width: 18, height: 18)
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: SonnetPalette.ink.opacity(0.16), radius: 10, y: 6)
                )
                .overlay(Circle().strokeBorder(SonnetPalette.glassRim, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressBounceButtonStyle())
        .help(Localizer.shared.t(.sonnetAI) + " (⇧⌘A)")
    }

    // MARK: 공통

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DSFonts.font(size: 12, weight: .semibold, family: .pretendard))
            .foregroundStyle(SonnetPalette.inkMuted)
            .kerning(1)
    }

    /// 작가 이름이 설정돼 있으면 이름을 넣은 인사말, 아니면 일반 문구.
    private var greetingText: String {
        let l10n = Localizer.shared
        let name = app.settings.applied.authorName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return l10n.t(timeOfDay.plainKey) }
        return String(format: l10n.t(timeOfDay.namedKey), name)
    }

    private enum TimeOfDay {
        case morning, afternoon, evening, night

        var plainKey: L10nKey {
            switch self {
            case .morning: .greetingMorning
            case .afternoon: .greetingAfternoon
            case .evening: .greetingEvening
            case .night: .greetingNight
            }
        }

        var namedKey: L10nKey {
            switch self {
            case .morning: .greetingMorningNamed
            case .afternoon: .greetingAfternoonNamed
            case .evening: .greetingEveningNamed
            case .night: .greetingNightNamed
            }
        }
    }

    private var timeOfDay: TimeOfDay {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: .morning
        case 12..<18: .afternoon
        case 18..<23: .evening
        default: .night
        }
    }
}

/// 홈 카드 공통 배경 — Sheet 백지 + 얇은 잉크 테두리.
private func homeCardBackground(cornerRadius: CGFloat = 14) -> some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(SonnetPalette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(SonnetPalette.ink.opacity(0.09), lineWidth: 1)
        )
}

/// 빠른 시작 카드 — 유형 배지 + 이름 + 설명 (호버 리프트 y-2px).
private struct QuickStartCard: View {
    let type: DSFileType
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(type.extensionLabel)
                    .font(DSType.mono(size: 11, weight: .semibold))
                    .foregroundStyle(type.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.bottom, 6)
                Text(title)
                    .font(DSFonts.font(size: 14, weight: .semibold, family: .pretendard))
                    .foregroundStyle(SonnetPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(DSFonts.font(size: 11.5, family: .pretendard))
                    .foregroundStyle(SonnetPalette.inkMuted)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(homeCardBackground(cornerRadius: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiftButtonStyle(hoverScale: 1.02, pressScale: 0.97))
    }
}

/// 이어서 쓰기 카드 — 유형 배지 + 상대 시각 + 세리프 제목 + 프로젝트.
private struct ContinueCard: View {
    let item: DocumentListItem
    let action: () -> Void

    private var fileType: DSFileType {
        if item.envelope.isCharacterPage { return .character }
        switch item.envelope.kind {
        case .scenario: return .scenario
        case .mindmap: return .mindmap
        case .page: return .page
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(fileType.extensionLabel)
                        .font(DSType.mono(size: 11, weight: .semibold))
                        .foregroundStyle(fileType.color)
                    Spacer()
                    Text(item.envelope.modifiedAt, style: .relative)
                        .font(DSFonts.font(size: 11, family: .pretendard))
                        .foregroundStyle(SonnetPalette.inkMuted)
                }
                .padding(.bottom, 10)
                Text(item.envelope.title.isEmpty ? Localizer.shared.t(.untitled) : item.envelope.title)
                    .font(DSFonts.display(size: 15, weight: .semibold))
                    .foregroundStyle(SonnetPalette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 10)
                if let project = item.projectName {
                    Text(project)
                        .font(DSFonts.font(size: 11, family: .pretendard))
                        .foregroundStyle(SonnetPalette.pine)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(homeCardBackground(cornerRadius: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(LiftButtonStyle(hoverScale: 1.02, pressScale: 0.97))
    }
}

/// 프로젝트 행.
private struct HomeProjectRow: View {
    let project: ProjectFolder
    let dotColor: Color
    let isActive: Bool
    let action: () -> Void

    @Environment(AppState.self) private var app
    @State private var hovering = false

    private var docCount: Int {
        app.workspace.visibleDocuments.count { $0.envelope.projectID == project.id }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(project.manifest.name)
                    .font(DSFonts.font(size: 13, weight: isActive ? .semibold : .regular, family: .pretendard))
                    .lineLimit(1)
                Spacer()
                Text("\(docCount)")
                    .font(DSFonts.font(size: 11, family: .pretendard))
                    .foregroundStyle(SonnetPalette.inkMuted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isActive
                            ? SonnetPalette.accentTint
                            : (hovering ? SonnetPalette.ink.opacity(0.05) : .clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DesignTokens.Motion.glassPop, value: hovering)
        .contextMenu {
            let l10n = Localizer.shared
            Button(l10n.t(.exportProject)) { app.exportProject(project) }
            Button(l10n.t(.deleteProject), role: .destructive) { app.requestDeleteProject(project) }
        }
    }
}

/// 4×4 도트 매트릭스 웨이브 — AI 플로팅 버튼 아이콘 (1b).
struct DotMatrixWave: View {
    let color: Color

    @Environment(\.decorAnimationsPaused) private var animationsPaused

    var body: some View {
        Group {
            if animationsPaused {
                grid(time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
                    grid(time: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func grid(time t: TimeInterval) -> some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<4, id: \.self) { col in
                        let phase = Double(row + col) * 0.11
                        let wave = 0.5 + 0.5 * sin((t / 1.8 - phase) * 2 * .pi)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color)
                            .frame(width: 3, height: 3)
                            .opacity(0.2 + 0.8 * wave)
                            .scaleEffect(0.72 + 0.28 * wave)
                    }
                }
            }
        }
    }
}
