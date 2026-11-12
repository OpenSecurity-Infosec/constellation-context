import AppKit
import ContextDomain
import SwiftUI

/// Live timer state for the fullscreen display.
struct TimerSnapshot {
    var name: String
    var display: String
    var fraction: Double?
    var running: Bool
    var modeLabel: String
    var finished: Bool
    var elapsed: TimeInterval
    var total: TimeInterval?
}

/// Named fullscreen timer for `timer` notes: big time, note name,
/// countdown progress, start/stop/reset. Esc exits. Beeps once when
/// a running countdown reaches zero.
@MainActor
final class TimerWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let vm: TimerViewModel
    private let read: () -> TimerSnapshot?
    private let onStart: () -> Void
    private let onStop: () -> Void
    private let onReset: () -> Void
    private let onClose: () -> Void
    private var tick: Timer?
    private var announcedFinish = false

    init(
        read: @escaping () -> TimerSnapshot?,
        onStart: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.read = read
        self.onStart = onStart
        self.onStop = onStop
        self.onReset = onReset
        self.onClose = onClose
        vm = TimerViewModel()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Timer"
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        super.init()
        window.delegate = self
        window.contentView = NSHostingView(rootView: TimerFullscreenView(
            vm: vm,
            onStart: { [weak self] in self?.onStart() },
            onStop: { [weak self] in self?.onStop() },
            onReset: { [weak self] in self?.onReset() },
            onExit: { [weak self] in self?.close() }
        ))
    }

    func show() {
        pulse()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        tick?.invalidate()
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pulse() }
        }
    }

    func close() {
        tick?.invalidate()
        tick = nil
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        window.orderOut(nil)
        onClose()
    }

    func windowWillClose(_ notification: Notification) {
        tick?.invalidate()
        tick = nil
        onClose()
    }

    private func pulse() {
        guard let snap = read() else { close(); return }
        if snap.finished, !announcedFinish {
            announcedFinish = true
            NSSound.beep()
        } else if !snap.finished {
            announcedFinish = false
        }
        vm.snapshot = snap
        if window.title != snap.name { window.title = snap.name }
    }
}

@MainActor
final class TimerViewModel: ObservableObject {
    @Published var snapshot = TimerSnapshot(
        name: "Timer", display: "0:00", fraction: nil,
        running: false, modeLabel: "", finished: false,
        elapsed: 0, total: nil
    )
}

private struct TimerFullscreenView: View {
    @ObservedObject var vm: TimerViewModel
    var onStart: () -> Void
    var onStop: () -> Void
    var onReset: () -> Void
    var onExit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            if !vm.snapshot.modeLabel.isEmpty {
                Text(vm.snapshot.modeLabel)
                    .font(.title3).foregroundStyle(.secondary)
            }
            Text(vm.snapshot.name)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if vm.snapshot.finished {
                Text("Done")
                    .font(.system(size: 112, weight: .light, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(Color.ctxAccent)
                Text(TimerScene.finishLine(total: vm.snapshot.total))
                    .font(.title2).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 32) {
                    if let fraction = vm.snapshot.fraction {
                        ZStack {
                            Circle()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 6)
                            Circle()
                                .trim(from: 0, to: min(1, max(0, fraction)))
                                .stroke(Color.ctxAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(reduceMotion ? nil : .linear(duration: 0.25), value: fraction)
                            Text(TimerScene.ringLabel(fraction: fraction))
                                .font(.system(size: 18, weight: .medium, design: .rounded).monospacedDigit())
                        }
                        .frame(width: 120, height: 120)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Progress")
                        .accessibilityValue(TimerScene.ringLabel(fraction: fraction))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.snapshot.display)
                            .font(.system(size: 112, weight: .light, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                        let remaining = vm.snapshot.total.map { max(0, $0 - vm.snapshot.elapsed) }
                        let line = TimerScene.statusLine(
                            elapsed: vm.snapshot.elapsed,
                            remaining: vm.snapshot.total == nil ? nil : remaining,
                            running: vm.snapshot.running
                        )
                        if !line.isEmpty {
                            Text(line)
                                .font(.title3).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack(spacing: 16) {
                Button(vm.snapshot.running ? "Stop" : "Start") {
                    vm.snapshot.running ? onStop() : onStart()
                }
                .keyboardShortcut(.return, modifiers: [])
                Button("Reset") { onReset() }
                Button("Exit") { onExit() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .font(.title3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
        .background(TimerAtmosphere(reduceMotion: reduceMotion))
        .tint(.ctxAccent)
    }
}

/// Palette-derived aurora: the same paper and accent tokens as the editor.
private struct TimerAtmosphere: View {
    let reduceMotion: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / 18
            GeometryReader { geometry in
                ZStack {
                    Color.ctxEditorBackground
                    ForEach(0..<3) { index in
                        Ellipse()
                            .fill(RadialGradient(
                                colors: [Color.ctxAccent.opacity(colorScheme == .dark ? 0.22 : 0.14), .clear],
                                center: .center, startRadius: 0,
                                endRadius: geometry.size.width * 0.45))
                            .frame(width: geometry.size.width * 0.9, height: geometry.size.height * 0.9)
                            .position(
                                x: geometry.size.width * (0.5 + 0.4 * sin(phase + Double(index) * 2.1)),
                                y: geometry.size.height * (0.5 + 0.4 * cos(phase * 0.7 + Double(index) * 2.1)))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
