import CoreGraphics
import Foundation
import ImageIO

/// The program's icon from its resources: the image, and its pixels premultiplied by alpha, rows from the top, so
/// that the smaller mip levels do not darken at the edges with the color of the transparent pixels.
struct IconImage {
    let image: CGImage
    let width: Int
    let height: Int
    let premultipliedPixels: [UInt8]

    init?() {
        guard let url = ResourceBundle.url(forResource: "reversi3d", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.image = image
        self.width = width
        self.height = height
        premultipliedPixels = pixels
    }
}
