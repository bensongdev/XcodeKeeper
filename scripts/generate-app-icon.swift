// 앱 아이콘 생성기: 1024px 원본을 CoreGraphics로 그리고 macOS가 요구하는 크기별 PNG와 Contents.json을 만든다.
// SF Symbols는 라이선스상 앱 아이콘에 쓸 수 없으므로 도형을 직접 그린다.
// 사용법: swift scripts/generate-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "App/Resources/Assets.xcassets/AppIcon.appiconset")

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func linearGradient(_ context: CGContext, _ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [])
}

/// 네 꼭짓점 별(반짝임). 좌표는 왼쪽 아래 원점.
func sparkle(center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let inner = radius * 0.22
    path.move(to: CGPoint(x: center.x, y: center.y + radius))
    path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + inner, y: center.y + inner))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x + inner, y: center.y - inner))
    path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - inner, y: center.y - inner))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x - inner, y: center.y + inner))
    path.closeSubpath()
    return path
}

func drawIcon(size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)

    // macOS 아이콘 격자: 1024 캔버스 안에 824 크기 본체, 아래로 살짝 그림자.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
    context.addPath(bodyPath)
    context.setFillColor(color(0.15, 0.36, 0.86))
    context.fillPath()
    context.restoreGState()

    // 배경: 위는 밝은 파랑, 아래는 짙은 남색.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    linearGradient(context, [color(0.27, 0.62, 1.0), color(0.13, 0.25, 0.70)],
                   from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    // 위쪽 은은한 광택
    context.setFillColor(color(1, 1, 1, 0.08))
    context.fillEllipse(in: CGRect(x: -80, y: 560, width: 1184, height: 700))
    context.restoreGState()

    // 디스크 드라이브 본체
    let drive = CGRect(x: 222, y: 300, width: 580, height: 300)
    let drivePath = CGPath(roundedRect: drive, cornerWidth: 72, cornerHeight: 72, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0.03, 0.08, 0.25, 0.45))
    context.addPath(drivePath)
    context.setFillColor(color(0.96, 0.97, 1.0))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(drivePath)
    context.clip()
    linearGradient(context, [color(1, 1, 1), color(0.84, 0.88, 0.95)],
                   from: CGPoint(x: 512, y: 600), to: CGPoint(x: 512, y: 300))
    // 아래 1/3 구분선 위쪽 면
    context.setFillColor(color(0.70, 0.76, 0.88, 0.55))
    context.fill(CGRect(x: drive.minX, y: drive.minY + 104, width: drive.width, height: 7))
    context.restoreGState()

    // 통풍구 5개와 초록 상태 표시등
    context.setFillColor(color(0.45, 0.52, 0.68))
    for index in 0..<5 {
        let bar = CGRect(x: 290 + CGFloat(index) * 44, y: 340, width: 24, height: 40)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 12, cornerHeight: 12, transform: nil))
    }
    context.fillPath()
    context.setFillColor(color(0.20, 0.82, 0.45))
    context.fillEllipse(in: CGRect(x: 706, y: 340, width: 40, height: 40))

    // 깨끗함을 뜻하는 반짝임
    context.saveGState()
    context.setShadow(offset: .zero, blur: 24, color: color(1, 0.85, 0.3, 0.7))
    context.setFillColor(color(1, 0.86, 0.32))
    context.addPath(sparkle(center: CGPoint(x: 735, y: 690), radius: 112))
    context.fillPath()
    context.setFillColor(color(1, 0.95, 0.75))
    context.addPath(sparkle(center: CGPoint(x: 598, y: 770), radius: 52))
    context.fillPath()
    context.restoreGState()

    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 변환 실패"])
    }
    try data.write(to: url)
}

// (포인트 크기, 배율)
let entries: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
var images: [String] = []
for (points, scale) in entries {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try writePNG(drawIcon(size: points * scale), to: outputDirectory.appendingPathComponent(name))
    images.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(points)x\(points)" }
    """)
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contents.write(to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("생성: \(outputDirectory.path) (\(entries.count)개)")
