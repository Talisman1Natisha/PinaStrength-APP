import SwiftUI

struct CustomKeyboardView: View {
    @Binding var text: String
    var isDecimalAllowed: Bool
    var onNextAction: () -> Void
    var onIncrement: () -> Void
    var onDecrement: () -> Void

    private let numberKeyColumns: [GridItem] = Array(repeating: .init(.flexible(), spacing: 6), count: 3)
    private let keySpacing: CGFloat = 6
    private let buttonHeight: CGFloat = 50 // Adjusted button height
    private let keyboardWidthFraction: CGFloat = 0.95 // Use 95% of screen width

    var body: some View {
        VStack(spacing: 0) { // Main container for the keyboard, no internal padding here
            HStack(alignment: .top, spacing: keySpacing) {
                // Left Side: Number Pad
                VStack(spacing: keySpacing) {
                    LazyVGrid(columns: numberKeyColumns, spacing: keySpacing) {
                        ForEach(1...9, id: \.self) { number in
                            NumberButton(value: String(number), height: buttonHeight, action: { appendCharacter(String(number)) })
                        }

                        if isDecimalAllowed {
                            NumberButton(value: ".", height: buttonHeight, action: { appendCharacter(".") })
                        } else {
                            Spacer().frame(height: buttonHeight) // Maintain layout
                        }
                        
                        NumberButton(value: "0", height: buttonHeight, action: { appendCharacter("0") })
                        
                        UtilityButton(systemImage: "delete.left.fill", height: buttonHeight, action: { text = String(text.dropLast()) })
                    }
                }
                .frame(maxWidth: .infinity)

                // Right Side: Action Buttons
                VStack(spacing: keySpacing) {
                    UtilityButton(systemImage: "plus.circle.fill", height: buttonHeight, action: onIncrement)
                    UtilityButton(systemImage: "minus.circle.fill", height: buttonHeight, action: onDecrement)
                    
                    Button(action: onNextAction) {
                        Text("Next")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: buttonHeight * 2 + keySpacing) // Span two rows height
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .frame(width: 80) // Fixed width for the action button column
            }
            .padding(keySpacing) // Padding around the Hstack
        }
        .frame(height: (buttonHeight * 4) + (keySpacing * 4) + 5) // Calculated height: 4 rows + spacing
        .frame(width: UIScreen.main.bounds.width * keyboardWidthFraction)
        .background(Color(UIColor.systemGray4).opacity(0.9)) // Slightly transparent dark gray background
        .cornerRadius(10)
    }

    private func appendCharacter(_ character: String) {
        if character == "." && (!isDecimalAllowed || text.contains(".")) {
            return 
        }
        text.append(character)
    }
}

// Reusable Button Styles
struct NumberButton: View {
    let value: String
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(value)
                .font(.title2)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Color.gray.opacity(0.35))
                .foregroundColor(Color(UIColor.label))
                .cornerRadius(8)
        }
    }
}

struct UtilityButton: View {
    let systemImage: String
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Color.gray.opacity(0.5))
                .foregroundColor(Color(UIColor.label))
                .cornerRadius(8)
        }
    }
}

struct CustomKeyboardView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Sample Text: 123.45").padding()
            Spacer()
            CustomKeyboardView(text: .constant("123.45"), 
                             isDecimalAllowed: true, 
                             onNextAction: { print("Next/Done Tapped") },
                             onIncrement: { print("Increment") },
                             onDecrement: { print("Decrement") })
        }
        .background(Color.gray) // Add a background to the preview container for contrast
    }
} 