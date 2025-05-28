import SwiftUI

struct CustomKeyboardView: View {
    @Binding var text: String
    var isDecimalAllowed: Bool
    var onNextAction: () -> Void
    var onIncrement: () -> Void
    var onDecrement: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    private let buttonHeight: CGFloat = 54

    var body: some View {
        KeyboardPlateView {
            HStack(spacing: 8) {
                // Left side: Number grid
                LazyVGrid(columns: columns, spacing: 8) {
                    // Numbers 1-9
                    ForEach(1...9, id: \.self) { number in
                        KeyButton(label: String(number)) {
                            appendCharacter(String(number))
                        }
                    }
                    
                    // Bottom row: decimal/empty, 0, delete
                    if isDecimalAllowed {
                        KeyButton(label: ".") {
                            appendCharacter(".")
                        }
                    } else {
                        Color.clear
                            .frame(height: buttonHeight)
                    }
                    
                    KeyButton(label: "0") {
                        appendCharacter("0")
                    }
                    
                    KeyButton(systemImage: "delete.left.fill") {
                        if !text.isEmpty {
                            text.removeLast()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                // Right side: Action buttons
                VStack(spacing: 8) {
                    KeyButton(systemImage: "plus.circle.fill") {
                        onIncrement()
                    }
                    
                    KeyButton(systemImage: "minus.circle.fill") {
                        onDecrement()
                    }
                    
                    Button(action: onNextAction) {
                        Text("Next")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: buttonHeight * 2 + 8) // Spans 2 rows
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
                }
                .frame(width: 90)
            }
        }
    }

    private func appendCharacter(_ character: String) {
        if character == "." && (!isDecimalAllowed || text.contains(".")) {
            return 
        }
        text.append(character)
    }
}

// Reusable key button component
private struct KeyButton: View {
    let label: String?
    let systemImage: String?
    let action: () -> Void
    
    init(label: String, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = nil
        self.action = action
    }
    
    init(systemImage: String, action: @escaping () -> Void) {
        self.label = nil
        self.systemImage = systemImage
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                if let label = label {
                    Text(label)
                        .font(.system(size: 22, weight: .medium))
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                }
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }
}

struct CustomKeyboardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            CustomKeyboardView(
                text: .constant("123.45"), 
                isDecimalAllowed: true, 
                onNextAction: { print("Next/Done Tapped") },
                onIncrement: { print("Increment") },
                onDecrement: { print("Decrement") }
            )
        }
        .background(Color.gray)
    }
} 