import Foundation

final class AICoachService {
    static let shared = AICoachService()
    private let maxRetries = 3
    
    private init() {}
    
    // Send conversation to AI and get response
    func send(conversation: [ConversationMessage]) async throws -> AIMessage {
        var lastError: Error?
        
        // Retry logic
        for attempt in 1...maxRetries {
            do {
                return try await performRequest(conversation: conversation)
            } catch {
                lastError = error
                print("AI Coach request attempt \(attempt) failed: \(error)")
                
                // Wait before retry (exponential backoff)
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
                }
            }
        }
        
        // All retries failed
        throw lastError ?? URLError(.unknown)
    }
    
    private func performRequest(conversation: [ConversationMessage]) async throws -> AIMessage {
        guard let url = URL(string: "https://ohafcyimcowonnvocvwr.supabase.co/functions/v1/generateRoutine") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9oYWZjeWltY293b25udm9jdndyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgxOTcwNzYsImV4cCI6MjA2Mzc3MzA3Nn0.RgZ6Ai2_HrzA6pnoBkgmjkpZz4qU8r37od0YGalpK74", forHTTPHeaderField: "apikey")
        
        let payload = ["conversation": conversation]
        request.httpBody = try JSONEncoder().encode(payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw NSError(domain: "AICoach", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error])
            }
            throw URLError(.badServerResponse)
        }
        
        // Parse OpenAI response
        let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let message = openAIResponse.message
        
        // Handle function calls
        if let functionCall = message.function_call {
            switch functionCall.name {
            case "createRoutine":
                let routine = try JSONDecoder().decode(AIRoutineResponse.self, from: Data(functionCall.arguments.utf8))
                return AIMessage(type: .routine(routine))
                
            case "suggestRecovery":
                let recovery = try JSONDecoder().decode(RecoveryPlan.self, from: Data(functionCall.arguments.utf8))
                return AIMessage(type: .recovery(recovery))
                
            case "normalReply":
                if let args = try? JSONDecoder().decode(NormalReplyArgs.self, from: Data(functionCall.arguments.utf8)) {
                    return AIMessage(type: .assistantText(args.message))
                }
                fallthrough
                
            default:
                // If we can't parse the function call, use the content
                return AIMessage(type: .assistantText(message.content ?? "I'm not sure how to respond to that."))
            }
        } else {
            // Regular text response
            return AIMessage(type: .assistantText(message.content ?? "I'm not sure how to respond to that."))
        }
    }
    
    // Check if we have network connectivity
    func isNetworkAvailable() -> Bool {
        // Simple check - try to create a connection
        guard let url = URL(string: "https://www.google.com") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3.0
        
        var available = false
        let semaphore = DispatchSemaphore(value: 0)
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                available = httpResponse.statusCode == 200
            }
            semaphore.signal()
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 3)
        return available
    }
}

// Helper structures
private struct ErrorResponse: Codable {
    let error: String
}

private struct NormalReplyArgs: Codable {
    let message: String
} 