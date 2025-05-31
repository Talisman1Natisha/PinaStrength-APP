import Foundation
import Supabase

@MainActor
class SecureDataService: ObservableObject {
    private let client = SupabaseManager.shared.client
    
    // MARK: - Authentication Helper
    
    private func getCurrentUserId() async throws -> UUID {
        let session = try await client.auth.session
        return session.user.id
    }
    
    // MARK: - User Profile Operations
    
    func fetchUserProfile() async throws -> User {
        let userId = try await getCurrentUserId()
        
        let user: User = try await client.database
            .from("users")
            .select("*")
            .eq("auth_user_id", value: userId)
            .single()
            .execute()
            .value
        
        return user
    }
    
    func updateUserProfile(fullName: String?, avatarUrl: String?) async throws {
        let userId = try await getCurrentUserId()
        
        let updates: [String: AnyJSON] = [
            "full_name": AnyJSON.string(fullName ?? ""),
            "avatar_url": AnyJSON.string(avatarUrl ?? ""),
            "updated_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))
        ]
        
        try await client.database
            .from("users")
            .update(updates)
            .eq("auth_user_id", value: userId)
            .execute()
    }
    
    // MARK: - Exercise Operations
    
    func fetchExercises() async throws -> [Exercise] {
        let userId = try await getCurrentUserId()
        
        // Fetch both global exercises and user's custom exercises
        let exercises: [Exercise] = try await client.database
            .from("exercises")
            .select("*")
            .or("is_global.eq.true,and(created_by_user_id.eq.\(userId),is_global.eq.false)")
            .order("name", ascending: true)
            .execute()
            .value
        
        return exercises
    }
    
    func createCustomExercise(name: String, bodyPart: String?, category: String?, equipment: String?, instructions: String?) async throws -> Exercise {
        let userId = try await getCurrentUserId()
        
        let exerciseInsert = SecureCustomExerciseInsert(
            name: name,
            bodyPart: bodyPart,
            category: category,
            equipment: equipment,
            instructions: instructions,
            createdByUserId: userId
        )
        
        let newExercise: Exercise = try await client.database
            .from("exercises")
            .insert(exerciseInsert)
            .select("*")
            .single()
            .execute()
            .value
        
        return newExercise
    }
    
    func deleteCustomExercise(exerciseId: UUID) async throws {
        let userId = try await getCurrentUserId()
        
        // Delete the custom exercise - RLS policies ensure user can only delete their own custom exercises
        // The policy checks: created_by_user_id = auth.uid() AND is_global = FALSE
        // This prevents deletion of global exercises and exercises created by other users
        try await client.database
            .from("exercises")
            .delete()
            .eq("id", value: exerciseId)
            .eq("created_by_user_id", value: userId) // Extra security check
            .eq("is_global", value: false) // Ensure it's not a global exercise
            .execute()
    }
    
    // MARK: - Routine Operations
    
    func fetchRoutines() async throws -> [RoutineListItem] {
        let userId = try await getCurrentUserId()
        
        let routines: [RoutineListItem] = try await client.database
            .from("routines")
            .select("*")
            .eq("user_id", value: userId)
            .order("updated_at", ascending: false)
            .execute()
            .value
        
        return routines
    }
    
    func createRoutine(name: String, description: String?) async throws -> UUID {
        let userId = try await getCurrentUserId()
        
        let routineInsert = SecureRoutineInsert(
            userId: userId,
            name: name,
            description: description
        )
        
        struct RoutineResponse: Decodable {
            let id: UUID
        }
        
        let response: RoutineResponse = try await client.database
            .from("routines")
            .insert(routineInsert)
            .select("id")
            .single()
            .execute()
            .value
        
        return response.id
    }
    
    func deleteRoutine(routineId: UUID) async throws {
        let userId = try await getCurrentUserId()
        
        // Delete the routine - RLS policies ensure user can only delete their own routines
        // The database CASCADE DELETE will automatically remove:
        // - routine_exercises (and their routine_exercise_sets via CASCADE)
        // This is safe because of the foreign key constraints and RLS policies
        try await client.database
            .from("routines")
            .delete()
            .eq("id", value: routineId)
            .eq("user_id", value: userId) // Extra security check
            .execute()
    }
    
    func fetchRoutineDetails(routineId: UUID) async throws -> [RoutineExerciseDetailItem] {
        let userId = try await getCurrentUserId()
        
        // Fetch routine exercises with exercise details
        struct RoutineExerciseWithName: Decodable {
            let id: UUID
            let routine_id: UUID
            let exercise_id: UUID
            let user_id: UUID
            let order_index: Int?
            let exercises: ExerciseInfo
            
            struct ExerciseInfo: Decodable {
                let name: String
            }
        }
        
        let routineExercises: [RoutineExerciseWithName] = try await client.database
            .from("routine_exercises")
            .select("id, routine_id, exercise_id, user_id, order_index, exercises(name)")
            .eq("routine_id", value: routineId)
            .eq("user_id", value: userId)
            .order("order_index", ascending: true)
            .execute()
            .value
        
        var detailItems: [RoutineExerciseDetailItem] = []
        
        for routineExercise in routineExercises {
            // Fetch set templates for this routine exercise
            let setTemplates: [RoutineSetTemplateInput] = try await client.database
                .from("routine_exercise_sets")
                .select("*")
                .eq("routine_exercise_id", value: routineExercise.id)
                .eq("user_id", value: userId)
                .order("set_number", ascending: true)
                .execute()
                .value
            
            let detailItem = RoutineExerciseDetailItem(
                id: routineExercise.id,
                routineId: routineExercise.routine_id,
                exerciseId: routineExercise.exercise_id,
                exerciseName: routineExercise.exercises.name,
                userId: routineExercise.user_id,
                orderIndex: routineExercise.order_index,
                setTemplates: setTemplates
            )
            
            detailItems.append(detailItem)
        }
        
        return detailItems
    }
    
