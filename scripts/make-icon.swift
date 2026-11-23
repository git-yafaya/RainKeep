// 把图标 SVG 渲染成 .iconset 需要的各尺寸 PNG（带系统图标那样的轻阴影），再由 make-icon.sh 交给 iconutil
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let image = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("用法：make-icon.swift <图标.svg> <输出.iconset>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// 按像素边长渲染一张 PNG
func render(pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = size * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
    shadow.set()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    return png
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(pixels: base * scale).write(to: output.appending(path: name))
    }
}
