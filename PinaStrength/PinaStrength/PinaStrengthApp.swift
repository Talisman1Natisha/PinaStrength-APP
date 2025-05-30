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
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isLoading {
                // Show loading screen while checking auth state
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            } else if authManager.isAuthenticated {
                // Show main app when authenticated
                ContentView()
                    .environmentObject(tabSelection)
                    .environmentObject(workoutStarterService)
                    .environmentObject(authManager)
            } else {
                // Show auth screen when not authenticated
                AuthView(onAuthenticated: {
                    authManager.signIn()
                })
            }
        }
    }
}

