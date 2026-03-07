import SwiftUI
import AppKit

// MARK: - OnboardingWindowController

final class OnboardingWindowController: NSWindowController {

    static let shared = OnboardingWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.center()
        window.setFrameAutosaveName("BattyOnboarding")
        window.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1.0)
        window.isOpaque = true
        window.hasShadow = true
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let host = NSHostingView(rootView: OnboardingView(controller: self))
        window.contentView = host
    }

    required override init?(coder: NSCoder) { fatalError() }

    func show() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.close()
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    weak var controller: OnboardingWindowController?
    @ObservedObject private var limitManager = ChargeLimitManager.shared

    @State private var step: Int = 0     // 0 = welcome, 1 = permission, 2 = done

    var body: some View {
        ZStack {
            // Background — plain opaque white, same feel as the popover
            Color(NSColor.windowBackgroundColor)

            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(width: 80, height: 80)
                    Image(systemName: iconForStep(step))
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(Color.primary.opacity(0.7))
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
                }

                Spacer().frame(height: 28)

                // Title
                Text(titleForStep(step))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: step)

                Spacer().frame(height: 12)

                // Body
                Text(bodyForStep(step))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 340)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: step)

                Spacer().frame(height: 32)

                // Step-specific content
                if step == 1 {
                    permissionDetail
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule()
                            .fill(Color.primary.opacity(i == step ? 0.7 : 0.15))
                            .frame(width: i == step ? 20 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step)
                    }
                }

                Spacer().frame(height: 28)

                // CTA Button
                ctaButton

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 44)
        }
        .frame(width: 480, height: 540)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: limitManager.isSettingUp) { isSettingUp in
            // When setup finishes successfully, advance to done
            if !isSettingUp && step == 1 && limitManager.isSetupComplete {
                withAnimation(.easeInOut(duration: 0.3)) {
                    step = 2
                }
            }
        }
    }

    // MARK: - Permission Detail (step 1)

    private var permissionDetail: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What Batty writes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.6))
                    Text("/etc/sudoers.d/batty — lets the app run the bundled smc binary as root to flip Apple's charge-limit SMC keys. No other commands allowed.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if limitManager.isSettingUp {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Enter admin password when macOS prompts…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                .padding(.top, 4)
            }

            if !limitManager.isSettingUp && !limitManager.isSetupComplete && !limitManager.setupStatus.isEmpty
               && limitManager.setupStatus != "Needs one-time setup" {
                Text(limitManager.setupStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: 360)
    }

    // MARK: - CTA Button

    @ViewBuilder
    private var ctaButton: some View {
        switch step {
        case 0:
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    step = 1
                }
            } label: {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.primary.opacity(0.85))
                    .foregroundStyle(Color(NSColor.windowBackgroundColor))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

        case 1:
            Button {
                guard !limitManager.isSettingUp else { return }
                Task { @MainActor in
                    _ = await ChargeLimitManager.shared.ensureSetup()
                }
            } label: {
                HStack(spacing: 8) {
                    if limitManager.isSettingUp {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color(NSColor.windowBackgroundColor))
                    }
                    Text(limitManager.isSettingUp ? "Setting up…" : "Grant Permission")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.primary.opacity(limitManager.isSettingUp ? 0.5 : 0.85))
                .foregroundStyle(Color(NSColor.windowBackgroundColor))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(limitManager.isSettingUp)

        case 2:
            Button {
                controller?.dismiss()
            } label: {
                Text("Start Using Batty")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.primary.opacity(0.85))
                    .foregroundStyle(Color(NSColor.windowBackgroundColor))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

        default:
            EmptyView()
        }
    }

    // MARK: - Step content

    private func iconForStep(_ s: Int) -> String {
        switch s {
        case 0: return "bolt.heart"
        case 1: return "lock.open.fill"
        case 2: return "checkmark.circle.fill"
        default: return "bolt.heart"
        }
    }

    private func titleForStep(_ s: Int) -> String {
        switch s {
        case 0: return "Welcome to Batty"
        case 1: return "One-time permission"
        case 2: return "All set"
        default: return ""
        }
    }

    private func bodyForStep(_ s: Int) -> String {
        switch s {
        case 0:
            return "Batty keeps your battery healthy by enforcing a real hardware charge limit — not just a software reminder.\n\nSetup takes 30 seconds. You'll only need to do this once."
        case 1:
            return "To write charge-limit commands to the hardware, Batty needs your admin password once to install a sudoers entry.\n\nAfter that, no more prompts — ever."
        case 2:
            return "Batty is running in the menu bar. Open it, go to Settings, and set your charge limit.\n\n80% is a good default for all-day desk use."
        default:
            return ""
        }
    }
}
