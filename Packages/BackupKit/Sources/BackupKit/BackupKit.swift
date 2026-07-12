import AppCore
import DocumentKit
import Foundation

/// 타임라인 백업 한 시점.
public struct BackupRecord: Identifiable, Sendable, Equatable {
    public let id: String // 폴더명 (yyyyMMdd-HHmmss)
    public let date: Date
    public let url: URL

    public init(id: String, date: Date, url: URL) {
        self.id = id
        self.date = date
        self.url = url
    }
}

/// 타임라인 백업/복구 + .scproj 프로젝트 패키지 입출력.
public struct BackupManager: Sendable {
    public let workspaceRoot: URL

    private var backupsDir: URL {
        workspaceRoot.appendingPathComponent(".sonnetcreate/Backups", isDirectory: true)
    }

    private static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    /// 워크스페이스 전체 스냅샷 (내부 관리 폴더 제외). 종료 시 자동 백업에 사용.
    @discardableResult
    public func snapshot() throws -> BackupRecord {
        let fm = FileManager.default
        let stamp = Self.stampFormat.string(from: Date())
        let target = backupsDir.appendingPathComponent(stamp, isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)

        let items = try fm.contentsOfDirectory(at: workspaceRoot, includingPropertiesForKeys: nil)
        for item in items where item.lastPathComponent != ".sonnetcreate" {
            try fm.copyItem(at: item, to: target.appendingPathComponent(item.lastPathComponent))
        }
        prune(keeping: 20)
        return BackupRecord(id: stamp, date: Date(), url: target)
    }

    /// 백업 타임라인 (최신순).
    public func timeline() -> [BackupRecord] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: backupsDir, includingPropertiesForKeys: nil) else {
            return []
        }
        return items.compactMap { url in
            guard let date = Self.stampFormat.date(from: url.lastPathComponent) else { return nil }
            return BackupRecord(id: url.lastPathComponent, date: date, url: url)
        }
        .sorted { $0.date > $1.date }
    }

    /// 특정 시점으로 복원. 현재 상태는 복원 직전에 자동 스냅샷을 남긴다.
    public func restore(_ record: BackupRecord) throws {
        let fm = FileManager.default
        _ = try? snapshot()

        // 현재 워크스페이스 콘텐츠 제거 (관리 폴더 제외)
        let current = try fm.contentsOfDirectory(at: workspaceRoot, includingPropertiesForKeys: nil)
        for item in current where item.lastPathComponent != ".sonnetcreate" {
            try fm.removeItem(at: item)
        }
        // 백업 내용 복사
        let backupItems = try fm.contentsOfDirectory(at: record.url, includingPropertiesForKeys: nil)
        for item in backupItems {
            try fm.copyItem(at: item, to: workspaceRoot.appendingPathComponent(item.lastPathComponent))
        }
    }

    public func delete(_ record: BackupRecord) {
        try? FileManager.default.removeItem(at: record.url)
    }

    /// 백업 한 건의 요약 정보 (총 용량 · 문서 번들 수) — 타임라인 표시용.
    /// 전체 파일 순회라 호출부에서 백그라운드로 돌리는 것을 전제로 한다.
    public struct BackupDetail: Sendable, Equatable {
        public let byteSize: Int64
        public let documentCount: Int
    }

    public func detail(of record: BackupRecord) -> BackupDetail {
        let fm = FileManager.default
        var size: Int64 = 0
        var docs = 0
        let documentExtensions: Set<String> = ["scen", "scno", "scpa"]
        if let enumerator = fm.enumerator(at: record.url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                size += Int64(values?.fileSize ?? 0)
                if values?.isDirectory == true, documentExtensions.contains(url.pathExtension.lowercased()) {
                    docs += 1
                }
            }
        }
        return BackupDetail(byteSize: size, documentCount: docs)
    }

    private func prune(keeping limit: Int) {
        let records = timeline()
        guard records.count > limit else { return }
        for record in records.dropFirst(limit) {
            delete(record)
        }
    }

    // MARK: .scproj 내보내기/가져오기 (ZIP 패키지 + manifest)

    /// 프로젝트 폴더 → .scproj (ZIP). 백업·이동·복원용 패키지.
    public func exportProject(_ project: ProjectFolder, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-ck", "--sequesterRsrc", project.url.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BackupKit", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "프로젝트 압축에 실패했습니다.",
            ])
        }
    }

    /// .scproj → 워크스페이스로 복원. 매니페스트 확인 후 구조를 되살린다.
    @discardableResult
    public func importProject(from archive: URL) throws -> ProjectFolder {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-xk", archive.path, temp.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw NSError(domain: "BackupKit", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "패키지 압축 해제에 실패했습니다.",
            ])
        }

        // 매니페스트(project.json)를 가진 루트 폴더 탐색
        let candidates = try fm.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)
        guard let projectRoot = candidates.first(where: {
            fm.fileExists(atPath: $0.appendingPathComponent("project.json").path)
        }), let loaded = ProjectIO.load(from: projectRoot) else {
            throw NSError(domain: "BackupKit", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "유효한 프로젝트 매니페스트를 찾지 못했습니다.",
            ])
        }

        var destination = workspaceRoot.appendingPathComponent(projectRoot.lastPathComponent, isDirectory: true)
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            destination = workspaceRoot.appendingPathComponent("\(projectRoot.lastPathComponent) \(counter)", isDirectory: true)
            counter += 1
        }
        try fm.copyItem(at: projectRoot, to: destination)
        return ProjectFolder(manifest: loaded.manifest, url: destination)
    }
}
