import Foundation
import SwiftUI

// Chat message types
enum ChatMessage: Identifiable {
    case user(String)
    case ai(String)
    case error(String)
    case routine(AIRoutineResponse)
    
    var id: UUID { UUID() }
    
    var isUser: Bool {
        if case .user = self { return true }
        return false
    }
}

@MainActor
final class AICoachViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    
    init() {
        // Add welcome message
        messages.append(.ai("Hi! I'm your AI workout coach. Tell me about your fitness goals, available equipment, and how much time you have, and I'll create a personalized workout for you!"))
    }
    
    func send(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        messages.append(.user(text))
        isThinking = true
        
        do {
            // Parse user input for structured data
            let req = parseUserInput(text)
            let routine = try await AICoachService.generateRoutine(req)
            
            // Add routine as a special message type
            messages.append(.routine(routine))
            
            // Add follow-up message
            messages.append(.ai("I've created a \(routine.name) workout for you! This routine includes \(routine.exercises.count) exercises. Would you like to start this workout now or save it as a routine?"))
            
        } catch {
            messages.append(.error("I couldn't generate a workout plan. Please try again or check your internet connection."))
            print("AI Coach Error: \(error)")
        }
        
        isThinking = false
    }
    
    // Add method to append messages from external sources
    func addMessage(_ message: ChatMessage) async {
        await MainActor.run {
            messages.append(message)
        }
    }
    
    private func parseUserInput(_ text: String) -> RoutineRequest {
        // More sophisticated parsing
        var equipment: String? = nil
        var minutes: Int? = nil
        var soreness: String? = nil
        
        let lowercased = text.lowercased()
        
        // Detect equipment mentions with better matching
        if lowercased.contains("dumbbell") || lowercased.contains("dumbell") {
            equipment = "Dumbbell"
        } else if lowercased.contains("barbell") {
            equipment = "Barbell"
        } else if lowercased.contains("bodyweight") || lowercased.contains("no equipment") || lowercased.contains("body weight") {
            equipment = "None"
        } else if lowercased.contains("gym") || lowercased.contains("full gym") {
            equipment = "Full Gym"
        } else if lowercased.contains("cable") {
            equipment = "Cable"
        } else if lowercased.contains("machine") {
            equipment = "Machine"
        } else if lowercased.contains("kettlebell") {
            equipment = "Kettlebell"
        } else if lowercased.contains("band") || lowercased.contains("resistance") {
            equipment = "Bands"
        }
        
        // Detect time mentions - improved regex
        let timePatterns = [
            #"(\d+)\s*(?:min|minute|minutes)"#,
            #"(\d+)\s*(?:hr|hour|hours)"#,
            #"(?:for|about|around)\s*(\d+)"#
        ]
        
        for pattern in timePatterns {
            if let range = lowercased.range(of: pattern, options: .regularExpression) {
                let match = String(lowercased[range])
                if let number = Int(match.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                    if match.contains("hr") || match.contains("hour") {
                        minutes = number * 60
                    } else {
                        minutes = number
                    }
                    break
                }
            }
        }
        
        // Detect soreness - more comprehensive
        if lowercased.contains("sore") {
            var soreAreas: [String] = []
            
            // Check for specific body parts
            let bodyParts = [
                "leg": ["leg", "quad", "hamstring", "glute", "calf", "thigh"],
                "chest": ["chest", "pec"],
                "back": ["back", "lat", "trap"],
                "shoulder": ["shoulder", "delt"],
                "arm": ["arm", "bicep", "tricep"],
                "core": ["core", "ab", "stomach"]
            ]
            
            for (area, keywords) in bodyParts {
                for keyword in keywords {
                    if lowercased.contains(keyword) {
                        soreAreas.append(area)
                        break
                    }
                }
            }
            
            if soreAreas.isEmpty {
                soreness = lowercased.contains("very") || lowercased.contains("really") ? "High" : "Moderate"
            } else {
                soreness = "Sore in: \(soreAreas.joined(separator: ", "))"
            }
        }
        
        return RoutineRequest(
            goal: text,
            equipment: equipment,
            soreness: soreness,
            minutes: minutes
        )
    }
    
    func startWorkoutFromRoutine(_ routine: AIRoutineResponse) async {
        // Convert AI routine to actual workout
        messages.append(.ai("Great! I'm preparing your workout. One moment..."))
        
        // We'll need to match exercise names to database exercises
        // For now, just show a message
        messages.append(.ai("Ready to start! Head to the Log tab and tap 'Start an Empty Workout'. Then add these exercises:\n\n" + routine.prettyDescription))
    }
    
    func saveAsRoutine(_ routine: AIRoutineResponse) async {
        messages.append(.ai("Saving this routine for future use..."))
        
        // TODO: Implement actual save functionality
        // This will require matching exercises to database and creating routine records
        
        messages.append(.ai("I've noted this routine for you. In the next update, you'll be able to save it directly to your routines!"))
    }
    
    // Add method to fetch available exercises
    func fetchAvailableExercises() async -> [Exercise] {
        do {
            let exercises: [Exercise] = try await SupabaseManager.shared.client
                .from("exercises")
                .select()
                .execute()
                .value
            return exercises
        } catch {
            print("Error fetching exercises: \(error)")
            return []
        }
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