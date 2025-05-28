import SwiftUI

struct RestTimerKeyboardView: View {
    @Binding var remaining: Int  // Using Int to match existing restTimeRemaining type
    @Binding var isPaused: Bool
    var onSkip: () -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    private let buttonHeight: CGFloat = 54
    
    var body: some View {
        KeyboardPlateView {
            VStack(spacing: 8) {
                // Time adjustment grid
                LazyVGrid(columns: columns, spacing: 8) {
                    // Add time buttons
                    TimeButton(seconds: 5, isAdd: true) {
                        remaining += 5
                    }
                    TimeButton(seconds: 10, isAdd: true) {
                        remaining += 10
                    }
                    TimeButton(seconds: 30, isAdd: true) {
                        remaining += 30
                    }
                    
                    // Subtract time buttons
                    TimeButton(seconds: 5, isAdd: false) {
                        remaining = max(0, remaining - 5)
                    }
                    TimeButton(seconds: 10, isAdd: false) {
                        remaining = max(0, remaining - 10)
                    }
                    TimeButton(seconds: 30, isAdd: false) {
                        remaining = max(0, remaining - 30)
                    }
                }
                
                // Control buttons
                HStack(spacing: 8) {
                    Button(action: { isPaused.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 16, weight: .medium))
                            Text(isPaused ? "Resume" : "Pause")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: buttonHeight)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
                    
                    Button(action: onSkip) {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 16, weight: .medium))
                            Text("Skip")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: buttonHeight)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
                }
            }
        }
    }
}

// Time adjustment button component
private struct TimeButton: View {
    let seconds: Int
    let isAdd: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text("\(isAdd ? "+" : "-")\(seconds)s")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

// Preview
struct RestTimerKeyboardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            RestTimerKeyboardView(
                remaining: .constant(60),
                isPaused: .constant(false),
                onSkip: { print("Skip pressed") }
            )
        }
        .background(Color.gray)
    }
} 