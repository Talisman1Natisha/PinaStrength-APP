import SwiftUI
import Supabase

// MARK: - Data Model for Routine Set Template Input
struct RoutineSetTemplateInput: Identifiable, Equatable, Hashable, Decodable {
    let id: UUID
    var setNumber: Int?      
    var targetReps: String?    // Changed to Optional
    var targetWeight: String?  // Changed to Optional
    var targetRestSeconds: String? // Changed to Optional

    enum CodingKeys: String, CodingKey { 
        case id 
        case setNumber = "set_number"
        case targetReps = "target_reps"
        case targetWeight = "target_weight"
        case targetRestSeconds = "target_rest_seconds"
    }
    
    init(id: UUID = UUID(), setNumber: Int? = nil, targetReps: String? = nil, targetWeight: String? = nil, targetRestSeconds: String? = nil) {
        self.id = id
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.targetRestSeconds = targetRestSeconds
    }
}

// MARK: - New Subview for a single Set Template Input Row
struct RoutineSetTemplateInputRowView: View {
    let setIndex: Int
    let initialTemplate: RoutineSetTemplateInput
    let onSetTemplateChanged: (RoutineSetTemplateInput) -> Void

    @State private var localTargetWeight: String
    @State private var localTargetReps: String
    @State private var localTargetRestSeconds: String

    init(setIndex: Int, template: RoutineSetTemplateInput, onSetTemplateChanged: @escaping (RoutineSetTemplateInput) -> Void) {
        self.setIndex = setIndex
        self.initialTemplate = template
        self.onSetTemplateChanged = onSetTemplateChanged
        _localTargetWeight = State(initialValue: template.targetWeight ?? "")
        _localTargetReps = State(initialValue: template.targetReps ?? "")
        _localTargetRestSeconds = State(initialValue: template.targetRestSeconds ?? "")
    }

    var body: some View {
        HStack {
            Text("\(setIndex + 1)").frame(minWidth: 30, alignment: .leading)
            TextField("e.g. 100, Last", text: $localTargetWeight)
                .textFieldStyle(RoundedBorderTextFieldStyle()).font(.body)
                .onChange(of: localTargetWeight) { _ in reportChange() }
            TextField("e.g. 8-12, AMRAP", text: $localTargetReps)
                .textFieldStyle(RoundedBorderTextFieldStyle()).font(.body)
                .onChange(of: localTargetReps) { _ in reportChange() }
            TextField("e.g. 60", text: $localTargetRestSeconds)
                .keyboardType(.numberPad)
                .textFieldStyle(RoundedBorderTextFieldStyle()).font(.body)
                .frame(minWidth: 50, maxWidth: 70)
                .onChange(of: localTargetRestSeconds) { _ in reportChange() }
            // TODO: Add delete button for set template row
        }
        .padding(.vertical, 1)
        .onChange(of: initialTemplate) { newTemplate in 
            localTargetWeight = newTemplate.targetWeight ?? ""
            localTargetReps = newTemplate.targetReps ?? ""
            localTargetRestSeconds = newTemplate.targetRestSeconds ?? ""
        }
    }

    private func reportChange() {
        var changedTemplate = initialTemplate
        changedTemplate.targetWeight = localTargetWeight.isEmpty ? nil : localTargetWeight
        changedTemplate.targetReps = localTargetReps.isEmpty ? nil : localTargetReps
        changedTemplate.targetRestSeconds = localTargetRestSeconds.isEmpty ? nil : localTargetRestSeconds
        onSetTemplateChanged(changedTemplate)
    }
}

// MARK: - Exercise Template Row View (Modified for closure-based updates)
struct ExerciseTemplateRowView: View {
    let exercise: Exercise
    let setTemplates: [RoutineSetTemplateInput] // Now immutable
    let onAddSetTemplate: () -> Void
    let onSetTemplateUpdate: (Int, RoutineSetTemplateInput) -> Void // New closure
    // let onRemoveSetTemplate: (IndexSet) -> Void // For future delete functionality

