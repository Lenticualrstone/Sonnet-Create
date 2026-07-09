import Foundation

/// content.json 원본 JSON을 fromVersion → fromVersion+1로 변환하는 단일 스텝.
public protocol DocumentContentMigration: Sendable {
    var fromVersion: Int { get }
    func migrate(_ json: [String: Any], kind: DocumentKind) -> [String: Any]
}

public enum DocumentContentMigrations {
    /// 버전 오름차순으로 등록. 지금은 비어 있다 — 스키마를 깨는 변경을 할 때 여기 추가한다.
    public static let all: [DocumentContentMigration] = []

    /// envelope.formatVersion이 최신보다 낮으면 raw JSON을 단계적으로 변환한다.
    /// 마이그레이션이 없거나 이미 최신이면 원본 Data를 그대로 반환한다 (빠른 경로).
    static func apply(to data: Data, from version: Int, kind: DocumentKind) -> Data {
        guard version < DocumentFormatVersion.current, !all.isEmpty else { return data }
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
        for migration in all.sorted(by: { $0.fromVersion < $1.fromVersion }) where migration.fromVersion >= version {
            json = migration.migrate(json, kind: kind)
        }
        return (try? JSONSerialization.data(withJSONObject: json)) ?? data
    }
}
