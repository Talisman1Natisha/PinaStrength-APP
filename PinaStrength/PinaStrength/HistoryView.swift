//
//  HistoryView.swift
//  PinaStrength
//
//  Created by user on 5/25/25.
//

import Foundation
import SwiftUI
import Supabase

// MARK: - Data Model for History List Item

struct WorkoutLogRow: Identifiable, Decodable, Hashable {
    let id: UUID
    let notes: String? // Workout name/notes
    let date: Date // Start time
    let endTime: Date? // End time, optional

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(date)
    }
    
    var displayName: String {
        notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? notes! : "Workout"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case notes
        case date
        case endTime = "end_time" // Ensure this matches your DB column name
    }
}

// MARK: - History View

struct HistoryView: View {
    @State private var pastWorkouts: [WorkoutLogRow] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    private let client = SupabaseManager.shared.client

    // Formatter for duration
    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated // e.g., "1h 15m" or "45m"
        return formatter.string(from: interval) ?? ""
    }

    var body: some View {
        // Assuming ContentView provides the outer NavigationStack
        VStack {
            if isLoading {
                Spacer()
                ProgressView("Loading workout history...")
                Spacer()
            } else if let errorMessage {
                Spacer()
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else if pastWorkouts.isEmpty {
                Spacer()
                Text("No Workouts Yet")
                    .font(.headline)
                Text("Complete a workout to see it listed here.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
            } else {
                List {
                    ForEach(pastWorkouts) { workoutLog in
                        NavigationLink(destination: PastWorkoutDetailView(workoutLogId: workoutLog.id)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(workoutLog.displayName)
                                        .font(.headline)
                                    Text(workoutLog.date, style: .date)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if let duration = workoutLog.duration {
                                    Text(formatDuration(duration))
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .task {
            await fetchPastWorkouts()
        }
    }

    func fetchPastWorkouts() async {
        isLoading = true
        errorMessage = nil
        
        guard let userId = try? await client.auth.session.user.id else {
            errorMessage = "User not authenticated."
            isLoading = false
            return
        }

        do {
            let fetchedData: [WorkoutLogRow] = try await client.database
                .from("workouts")
                .select("id, notes, date, end_time") // Select specific columns
                .eq("user_id", value: userId)
                .order("date", ascending: false) // Most recent first
                .execute()
                .value
            
            DispatchQueue.main.async {
                self.pastWorkouts = fetchedData
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                print("Error fetching past workouts: \(error)")
            }
        }
    }
}

// MARK: - Preview

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { // Add NavigationView for preview context if needed
            HistoryView()
        }
    }
}
