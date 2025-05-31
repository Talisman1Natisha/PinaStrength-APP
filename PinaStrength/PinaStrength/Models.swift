import Foundation

// MARK: - User Model (Custom user profiles)

struct User: Identifiable, Codable, Hashable {
    let id: UUID
    let authUserId: UUID
    let email: String?
    let fullName: String?
    let avatarUrl: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authUserId = "auth_user_id"
        case email
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Exercise Model

struct Exercise: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let bodyPart: String?
    let category: String?
    let equipment: String?
    let instructions: String?
    let createdByUserId: UUID?
    let imageUrl: String?
    let isGlobal: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bodyPart = "body_part"
        case category
        case equipment
        case instructions
        case createdByUserId = "created_by_user_id"
        case imageUrl = "image_url"
        case isGlobal = "is_global"
    }
    
    // Computed property to check if user can edit this exercise
    var isCustomExercise: Bool {
        return !isGlobal && createdByUserId != nil
    }
}

// MARK: - Routine Model

struct RoutineListItem: Identifiable, Decodable, Hashable {
    let id: UUID
    let userId: UUID
    let name: String
    let description: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case description
        case updatedAt = "updated_at"
    }
}

// MARK: - Routine Detail Models

struct RoutineExerciseDetailItem: Identifiable, Hashable {
    let id: UUID // routine_exercises.id
    let routineId: UUID
    let exerciseId: UUID
    let exerciseName: String
    let userId: UUID
    let orderIndex: Int?
    var setTemplates: [RoutineSetTemplateInput] = []
}

struct RoutineSetTemplateInput: Identifiable, Equatable, Hashable, Decodable {
    let id: UUID
    let routineExerciseId: UUID
    let userId: UUID
    var setNumber: Int?      
    var targetReps: String?
    var targetWeight: String?
    var targetRestSeconds: String?

    enum CodingKeys: String, CodingKey { 
        case id 
        case routineExerciseId = "routine_exercise_id"
        case userId = "user_id"
        case setNumber = "set_number"
        case targetReps = "target_reps"
        case targetWeight = "target_weight"
        case targetRestSeconds = "target_rest_seconds"
    }
    
    init(id: UUID = UUID(), routineExerciseId: UUID, userId: UUID, setNumber: Int? = nil, targetReps: String? = nil, targetWeight: String? = nil, targetRestSeconds: String? = nil) {
        self.id = id
        self.routineExerciseId = routineExerciseId
        self.userId = userId
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetRestSeconds = targetRestSeconds
    }
}

// MARK: - Workout Models

struct WorkoutListItem: Identifiable, Decodable, Hashable {
    let id: UUID
    let userId: UUID
    let notes: String?
    let date: Date
    let endTime: Date?
    let routineId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case notes
        case date
        case endTime = "end_time"
        case routineId = "routine_id"
    }
    
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(date)
    }
    
    var displayName: String {
        notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? notes! : "Workout"
    }
}

// MARK: - Secure Data Transfer Objects

struct SecureWorkoutInsert: Encodable {
    let userId: UUID
    let notes: String
    let date: Date
    let routineId: UUID?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case notes
        case date
        case routineId = "routine_id"
    }
}

struct SecureWorkoutExerciseInsert: Encodable {
    let workoutId: UUID
    let exerciseId: UUID
    let userId: UUID
    let orderIndex: Int
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case exerciseId = "exercise_id"
        case userId = "user_id"
        case orderIndex = "order_index"
        case notes
    }
}

struct SecureWorkoutSetInsert: Encodable {
    let workoutExerciseId: UUID
    let userId: UUID
    let setNumber: Int
    let weight: Double?
    let reps: Int?
    let restSeconds: Int?
    
    enum CodingKeys: String, CodingKey {
        case workoutExerciseId = "workout_exercise_id"
        case userId = "user_id"
        case setNumber = "set_number"
        case weight
        case reps
        case restSeconds = "rest_seconds"
    }
}

struct SecureRoutineInsert: Encodable {
    let userId: UUID
    let name: String
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case description
    }
}

struct SecureRoutineExerciseInsert: Encodable {
    let routineId: UUID
    let exerciseId: UUID
    let userId: UUID
    let orderIndex: Int
    
    enum CodingKeys: String, CodingKey {
        case routineId = "routine_id"
        case exerciseId = "exercise_id"
        case userId = "user_id"
        case orderIndex = "order_index"
    }
}

struct SecureCustomExerciseInsert: Encodable {
    let name: String
    let bodyPart: String?
    let category: String?
    let equipment: String?
    let instructions: String?
    let createdByUserId: UUID
    let isGlobal: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case name
        case bodyPart = "body_part"
        case category
        case equipment
        case instructions
        case createdByUserId = "created_by_user_id"
        case isGlobal = "is_global"
    }
}

// MARK: - AI Coach Models

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

// Generic AI Message types
enum AIMessageType {
    case user(String)
    case assistantText(String)
    case routine(AIRoutineResponse)
    case recovery(RecoveryPlan)
    case error(String)
}

struct AIMessage: Identifiable {
    let id = UUID()
    let type: AIMessageType
    let timestamp = Date()
    
    var isUser: Bool {
        if case .user = type { return true }
        return false
    }
}

// Recovery Plan model
struct RecoveryPlan: Codable {
    let title: String
    let description: String
    let activities: [RecoveryActivity]
}

struct RecoveryActivity: Codable {
    let name: String
    let duration: String
    let instructions: String
    let type: RecoveryActivityType
}

enum RecoveryActivityType: String, Codable {
    case stretch
    case rest
    case mobility
    case foam_roll
}

// OpenAI Function Call Response
struct OpenAIFunctionCall: Codable {
    let name: String
    let arguments: String
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String?
    let function_call: OpenAIFunctionCall?
}

struct OpenAIResponse: Codable {
    let message: OpenAIMessage
}

// Conversation Message for API
struct ConversationMessage: Codable {
    let role: String
    let content: String
} 