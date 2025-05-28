import SwiftUI
import Supabase
import Combine

// Represents the active workout session, presented as a full-screen cover.
struct ActiveWorkoutSessionView: View {
    @Environment(\.dismiss) var dismiss
    private let client = SupabaseManager.shared.client
    private let workoutLogger = WorkoutLogger() // If still needed for specific sub-tasks, or remove if all logic is here

    // Passed-in initial data
    let workoutId: UUID
    @State var workoutName: String
    @State var startTime: Date

    // Internal State for the active session
    @State private var elapsedTime: TimeInterval = 0
    @State private var timerSubscription: Cancellable? = nil

    @State private var selectedExercisesForWorkout: [Exercise] = []
    @State private var workoutSets: [UUID: [WorkoutSetInput]] = [:] // Key is exercise.id
    @State private var previousPerformances: [UUID: PreviousSetData?] = [:]
    @State private var workoutExerciseDbIds: [UUID: UUID] = [:] // Maps Exercise.id to workout_exercises.id

    // Custom Keyboard Management State
    @State private var activeKeyboardInfo: KeyboardTargetInfo?

    // UI State
    @State private var isExercisePickerVisible: Bool = false
    @State private var showCancelWorkoutAlert: Bool = false
    @State private var isEditingWorkoutName: Bool = false
    @State private var temporaryWorkoutName: String = ""
    @State private var finishWorkoutError: String? = nil
    @State private var isFinishingWorkout: Bool = false
    @State private var isAddingExerciseToDb: Bool = false // Optional: for loading state if needed
    
    // Rest Timer State - Revised for per-exercise display context
    @State private var activeRestTimerExerciseId: UUID? = nil
    @State private var lastCompletedSetId: UUID? = nil // NEW: Tracks which set triggered the timer
    @State private var isRestTimerGloballyActive: Bool = false // Tracks if any timer is running
    @State private var restTimeRemaining: Int = 0
    private let defaultRestDuration: Int = 60 // Default rest time in seconds
    @State private var restTimerSubscription: Cancellable? = nil

    // Callback for when the session is dismissed
    var onDismissSession: ((_ didSave: Bool) -> Void)?

    // For preloading exercises when starting from a routine
    let exercisesToPreload: [RoutineExerciseDetailItem]?

    // Initializer
    init(workoutId: UUID, initialWorkoutName: String, initialStartTime: Date, exercisesToPreload: [RoutineExerciseDetailItem]? = nil, onDismiss: ((_ didSave: Bool) -> Void)? = nil) {
        self.workoutId = workoutId
        _workoutName = State(initialValue: initialWorkoutName)
        _startTime = State(initialValue: initialStartTime)
        self.exercisesToPreload = exercisesToPreload
        self.onDismissSession = onDismiss
    }

