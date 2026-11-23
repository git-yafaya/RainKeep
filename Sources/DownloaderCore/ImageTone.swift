// 背景图明暗：缩到 32×32 求平均相对亮度，亮图配深色字，暗图配浅色字
import CoreGraphics

public enum ImageTone {
    private static let sampleSide = 32
    /// 高于它算亮图
    public static let brightThreshold = 0.55

    /// 0（全黑）到 1（全白）；画不出来返回 nil
    public static func luminance(of image: CGImage) -> Double? {
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
        }
        return sum / Double(side * side) / 255
    }

    public static func isBright(_ image: CGImage) -> Bool { (luminance(of: image) ?? 1) > brightThreshold }
}
