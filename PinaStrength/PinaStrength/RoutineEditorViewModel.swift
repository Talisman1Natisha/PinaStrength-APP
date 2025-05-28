import SwiftUI
import Supabase
import Combine

// MARK: - Helper Models

struct SetTemplate: Identifiable {
    let id = UUID()
    var reps: String = ""
    var weight: String = ""
    var rest: String = ""
}

struct SelectedExercise: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var sets: [SetTemplate] = [SetTemplate()] // Start with one default set
}

// MARK: - View Model

@MainActor
final class RoutineEditorViewModel: ObservableObject {
    @Published var name = ""
    @Published var exercises: [SelectedExercise] = []
    @Published var showPicker = false
    @Published var isSaving = false
    @Published var error: String?
    
    private let supabase = SupabaseManager.shared
    
    // Prefilled data structure
    struct PrefilledData {
        let name: String
        let exercises: [SelectedExercise]
    }
    
    // Initialize with optional prefilled data
    init(prefilledData: PrefilledData? = nil) {
        if let data = prefilledData {
            self.name = data.name
            self.exercises = data.exercises
        }
    }
    
    // Computed property to get user ID
    private var userID: UUID? {
        get async {
            try? await supabase.client.auth.session.user.id
        }
    }
    
    // Add exercise from picker
    func addExercises(_ newExercises: [Exercise]) {
        for exercise in newExercises {
            // Don't add duplicates
            if !exercises.contains(where: { $0.exercise.id == exercise.id }) {
                exercises.append(SelectedExercise(exercise: exercise))
            }
        }
    }
    
    // Remove exercise
    func removeExercise(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
    }
    
    // Move exercises for reordering
    func moveExercise(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
    }
    
    // Add set to exercise
    func addSet(to exercise: SelectedExercise) {
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            exercises[index].sets.append(SetTemplate())
        }
    }
    
    // Remove set from exercise
    func removeSet(from exercise: SelectedExercise, at index: Int) {
        if let exerciseIndex = exercises.firstIndex(where: { $0.id == exercise.id }),
           exercises[exerciseIndex].sets.indices.contains(index) {
            exercises[exerciseIndex].sets.remove(at: index)
        }
    }
    
    // MARK: - Save Routine
    func save() async -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !exercises.isEmpty,
              let userID = await userID else {
            error = "Please provide a name and at least one exercise"
            return false
        }
        
        isSaving = true
        error = nil
        
        do {
            let routineId = UUID()
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            
            // 1. Insert routine
            struct RoutineInsert: Encodable {
                let id: UUID
                let user_id: UUID
                let name: String
            }
            
            let routinePayload = RoutineInsert(id: routineId, user_id: userID, name: trimmedName)
            
            try await supabase.client
                .from("routines")
                .insert(routinePayload)
                .execute()
            
            // 2. Insert routine_exercises and their sets
            for (idx, selectedExercise) in exercises.enumerated() {
                let routineExerciseId = UUID()
                
                struct RoutineExerciseInsert: Encodable {
                    let id: UUID
                    let routine_id: UUID
                    let exercise_id: UUID
                    let user_id: UUID
                    let order_index: Int
                }
                
                let routineExercisePayload = RoutineExerciseInsert(
                    id: routineExerciseId,
                    routine_id: routineId,
                    exercise_id: selectedExercise.exercise.id,
                    user_id: userID,
                    order_index: idx
                )
                
                try await supabase.client
                    .from("routine_exercises")
                    .insert(routineExercisePayload)
                    .execute()
                
                // 3. Insert sets for this exercise
                struct SetInsert: Encodable {
                    let id: UUID
                    let routine_exercise_id: UUID
                    let user_id: UUID
                    let set_number: Int
                    let target_reps: String?
                    let target_weight: String?
                    let target_rest_seconds: Int?
                }
                
                var setInserts: [SetInsert] = []
                for (setIdx, setTemplate) in selectedExercise.sets.enumerated() {
                    let setInsert = SetInsert(
                        id: UUID(),
                        routine_exercise_id: routineExerciseId,
                        user_id: userID,
                        set_number: setIdx + 1,
                        target_reps: setTemplate.reps.isEmpty ? nil : setTemplate.reps,
                        target_weight: setTemplate.weight.isEmpty ? nil : setTemplate.weight,
                        target_rest_seconds: setTemplate.rest.isEmpty ? nil : Int(setTemplate.rest)
                    )
                    setInserts.append(setInsert)
                }
                
                if !setInserts.isEmpty {
                    try await supabase.client
                        .from("routine_exercise_sets")
                        .insert(setInserts)
                        .execute()
                }
            }
            
            // Notify that routines have changed
            NotificationCenter.default.post(name: .routineChanged, object: nil)
            
            isSaving = false
            return true
            
        } catch {
            self.error = error.localizedDescription
            isSaving = false
            return false
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let routineChanged = Notification.Name("routineChanged")
} 