    var body: some View {
        NavigationView { // Each fullScreenCover should have its own NavigationView for toolbar and title
            ZStack(alignment: .bottom) {
                workoutContentView
                
                // Custom Keyboard Overlay
                if let info = activeKeyboardInfo {
                    CustomKeyboardView(
                        text: editingTextBinding(info: info),
                        isDecimalAllowed: info.fieldType == .lbs,
                        onNextAction: { handleKeyboardNextAction(info: info) },
                        onIncrement: { handleNumericInputManipulation(info: info, delta: 1.0) },
                        onDecrement: { handleNumericInputManipulation(info: info, delta: -1.0) }
                    )
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).animation(.spring()))
                    .zIndex(1)
                }
            }
            .navigationTitle(workoutName) // Use dynamic workout name
            .navigationBarTitleDisplayMode(.inline) // Or .large, as preferred
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showCancelWorkoutAlert = true }
                        .disabled(isFinishingWorkout)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isFinishingWorkout {
                        ProgressView()
                    } else {
                        Button("Finish") { Task { await finishWorkout() } }
                            .fontWeight(.semibold)
                    }
                }
                // Potentially add more toolbar items here like the ellipsis menu if desired
            }
            .onAppear {
                startTimer()
                if let preloadItems = exercisesToPreload, !preloadItems.isEmpty {
                    Task {
                        await preloadExercisesFromRoutine(items: preloadItems)
                    }
                }
            }
            .onDisappear {
                stopTimer()
            }
            .sheet(isPresented: $isExercisePickerVisible) {
                ExercisesView(onSave: { returnedExercises in
                    Task {
                        isAddingExerciseToDb = true
                        for exercise in returnedExercises {
                            if !selectedExercisesForWorkout.contains(where: { $0.id == exercise.id }) {
                                selectedExercisesForWorkout.append(exercise)
                                workoutSets[exercise.id] = [WorkoutSetInput()] // Add default set
                                await addExerciseToCurrentWorkoutInDatabase(exercise: exercise)
                                await fetchPreviousPerformance(for: exercise.id)
                            }
                        }
                        isAddingExerciseToDb = false
                    }
                    isExercisePickerVisible = false
                })
            }
            .alert("Cancel Workout?", isPresented: $showCancelWorkoutAlert) {
                Button("Confirm Cancel", role: .destructive) { Task { await cancelWorkoutConfirmed() } }
                Button("Keep Working", role: .cancel) {}
            } message: {
                Text("Are you sure you want to cancel this workout? All unsaved progress will be lost.")
            }
            .alert("Edit Workout Name", isPresented: $isEditingWorkoutName) {
                TextField("Workout Name", text: $temporaryWorkoutName)
                Button("Save") {
                    if !temporaryWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        workoutName = temporaryWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                        // TODO: Optionally update workout name in DB immediately if desired
                    }
                    isEditingWorkoutName = false
                }
                Button("Cancel", role: .cancel) { isEditingWorkoutName = false }
            } message: {
                Text("Enter a new name for your workout.")
            }
            .alert("Save Error", isPresented: Binding(get: { finishWorkoutError != nil }, set: { if !$0 { finishWorkoutError = nil } })) {
                Button("OK") { finishWorkoutError = nil } 
            } message: {
                Text(finishWorkoutError ?? "An unknown error occurred.")
            }
        }
    }

    @ViewBuilder
    private var workoutContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Workout Header (Simplified, as title is in Nav Bar)
            VStack(alignment: .leading) {
                 HStack {
                    Image(systemName: "calendar")
                    Text(startTime.formatted(date: .long, time: .omitted))
                }
                .font(.subheadline)
                .foregroundColor(.gray)
                HStack {
                    Image(systemName: "clock")
                    Text(formatTimeInterval(elapsedTime))
                }
                .font(.subheadline)
                .foregroundColor(.gray)
            }
            .padding([.horizontal, .top])
            .padding(.bottom, 10)

            Divider()

            if selectedExercisesForWorkout.isEmpty {
                emptyStateView
            } else {
                exerciseListView
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text("No exercises added yet.").font(.headline).foregroundColor(.gray)
            Text("Tap 'Add Exercises' below to get started.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { actionButtonsVStack }
    }

    @ViewBuilder
    private var exerciseListView: some View {
        List {
            ForEach(selectedExercisesForWorkout) { exercise in
                ExerciseSectionView(
                    exercise: exercise,
                    sets: workoutSets[exercise.id] ?? [],
                    previousPerformanceForExercise: previousPerformances[exercise.id] ?? nil,
                    activeKeyboardInfo: activeKeyboardInfo, 
                    isRestTimerGloballyActive: isRestTimerGloballyActive,
                    activeRestTimerExerciseId: activeRestTimerExerciseId,
                    lastCompletedSetId: lastCompletedSetId,
                    currentRestTimeRemaining: restTimeRemaining,
                    formatRestTime: formatRestTime,
                    onAddSet: { addSet(for: exercise.id) },
                    onRequestKeyboard: { exId, setId, fieldType in requestKeyboard(exerciseId: exId, setId: setId, fieldType: fieldType) },
                    onToggleCompletion: { exId, setId in toggleSetCompletion(exerciseId: exId, setId: setId) },
                    onFillFromPrevious: { exId, setId in fillSetFromPrevious(exerciseId: exId, setId: setId) }
                )
            }
            Section { actionButtonsVStack } // Buttons at the end of the list
               .textCase(nil)
        }
    }
    
    private var actionButtonsVStack: some View {
        VStack {
            Button("Add Exercises") { isExercisePickerVisible = true }
                .disabled(isFinishingWorkout)
                .padding().frame(maxWidth: .infinity).background(Color.blue).foregroundColor(.white).cornerRadius(10)
            // Note: Cancel button is in toolbar now for full-screen context
        }.padding()
    }

    // MARK: - Timer Logic
    func startTimer() {
        stopTimer()
        timerSubscription = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in
            elapsedTime = Date().timeIntervalSince(startTime)
        }
    }
    func stopTimer() { timerSubscription?.cancel(); timerSubscription = nil }
    func formatTimeInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "00:00"
    }

    // MARK: - Rest Timer Logic - Revised
    func startRestTimer(for exerciseId: UUID, setId: UUID, duration: Int) {
        stopRestTimer() // Clear any existing timer first
        
        activeRestTimerExerciseId = exerciseId
        lastCompletedSetId = setId // Record the set that triggered this timer
        restTimeRemaining = duration
        isRestTimerGloballyActive = true
        
        restTimerSubscription = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if restTimeRemaining > 0 {
                    restTimeRemaining -= 1
                } else {
                    stopRestTimer()
                    print("Rest timer for exercise \(exerciseId) finished!")
                    // TODO: Add sound/haptic feedback
                }
            }
    }

    func stopRestTimer() {
        restTimerSubscription?.cancel()
        restTimerSubscription = nil
        isRestTimerGloballyActive = false
        activeRestTimerExerciseId = nil 
        lastCompletedSetId = nil // Clear the last completed set ID
        // restTimeRemaining = 0 // Optional: reset displayed time, or let it show 0 if stopped.
    }

    func formatRestTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Keyboard Logic
    func requestKeyboard(exerciseId: UUID, setId: UUID, fieldType: FieldType) {
        stopRestTimer() // Stop rest timer when user intends to start a new set by tapping a field
        self.activeKeyboardInfo = KeyboardTargetInfo(exerciseId: exerciseId, setId: setId, fieldType: fieldType)
    }
    
    func handleKeyboardNextAction(info: KeyboardTargetInfo) {
        if info.fieldType == .lbs {
            self.activeKeyboardInfo = KeyboardTargetInfo(exerciseId: info.exerciseId, setId: info.setId, fieldType: .reps)
        } else {
            self.activeKeyboardInfo = nil
        }
    }

    // New function to handle increment/decrement for the keyboard
    func handleNumericInputManipulation(info: KeyboardTargetInfo, delta: Double) {
        var currentTextBinding = editingTextBinding(info: info)
        var currentValue = Double(currentTextBinding.wrappedValue) ?? 0

        if info.fieldType == .reps { // Reps are whole numbers
            currentValue = round(currentValue)
            let repDelta = Int(round(delta))
            let newRepValue = Int(currentValue) + repDelta
            currentTextBinding.wrappedValue = String(max(0, newRepValue)) // Ensure reps are not negative
        } else { // Lbs can be decimal
            let newWeightValue = currentValue + delta
            // Format to one decimal place, ensure not negative
            currentTextBinding.wrappedValue = String(format: "%.1f", max(0, newWeightValue)) 
        }
    }

    private func editingTextBinding(info: KeyboardTargetInfo) -> Binding<String> {
        Binding<String>(
            get: {
                guard let sets = workoutSets[info.exerciseId], let index = sets.firstIndex(where: { $0.id == info.setId }) else { return "" }
                return info.fieldType == .lbs ? sets[index].weight : sets[index].reps
            },
            set: { newValue in
                guard var sets = workoutSets[info.exerciseId], let index = sets.firstIndex(where: { $0.id == info.setId }) else { return }
                
                let previousCompletionState = sets[index].isCompleted // Capture state before change

                if info.fieldType == .lbs { sets[index].weight = newValue } else { sets[index].reps = newValue }
                
                let currentWeight = sets[index].weight.trimmingCharacters(in: .whitespacesAndNewlines)
                let currentReps = sets[index].reps.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let isNowConsideredComplete = !currentWeight.isEmpty && !currentReps.isEmpty
                sets[index].isCompleted = isNowConsideredComplete
                
                workoutSets[info.exerciseId] = sets

                // If the set just became complete (was not complete before, but is now)
                if !previousCompletionState && isNowConsideredComplete {
                    startRestTimer(for: info.exerciseId, setId: info.setId, duration: defaultRestDuration)
                }
            }
        )
    }
    
    func addSet(for exerciseId: UUID) {
        workoutSets[exerciseId, default: []].append(WorkoutSetInput())
        stopRestTimer() // Stop rest timer if user manually adds a new set (they are about to work)
    }

    func toggleSetCompletion(exerciseId: UUID, setId: UUID) {
        guard var sets = workoutSets[exerciseId], let index = sets.firstIndex(where: { $0.id == setId }) else { return }
        
        let oldCompletionState = sets[index].isCompleted
        let currentlyEmpty = sets[index].weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sets[index].reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        
        if !oldCompletionState && currentlyEmpty, let prevData = previousPerformances[exerciseId] as? PreviousSetData {
            sets[index].weight = String(format: "%.1f", prevData.weight); sets[index].reps = String(prevData.reps); sets[index].isCompleted = true
        } else {
            sets[index].isCompleted.toggle()
        }
        workoutSets[exerciseId] = sets

        // Start rest timer if the set was just marked as complete and is not empty
        if sets[index].isCompleted && !currentlyEmpty {
            startRestTimer(for: exerciseId, setId: sets[index].id, duration: defaultRestDuration)
        } else if !sets[index].isCompleted { // If set was marked incomplete, stop any active rest timer
            stopRestTimer()
        }
    }

    func fillSetFromPrevious(exerciseId: UUID, setId: UUID) {
        guard var sets = workoutSets[exerciseId], let index = sets.firstIndex(where: { $0.id == setId }), let prevData = previousPerformances[exerciseId] as? PreviousSetData else { return }
        sets[index].weight = String(format: "%.1f", prevData.weight); sets[index].reps = String(prevData.reps); sets[index].isCompleted = true
        workoutSets[exerciseId] = sets
        startRestTimer(for: exerciseId, setId: sets[index].id, duration: defaultRestDuration)
    }

    // MARK: - Supabase/Data Logic
    func addExerciseToCurrentWorkoutInDatabase(exercise: Exercise) async {
        guard let userId = try? await client.auth.session.user.id else { return }
        let orderIndex = selectedExercisesForWorkout.firstIndex(where: { $0.id == exercise.id }) ?? (selectedExercisesForWorkout.count > 0 ? selectedExercisesForWorkout.count - 1 : 0)
        let payload = WorkoutExerciseInsertPayload(workout_id: self.workoutId, exercise_id: exercise.id, order_index: orderIndex, user_id: userId)
        do {
            let newWorkoutExerciseResponse: [IdResponse] = try await client.database.from("workout_exercises").insert(payload, returning: .representation).select("id").execute().value
            if let firstResponse = newWorkoutExerciseResponse.first { workoutExerciseDbIds[exercise.id] = firstResponse.id }
        } catch { print("Error inserting workout_exercise: \(error.localizedDescription)") }
    }

    func fetchPreviousPerformance(for exerciseId: UUID) async {
        guard let userId = try? await client.auth.session.user.id else { return }
        struct RpcParams: Encodable { let p_exercise_id: UUID; let p_user_id: UUID }
        do {
            let result: [PreviousSetData] = try await client.rpc("get_previous_performance", params: RpcParams(p_exercise_id: exerciseId, p_user_id: userId)).execute().value
            DispatchQueue.main.async { previousPerformances[exerciseId] = result.first ?? nil }
        } catch { print("Error fetching previous performance: \(error)"); DispatchQueue.main.async { previousPerformances[exerciseId] = nil } }
    }

    func finishWorkout() async {
        guard let userId = try? await client.auth.session.user.id else {
            finishWorkoutError = "Could not save workout. User not found."; return
        }
        isFinishingWorkout = true; finishWorkoutError = nil
        var setsToInsert: [WorkoutSetInsertPayload] = []

        for exercise in selectedExercisesForWorkout {
            guard let workoutExerciseId = workoutExerciseDbIds[exercise.id] else { continue }
            if let setsForExercise = workoutSets[exercise.id] {
                for (index, setInput) in setsForExercise.enumerated() {
                    if setInput.isCompleted, let weight = Double(setInput.weight), weight > 0, let reps = Int(setInput.reps), reps > 0 {
                        setsToInsert.append(WorkoutSetInsertPayload(workout_exercise_id: workoutExerciseId, set_number: index + 1, weight: weight, reps: reps, user_id: userId, rest_seconds: nil))
                    }
                }
            }
        }
        do {
            if !setsToInsert.isEmpty { try await client.database.from("workout_sets").insert(setsToInsert).execute() }
            let updatePayload = WorkoutUpdatePayload(notes: workoutName, end_time: Date())
            try await client.database.from("workouts").update(updatePayload).eq("id", value: self.workoutId).execute()
            DispatchQueue.main.async {
                stopTimer(); isFinishingWorkout = false;
                onDismissSession?(true) // Indicate save was successful
                dismiss() 
            }
        } catch {
            print("Error finishing workout: \(error.localizedDescription)")
            DispatchQueue.main.async { finishWorkoutError = "Failed to save workout: \(error.localizedDescription)"; isFinishingWorkout = false }
        }
    }

    func cancelWorkoutConfirmed() async {
        stopTimer()
        // The workout record itself was created by LogWorkoutView. 
        // We only need to delete it if it's a true cancellation of a new workout.
        // If it was an existing workout being edited (future feature), logic might differ.
        do {
            try await client.database.from("workouts").delete().eq("id", value: self.workoutId).execute()
            print("Successfully deleted workout ID: \(self.workoutId) from database due to cancellation.")
        } catch {
            print("Error deleting workout ID: \(self.workoutId) on cancel: \(error.localizedDescription)")
        }
        DispatchQueue.main.async { 
            onDismissSession?(false) // Indicate save was NOT successful (cancelled)
            dismiss() 
        }
    }

    // MARK: - Routine Preloading
    func preloadExercisesFromRoutine(items: [RoutineExerciseDetailItem]) async {
        isAddingExerciseToDb = true // Use existing state for visual feedback if needed
        var tempSelectedExercises: [Exercise] = []
        var tempWorkoutSets: [UUID: [WorkoutSetInput]] = [:]

        for exerciseDetail in items.sorted(by: { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }) {
            // Assuming Exercise struct can be initialized with just id and name for this purpose.
            // A more robust solution might fetch full Exercise details if needed.
            let exercise = Exercise(id: exerciseDetail.exerciseId, name: exerciseDetail.exerciseName, bodyPart: nil, category: nil, equipment: nil, instructions: nil, createdByUser_id: nil) 
            tempSelectedExercises.append(exercise)
            
            var setsForThisExercise: [WorkoutSetInput] = []
            for setTemplate in exerciseDetail.setTemplates.sorted(by: { ($0.setNumber ?? 0) < ($1.setNumber ?? 0) }) {
                setsForThisExercise.append(WorkoutSetInput(
                    weight: setTemplate.targetWeight ?? "",
                    reps: setTemplate.targetReps ?? "",
                    isCompleted: false // Start uncompleted
                ))
            }
            if setsForThisExercise.isEmpty { // Ensure at least one set if template had none
                setsForThisExercise.append(WorkoutSetInput())
            }
            tempWorkoutSets[exercise.id] = setsForThisExercise
            
            // Save this exercise to workout_exercises table & fetch previous performance
            // These calls are async and will run sequentially per exercise here.
            await addExerciseToCurrentWorkoutInDatabase(exercise: exercise)
            await fetchPreviousPerformance(for: exercise.id)
        }

        // Update main state variables on the main thread
        DispatchQueue.main.async {
            self.selectedExercisesForWorkout = tempSelectedExercises
            self.workoutSets = tempWorkoutSets
            self.isAddingExerciseToDb = false
        }
    }
}

