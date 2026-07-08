import AppCore
import Foundation
import Observation

/// 발열/전원 상태와 사용자 설정을 종합해 실효 품질 단계를 결정한다.
@MainActor
@Observable
public final class QualityGovernor {
    /// 사용자가 설정에서 고른 단계
    public var userPreference: RenderQuality = .standard

    /// 시스템 발열 상태에 따른 상한
    public private(set) var thermalCap: RenderQuality = .high

    /// 실효 품질 = min(사용자 설정, 발열 상한)
    public var effective: RenderQuality {
        let order: [RenderQuality] = [.low, .standard, .high]
        let userIndex = order.firstIndex(of: userPreference) ?? 1
        let capIndex = order.firstIndex(of: thermalCap) ?? 2
        return order[min(userIndex, capIndex)]
    }

    private var observer: (any NSObjectProtocol)?

    public init() {
        refreshThermalCap()
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshThermalCap()
            }
        }
    }

    private func refreshThermalCap() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalCap = .high
        case .fair: thermalCap = .standard
        case .serious, .critical: thermalCap = .low
        @unknown default: thermalCap = .standard
        }
    }
}
