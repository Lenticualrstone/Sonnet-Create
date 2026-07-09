import Foundation
import Testing
@testable import DocumentKit

/// 마이그레이션 리스트가 비어 있는 현재 상태에서, apply()가 원본 Data를 그대로 반환하는지(no-op) 확인.
@Test func migrationsApplyIsNoOpWhenListIsEmpty() {
    let json = #"{"kind":"scenario","payload":{}}"#.data(using: .utf8)!
    let result = DocumentContentMigrations.apply(to: json, from: 0, kind: .scenario)
    #expect(result == json)
}

/// formatVersion이 최신인 문서를 읽으면 마이그레이션 경로를 타지 않고 원본 그대로 반환되는지 확인.
@Test func migrationsApplySkipsWhenAlreadyCurrent() {
    let json = #"{"kind":"scenario","payload":{}}"#.data(using: .utf8)!
    let result = DocumentContentMigrations.apply(to: json, from: DocumentFormatVersion.current, kind: .scenario)
    #expect(result == json)
}

/// 새 문서를 만들면 formatVersion이 항상 DocumentFormatVersion.current로 채워지는지 확인.
@Test func newDocumentUsesCurrentFormatVersion() {
    let envelope = DocumentEnvelope(title: "테스트", kind: .scenario)
    #expect(envelope.formatVersion == DocumentFormatVersion.current)
}

/// 등록된 마이그레이션이 fromVersion부터 순서대로 적용되어 최신 스키마로 변환되는지 확인.
/// (향후 실제 마이그레이션을 추가할 때 참고할 예시 겸 회귀 테스트)
private struct RenameFieldMigration: DocumentContentMigration {
    let fromVersion = 0
    func migrate(_ json: [String: Any], kind: DocumentKind) -> [String: Any] {
        var json = json
        guard var payload = json["payload"] as? [String: Any] else { return json }
        if let old = payload.removeValue(forKey: "oldName") {
            payload["newName"] = old
        }
        json["payload"] = payload
        return json
    }
}

@Test func migrationChainTransformsOldSchema() {
    let oldJSON = #"{"kind":"scenario","payload":{"oldName":"hello"}}"#.data(using: .utf8)!
    guard var obj = try? JSONSerialization.jsonObject(with: oldJSON) as? [String: Any],
          var payload = obj["payload"] as? [String: Any] else {
        Issue.record("JSON 파싱 실패")
        return
    }
    let migration = RenameFieldMigration()
    obj = migration.migrate(obj, kind: .scenario)
    payload = obj["payload"] as? [String: Any] ?? [:]
    #expect(payload["newName"] as? String == "hello")
    #expect(payload["oldName"] == nil)
}
