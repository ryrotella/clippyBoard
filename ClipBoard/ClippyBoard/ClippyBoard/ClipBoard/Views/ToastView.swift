import SwiftUI
import AppKit

struct ToastView: View {
    let message: String
    let icon: String
    var isSuccess: Bool = true

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSuccess ? .green : .red)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .scaleEffect(isVisible ? 1 : 0.8)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Toast Overlay Modifier

struct ToastOverlayModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let icon: String
    var duration: Double = 1.5
    var playSound: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isShowing {
                    ToastView(message: message, icon: icon)
                        .padding(.top, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            if playSound {
                                NSSound.beep()
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isShowing = false
                                }
                            }
                        }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShowing)
    }
}

extension View {
    func toast(
        isShowing: Binding<Bool>,
        message: String,
        icon: String = "checkmark.circle.fill",
        duration: Double = 1.5,
        playSound: Bool = false
    ) -> some View {
        modifier(ToastOverlayModifier(
            isShowing: isShowing,
            message: message,
            icon: icon,
            duration: duration,
            playSound: playSound
        ))
    }
}

// MARK: - Toast Manager

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var isShowingCopyToast = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCopyNotification),
            name: .didCopyItem,
            object: nil
        )
    }

    @objc private func handleCopyNotification() {
        guard AppSettings.shared.copyFeedbackToast else { return }

        Task { @MainActor in
            isShowingCopyToast = true

            // Play sound if enabled
            if AppSettings.shared.copyFeedbackSound {
                NSSound.beep()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ToastView(message: "Copied!", icon: "checkmark.circle.fill")
        ToastView(message: "Error", icon: "xmark.circle.fill", isSuccess: false)
    }
    .padding()
    .frame(width: 300, height: 200)
}
