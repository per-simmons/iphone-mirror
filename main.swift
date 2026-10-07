// iPhone Mirror — live, wired (USB) mirror of an iPhone inside Apple's official bezel.
// Uses the same CoreMediaIO screen-capture device QuickTime uses: full resolution,
// ~1 frame of latency, rendered straight to an AVCaptureVideoPreviewLayer.
//
// Quit: Q, Cmd+Q, right-click > Quit, or Dock icon > Quit.
// Keys: B stage (cream 16:9 background) · C bezel color · T keep on top
//       1/2/3 size · Q quit. Drag anywhere to move; resize from the edges.
import AppKit
import AVFoundation
import CoreMediaIO

let bezels = ["iphone-17-pro-silver", "iphone-17-pro-deep-blue", "iphone-17-pro-cosmic-orange",
              "iphone-17-black", "iphone-17-white"]
let bezelSize = CGSize(width: 1350, height: 2760)
let screenRect = CGRect(x: 72, y: 69, width: 1206, height: 2622)  // top-left origin, bezel px
let stageColor = NSColor(srgbRed: 0.980, green: 0.973, blue: 0.957, alpha: 1)  // #FAF8F4

func resource(_ name: String) -> CGImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let img = NSImage(contentsOf: url) else { return nil }
    return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

func allowScreenCaptureDevices() {
    var prop = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var allow: UInt32 = 1
    CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil,
                              UInt32(MemoryLayout<UInt32>.size), &allow)
}

