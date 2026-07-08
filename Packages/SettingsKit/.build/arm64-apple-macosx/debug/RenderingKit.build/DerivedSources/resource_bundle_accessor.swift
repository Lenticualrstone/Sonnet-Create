import Foundation

extension Foundation.Bundle {
    static nonisolated let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("RenderingKit_RenderingKit.bundle").path
        let buildPath = "/Users/stelladust/Claude Code/Sonnet Create (with Fable 5)/Packages/SettingsKit/.build/arm64-apple-macosx/debug/RenderingKit_RenderingKit.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}