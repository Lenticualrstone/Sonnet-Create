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

// MARK: 패키지 IO — 손상/부분 손실 안전성

/// content.json이 손상된 번들은 빈 문서로 대체되지 않고 corruptedContent를 던져야 한다 —
/// 빈 대체본이 다음 저장에서 원본을 덮어쓰는 데이터 손실을 막는 회귀 테스트.
@Test func corruptedContentThrowsInsteadOfReplacingWithEmpty() throws {
    let document = try DocumentPackageIO.create(
        title: "손상 테스트", kind: .page,
        in: FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-test-\(UUID().uuidString)", isDirectory: true)
    )
    defer { try? FileManager.default.removeItem(at: document.url.deletingLastPathComponent()) }

    // content.json을 반쯤 잘린 JSON으로 오염
    try Data("{\"kind\":\"page\",\"payl".utf8)
        .write(to: document.url.appendingPathComponent("content.json"))

    #expect(throws: DocumentIOError.self) {
        _ = try DocumentPackageIO.read(from: document.url)
    }
}

/// content.json이 아예 없는 번들(구버전/미완성 저장)은 빈 문서로 열려야 한다.
@Test func missingContentFallsBackToEmpty() throws {
    let document = try DocumentPackageIO.create(
        title: "빈 폴백", kind: .page,
        in: FileManager.default.temporaryDirectory.appendingPathComponent("missing-test-\(UUID().uuidString)", isDirectory: true)
    )
    defer { try? FileManager.default.removeItem(at: document.url.deletingLastPathComponent()) }

    try FileManager.default.removeItem(at: document.url.appendingPathComponent("content.json"))
    let reread = try DocumentPackageIO.read(from: document.url)
    #expect(reread.envelope.id == document.envelope.id)
}

/// updateEnvelope는 metadata.json만 다시 쓰고 content.json은 건드리지 않아야 한다 —
/// 손상 문서도 휴지통 이동/이름 변경이 가능해야 하기 때문.
@Test func updateEnvelopeLeavesContentUntouched() throws {
    let document = try DocumentPackageIO.create(
        title: "원제", kind: .page,
        in: FileManager.default.temporaryDirectory.appendingPathComponent("envelope-test-\(UUID().uuidString)", isDirectory: true)
    )
    defer { try? FileManager.default.removeItem(at: document.url.deletingLastPathComponent()) }

    let contentURL = document.url.appendingPathComponent("content.json")
    let corrupted = Data("not json at all".utf8)
    try corrupted.write(to: contentURL)

    let updated = try DocumentPackageIO.updateEnvelope(at: document.url) {
        $0.title = "변경됨"
        $0.isTrashed = true
    }
    #expect(updated.title == "변경됨")
    #expect(try Data(contentsOf: contentURL) == corrupted)
    #expect(DocumentPackageIO.readEnvelope(from: document.url)?.isTrashed == true)
}

// MARK: 스냅샷 IO

@Test func snapshotRoundTripAndOrdering() throws {
    let bundle = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundle) }

    let older = DocumentSnapshot(
        name: "초고",
        createdAt: Date(timeIntervalSinceNow: -100),
        content: .page(PageContent(blocks: [PageBlock(kind: .paragraph, text: "hello")]))
    )
    let newer = DocumentSnapshot(
        name: "퇴고",
        content: .page(PageContent(blocks: []))
    )
    try SnapshotIO.save(older, in: bundle)
    try SnapshotIO.save(newer, in: bundle)

    let listed = SnapshotIO.list(in: bundle)
    #expect(listed.count == 2)
    #expect(listed.first?.name == "퇴고") // 최신순
    #expect(listed.last?.content == older.content)

    SnapshotIO.delete(newer.id, in: bundle)
    #expect(SnapshotIO.list(in: bundle).count == 1)
}
