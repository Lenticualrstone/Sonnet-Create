import Foundation

/// 앱 전역에서 공유하는 로깅 유틸리티.
public struct AppLogger: Sendable {
    public enum Level: String, Sendable {
        case debug, info, warning, error
    }

    public let subsystem: String

    public init(subsystem: String = "com.seolhwarim.sonnetcreate") {
        self.subsystem = subsystem
    }

    public func log(_ message: String, level: Level = .info) {
        print("[\(subsystem)][\(level.rawValue)] \(message)")
    }
}

/// 최소 의존성 주입 컨테이너.
public final class DependencyContainer: @unchecked Sendable {
    public static let shared = DependencyContainer()

    private var factories: [ObjectIdentifier: () -> Any] = [:]

    public init() {}

    public func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        factories[ObjectIdentifier(type)] = factory
    }

    public func resolve<T>(_ type: T.Type = T.self) -> T? {
        factories[ObjectIdentifier(type)]?() as? T
    }
}
