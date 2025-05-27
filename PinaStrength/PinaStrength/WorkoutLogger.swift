import Foundation
import Supabase

// Helper struct to decode responses containing an ID
private struct IdResponse: Decodable {
    let id: UUID
}

// Payload structs for inserts
private struct WorkoutInsertPayload: Encodable {
    let user_id: UUID
    let notes: String // notes from function signature is String, not String?
}

private struct WorkoutExerciseInsertPayload: Encodable {
    let workout_id: UUID
    let exercise_id: UUID
    let order_index: Int
    let user_id: UUID
    // let notes: String? // workout_exercises table has an optional notes field
}

private struct WorkoutSetInsertPayload: Encodable {
    let workout_exercise_id: UUID
    let set_number: Int
    let weight: Double
    let reps: Int
    let user_id: UUID
    let rest_seconds: Int? // This is optional
}

struct WorkoutLogger {
    let client = SupabaseManager.shared.client

    func logWorkout(notes: String, exercises: [ExerciseInput]) async throws {
        let userId = try await client.auth.session.user.id

        let workoutToInsert = WorkoutInsertPayload(user_id: userId, notes: notes)
        let workoutInsertData: IdResponse = try await client.database
            .from("workouts")
            .insert(workoutToInsert) // Use Encodable struct
            .select("id")
            .single()
            .execute()
            .value

        let workoutId = workoutInsertData.id

        for (index, exercise) in exercises.enumerated() {
            guard let exerciseIdUUID = UUID(uuidString: exercise.exerciseId) else {
                throw NSError(domain: "Invalid exerciseId format", code: 400, userInfo: ["exerciseId": exercise.exerciseId])
            }
            
            let workoutExerciseToInsert = WorkoutExerciseInsertPayload(
                workout_id: workoutId,
                exercise_id: exerciseIdUUID,
                order_index: index,
                user_id: userId
            )
            let exerciseInsertData: IdResponse = try await client.database
                .from("workout_exercises")
                .insert(workoutExerciseToInsert) // Use Encodable struct
                .select("id")
                .single()
                .execute()
                .value

            let workoutExerciseId = exerciseInsertData.id

            for (setIndex, set) in exercise.sets.enumerated() {
                let setToInsert = WorkoutSetInsertPayload(
                    workout_exercise_id: workoutExerciseId,
                    set_number: setIndex + 1,
                    weight: set.weight,
                    reps: set.reps,
                    user_id: userId,
                    rest_seconds: set.restSeconds
                )
                try await client.database
                    .from("workout_sets")
                    .insert(setToInsert) // Use Encodable struct
                    .execute()
            }
        }

        print("✅ Workout logged successfully")
    }
}

// Supporting data types

struct ExerciseInput {
    let exerciseId: String // This string MUST be a valid UUID representation
    let sets: [WorkoutSet]
    // let notes: String? // Optional: if you want to add notes per exercise
}

struct WorkoutSet {
    let weight: Double // Changed from Int to Double
    let reps: Int
    let restSeconds: Int? // Added from schema
}

