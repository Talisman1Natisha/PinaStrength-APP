import Foundation
import Supabase

struct RoutineRequest: Codable {
    var goal: String
    var equipment: String? = nil
    var soreness: String? = nil
    var minutes: Int? = nil
}

struct AIRoutineResponse: Codable {
    let name: String
    let exercises: [AIExercise]
    
    struct AIExercise: Codable {
        let name: String
        let sets: Int
        let reps: Int
        let equipment: String?
    }
}

struct AICoachService {
    static let supabase = SupabaseManager.shared.client
    
    static func generateRoutine(_ reqPayload: RoutineRequest) async throws -> AIRoutineResponse {
        // Construct the function URL manually
        let baseURL = URL(string: "https://ohafcyimcowonnvocvwr.supabase.co")!
        let functionUrl = baseURL.appendingPathComponent("functions/v1/generateRoutine")
        
        var request = URLRequest(url: functionUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9oYWZjeWltY293b25udm9jdndyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgxOTcwNzYsImV4cCI6MjA2Mzc3MzA3Nn0.RgZ6Ai2_HrzA6pnoBkgmjkpZz4qU8r37od0YGalpK74", forHTTPHeaderField: "apikey")
        
        if let authToken = try? await supabase.auth.session.accessToken {
            request.addValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONEncoder().encode(reqPayload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(AIRoutineResponse.self, from: data)
    }
} 