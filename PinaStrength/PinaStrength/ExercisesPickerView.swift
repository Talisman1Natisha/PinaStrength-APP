import SwiftUI
import Supabase

struct ExercisesPickerView: View {
    @Environment(\.dismiss) var dismiss
    @State private var exercises: [Exercise] = []
    @State private var selectedExercises: Set<UUID> = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    let onSelection: ([Exercise]) -> Void
    
    private let supabase = SupabaseManager.shared
    
    var filteredExercises: [Exercise] {
        if searchText.isEmpty {
            return exercises
        } else {
            return exercises.filter { exercise in
                exercise.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading exercises...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Text("Error loading exercises")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await loadExercises() }
                        }
                    }
                    .padding()
                } else {
                    List {
                        ForEach(filteredExercises) { exercise in
                            ExercisePickerRow(
                                exercise: exercise,
                                isSelected: selectedExercises.contains(exercise.id),
                                onToggle: { toggleSelection(for: exercise) }
                            )
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search exercises")
                }
            }
            .navigationTitle("Select Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        let selected = exercises.filter { selectedExercises.contains($0.id) }
                        onSelection(selected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedExercises.isEmpty)
                }
            }
        }
        .task {
            await loadExercises()
        }
    }
    
    private func toggleSelection(for exercise: Exercise) {
        if selectedExercises.contains(exercise.id) {
            selectedExercises.remove(exercise.id)
        } else {
            selectedExercises.insert(exercise.id)
        }
    }
    
    private func loadExercises() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let userId = try? await supabase.client.auth.session.user.id else {
                errorMessage = "User not authenticated"
                isLoading = false
                return
            }
            
            let fetchedExercises: [Exercise] = try await supabase.client
                .from("exercises")
                .select("*")
                .or("is_global.eq.true,created_by_user_id.eq.\(userId)")
                .order("name", ascending: true)
                .execute()
                .value
            
            self.exercises = fetchedExercises
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
}

// MARK: - Exercise Picker Row
struct ExercisePickerRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        if let bodyPart = exercise.bodyPart {
                            Label(bodyPart, systemImage: "figure.strengthtraining.traditional")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let category = exercise.category {
                            Text(category)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview
struct ExercisesPickerView_Previews: PreviewProvider {
    static var previews: some View {
        ExercisesPickerView { selected in
            print("Selected \(selected.count) exercises")
        }
    }
} 