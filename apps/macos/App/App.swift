import SwiftUI
import AppKit
import CoreServices
import ImageIO
import UniformTypeIdentifiers

private enum MenuBarBrand {
    static let image: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let source = NSImage(named: "BrandMark") ?? NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) ?? NSImage(size: size)
        let image = NSImage(size: size)
        for scale in [1, 2] {
            let pixels = 16 * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = size
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context; context.imageInterpolation = .high
            source.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = false
        return image
    }()
}

@main struct BillingApp: App {
    @NSApplicationDelegateAdaptor(StartupDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    var body: some Scene {
        MenuBarExtra { Panel().environmentObject(model) } label: {
            HStack { Image(nsImage: MenuBarBrand.image).accessibilityHidden(true); if !quotaAlerts(model.current, cycle: model.activeCycle).isEmpty { Image(systemName: "exclamationmark.triangle.fill").accessibilityLabel(tr("Free quota alert", "免费额度预警")) }; Text((model.isDesignPreview ? tr("Preview ", "预览 ") : (model.isSampleSelected ? tr("Sample ", "示例 ") : "")) + (model.totals.first.flatMap { total in total.total.map { _ in "≈" + money(total.total, total.currency) } } ?? "--")) }.accessibilityLabel((model.isDesignPreview ? tr("Preview, ", "预览，") : (model.isSampleSelected ? tr("Local sample data, ", "本地示例数据，") : "")) + tr("Cloudflare® billing estimate", "Cloudflare® 账户费用估算") + ": " + (model.totals.first.flatMap { total in total.total.map { _ in money(total.total, total.currency) } } ?? tr("Unavailable", "暂不可用")))
        }.menuBarExtraStyle(.window)
            .commands { CommandGroup(after: .appInfo) { Button(tr("Open main window", "打开主窗口")) { MainWindowPresenter.shared.show(model: model) }.keyboardShortcut("0", modifiers: .command) } }
    }
}


func isLoginItemLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
    guard let event, event.eventClass == AEEventClass(kCoreEventClass), event.eventID == AEEventID(kAEOpenApplication),
          let origin = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else { return false }
    return origin.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
}

@MainActor final class StartupDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowPresenter.shared.show(model: AppModel.shared); return false
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let previewOnlyArguments = ["--export-previews", "--show-preview"]
        if Bundle.main.bundleIdentifier != "com.meathill.CloudflareBillingHelper.DesignPreview", previewOnlyArguments.contains(where: CommandLine.arguments.contains) {
            fputs("Preview export and preview windows are available only in DesignPreview.\n", stderr)
            NSApp.terminate(nil); return
        }
        let model = AppModel.shared
        if model.isDesignPreview && CommandLine.arguments.contains("--preview-product-fallback") { model.setupDemo(seed: true); model.setupProductFallbackPreview() }
        if model.isDesignPreview, let index = CommandLine.arguments.firstIndex(of: "--export-previews"), CommandLine.arguments.indices.contains(index + 1) {
            do { try exportPreviews(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true), model: model) }
            catch { fputs("Preview export failed: \(error)\n", stderr) }
            NSApp.terminate(nil); return
        }
        let preview = model.isDesignPreview && CommandLine.arguments.contains("--show-preview")
        let showSettings = CommandLine.arguments.contains("--show-settings")
        let launchIsLoginItem = isLoginItemLaunch(NSAppleEventManager.shared().currentAppleEvent)
        guard preview || showSettings || model.isDesignPreview || !launchIsLoginItem else { return }
        if preview {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 370, height: 620), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = model.isDesignPreview ? "Billing Helper for Cloudflare® · Design Preview / 设计预览" : "Billing Helper for Cloudflare®"
            window.contentView = NSHostingView(rootView: Panel().environmentObject(model))
            window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); self.window = window
        } else { MainWindowPresenter.shared.show(model: model) }
    }
}

@MainActor final class MainWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = MainWindowPresenter()
    private var window: NSWindow?
    private weak var model: AppModel?
    func show(model: AppModel) {
        if !NSApp.setActivationPolicy(.regular) { NSLog("Could not switch application activation policy to regular.") }
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = model.isDesignPreview ? "Billing Helper for Cloudflare® · Design Preview / 设计预览" : "Billing Helper for Cloudflare®"
        window.contentMinSize = NSSize(width: 900, height: 650); window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(model)); window.delegate = self
        self.model = model; self.window = window
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        let appModel = model
        appModel?.cancelDiscovery(); window?.contentView = nil; window?.delegate = nil; window = nil; model = nil
        if !NSApp.setActivationPolicy(.accessory) { NSLog("Could not switch application activation policy to accessory.") }
    }
}

