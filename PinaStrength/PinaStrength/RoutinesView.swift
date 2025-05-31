//
//  RoutinesView.swift
//  PinaStrength
//
//  Created by user on 5/25/25.
//

import Foundation
import SwiftUI
import Supabase

// MARK: - Routines View

struct RoutinesView: View {
    @State private var routines: [RoutineListItem] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var showingCreateRoutineView = false
    @State private var showDeleteConfirmation = false
    @State private var routineToDelete: RoutineListItem?
    @State private var isDeleting = false
    // No longer need selectedRoutine if using NavigationLink directly for detail

    private let client = SupabaseManager.shared.client
    private let secureDataService = SecureDataService()

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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                HStack {
                                    Text("Last updated: \(routine.updatedAt, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    Spacer()
                                    
                                    if let description = routine.description, !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                routineToDelete = routine
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete Routine", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteRoutines)
                }
                .refreshable {
                    await fetchRoutines()
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
        .alert("Delete Routine", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                routineToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let routine = routineToDelete {
                    Task {
                        await confirmDeleteRoutine(routine)
                    }
                }
            }
        } message: {
            if let routine = routineToDelete {
                Text("Are you sure you want to delete '\(routine.name)'? This will also delete all exercises and sets in this routine. This action cannot be undone.")
            }
        }
        .overlay {
            if isDeleting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Deleting routine...")
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
            }
        }
    }

    private func deleteRoutines(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        routineToDelete = routines[index]
        showDeleteConfirmation = true
    }
    
    private func confirmDeleteRoutine(_ routine: RoutineListItem) async {
        isDeleting = true
        
        do {
            try await secureDataService.deleteRoutine(routineId: routine.id)
            
            // Remove from local array
            DispatchQueue.main.async {
                if let index = self.routines.firstIndex(where: { $0.id == routine.id }) {
                    self.routines.remove(at: index)
                }
                self.routineToDelete = nil
                self.isDeleting = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to delete routine: \(error.localizedDescription)"
                self.routineToDelete = nil
                self.isDeleting = false
            }
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
                .select("*")
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
