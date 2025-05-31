import SwiftUI
import Supabase
import Combine

// MARK: - Models

// Extended version of RoutineListItem with additional fields for the grid view
struct RoutineGridItem: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let updatedAt: Date
    let user_id: UUID
    let created_at: Date
    var exercises: [RoutineExercise]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case updatedAt = "updated_at"
        case user_id
        case created_at
        case exercises
    }
    
    // Convert to RoutineListItem for compatibility
    var asRoutineListItem: RoutineListItem {
        RoutineListItem(
            id: id, 
            userId: user_id, 
            name: name, 
            description: nil, 
            updatedAt: updatedAt
        )
    }
}

struct RoutineExercise: Identifiable, Decodable, Hashable {
    let id: UUID
    let routine_id: UUID
    let exercise_id: UUID
    let orderIndex: Int?
    var exercise: Exercise?
    
    enum CodingKeys: String, CodingKey {
        case id
        case routine_id
        case exercise_id
        case orderIndex = "order_index"
        case exercise
    }
}

// MARK: - View Model

@MainActor
class RoutineGridViewModel: ObservableObject {
    @Published var routines: [RoutineGridItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    private let supabaseManager: SupabaseManager
    private var cancellables = Set<AnyCancellable>()
    
    init(supabaseManager: SupabaseManager = SupabaseManager.shared) {
        self.supabaseManager = supabaseManager
        Task {
            await loadRoutines()
        }
    }
    
    func loadRoutines() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let userId = try? await supabaseManager.client.auth.session.user.id else {
                errorMessage = "User not authenticated"
                isLoading = false
                return
            }
            
            // Fetch the 10 most recently used routines
            let fetchedRoutines: [RoutineGridItem] = try await supabaseManager.client
                .from("routines")
                .select("""
                    *,
                    exercises:routine_exercises(
                        *,
                        exercise:exercises(*)
                    )
                """)
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .limit(10)
                .execute()
                .value
            
            self.routines = fetchedRoutines
            
        } catch {
            print("Error loading routines: \(error)")
            errorMessage = "Failed to load routines"
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadRoutines()
    }
    
    func deleteRoutine(_ routineId: UUID) async {
        do {
            guard let userId = try? await supabaseManager.client.auth.session.user.id else {
                errorMessage = "User not authenticated"
                return
            }
            
            // Delete the routine (cascade will handle related records)
            try await supabaseManager.client
                .from("routines")
                .delete()
                .eq("id", value: routineId)
                .eq("user_id", value: userId) // Extra safety check
                .execute()
            
            // Remove from local array
            routines.removeAll { $0.id == routineId }
            
            // Post notification
            NotificationCenter.default.post(name: .routineChanged, object: nil)
            
        } catch {
            print("Error deleting routine: \(error)")
            errorMessage = "Failed to delete routine"
        }
    }
} 