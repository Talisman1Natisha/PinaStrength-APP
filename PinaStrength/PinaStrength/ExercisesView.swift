import SwiftUI
import Supabase

// MARK: - Data Model

struct Exercise: Identifiable, Decodable, Hashable {
    let id: UUID
    let name: String
    let bodyPart: String?
    let category: String?
    let equipment: String?
    let instructions: String?
    let createdByUser_id: UUID? // Field for user-created exercises

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bodyPart = "body_part"
        case category
        case equipment
        case instructions
        case createdByUser_id = "created_by_user_id"
    }
}

// MARK: - Main Exercises View (Adapted for Selection)

struct ExercisesView: View {
    @Environment(\.dismiss) var dismiss // For dismissing the sheet/modal
    var onSave: (([Exercise]) -> Void)? = nil // Optional: For returning selected exercises
    var isSelectionMode: Bool { onSave != nil } // Determined by presence of onSave closure

    @State private var exercises: [Exercise] = []
    @State private var searchText: String = ""
    @State private var selectedBodyPart: String? = nil
    @State private var selectedCategory: String? = nil
    @State private var showCreateModal: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    @State private var currentlySelectedExercises: [Exercise] = [] // For multi-select in selection mode
    @State private var selectedExerciseForDetail: Exercise? = nil // Re-add state for presenting ExerciseDetailView

    private let client = SupabaseManager.shared.client
    private let bodyParts = ["All"] + ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body", "Cardio", "Olympic", "Other"]
    private let categories = ["All"] + ["Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Bands"]

    var filteredExercises: [Exercise] {
        exercises.filter {
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)) &&
            (selectedBodyPart == nil || selectedBodyPart == "All" || $0.bodyPart == selectedBodyPart) &&
            (selectedCategory == nil || selectedCategory == "All" || $0.category == selectedCategory)
        }.sorted(by: { $0.name < $1.name }) // Keep it sorted by name
    }

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Picker("Body Part", selection: $selectedBodyPart) {
                        ForEach(bodyParts, id: \.self) { part in Text(part).tag(part as String?) }
                    }.pickerStyle(.menu)
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { cat in Text(cat).tag(cat as String?) }
                    }.pickerStyle(.menu)
                }.padding(.horizontal)

                if isLoading {
                    ProgressView("Loading exercises...").padding()
                } else if let errorMessage {
                    Text("Error: \(errorMessage)").foregroundColor(.red).padding()
                }

                List(filteredExercises) { exercise in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(exercise.name).font(.headline)
                            HStack {
                                if let bodyPart = exercise.bodyPart, !bodyPart.isEmpty {
                                    Text(bodyPart).font(.caption).foregroundColor(.gray)
                                }
                                if let category = exercise.category, !category.isEmpty {
                                    Text(category).font(.caption).foregroundColor(.gray)
                                }
                            }.opacity(0.8)
                        }
                        Spacer()
                        if isSelectionMode {
                            if currentlySelectedExercises.contains(where: { $0.id == exercise.id }) {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                            } else {
                                Image(systemName: "circle").foregroundColor(.gray)
                            }
                        }
                    }
                    .contentShape(Rectangle()) // Make the whole Hstack area tappable
                    .onTapGesture {
                        if isSelectionMode {
                            toggleSelection(for: exercise)
                        } else {
                            // Restore presenting detail view
                            selectedExerciseForDetail = exercise
                        }
                    }
                }
            }
            .navigationTitle(isSelectionMode ? "Select Exercises" : "Exercises")
            .searchable(text: $searchText, prompt: "Search exercises")
            .toolbar {
                // Toolbar items depend on whether it's in selection mode
                if isSelectionMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(currentlySelectedExercises.isEmpty ? "Add" : "Add (\(currentlySelectedExercises.count))") {
                            onSave?(currentlySelectedExercises)
                            dismiss()
                        }
                        .disabled(currentlySelectedExercises.isEmpty && onSave != nil) // Disable if no selection and it's selection mode
                    }
                } else {
                    // Original toolbar for browsing mode
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showCreateModal = true
                        } label: {
                            Label("Add New Exercise", systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateModal) { // For creating a new exercise
                CreateExerciseView {
                    newExercise in
                    exercises.append(newExercise)
                    if isSelectionMode { // If in selection mode, also select the newly created one
                        if !currentlySelectedExercises.contains(where: { $0.id == newExercise.id }) {
                            currentlySelectedExercises.append(newExercise)
                        }
                    }
                    showCreateModal = false
                }
            }
            // Re-add .fullScreenCover for ExerciseDetailView
            .fullScreenCover(item: $selectedExerciseForDetail) { exerciseToShow in
                ExerciseDetailView(exercise: exerciseToShow)
            }
            .task {
                await fetchExercises()
            }
        }
    }

    private func toggleSelection(for exercise: Exercise) {
        if let index = currentlySelectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            currentlySelectedExercises.remove(at: index)
        } else {
            currentlySelectedExercises.append(exercise)
        }
    }

    func fetchExercises() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedExercisesData: [Exercise] = try await client.database
                .from("exercises").select().execute().value
            DispatchQueue.main.async {
                self.exercises = fetchedExercisesData
                isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                isLoading = false
                print("Error fetching exercises: \(error)")
            }
        }
    }
}

