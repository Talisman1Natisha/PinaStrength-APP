//
//  PinaStrengthApp.swift
//  PinaStrength
//
//  Created by user on 5/25/25.
//
import Foundation
import SwiftUI

@main
struct PinaStrengthApp: App {
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var workoutStarterService = WorkoutStarterService()

    init() {
        Task {
            do {
                // Test credentials
                let email = "itsnatanimabebe@gmail.com"
                let password = "PGAwinner"

                // Attempt to sign in first
                let session = try await SupabaseManager.shared.client.auth.signIn(
                    email: email,
                    password: password
                )
                print("✅ Logged in with email: \(session.user.email ?? "unknown")")
            } catch {
                print("❌ Login failed: \(error.localizedDescription)")
                print("Full error details: \(error)") // This might give more info
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(tabSelection)
                .environmentObject(workoutStarterService)
        }
    }
}

