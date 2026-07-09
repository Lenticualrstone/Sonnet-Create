import AppKit
import Testing
@testable import AppCore

private func makeTestPNG(pixelSize: Int) throws -> URL {
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
    try png.write(to: url)
    return url
}

@Test func thumbnailIsDownsampledToRequestedSize() throws {
    let url = try makeTestPNG(pixelSize: 1000)
    defer { try? FileManager.default.removeItem(at: url) }

    let thumbnail = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 100)
    #expect(thumbnail != nil)
    guard let rep = thumbnail?.representations.first else {
        Issue.record("썸네일에 representation이 없음")
        return
    }
    // 화면 배율(최대 3배 가정)을 감안해도 원본(1000px)보다는 훨씬 작아야 한다.
    #expect(rep.pixelsWide <= 400)
    #expect(rep.pixelsWide > 0)
}

@Test func thumbnailReusesCacheForSameArguments() throws {
    let url = try makeTestPNG(pixelSize: 500)
    defer { try? FileManager.default.removeItem(at: url) }

    let first = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 80)
    let second = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 80)
    #expect(first != nil)
    #expect(first === second)
}

@Test func thumbnailFallsBackSafelyForMissingFile() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).png")
    let thumbnail = ImageThumbnailCache.thumbnail(for: url, maxPointSize: 100)
    #expect(thumbnail == nil)
}
