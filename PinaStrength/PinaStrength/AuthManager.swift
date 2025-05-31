import SwiftUI
import Supabase
import Combine

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = true
    @Published var currentUser: User?
    @Published var authError: String?
    
    private let client = SupabaseManager.shared.client
    private var authStateChangesTask: Task<Void, Never>?
    
    init() {
        // Check initial auth state
        checkAuthState()
        
        // Listen for auth state changes
        authStateChangesTask = Task {
            for await state in client.auth.authStateChanges {
                await MainActor.run {
                    switch state.event {
                    case .signedIn:
                        if let session = state.session {
                            Task {
                                await self.handleSignIn(session: session)
                            }
                        }
                    case .signedOut:
                        self.handleSignOut()
                    case .initialSession:
                        if let session = state.session {
                            Task {
                                await self.handleSignIn(session: session)
                            }
                        } else {
                            self.isAuthenticated = false
                            self.isLoading = false
                        }
                    default:
                        break
                    }
                }
            }
        }
    }
    
    deinit {
        authStateChangesTask?.cancel()
    }
    
    func checkAuthState() {
        Task {
            do {
                let session = try await client.auth.session
                await handleSignIn(session: session)
            } catch {
                // No session exists
                await MainActor.run {
                    self.isAuthenticated = false
                    self.isLoading = false
                }
            }
        }
    }
    
    private func handleSignIn(session: Session) async {
        do {
            // Fetch or create user profile
            let userProfile = try await fetchOrCreateUserProfile(for: session.user)
            
            await MainActor.run {
                self.currentUser = userProfile
                self.isAuthenticated = true
                self.isLoading = false
                self.authError = nil
            }
        } catch {
            await MainActor.run {
                self.authError = "Failed to load user profile: \(error.localizedDescription)"
                self.isAuthenticated = false
                self.isLoading = false
            }
        }
    }
    
    private func handleSignOut() {
        currentUser = nil
        isAuthenticated = false
        authError = nil
    }
    
    private func fetchOrCreateUserProfile(for authUser: Supabase.User) async throws -> User {
        // First, try to fetch existing user profile
        do {
            let existingUser: User = try await client.database
                .from("users")
                .select("*")
                .eq("auth_user_id", value: authUser.id)
                .single()
                .execute()
                .value
            
            return existingUser
        } catch {
            // User profile doesn't exist, create it
            let newUser = User(
                id: UUID(),
                authUserId: authUser.id,
                email: authUser.email,
                fullName: authUser.userMetadata["full_name"] as? String,
                avatarUrl: authUser.userMetadata["avatar_url"] as? String,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            try await client.database
                .from("users")
                .insert(newUser)
                .execute()
            
            return newUser
        }
    }
    
    func signUp(email: String, password: String, fullName: String? = nil) async throws {
        authError = nil
        
        var metadata: [String: AnyJSON] = [:]
        if let fullName = fullName {
            metadata["full_name"] = AnyJSON.string(fullName)
        }
        
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: metadata
        )
        
        // The auth state change listener will handle the rest
    }
    
    func signIn(email: String, password: String) async throws {
        authError = nil
        
        let response = try await client.auth.signIn(
            email: email,
            password: password
        )
        
        // The auth state change listener will handle the rest
    }
    
    func signOut() async {
        do {
            try await client.auth.signOut()
            // The auth state change listener will handle the rest
        } catch {
            await MainActor.run {
                self.authError = "Error signing out: \(error.localizedDescription)"
            }
        }
    }
    
    func updateProfile(fullName: String?, avatarUrl: String?) async throws {
        guard let currentUser = currentUser else {
            throw NSError(domain: "AuthManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "No current user"])
        }
        
        // Update in Supabase auth metadata
        var metadata: [String: AnyJSON] = [:]
        if let fullName = fullName {
            metadata["full_name"] = AnyJSON.string(fullName)
        }
        if let avatarUrl = avatarUrl {
            metadata["avatar_url"] = AnyJSON.string(avatarUrl)
        }
        
        try await client.auth.update(user: UserAttributes(data: metadata))
        
        // Update in our users table
        let updatedUser = User(
            id: currentUser.id,
            authUserId: currentUser.authUserId,
            email: currentUser.email,
            fullName: fullName ?? currentUser.fullName,
            avatarUrl: avatarUrl ?? currentUser.avatarUrl,
            createdAt: currentUser.createdAt,
            updatedAt: Date()
        )
        
        try await client.database
            .from("users")
            .update(updatedUser)
            .eq("auth_user_id", value: currentUser.authUserId)
            .execute()
        
        await MainActor.run {
            self.currentUser = updatedUser
        }
    }
} 