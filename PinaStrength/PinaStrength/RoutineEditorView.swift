import SwiftUI

struct RoutineEditorView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: RoutineEditorViewModel
    @FocusState private var focusedField: Field?
    
    let onSave: (() -> Void)?
    
    init(prefilledData: RoutineEditorViewModel.PrefilledData? = nil, onSave: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: RoutineEditorViewModel(prefilledData: prefilledData))
        self.onSave = onSave
    }
    
    enum Field: Hashable {
        case name
        case set(exerciseId: UUID, setIndex: Int, field: SetField)
        
        enum SetField {
            case reps, weight, rest
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Routine Name Section
                Section {
                    TextField("Routine Name", text: $viewModel.name)
                        .font(.title3.bold())
                        .focused($focusedField, equals: .name)
                } header: {
                    Text("NAME")
                }
                
                // Exercises Section
                if !viewModel.exercises.isEmpty {
                    Section {
                        ForEach(viewModel.exercises) { selectedExercise in
                            ExerciseSection(
                                selectedExercise: selectedExercise,
                                viewModel: viewModel,
                                focusedField: $focusedField
                            )
                        }
                        .onDelete { offsets in
                            viewModel.removeExercise(at: offsets)
                        }
                        .onMove { source, destination in
                            viewModel.moveExercise(from: source, to: destination)
                        }
                    } header: {
                        Text("EXERCISES (\(viewModel.exercises.count))")
                    }
                }
                
                // Add Exercises Button
                Section {
                    Button(action: { viewModel.showPicker = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                            Text("Add Exercises")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.blue)
                    }
                }
                
                // Error Display
                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task {
                                if await viewModel.save() {
                                    onSave?()
                                    dismiss()
                                }
                            }
                        }
                        .fontWeight(.semibold)
                        .disabled(viewModel.name.isEmpty || viewModel.exercises.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showPicker) {
                ExercisesPickerView { selectedExercises in
                    viewModel.addExercises(selectedExercises)
                }
            }
        }
    }
}

// MARK: - Exercise Section View
struct ExerciseSection: View {
    let selectedExercise: SelectedExercise
    let viewModel: RoutineEditorViewModel
    @FocusState.Binding var focusedField: RoutineEditorView.Field?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Exercise Name
            Text(selectedExercise.exercise.name)
                .font(.headline)
                .padding(.bottom, 4)
            
            // Set Headers
            HStack {
                Text("Set")
                    .frame(width: 40, alignment: .leading)
                Text("Reps")
                    .frame(maxWidth: .infinity)
                Text("Weight")
                    .frame(maxWidth: .infinity)
                Text("Rest (s)")
                    .frame(maxWidth: .infinity)
                Spacer().frame(width: 30) // Space for delete button
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Sets
            ForEach(Array(selectedExercise.sets.enumerated()), id: \.element.id) { index, setTemplate in
                SetTemplateRow(
                    setNumber: index + 1,
                    set: setTemplate,
                    exerciseId: selectedExercise.id,
                    setIndex: index,
                    focusedField: $focusedField,
                    onDelete: {
                        viewModel.removeSet(from: selectedExercise, at: index)
                    },
                    onChange: { updatedSet in
                        if let exerciseIndex = viewModel.exercises.firstIndex(where: { $0.id == selectedExercise.id }) {
                            viewModel.exercises[exerciseIndex].sets[index] = updatedSet
                        }
                    }
                )
            }
            
            // Add Set Button
            Button(action: {
                viewModel.addSet(to: selectedExercise)
            }) {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Add Set")
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Set Template Row
struct SetTemplateRow: View {
    let setNumber: Int
    @State var set: SetTemplate
    let exerciseId: UUID
    let setIndex: Int
    @FocusState.Binding var focusedField: RoutineEditorView.Field?
    let onDelete: () -> Void
    let onChange: (SetTemplate) -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Text("\(setNumber)")
                .frame(width: 40, alignment: .leading)
                .foregroundColor(.secondary)
            
            TextField("12", text: $set.reps)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .set(exerciseId: exerciseId, setIndex: setIndex, field: .reps))
                .onChange(of: set.reps) { _ in onChange(set) }
            
            TextField("135", text: $set.weight)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .set(exerciseId: exerciseId, setIndex: setIndex, field: .weight))
                .onChange(of: set.weight) { _ in onChange(set) }
            
            TextField("90", text: $set.rest)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .set(exerciseId: exerciseId, setIndex: setIndex, field: .rest))
                .onChange(of: set.rest) { _ in onChange(set) }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .frame(width: 30)
        }
    }
}

// MARK: - Preview
struct RoutineEditorView_Previews: PreviewProvider {
    static var previews: some View {
        RoutineEditorView()
    }
} 