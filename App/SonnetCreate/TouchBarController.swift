import AppCore
import AppKit

/// Touch Bar 지원 (베타) — 홈/저장/새 페이지/AI/아카이브 버튼을 제공한다.
/// 설정에서 켜면 모든 윈도우에 부착되고, 끄면 제거된다.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {
    weak var appState: AppState?

    private var keyWindowObserver: (any NSObjectProtocol)?
    private var enabled = false

    private enum ItemID {
        static let home = NSTouchBarItem.Identifier("com.seolhwarim.sonnetcreate.tb.home")
        static let save = NSTouchBarItem.Identifier("com.seolhwarim.sonnetcreate.tb.save")
        static let newPage = NSTouchBarItem.Identifier("com.seolhwarim.sonnetcreate.tb.newpage")
        static let ai = NSTouchBarItem.Identifier("com.seolhwarim.sonnetcreate.tb.ai")
        static let archive = NSTouchBarItem.Identifier("com.seolhwarim.sonnetcreate.tb.archive")
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        if on {
            installOnAllWindows()
            if keyWindowObserver == nil {
                keyWindowObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.enabled else { return }
                        // 새로 키가 된 윈도우 포함 전체에 재부착
                        self.installOnAllWindows()
                    }
                }
            }
        } else {
            if let observer = keyWindowObserver {
                NotificationCenter.default.removeObserver(observer)
                keyWindowObserver = nil
            }
            NSApp.windows.forEach { $0.touchBar = nil }
        }
    }

    private func installOnAllWindows() {
        NSApp.windows.forEach { $0.touchBar = makeTouchBar() }
    }

    private func makeTouchBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [ItemID.home, ItemID.save, ItemID.newPage, ItemID.ai, ItemID.archive]
        return bar
    }

    nonisolated func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        MainActor.assumeIsolated {
            let l10n = Localizer.shared
            switch identifier {
            case ItemID.home:
                return button(identifier, l10n.t(.home), "house", #selector(actHome))
            case ItemID.save:
                return button(identifier, l10n.t(.save), "square.and.arrow.down", #selector(actSave))
            case ItemID.newPage:
                return button(identifier, l10n.t(.newPage), "doc.badge.plus", #selector(actNewPage))
            case ItemID.ai:
                return button(identifier, l10n.t(.aiAgent), "sparkles", #selector(actAI))
            case ItemID.archive:
                return button(identifier, l10n.t(.archive), "archivebox", #selector(actArchive))
            default:
                return nil
            }
        }
    }

    private func button(
        _ identifier: NSTouchBarItem.Identifier,
        _ title: String,
        _ symbol: String,
        _ action: Selector
    ) -> NSTouchBarItem {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        let item: NSButtonTouchBarItem
        if let image {
            item = NSButtonTouchBarItem(identifier: identifier, title: title, image: image, target: self, action: action)
        } else {
            item = NSButtonTouchBarItem(identifier: identifier, title: title, target: self, action: action)
        }
        return item
    }

    // MARK: 액션

    @objc private func actHome() { appState?.selectOrOpenHome() }
    @objc private func actSave() { appState?.saveSelectedDocument() }
    @objc private func actNewPage() { appState?.createAndOpen(kind: .page) }
    @objc private func actAI() { appState?.openAIChatTab() }
    @objc private func actArchive() { appState?.openArchiveTab() }
}