func findPhone() -> AVCaptureDevice? {
    AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
        .devices.first { $0.hasMediaType(.muxed) }
}

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/iPhoneMirror.log")
func log(_ s: String) {
    let line = "\(Date()) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

final class MirrorView: NSView {
    let phone = CALayer(), preview = AVSampleBufferDisplayLayer(), bezel = CALayer()
    let mask = CALayer(), hint = CATextLayer()
    var stage = false { didSet { layout(); window?.invalidateShadow() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer!.backgroundColor = .clear
        preview.videoGravity = .resizeAspectFill
        preview.backgroundColor = NSColor.black.cgColor
        mask.contents = resource("screen-mask")
        preview.mask = mask
        hint.string = "Plug in your iPhone\nwith a cable and tap Trust"
        hint.alignmentMode = .center
        hint.foregroundColor = NSColor(white: 1, alpha: 0.6).cgColor
        hint.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        hint.fontSize = 15
        hint.isWrapped = true
        bezel.contentsGravity = .resize
        for l in [preview, hint, bezel] { phone.addSublayer(l) }
        layer!.addSublayer(phone)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer!.backgroundColor = stage ? stageColor.cgColor : .clear
        let b = bounds
        let h = stage ? b.height * 0.9 : b.height
        let w = h * bezelSize.width / bezelSize.height
        phone.frame = CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
        let s = h / bezelSize.height
        // CALayer y-up inside a flipped view's backing layer is still top-left here (geometryFlipped).
        let r = CGRect(x: screenRect.minX * s, y: screenRect.minY * s,
                       width: screenRect.width * s, height: screenRect.height * s)
        preview.frame = r
        mask.frame = preview.bounds
        bezel.frame = phone.bounds
        hint.fontSize = max(11, r.width * 0.055)
        hint.frame = CGRect(x: r.minX + 16, y: r.midY - hint.fontSize * 1.4, width: r.width - 32, height: hint.fontSize * 2.8)
        hint.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }
}

// Borderless windows refuse key status by default, which swallowed every shortcut.
final class MirrorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class App: NSObject, NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var window: NSWindow!
    let videoOut = AVCaptureVideoDataOutput(), videoQueue = DispatchQueue(label: "video", qos: .userInteractive)
    var activity: NSObjectProtocol?, frames = 0
    let view = MirrorView(frame: .zero)
    let session = AVCaptureSession()
    var color = 0, sizeStep = 1

    func applicationDidFinishLaunching(_ n: Notification) {
        let h = sizeFor(step: sizeStep)
        window = MirrorWindow(contentRect: NSRect(x: 0, y: 0, width: h * bezelSize.width / bezelSize.height, height: h),
                          styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentAspectRatio = bezelSize
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        setBezel()
        NSApp.activate(ignoringOtherApps: true)

        let menu = NSMenu(), item = NSMenuItem(), sub = NSMenu()
        sub.addItem(withTitle: "Quit iPhone Mirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = sub; menu.addItem(item); NSApp.mainMenu = menu
        let ctx = NSMenu()
        ctx.addItem(withTitle: "Quit iPhone Mirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        view.menu = ctx
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.key(e) ?? e }

        // Keep capture callbacks at full rate when the window is behind other apps (App Nap froze it).
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "live mirror")
        videoOut.alwaysDiscardsLateVideoFrames = true
        videoOut.setSampleBufferDelegate(self, queue: videoQueue)
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] n in
                log("session \(n.name.rawValue) \(n.userInfo ?? [:])"); self?.restart()
            }
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.report() }
        allowScreenCaptureDevices()
        NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main) { [weak self] _ in self?.connect() }
        NotificationCenter.default.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main) { [weak self] _ in self?.disconnectIfGone() }
        // The phone's capture device can take a couple of seconds to appear after the CMIO flag is set.
        AVCaptureDevice.requestAccess(for: .video) { _ in
            DispatchQueue.main.async { self.connect() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.connect() }
        }
    }

    func connect() {
        guard session.inputs.isEmpty, let dev = findPhone(),
              let input = try? AVCaptureDeviceInput(device: dev) else { return }
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.outputs.isEmpty {
            if session.canAddOutput(videoOut) { session.addOutput(videoOut) }
        }
        session.commitConfiguration()
        view.hint.isHidden = true
        log("connected \(dev.localizedName) format \(dev.activeFormat)")
        DispatchQueue.global(qos: .userInteractive).async { self.session.startRunning() }
    }

    func restart() {
        DispatchQueue.global(qos: .userInteractive).async {
            self.session.stopRunning(); self.session.startRunning()
            log("restarted, running=\(self.session.isRunning)")
        }
    }

    func report() {
        let n = frames; frames = 0
        let r = view.preview.sampleBufferRenderer
        if r.status == .failed { log("renderer failed \(String(describing: r.error)), flushing"); r.flush() }
        if session.isRunning || n > 0 { log("fps \(Double(n) / 5) running=\(session.isRunning)") }
    }

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        // Show each frame as soon as it arrives instead of on its presentation timestamp.
        if let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true), CFArrayGetCount(a) > 0 {
            let d = unsafeBitCast(CFArrayGetValueAtIndex(a, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(d, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let r = view.preview.sampleBufferRenderer
        if r.status == .failed { r.flush() }
        r.enqueue(sb)
        DispatchQueue.main.async { self.frames += 1 }
    }

    func disconnectIfGone() {
        guard let input = session.inputs.first as? AVCaptureDeviceInput, !input.device.isConnected else { return }
        session.stopRunning()
        session.removeInput(input)
        view.hint.isHidden = false
    }

    func setBezel() {
        view.bezel.contents = resource(bezels[color])
        window.invalidateShadow()
    }

    func sizeFor(step: Int) -> CGFloat {
        let vis = (NSScreen.main?.visibleFrame.height ?? 900)
        return vis * [0.55, 0.8, 0.97][step]
    }

    func resize() {
        let h = sizeFor(step: sizeStep)
        let w = view.stage ? h * 16 / 9 : h * bezelSize.width / bezelSize.height
        let f = window.frame
        window.setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h), display: true, animate: true)
    }

    func key(_ e: NSEvent) -> NSEvent? {
        switch e.charactersIgnoringModifiers?.lowercased() {
        case "q": NSApp.terminate(nil)
        case "b":
            view.stage.toggle()
            window.contentAspectRatio = view.stage ? NSSize(width: 16, height: 9) : bezelSize
            window.hasShadow = !view.stage
            resize()
        case "c": color = (color + 1) % bezels.count; setBezel()
        case "t": window.level = window.level == .floating ? .normal : .floating
        case "1", "2", "3": sizeStep = Int(e.charactersIgnoringModifiers!)! - 1; resize()
        default: return e
        }
        return nil
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