    // MARK: - Workout Operations
    
    func fetchWorkoutHistory() async throws -> [WorkoutListItem] {
        let userId = try await getCurrentUserId()
        
        let workouts: [WorkoutListItem] = try await client.database
            .from("workouts")
            .select("*")
            .eq("user_id", value: userId)
            .order("date", ascending: false)
            .execute()
            .value
        
        return workouts
    }
    
    func createWorkout(notes: String, date: Date = Date(), routineId: UUID? = nil) async throws -> UUID {
        let userId = try await getCurrentUserId()
        
        let workoutInsert = SecureWorkoutInsert(
            userId: userId,
            notes: notes,
            date: date,
            routineId: routineId
        )
        
        struct WorkoutResponse: Decodable {
            let id: UUID
        }
        
        let response: WorkoutResponse = try await client.database
            .from("workouts")
            .insert(workoutInsert)
            .select("id")
            .single()
            .execute()
            .value
        
        return response.id
    }
    
    func addExerciseToWorkout(workoutId: UUID, exerciseId: UUID, orderIndex: Int) async throws -> UUID {
        let userId = try await getCurrentUserId()
        
        let workoutExerciseInsert = SecureWorkoutExerciseInsert(
            workoutId: workoutId,
            exerciseId: exerciseId,
            userId: userId,
            orderIndex: orderIndex,
            notes: nil
        )
        
        struct WorkoutExerciseResponse: Decodable {
            let id: UUID
        }
        
        let response: WorkoutExerciseResponse = try await client.database
            .from("workout_exercises")
            .insert(workoutExerciseInsert)
            .select("id")
            .single()
            .execute()
            .value
        
        return response.id
    }
    
    func addSetToWorkout(workoutExerciseId: UUID, setNumber: Int, weight: Double?, reps: Int?, restSeconds: Int?) async throws {
        let userId = try await getCurrentUserId()
        
        let setInsert = SecureWorkoutSetInsert(
            workoutExerciseId: workoutExerciseId,
            userId: userId,
            setNumber: setNumber,
            weight: weight,
            reps: reps,
            restSeconds: restSeconds
        )
        
        try await client.database
            .from("workout_sets")
            .insert(setInsert)
            .execute()
    }
    
    func finishWorkout(workoutId: UUID, endTime: Date = Date()) async throws {
        let userId = try await getCurrentUserId()
        
        let updates: [String: AnyJSON] = [
            "end_time": AnyJSON.string(ISO8601DateFormatter().string(from: endTime)),
            "updated_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))
        ]
        
        try await client.database
            .from("workouts")
            .update(updates)
            .eq("id", value: workoutId)
            .eq("user_id", value: userId) // Extra security check
            .execute()
    }
    
    func deleteWorkout(workoutId: UUID) async throws {
        let userId = try await getCurrentUserId()
        
        // Delete the workout - RLS policies ensure user can only delete their own workouts
        // The database CASCADE DELETE will automatically remove:
        // - workout_exercises (and their workout_sets via CASCADE)
        // This is safe because of the foreign key constraints and RLS policies
        try await client.database
            .from("workouts")
            .delete()
            .eq("id", value: workoutId)
            .eq("user_id", value: userId) // Extra security check
            .execute()
    }
    
    // MARK: - Exercise History & Analytics
    
    func fetchExerciseHistory(exerciseId: UUID, limit: Int = 50) async throws -> [WorkoutSetHistoryItem] {
        let userId = try await getCurrentUserId()
        
        struct HistoryParams: Encodable {
            let p_user: UUID
            let p_exercise: UUID
            let p_limit: Int
        }
        
        struct HistoryResponse: Decodable {
            let workout_id: UUID
            let workout_date: Date
            let set_number: Int
            let weight: Double
            let reps: Int
        }
        
        let params = HistoryParams(
            p_user: userId,
            p_exercise: exerciseId,
            p_limit: limit
        )
        
        let response: [HistoryResponse] = try await client.rpc(
            "get_exercise_history",
            params: params
        )
        .execute()
        .value
        
        // Convert to WorkoutSetHistoryItem format
        let historyItems = response.map { item in
            WorkoutSetHistoryItem(
                id: UUID(),
                workoutId: item.workout_id,
                workoutDate: item.workout_date,
                workoutNotes: nil,
                setNumber: item.set_number,
                weight: item.weight,
                reps: item.reps,
                restSeconds: nil
            )
        }
        
        return historyItems
    }
    
    func fetchPreviousPerformance(exerciseId: UUID) async throws -> PreviousSetData? {
        let userId = try await getCurrentUserId()
        
        struct RpcParams: Encodable {
            let p_exercise_id: UUID
            let p_user_id: UUID
        }
        
        let params = RpcParams(p_exercise_id: exerciseId, p_user_id: userId)
        
        let result: [PreviousSetData] = try await client.rpc(
            "get_previous_performance",
            params: params
        )
        .execute()
        .value
        
        return result.first
    }
    
    // MARK: - Data Validation
    
    private func validateUserOwnership(userId: UUID) async throws {
        let currentUserId = try await getCurrentUserId()
        guard currentUserId == userId else {
            throw NSError(domain: "SecureDataService", code: 403, userInfo: [
                NSLocalizedDescriptionKey: "Access denied: User ID mismatch"
            ])
        }
    }
} 