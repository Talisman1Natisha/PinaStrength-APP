import Foundation
import SwiftUI
import Network

@MainActor
final class AICoachViewModel: ObservableObject {
    @Published var messages: [AIMessage] = []
    @Published var isThinking = false
    @Published var isOffline = false
    @Published var hasError = false
    @Published var errorMessage = ""
    
    private let service = AICoachService.shared
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    // Maintain full conversation for context
    private var conversation: [ConversationMessage] = []
    
    init() {
        // Add welcome message
        messages.append(AIMessage(type: .assistantText(
            "Hi! I'm your AI fitness coach. I can help you with:\n\n" +
            "• Creating personalized workouts\n" +
            "• Answering fitness questions\n" +
            "• Suggesting recovery routines if you're sore\n" +
            "• Providing stretching exercises\n\n" +
            "What would you like help with today?"
        )))
        
        // Start network monitoring
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOffline = path.status != .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    deinit {
        monitor.cancel()
    }
    
    func send(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        // Add user message
        let userMessage = AIMessage(type: .user(text))
        messages.append(userMessage)
        conversation.append(ConversationMessage(role: "user", content: text))
        
        // Check network status
        if isOffline {
            handleOfflineError()
            return
        }
        
        isThinking = true
        hasError = false
        
        do {
            let response = try await service.send(conversation: conversation)
            
            // Add AI response
            messages.append(response)
            
            // Add to conversation history for context
            switch response.type {
            case .assistantText(let text):
                conversation.append(ConversationMessage(role: "assistant", content: text))
            case .routine(let routine):
                conversation.append(ConversationMessage(role: "assistant", content: "I've created a \(routine.name) workout for you."))
            case .recovery(let plan):
                conversation.append(ConversationMessage(role: "assistant", content: "I've created a recovery plan: \(plan.title)"))
            default:
                break
            }
            
        } catch {
            handleError(error)
        }
        
        isThinking = false
    }
    
    private func handleError(_ error: Error) {
        hasError = true
        
        // Determine error type and provide appropriate fallback
        if let nsError = error as NSError? {
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                    handleOfflineError()
                    return
                case NSURLErrorTimedOut:
                    errorMessage = "The request timed out. Please try again."
                default:
                    errorMessage = "Network error. Please check your connection."
                }
            } else {
                errorMessage = nsError.localizedDescription
            }
        } else {
            errorMessage = "Something went wrong. Please try again."
        }
        
        // Add error message
        messages.append(AIMessage(type: .error(errorMessage)))
        
        // Add helpful fallback
        addFallbackMessage()
    }
    
    private func handleOfflineError() {
        hasError = true
        isOffline = true
        errorMessage = "You appear to be offline."
        
        messages.append(AIMessage(type: .error("No internet connection")))
        
        // Provide offline fallback suggestions
        messages.append(AIMessage(type: .assistantText(
            "I'm unable to connect right now, but here are some general workout ideas you can try:\n\n" +
            "**Full Body (No Equipment):**\n" +
            "• Push-ups: 3 sets × 10-15 reps\n" +
            "• Bodyweight Squats: 3 sets × 15-20 reps\n" +
            "• Lunges: 3 sets × 10 reps each leg\n" +
            "• Plank: 3 sets × 30-60 seconds\n" +
            "• Mountain Climbers: 3 sets × 20 reps\n\n" +
            "**Upper Body (Dumbbells):**\n" +
            "• Dumbbell Press: 3 sets × 8-12 reps\n" +
            "• Bent-Over Rows: 3 sets × 10-12 reps\n" +
            "• Shoulder Press: 3 sets × 10-12 reps\n" +
            "• Bicep Curls: 3 sets × 12-15 reps\n" +
            "• Tricep Extensions: 3 sets × 12-15 reps\n\n" +
            "Remember to warm up before exercising and cool down afterwards!"
        )))
    }
    
    private func addFallbackMessage() {
        // Add a helpful fallback based on the last user message
        if let lastUserMessage = messages.reversed().first(where: { $0.isUser }),
           case .user(let text) = lastUserMessage.type {
            
            let lowercased = text.lowercased()
            
            if lowercased.contains("hurt") || lowercased.contains("pain") || lowercased.contains("sore") {
                messages.append(AIMessage(type: .assistantText(
                    "While I couldn't process your request online, here's some general advice for soreness:\n\n" +
                    "• Rest the affected area for 24-48 hours\n" +
                    "• Apply ice for 15-20 minutes several times a day\n" +
                    "• Gentle stretching once acute pain subsides\n" +
                    "• Stay hydrated\n" +
                    "• Consider light movement like walking\n\n" +
                    "If pain persists or worsens, please consult a healthcare professional."
                )))
            } else if lowercased.contains("stretch") {
                messages.append(AIMessage(type: .assistantText(
                    "Here are some basic stretches you can try:\n\n" +
                    "• Hamstring Stretch: 30 seconds each leg\n" +
                    "• Quad Stretch: 30 seconds each leg\n" +
                    "• Shoulder Stretch: 30 seconds each arm\n" +
                    "• Chest Doorway Stretch: 30 seconds\n" +
                    "• Cat-Cow Stretch: 10 reps\n" +
                    "• Child's Pose: Hold for 1 minute\n\n" +
                    "Remember to breathe deeply and never force a stretch!"
                )))
            } else {
                messages.append(AIMessage(type: .assistantText(
                    "I'm having trouble connecting right now. You can still:\n\n" +
                    "• Start an empty workout and add exercises manually\n" +
                    "• Use one of your saved routines\n" +
                    "• Try again when you have a better connection\n\n" +
                    "Stay consistent with your fitness journey! 💪"
                )))
            }
        }
    }
    
    // Method to retry last message
    func retryLastMessage() async {
        guard let lastUserMessage = conversation.last(where: { $0.role == "user" }) else { return }
        
        // Remove error messages
        messages.removeAll { message in
            if case .error = message.type { return true }
            return false
        }
        
        // Resend
        await send(lastUserMessage.content)
    }
    
    // Clear conversation and start fresh
    func clearConversation() {
        messages = [AIMessage(type: .assistantText(
            "Hi! I'm your AI fitness coach. How can I help you today?"
        ))]
        conversation = []
        hasError = false
        errorMessage = ""
    }
}

// Extension to make AIRoutineResponse display nicely
extension AIRoutineResponse {
    var prettyDescription: String {
        var description = "**\(name)**\n\n"
        
        for (index, exercise) in exercises.enumerated() {
            description += "\(index + 1). \(exercise.name)\n"
            description += "   • \(exercise.sets) sets × \(exercise.reps) reps"
            if let equipment = exercise.equipment {
                description += " (\(equipment))"
            }
            description += "\n\n"
        }
        
        return description
    }
} 