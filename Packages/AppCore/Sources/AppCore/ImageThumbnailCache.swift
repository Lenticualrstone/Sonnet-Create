import AppKit
import ImageIO

/// 로컬 이미지 파일을 표시 크기에 맞춰 다운샘플링해 캐시한다.
/// 원본을 그대로 로드해 매 렌더링마다 실시간 축소하는 대신, 표시 배율에 맞는
/// 비트맵을 한 번만 생성해 재사용해 화질(앨리어싱)과 렌더링 비용을 함께 개선한다.
public enum ImageThumbnailCache {
    private nonisolated(unsafe) static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    /// url의 이미지를, 긴 변 기준 maxPointSize(포인트)에 맞춰 다운샘플된 NSImage를 반환한다.
    /// 화면 배율(Retina)을 자동 반영해 픽셀 단위로 생성/캐시하며, 실패 시 원본 로드로 폴백한다.
    public static func thumbnail(for url: URL, maxPointSize: CGFloat) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let maxPixel = maxPointSize * scale
        let key = "\(url.path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }
        let image = NSImage(
            cgImage: cgThumb,
            size: NSSize(width: CGFloat(cgThumb.width) / scale, height: CGFloat(cgThumb.height) / scale)
        )
        cache.setObject(image, forKey: key)
        return image
    }
}
