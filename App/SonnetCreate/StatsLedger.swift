import Foundation
import Observation

/// 활동(저장 횟수)·집필(일별 글자 수) 원장 — 워크스페이스의 .sonnetcreate/에
/// JSON으로 보관한다. 기여도 그래프와 집필 목표 카드의 데이터 소스.
@MainActor
@Observable
final class StatsLedger {
    /// 일별 저장 횟수 (프로필의 GitHub식 기여도 그래프)
    private(set) var activity: [String: Int] = [:]
    /// 일별 집필 글자 수 (증가분 합산)
    private(set) var writing: [String: Int] = [:]

    private var rootURL: URL?
    private var writingPersistTask: Task<Void, Never>?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var activityURL: URL? {
        rootURL?.appendingPathComponent(".sonnetcreate/activity.json")
    }

    private var writingURL: URL? {
        rootURL?.appendingPathComponent(".sonnetcreate/writing.json")
    }

    /// 워크스페이스 루트가 정해지거나 바뀔 때 다시 읽는다.
    func load(rootURL: URL) {
        self.rootURL = rootURL
        activity = Self.decode(activityURL)
        writing = Self.decode(writingURL)
    }

    private static func decode(_ url: URL?) -> [String: Int] {
        guard let url,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return decoded
    }

    // MARK: 활동 (저장 횟수)

    /// 문서 저장 1회 = 활동 1.
    func recordActivity() {
        activity[Self.dayFormatter.string(from: Date()), default: 0] += 1
        if let activityURL, let data = try? JSONEncoder().encode(activity) {
            try? data.write(to: activityURL, options: .atomic)
        }
    }

    func activityCount(on date: Date) -> Int {
        activity[Self.dayFormatter.string(from: date)] ?? 0
    }

    // MARK: 집필 (글자 수)

    /// 문서 내용이 늘어난 만큼 오늘 칸에 더한다. 키 입력마다 불리므로
    /// 디스크 기록은 3초 디바운스 (앱 종료 시 flush가 마무리).
    func recordWriting(delta: Int) {
        guard delta > 0 else { return }
        writing[Self.dayFormatter.string(from: Date()), default: 0] += delta
        writingPersistTask?.cancel()
        writingPersistTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        writingPersistTask?.cancel()
        guard let writingURL, let data = try? JSONEncoder().encode(writing) else { return }
        try? data.write(to: writingURL, options: .atomic)
    }

    var todayWriting: Int {
        writing[Self.dayFormatter.string(from: Date())] ?? 0
    }

    func writingCount(on date: Date) -> Int {
        writing[Self.dayFormatter.string(from: date)] ?? 0
    }

    /// 오늘 포함 최근 7일의 (날짜, 글자 수) — 오래된 날부터. 주간 리포트 막대용.
    var recentWeekWriting: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date: day, count: writingCount(on: day))
        }
    }

    /// 그 이전 7일(8~14일 전) 합계 — 주간 증감 비교 기준.
    var previousWeekTotal: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (7..<14).reduce(0) { sum, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return sum }
            return sum + writingCount(on: day)
        }
    }

    /// 연속 집필 일수 — 오늘 썼다면 오늘부터, 아직이면 어제부터 거슬러 센다.
    var writingStreak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if writing[Self.dayFormatter.string(from: day)] == nil {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var streak = 0
        while (writing[Self.dayFormatter.string(from: day)] ?? 0) > 0 {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }
}
