//
//  RoutinesView.swift
//  PinaStrength
//
//  Created by user on 5/25/25.
//

import Foundation
import SwiftUI
import Supabase

// MARK: - Data Model for Routine List Item
struct RoutineListItem: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let updatedAt: Date // To show when it was last modified
    // We can add a count of exercises or a brief description later if needed

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case updatedAt = "updated_at"
    }
}

// MARK: - Routines View

struct RoutinesView: View {
    @State private var routines: [RoutineListItem] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var showingCreateRoutineView = false
    // No longer need selectedRoutine if using NavigationLink directly for detail

    private let client = SupabaseManager.shared.client

    var body: some View {
        // NavigationStack should be provided by ContentView
        VStack {
            if isLoading {
                Spacer()
                ProgressView("Loading routines...")
                Spacer()
            } else if let errorMessage {
                Spacer()
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red).multilineTextAlignment(.center).padding()
                Spacer()
            } else if routines.isEmpty {
                Spacer()
                Text("No Routines Yet")
                    .font(.headline)
                Text("Tap the '+' button to create your first workout template.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
                Spacer()
            } else {
                List {
                    ForEach(routines) { routine in
                        NavigationLink(destination: RoutineDetailView(routine: routine)) {
                            VStack(alignment: .leading) {
                                Text(routine.name).font(.headline)
                                Text("Last updated: \(routine.updatedAt, style: .relative) ago")
                                    .font(.caption).foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Routines")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCreateRoutineView = true
                } label: {
                    Label("Create Routine", systemImage: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $showingCreateRoutineView) {
            // When CreateEditRoutineView is saved, we should refresh the routines list
            CreateEditRoutineView(onSave: {
                showingCreateRoutineView = false
                // Add a slight delay to give DB time to process, or re-fetch on a specific signal
                Task {
                    await Task.sleep(500_000_000) // 0.5 seconds
                    await fetchRoutines()
                }
            })
        }
        .task {
            await fetchRoutines()
        }
    }

    func fetchRoutines() async {
        isLoading = true
        errorMessage = nil
        guard let userId = try? await client.auth.session.user.id else {
            errorMessage = "User not authenticated."
            isLoading = false
            return
        }

        do {
            let fetchedRoutines: [RoutineListItem] = try await client.database
                .from("routines")
                .select("id, name, updated_at")
                .eq("user_id", value: userId)
                .order("updated_at", ascending: false)
                .execute()
                .value
            
            DispatchQueue.main.async {
                self.routines = fetchedRoutines
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                print("Error fetching routines: \(error)")
            }
        }
    }
}

// MARK: - Preview
struct RoutinesView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { // RoutinesView will likely be in a NavigationView from ContentView
            RoutinesView()
        }
    }
}
