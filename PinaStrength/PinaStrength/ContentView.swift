//
//  ContentView.swift
//  PinaStrength
//
//  Created by user on 5/25/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var tabSelection: TabSelection // Get from environment

    var body: some View {
        TabView(selection: $tabSelection.selectedTab) { // Bind to the EnvironmentObject
            NavigationStack {
                LogWorkoutView()
            }
            .tabItem { Label("Log", systemImage: "plus.circle") }
            .tag(TabIdentifier.log) // Tag for programmatic selection

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label("History", systemImage: "clock") }
            .tag(TabIdentifier.history)

            NavigationStack {
                RoutinesView()
            }
            .tabItem { Label("Routines", systemImage: "list.bullet") }
            .tag(TabIdentifier.routines)

            NavigationStack {
                ExercisesView()
            }
            .tabItem { Label("Exercises", systemImage: "figure.strengthtraining.traditional") }
            .tag(TabIdentifier.exercises)

            NavigationStack {
                ProfileView()
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            .tag(TabIdentifier.profile)
        }
    }
}

// // You might need a simple ProfileView struct for this to compile // <-- Commenting out/Removing this
// struct ProfileView: View {                                       // <-- Commenting out/Removing this
//     var body: some View {                                        // <-- Commenting out/Removing this
//         Text("Profile View")                                     // <-- Commenting out/Removing this
//         .navigationTitle("Profile")                             // <-- Commenting out/Removing this
//     }
// }
