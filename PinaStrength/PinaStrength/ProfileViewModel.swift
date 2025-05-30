import SwiftUI
import Supabase

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var user: SupaUser?
    @Published var workoutCount = 0
    @Published var routineCount = 0
    @Published var loading = true
    
    private let client = SupabaseManager.shared.client
    
    init() {
        Task { await refresh() }
    }
    
    func refresh() async {
        loading = true
        
        do {
            // 1. Fetch user row
            let session = try await client.auth.session
            let authUser = session.user
            let meta = authUser.userMetadata
            
            self.user = SupaUser(
                id: authUser.id,
                email: authUser.email ?? "",
                name: meta["full_name"] as? String ?? "",
                avatarURL: meta["avatar_url"] as? String
            )
            
            // 2. Fetch counts
            // Workouts count
            let workoutsResponse = try await client
                .from("workouts")
                .select("id", head: false, count: .exact)
                .eq("user_id", value: authUser.id)
                .execute()
            
            workoutCount = workoutsResponse.count ?? 0
            
            // Routines count
            let routinesResponse = try await client
                .from("routines")
                .select("id", head: false, count: .exact)
                .eq("user_id", value: authUser.id)
                .execute()
            
            routineCount = routinesResponse.count ?? 0
            
        } catch {
            print("Error refreshing profile: \(error)")
        }
        
        loading = false
    }
    
    func update(name: String?, avatarURL: String?) async throws {
        do {
            var userData: [String: AnyJSON] = [:]
            
            if let name = name {
                userData["full_name"] = .string(name)
            }
            
            if let avatarURL = avatarURL {
                userData["avatar_url"] = .string(avatarURL)
            }
            
            let attributes = UserAttributes(data: userData)
            _ = try await client.auth.update(user: attributes)
            await refresh()
        } catch {
            print("Error updating profile: \(error)")
            throw error
        }
    }
    
    func signOut() async throws {
        try await client.auth.signOut()
    }
}

struct SupaUser: Identifiable {
    let id: UUID
    var email: String
    var name: String
    var avatarURL: String?
} 