// MARK: - Create Exercise View (Sheet)

struct CreateExerciseView: View {
    @Environment(\.dismiss) var dismiss // This dismiss is for the CreateExerciseView sheet itself
    var onSave: (Exercise) -> Void

    @State private var name: String = ""
    @State private var selectedBodyPart: String = "Other" 
    @State private var selectedCategory: String = "Bodyweight" 
    @State private var instructions: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submissionError: String? = nil

    private let client = SupabaseManager.shared.client
    private let bodyParts = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body", "Cardio", "Olympic", "Other"]
    private let categories = ["Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Bands"]

    struct NewExercisePayload: Encodable {
        let name: String
        let body_part: String?
        let category: String?
        let instructions: String?
        let created_by_user_id: UUID
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Exercise Details")) {
                    TextField("Exercise Name", text: $name)
                    Picker("Body Part", selection: $selectedBodyPart) {
                        ForEach(bodyParts, id: \.self) { part in Text(part) }
                    }
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { cat in Text(cat) }
                    }
                    TextEditorWithPlaceholder(text: $instructions, placeholder: "Instructions (Optional)")
                        .frame(height: 100)
                }

                if let submissionError { Text("Error: \(submissionError)").foregroundColor(.red) }

                Button(action: { Task { await submitExercise() } }) {
                    if isSubmitting { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Save Exercise").frame(maxWidth: .infinity) }
                }
                .disabled(name.isEmpty || isSubmitting)
            }
            .navigationTitle("Create New Exercise")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() } // Dismisses CreateExerciseView sheet
                }
            }
        }
    }

    func submitExercise() async {
        guard !name.isEmpty else {
            submissionError = "Exercise name cannot be empty."
            return
        }
        isSubmitting = true
        submissionError = nil
        do {
            let userId = try await client.auth.session.user.id
            let payload = NewExercisePayload(
                name: name,
                body_part: selectedBodyPart,
                category: selectedCategory,
                instructions: instructions.isEmpty ? nil : instructions,
                created_by_user_id: userId
            )
            let newExercise: Exercise = try await client.database
                .from("exercises").insert(payload, returning: .representation).select().single().execute().value
            DispatchQueue.main.async {
                onSave(newExercise)
                isSubmitting = false
                // dismiss() // This dismiss is now handled by onSave in the parent if it needs to close this sheet AND the picker
                           // Actually, this dismiss is correct for THIS sheet (CreateExerciseView).
                dismiss() 
            }
        } catch {
            DispatchQueue.main.async {
                submissionError = error.localizedDescription
                isSubmitting = false
                print("Error submitting exercise: \(error)")
            }
        }
    }
}

// MARK: - Helper Views

struct TextEditorWithPlaceholder: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(Color(UIColor.placeholderText))
                    .padding(.top, 8)
                    .padding(.leading, 5)
            }
            TextEditor(text: $text)
        }
    }
}

// MARK: - Preview

struct ExercisesView_Previews: PreviewProvider {
    static var previews: some View {
        ExercisesView()
            // For preview to work with SupabaseManager, you might need to mock it
            // or ensure it can initialize safely in a preview context.
    }
} 