    var body: some View {
        VStack(alignment: .leading) {
            Text(exercise.name).font(.headline)
            HStack { /* ... Column Headers ... */ 
                Text("Set").frame(minWidth: 30, alignment: .leading)
                Text("Target Weight").frame(maxWidth: .infinity, alignment: .leading)
                Text("Target Reps").frame(maxWidth: .infinity, alignment: .leading)
                Text("Rest (s)").frame(minWidth: 50, alignment: .leading)
            }.font(.caption).foregroundColor(.gray).padding(.bottom, 2)

            ForEach(setTemplates.indices, id: \.self) { index in
                RoutineSetTemplateInputRowView(
                    setIndex: index,
                    template: setTemplates[index],
                    onSetTemplateChanged: { updatedTemplate in
                        onSetTemplateUpdate(index, updatedTemplate)
                    }
                )
            }
            // If using ForEach(setTemplates) and setTemplates were Identifiable, then onDelete would be easier here if this VStack was inside a List section.
            // For now, deletion can be handled by a button per row or a swipe action if structured differently.

            Button(action: onAddSetTemplate) {
                HStack { /* ... Add Set Template button content ... */ 
                    Spacer(); Image(systemName: "plus.circle"); Text("Add Set Template"); Spacer()
                }
            }.padding(.top, 5)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Create/Edit Routine View

struct CreateEditRoutineView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: () -> Void // Callback when routine is saved
    // var routineToEdit: RoutineListItem? // Optional: Pass this in if editing an existing routine

    @State private var routineName: String = "New Template"
    @State private var exercisesInRoutine: [Exercise] = [] // Exercises selected for this template
    // [Exercise.id : [SetTemplateInput]]
    @State private var setTemplates: [UUID: [RoutineSetTemplateInput]] = [:] 
    
    @State private var isExercisePickerVisible = false
    @State private var isSaving: Bool = false
    @State private var saveError: String? = nil

    private let client = SupabaseManager.shared.client

    // Dummy header items for the set template rows, similar to LogWorkoutView
    private let setColumnHeaders = ["Set", "Weight", "Reps", "Rest"]

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                Form {
                    Section(header: Text("Routine Name")) {
                        TextField("Enter routine name", text: $routineName)
                        // TODO: Add a "..." menu here later for routine options (duplicate, delete if editing)
                    }

                    // List of Exercises in this Routine
                    Section(header: Text("Exercises (\(exercisesInRoutine.count))")) {
                        if exercisesInRoutine.isEmpty {
                            Text("No exercises added yet. Tap 'Add Exercises' below.")
                                .foregroundColor(.secondary)
                                .padding(.vertical)
                        } else {
                            ForEach(exercisesInRoutine) { exercise in
                                ExerciseTemplateRowView(
                                    exercise: exercise,
                                    setTemplates: setTemplates[exercise.id] ?? [], // Pass immutable data
                                    onAddSetTemplate: { addSetTemplate(for: exercise.id) },
                                    onSetTemplateUpdate: { setIndex, updatedTemplate in
                                        // Update the main state dictionary
                                        if setTemplates[exercise.id]?.indices.contains(setIndex) == true {
                                            setTemplates[exercise.id]?[setIndex] = updatedTemplate
                                        }
                                    }
                                )
                            }
                        }
                    }

                    // Add Exercises Button within the Form
                    Button(action: { isExercisePickerVisible = true }) {
                        HStack {
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                            Text("Add Exercises")
                            Spacer()
                        }
                    }
                }
                
                if let saveError {
                    Text("Error saving: \(saveError)")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle(routineName) // Dynamically update title? Or keep static "New Template"
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await saveRoutine() }
                        }
                        .disabled(routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exercisesInRoutine.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $isExercisePickerVisible) {
                ExercisesView(onSave: { selectedExercises in
                    // Append new exercises, avoid duplicates, initialize set templates
                    for exercise in selectedExercises {
                        if !exercisesInRoutine.contains(where: { $0.id == exercise.id }) {
                            exercisesInRoutine.append(exercise)
                            // Add one default set template when an exercise is added
                            if setTemplates[exercise.id] == nil {
                                setTemplates[exercise.id] = [RoutineSetTemplateInput()]
                            }
                        }
                    }
                    isExercisePickerVisible = false
                })
            }
        }
    }

    func addSetTemplate(for exerciseId: UUID) {
        setTemplates[exerciseId, default: []].append(RoutineSetTemplateInput())
    }

    func saveRoutine() async {
        guard let userId = try? await client.auth.session.user.id else {
            saveError = "User not authenticated. Cannot save routine."
            return
        }
        guard !routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            saveError = "Routine name cannot be empty."
            return
        }
        guard !exercisesInRoutine.isEmpty else {
            saveError = "Please add at least one exercise to the routine."
            return
        }

        isSaving = true
        saveError = nil

        // Step 1: Insert into `routines` table
        struct RoutineInsert: Encodable { let user_id: UUID; let name: String }
        struct RoutineResponse: Decodable { let id: UUID }

        do {
            let routinePayload = RoutineInsert(user_id: userId, name: routineName.trimmingCharacters(in: .whitespacesAndNewlines))
            let newRoutineResponse: [RoutineResponse] = try await client.database
                .from("routines")
                .insert(routinePayload, returning: .representation)
                .select("id").execute().value
            
            guard let newRoutineDbId = newRoutineResponse.first?.id else {
                saveError = "Failed to create routine in database."
                isSaving = false
                return
            }
            print("Created routine with ID: \(newRoutineDbId)")

            // Step 2: Insert into `routine_exercises` and `routine_exercise_sets`
            for (index, exercise) in exercisesInRoutine.enumerated() {
                struct RoutineExerciseInsert: Encodable { let routine_id: UUID; let exercise_id: UUID; let user_id: UUID; let order_index: Int }
                struct RoutineExerciseResponse: Decodable { let id: UUID }
                
                let rePayload = RoutineExerciseInsert(routine_id: newRoutineDbId, exercise_id: exercise.id, user_id: userId, order_index: index)
                let newRoutineExerciseResponse: [RoutineExerciseResponse] = try await client.database
                    .from("routine_exercises")
                    .insert(rePayload, returning: .representation)
                    .select("id").execute().value

                guard let newRoutineExerciseDbId = newRoutineExerciseResponse.first?.id else {
                    print("Failed to save exercise '\(exercise.name)' to routine. Skipping its sets.")
                    continue // Or handle error more robustly
                }

                if let setTemplatesForExercise = setTemplates[exercise.id] {
                    var setToInsert: [RoutineSetInsert] = []
                    struct RoutineSetInsert: Encodable {
                        let routine_exercise_id: UUID; let user_id: UUID; let set_number: Int
                        let target_reps: String?; let target_weight: String?; let target_rest_seconds: Int?
                    }
                    for (setIndex, template) in setTemplatesForExercise.enumerated() {
                        let restSeconds = Int(template.targetRestSeconds ?? "")
                        setToInsert.append(RoutineSetInsert(
                            routine_exercise_id: newRoutineExerciseDbId, 
                            user_id: userId, 
                            set_number: setIndex + 1, 
                            target_reps: template.targetReps?.isEmpty == true ? nil : template.targetReps, 
                            target_weight: template.targetWeight?.isEmpty == true ? nil : template.targetWeight,
                            target_rest_seconds: restSeconds
                        ))
                    }
                    if !setToInsert.isEmpty {
                        try await client.database.from("routine_exercise_sets").insert(setToInsert).execute()
                    }
                }
            }

            isSaving = false
            print("Routine '\(routineName)' saved successfully!")
            onSave() // Call callback to dismiss and refresh previous view
            dismiss()

        } catch {
            saveError = "Error saving routine: \(error.localizedDescription)"
            print("Full save error: \(error)")
            isSaving = false
        }
    }
}

// MARK: - Preview
struct CreateEditRoutineView_Previews: PreviewProvider {
    static var previews: some View {
        CreateEditRoutineView(onSave: { print("Routine saved from preview") })
    }
} 