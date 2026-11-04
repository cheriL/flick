#!/usr/bin/env swift
// Renders the Flick bubble glyph (green bubble + white F on transparent background)
// to a multi-resolution .icns. Run from the project root; output at Resources/Flick.icns.

import SwiftUI
import AppKit
import Foundation

struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.addLine(to: CGPoint(x: rect.width * 0.4, y: 0))
        p.closeSubpath()
        return p
    }
}

let flickGradient = LinearGradient(
    colors: [Color(red: 0.227, green: 0.855, blue: 0.584),
             Color(red: 0.071, green: 0.757, blue: 0.733)],
    startPoint: .top, endPoint: .bottom)

@MainActor
func renderHighRes(to url: URL) {
    let view = FlickBubbleIcon(side: 1024)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0

    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("render failed\n".utf8))
        exit(1)
    }
    try? png.write(to: url)
}

struct FlickBubbleIcon: View {
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                .fill(flickGradient)
                .frame(width: side * 0.94, height: side * 0.94)
            Text("F")
                .font(.system(size: side * 0.55, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: side, height: side)
    }
}

func runShell(_ launchPath: String, _ args: [String]) {
    let task = Process()
    task.launchPath = launchPath
    task.arguments = args
    try? task.run()
    task.waitUntilExit()
}

@MainActor
func runGenerate() {
    let cwd = FileManager.default.currentDirectoryPath
    let iconsetDir = URL(fileURLWithPath: cwd).appendingPathComponent("Flick.iconset")
    let icnsPath = URL(fileURLWithPath: cwd).appendingPathComponent("Resources/Flick.icns")

    try? FileManager.default.removeItem(at: iconsetDir)
    try? FileManager.default.removeItem(at: icnsPath)
    try? FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

    let highResURL = iconsetDir.appendingPathComponent("icon_512x512@2x.png")
    renderHighRes(to: highResURL)

    let sizes: [(Int, String)] = [
        (16,  "icon_16x16.png"),
        (32,  "icon_16x16@2x.png"),
        (32,  "icon_32x32.png"),
        (64,  "icon_32x32@2x.png"),
        (64,  "icon_64x64.png"),
        (128, "icon_64x64@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
    ]
    for (size, name) in sizes {
        let out = iconsetDir.appendingPathComponent(name)
        runShell("/usr/bin/sips", ["-z", String(size), String(size), highResURL.path, "--out", out.path])
    }

    runShell("/usr/bin/iconutil", ["-c", "icns", iconsetDir.path, "-o", icnsPath.path])
    try? FileManager.default.removeItem(at: iconsetDir)

    print("wrote \(icnsPath.path)")
    exit(0)
}

DispatchQueue.main.async {
    runGenerate()
}
RunLoop.main.run(until: Date(timeIntervalSinceNow: 10))
