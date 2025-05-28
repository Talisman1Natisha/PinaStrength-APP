import SwiftUI

struct KeyboardPlateView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top separator line
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
            
            // Grabber handle
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 8)
            
            // Keyboard content
            content
                .padding(.horizontal, 16)
            
            // Bottom padding for home indicator
            Color.clear
                .frame(height: 34) // Standard home indicator height
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground)) // Fully opaque, adapts to light/dark
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -4)
    }
}

// Alternative implementation using safeAreaInset modifier
struct BottomKeyboardContainer: ViewModifier {
    let isVisible: Bool
    let keyboard: () -> AnyView
    
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isVisible {
                    keyboard()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }
}

extension View {
    func bottomKeyboard<Keyboard: View>(isVisible: Bool, @ViewBuilder keyboard: @escaping () -> Keyboard) -> some View {
        self.modifier(BottomKeyboardContainer(isVisible: isVisible, keyboard: { AnyView(keyboard()) }))
    }
}

// Preview helper
struct KeyboardPlateView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Background content to test opacity
            List {
                ForEach(0..<20) { i in
                    Text("Row \(i)")
                        .padding()
                        .background(Color.blue.opacity(0.1))
                }
            }
            
            VStack {
                Spacer()
                
                KeyboardPlateView {
                    VStack {
                        Text("Sample Keyboard Content")
                            .padding()
                        HStack {
                            ForEach(0..<3) { _ in
                                Button("Key") {}
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 54)
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(10)
                            }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark) // Test in dark mode
    }
} 