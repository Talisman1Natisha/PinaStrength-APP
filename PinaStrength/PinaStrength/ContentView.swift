//
//  ContentView.swift
//  PinaStrength
//
//  Created by user on 5/25/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                LogWorkoutView()
            }
            .tabItem {
                Label("Log", systemImage: "plus.circle")
            }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock")
            }

            NavigationStack {
                RoutinesView()
            }
            .tabItem {
                Label("Routines", systemImage: "list.bullet")
            }

            NavigationStack {
                ExercisesView()
            }
            .tabItem {
                Label("Exercises", systemImage: "figure.strengthtraining.traditional")
            }

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
        }
    }
}
