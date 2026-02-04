import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var permissionService = PermissionService.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var bookmarkManager = SecurityScopedBookmarkManager.shared

    @State private var currentStep = 0
    @Environment(\.dismiss) private var dismiss

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressIndicator
                .padding(.top, 24)
                .padding(.horizontal, 24)

            // Content
            TabView(selection: $currentStep) {
                welcomeStep
                    .tag(0)

                accessibilityStep
                    .tag(1)

                fullDiskAccessStep
                    .tag(2)

                readyStep
                    .tag(3)
            }
            .tabViewStyle(.automatic)
            .padding(.vertical, 16)

            // Navigation
            navigationButtons
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(width: 520, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Welcome Step

    private var welcomeStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                Image(systemName: "clipboard.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                Text("Welcome to ClipBoard")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(spacing: 10) {
                    FeatureRow(
                        icon: "lock.shield",
                        title: "100% Local",
                        description: "Your clipboard data stays on your device."
                    )

                    FeatureRow(
                        icon: "clock.arrow.circlepath",
                        title: "Clipboard History",
                        description: "Access everything you've copied."
                    )

                    FeatureRow(
                        icon: "keyboard",
                        title: "Quick Access",
                        description: "Global shortcuts for instant pasting."
                    )
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Accessibility Step

    private var accessibilityStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 30)

                Image(systemName: "accessibility")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Accessibility Permission")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This permission enables click-to-paste and API paste automation, so items paste directly into your active app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    if permissionService.hasAccessibilityPermission {
                        Label("Permission Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.headline)
                    } else {
                        Button("Grant Accessibility Permission") {
                            permissionService.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)

                        Text("You can skip this - ClipBoard will work in copy-only mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 30)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Screenshots Folder Step

    private var fullDiskAccessStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 30)

                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Screenshot History")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select your Screenshots folder to automatically capture screenshots to your clipboard history.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 12) {
                    if bookmarkManager.hasScreenshotsFolderAccess,
                       let url = bookmarkManager.screenshotsFolderURL {
                        Label("Folder Selected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.headline)

                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)

                        Button("Change Folder") {
                            bookmarkManager.selectScreenshotsFolder()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Select Screenshots Folder") {
                            bookmarkManager.selectScreenshotsFolder()
                        }
                        .buttonStyle(.borderedProminent)

                        Text("Usually this is your Desktop or a Screenshots folder.\nThis is optional - skip if you don't want screenshot history.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer(minLength: 30)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Ready Step

    private var readyStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)

                Text("You're All Set!")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: permissionService.hasAccessibilityPermission ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(permissionService.hasAccessibilityPermission ? .green : .orange)
                        Text("Click-to-Paste: \(permissionService.hasAccessibilityPermission ? "Enabled" : "Copy-only")")
                            .font(.subheadline)
                    }

                    HStack {
                        Image(systemName: bookmarkManager.hasScreenshotsFolderAccess ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(bookmarkManager.hasScreenshotsFolderAccess ? .green : .orange)
                        Text("Screenshot History: \(bookmarkManager.hasScreenshotsFolderAccess ? "Enabled" : "Disabled")")
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)

                VStack(spacing: 6) {
                    Text("Use \(settings.popoverShortcut.displayString) to open ClipBoard")
                        .font(.headline)

                    Text("You can change permissions later in System Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 24)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    withAnimation {
                        currentStep -= 1
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button(currentStep == 0 ? "Get Started" : "Next") {
                    withAnimation {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Start Using ClipBoard") {
                    completeOnboarding()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func completeOnboarding() {
        settings.onboardingCompleted = true
        dismiss()
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
