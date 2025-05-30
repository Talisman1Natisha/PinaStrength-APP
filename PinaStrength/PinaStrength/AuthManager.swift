import SwiftUI
import Supabase
import Combine

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = true
    
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
                        self.isAuthenticated = true
                    case .signedOut:
                        self.isAuthenticated = false
                    case .initialSession:
                        // Don't auto-authenticate on initial session
                        self.isAuthenticated = false
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
                // Try to get the current session
                _ = try await client.auth.session
                // If we get here, there's a valid session, but we want to start signed out
                // So we'll sign out
                try? await client.auth.signOut()
                isAuthenticated = false
            } catch {
                // No session exists, which is what we want
                isAuthenticated = false
            }
            isLoading = false
        }
    }
    
    func signIn() {
        isAuthenticated = true
    }
    
    func signOut() async {
        do {
            try await client.auth.signOut()
            isAuthenticated = false
        } catch {
            print("Error signing out: \(error)")
        }
    }
} 