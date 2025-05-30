import Foundation

// MARK: - Exercise Model

struct Exercise: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let bodyPart: String?
    let category: String?
    let equipment: String?
    let instructions: String?
    let createdByUser_id: UUID?
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bodyPart = "body_part"
        case category
        case equipment
        case instructions
        case createdByUser_id = "created_by_user_id"
        case imageUrl = "image_url"
    }
}

// MARK: - Routine Model

struct RoutineListItem: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let updatedAt: Date // To show when it was last modified

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case updatedAt = "updated_at"
    }
}

// MARK: - Routine Detail Models

struct RoutineExerciseDetailItem: Identifiable, Hashable {
    let id: UUID // routine_exercises.id
    let exerciseId: UUID
    let exerciseName: String
    let orderIndex: Int?
    var setTemplates: [RoutineSetTemplateInput] = []
}

struct RoutineSetTemplateInput: Identifiable, Equatable, Hashable, Decodable {
    let id: UUID
    var setNumber: Int?      
    var targetReps: String?    // Changed to Optional
    var targetWeight: String?  // Changed to Optional
    var targetRestSeconds: String? // Changed to Optional

    enum CodingKeys: String, CodingKey { 
        case id 
        case setNumber = "set_number"
        case targetReps = "target_reps"
        case targetWeight = "target_weight"
        case targetRestSeconds = "target_rest_seconds"
    }
    
    init(id: UUID = UUID(), setNumber: Int? = nil, targetReps: String? = nil, targetWeight: String? = nil, targetRestSeconds: String? = nil) {
        self.id = id
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetRestSeconds = targetRestSeconds
    }
} 