@MainActor private func exportPreviews(to directory: URL, model: AppModel) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    func argument(_ name: String, allowed: [String]) throws -> String {
        guard let index = CommandLine.arguments.firstIndex(of: name), CommandLine.arguments.indices.contains(index + 1), allowed.contains(CommandLine.arguments[index + 1]) else { throw CocoaError(.fileReadInvalidFileName) }
        return CommandLine.arguments[index + 1]
    }
    let language = try argument("--preview-language", allowed: ["en", "zh"])
    let dark = try argument("--preview-appearance", allowed: ["light", "dark"]) == "dark"
    let previewView = try argument("--preview-view", allowed: ["panel", "settings", "privacy"])
    let settings = previewView == "settings"
    let privacy = previewView == "privacy"
    previewLanguage = language; model.setupDemo(seed: true)
    if model.isStoreScreenshot { model.setupStoreSampleScreenshot() }
    let productFallback = model.isDesignPreview && CommandLine.arguments.contains("--preview-product-fallback")
    if productFallback { model.setupProductFallbackPreview() }
    let longNames = model.isDesignPreview && CommandLine.arguments.contains("--preview-long-names")
    let minimum = model.isDesignPreview && CommandLine.arguments.contains("--preview-minimum")
    if longNames, model.accounts.count >= 2 {
        model.accounts[0].name = "VeryLongUnbrokenAccountNameForAccessibilityAndTruncationVerification1234567890"
        model.accounts[1].name = "这是一个用于验证长账户名称截断和辅助功能的中文示例账户名称非常非常长"
    }
    if model.isDesignPreview, CommandLine.arguments.firstIndex(of: "--preview-page").flatMap({ CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }) == "budget" {
        model.budgetEnabled = true; model.budgetCurrency = "USD"; model.budgetText = "100"; model.usePreviewBudgets()
    }
    let canvasWidth: CGFloat = model.isDesignPreview ? 1440 : 1280
    let canvasHeight: CGFloat = model.isDesignPreview ? 900 : 800
    do {
                let scene = ZStack {
                    Color(nsColor: dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.94, alpha: 1))
                    if privacy { PrivacyPolicySheet().frame(width: 680, height: 780).background(Color(nsColor: .windowBackgroundColor)) }
                    else if settings { SettingsView().environmentObject(model).frame(width: minimum ? 900 : 1100, height: minimum ? 650 : (model.isDesignPreview ? 780 : 700)).background(Color(nsColor: .windowBackgroundColor)) }
                    else { Panel().environmentObject(model).background(Color(nsColor: .windowBackgroundColor)) }
                }.frame(width: canvasWidth, height: canvasHeight).environment(\.locale, Locale(identifier: language == "zh" ? "zh_Hans" : "en"))
                    .preferredColorScheme(dark ? .dark : .light)
                let host = NSHostingView(rootView: scene)
                host.frame = NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.ignoresMouseEvents = true
                window.contentView = host; window.orderFrontRegardless()
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                // Give AppKit-backed controls time to finish their native display transaction.
                RunLoop.main.run(until: Date().addingTimeInterval(0.25))
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let sourceImage = bitmap.cgImage,
                      let context = CGContext(data: nil, width: Int(canvasWidth), height: Int(canvasHeight), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
                context.interpolationQuality = .high
                context.setFillColor(NSColor.windowBackgroundColor.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
                context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
                guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
                let bytes = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
                CGImageDestinationAddImage(destination, image, nil)
                guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
                let data = bytes as Data
                let page = CommandLine.arguments.firstIndex(of: "--preview-page").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? AppPage(rawValue: CommandLine.arguments[$0 + 1]) : nil }
                let name = (privacy ? "privacy" : (settings && model.isDesignPreview ? (page?.rawValue ?? "overview") : (settings ? "settings" : "panel"))) + (longNames ? "-long" : "") + (productFallback ? "-fallback" : "") + (minimum ? "-minimum" : "")
                try data.write(to: directory.appendingPathComponent("\(name)-\(language)-\(dark ? "dark" : "light").png"), options: .atomic)
                window.orderOut(nil)
    }
    previewLanguage = nil
}
