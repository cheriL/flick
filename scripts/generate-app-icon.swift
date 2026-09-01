#!/usr/bin/env swift
// Renders `f.square.fill` (palette: white f on green square) to a multi-resolution .icns
// for the Flick bundle. Run from the project root; output lands at Resources/Flick.icns.

import SwiftUI
import AppKit
import Foundation

@MainActor
func renderHighRes(to url: URL) {
    let view = Image(systemName: "f.square.fill")
        .font(.system(size: 1024, weight: .regular))
        .symbolRenderingMode(.palette)
        .foregroundStyle(.white, Color(red: 0.20, green: 0.78, blue: 0.35))
        .frame(width: 1024, height: 1024)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 1.0

    guard let nsImage = renderer.nsImage,
          let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
        exit(1)
    }
    try? png.write(to: url)
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