// Need to ensure these helper structs are accessible or redefined here/globally
// For now, assuming they are available (e.g. from LogWorkoutView or a shared Models file)
// struct WorkoutSetInput: Identifiable, Equatable, Hashable { ... }
// struct PreviousSetData: Decodable, Equatable { ... }
// struct Exercise: Identifiable, Codable, Hashable { ... } 
// LogWorkoutView.KeyboardTargetInfo and LogWorkoutView.FieldType will need to be accessible too.
// For example, by moving them out of LogWorkoutView or qualifying them if LogWorkoutView is still in the same module.
// For simplicity in this step, I'm assuming they can be resolved. If not, they'd need to be moved or redefined here.

// REMOVE local duplicate definitions of IdResponse and WorkoutExerciseInsertPayload
// Assuming these are defined in WorkoutLogger.swift or a shared model file and are accessible.
// struct IdResponse: Decodable, Identifiable { let id: UUID } 
// struct WorkoutExerciseInsertPayload: Encodable { 
//     let workout_id: UUID
//     let exercise_id: UUID
//     let user_id: UUID
//     let order_index: Int
// }

// Preview for ActiveWorkoutSessionView (requires some mock data)
struct ActiveWorkoutSessionView_Previews: PreviewProvider {
    static var previews: some View {
        ActiveWorkoutSessionView(
            workoutId: UUID(), 
            initialWorkoutName: "Morning Workout", 
            initialStartTime: Date(),
            onDismiss: { didSave in print("Preview Session Dismissed, didSave: \(didSave)") }
        )
    }
} 