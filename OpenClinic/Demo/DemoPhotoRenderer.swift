//
//  DemoPhotoRenderer.swift
//  OpenClinic
//
//  Draws the placeholder lesion images for the demo photo series. It uses
//  CoreGraphics and ImageIO only, so the same code runs on iOS, iPadOS, macOS
//  and visionOS. The images are schematic drawings, not clinical photographs.
//

import Foundation
import CoreGraphics
import ImageIO

nonisolated enum DemoPhotoRenderer {
    /// Drawing happens on a square canvas this many points wide.
    static let canvasPoints: CGFloat = 200
    /// Pixels per point in the written image.
    static let scale: CGFloat = 2

    /// JPEG data for one frame of a photo series, or nil if the image could not be drawn or encoded.
    static func jpegData(for frame: DemoPhotoFrame, compressionQuality: Double = 0.85) -> Data? {
        guard let image = makeImage(for: frame) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Writes the frame to `url` as a JPEG, replacing any file already there. Returns false on failure.
    @discardableResult
    static func writeJPEG(for frame: DemoPhotoFrame, to url: URL) -> Bool {
        guard let data = jpegData(for: frame) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func makeImage(for frame: DemoPhotoFrame) -> CGImage? {
        let pixels = Int(canvasPoints * scale)
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }
        context.scaleBy(x: scale, y: scale)

        // Skin background.
        context.setFillColor(red: 0.93, green: 0.78, blue: 0.68, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: canvasPoints, height: canvasPoints))

        switch frame.style {
        case .papule:
            drawPapule(frame, in: context)
        case .scar:
            drawScar(frame, in: context)
        }
        return context.makeImage()
    }

    // MARK: - Shapes

    /// A round lesion with a ring of erythema and a few pale flecks of scale.
    private static func drawPapule(_ frame: DemoPhotoFrame, in context: CGContext) {
        let center = canvasPoints / 2
        let radius = CGFloat(max(frame.size, 1))
        let haloRadius = radius + 3 + radius * 0.4

        context.setFillColor(red: 0.78, green: 0.32, blue: 0.30, alpha: CGFloat(clamp(frame.erythema)))
        context.fillEllipse(in: CGRect(x: center - haloRadius, y: center - haloRadius, width: haloRadius * 2, height: haloRadius * 2))

        setFill(frame.color, in: context)
        context.fillEllipse(in: CGRect(x: center - radius, y: center - radius, width: radius * 2, height: radius * 2))

        // Scale: small pale flecks at fixed offsets so the image is the same on every run.
        context.setFillColor(red: 0.97, green: 0.93, blue: 0.88, alpha: 0.85)
        let fleck = max(radius * 0.22, 0.8)
        let offsets: [(CGFloat, CGFloat)] = [(-0.35, 0.30), (0.25, -0.20), (0.05, 0.45)]
        for (dx, dy) in offsets {
            context.fillEllipse(in: CGRect(
                x: center + dx * radius - fleck / 2,
                y: center + dy * radius - fleck / 2,
                width: fleck,
                height: fleck
            ))
        }
    }

    /// A linear scar with a band of erythema and evenly spaced suture marks.
    private static func drawScar(_ frame: DemoPhotoFrame, in context: CGContext) {
        let center = canvasPoints / 2
        let halfLength = CGFloat(max(frame.size, 4))
        let start = CGPoint(x: center - halfLength, y: center - halfLength * 0.25)
        let end = CGPoint(x: center + halfLength, y: center + halfLength * 0.25)

        context.setLineCap(.round)

        // Redness around the line.
        context.setStrokeColor(red: 0.78, green: 0.32, blue: 0.30, alpha: CGFloat(clamp(frame.erythema)))
        context.setLineWidth(12)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // The scar line.
        context.setStrokeColor(red: CGFloat(clamp(frame.color.red)), green: CGFloat(clamp(frame.color.green)), blue: CGFloat(clamp(frame.color.blue)), alpha: 1)
        context.setLineWidth(2.5)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Suture marks across the line. They fade with the erythema as the scar matures.
        let markAlpha = CGFloat(clamp(frame.erythema * 1.6))
        guard markAlpha > 0.05 else { return }
        context.setStrokeColor(red: 0.45, green: 0.22, blue: 0.20, alpha: markAlpha)
        context.setLineWidth(1)
        let markCount = 6
        for index in 1...markCount {
            let t = CGFloat(index) / CGFloat(markCount + 1)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t
            context.move(to: CGPoint(x: x - 1.5, y: y - 5))
            context.addLine(to: CGPoint(x: x + 1.5, y: y + 5))
            context.strokePath()
        }
    }

    // MARK: - Helpers

    private static func setFill(_ color: DemoColor, in context: CGContext) {
        context.setFillColor(red: CGFloat(clamp(color.red)), green: CGFloat(clamp(color.green)), blue: CGFloat(clamp(color.blue)), alpha: 1)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
