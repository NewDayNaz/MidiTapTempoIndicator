#!/usr/bin/env swift
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("usage: generate-menu-bar-icon.swift <output-dir>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: args[1], isDirectory: true)

func renderSymbol(pixelSize: Int) -> CGImage? {
    guard let symbol = NSImage(systemSymbolName: "metronome.fill", accessibilityDescription: nil) else {
        return nil
    }
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(pixelSize) * 0.72, weight: .medium)
    let configured = symbol.withSymbolConfiguration(config) ?? symbol

    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let bytes = context.data?.bindMemory(to: UInt8.self, capacity: pixelSize * pixelSize * 4) else {
        return nil
    }

    context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext
    let size = configured.size
    let origin = NSPoint(
        x: (CGFloat(pixelSize) - size.width) / 2,
        y: (CGFloat(pixelSize) - size.height) / 2
    )
    configured.draw(in: NSRect(origin: origin, size: size))
    NSGraphicsContext.restoreGraphicsState()

    for i in 0..<(pixelSize * pixelSize) {
        let offset = i * 4
        let alpha = bytes[offset + 3]
        bytes[offset] = 0
        bytes[offset + 1] = 0
        bytes[offset + 2] = 0
        bytes[offset + 3] = alpha > 20 ? alpha : 0
    }

    return context.makeImage()
}

func writePNG(cgImage: CGImage, to url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return false
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    return CGImageDestinationFinalize(destination)
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

guard let icon18 = renderSymbol(pixelSize: 18),
      let icon36 = renderSymbol(pixelSize: 36) else {
    fputs("error: could not render metronome symbol\n", stderr)
    exit(1)
}

let out18 = outputDir.appendingPathComponent("MenuBarIcon.png")
let out36 = outputDir.appendingPathComponent("MenuBarIcon@2x.png")
guard writePNG(cgImage: icon18, to: out18), writePNG(cgImage: icon36, to: out36) else {
    fputs("error: could not write menu bar icons\n", stderr)
    exit(1)
}

print("Generated: \(out18.path)")
print("Generated: \(out36.path)")
