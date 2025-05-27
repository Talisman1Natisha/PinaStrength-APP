import SwiftUI
import Supabase
import Combine // Import Combine for the timer

// This struct will be used to manage set data in the UI for the current workout session.
struct WorkoutSetInput: Identifiable, Equatable {
    let id = UUID() // For ForEach loops
    var weight: String = ""   // Using String for TextField binding
    var reps: String = ""     // Using String for TextField binding
    var isCompleted: Bool = false // For the checkmark UI
    // We can add properties for 'previous' values later (Phase 5/6)
    // var previousWeight: String? = nil 
    // var previousReps: String? = nil
}

// Struct to hold data from the RPC
struct PreviousSetData: Decodable, Equatable {
    let weight: Double
    let reps: Int
}

// MARK: - Reusable Subview for a Single Set Row (Phase 6: Auto Checkmark)
struct ExerciseSetRowView: View {
    let setIndex: Int
    let initialSetInput: WorkoutSetInput
    let previousSetData: PreviousSetData? // Added property for previous data
    let onSetDataChanged: (WorkoutSetInput) -> Void

    @State private var localWeight: String
    @State private var localReps: String
    // localIsCompleted is no longer needed as a separate @State, 
    // its value will be determined by localWeight and localReps in reportChange

    init(setIndex: Int, setInput: WorkoutSetInput, previousSetData: PreviousSetData?, onSetDataChanged: @escaping (WorkoutSetInput) -> Void) {
        self.setIndex = setIndex
        self.initialSetInput = setInput
        self.previousSetData = previousSetData // Initialize
        self.onSetDataChanged = onSetDataChanged
        
        _localWeight = State(initialValue: setInput.weight)
        _localReps = State(initialValue: setInput.reps)
        // No need to initialize localIsCompleted from setInput.isCompleted directly anymore
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(setIndex + 1)").frame(maxWidth: .infinity, alignment: .leading)
            // Display previous data
            if let prev = previousSetData {
                Text("\(String(format: "%.1f", prev.weight)) x \(prev.reps)")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("-").frame(maxWidth: .infinity, alignment: .center).foregroundColor(.gray)
            }
            
            TextField("Lbs", text: $localWeight)
                .keyboardType(.decimalPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .onChange(of: localWeight) { _ in reportChange() }

            TextField("Reps", text: $localReps)
                .keyboardType(.numberPad)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .onChange(of: localReps) { _ in reportChange() }

            Image(systemName: (isCurrentSetComplete() ? "checkmark.circle.fill" : "circle"))
                .foregroundColor(isCurrentSetComplete() ? .green : .gray)
                .frame(maxWidth: .infinity, alignment: .trailing)
                // No onTapGesture needed here anymore for the checkmark itself
        }
        .padding(.vertical, 4)
        .onChange(of: initialSetInput) { newInitialValue in // Handles external changes, e.g., adding a new set
            localWeight = newInitialValue.weight
            localReps = newInitialValue.reps
            // isCompleted is derived, so no need to set it from newInitialValue directly here
        }
    }

    private func isCurrentSetComplete() -> Bool {
        return !localWeight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
               !localReps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func reportChange() {
        var changedSet = initialSetInput 
        changedSet.weight = localWeight
        changedSet.reps = localReps
        changedSet.isCompleted = isCurrentSetComplete() // Update isCompleted based on current inputs
        onSetDataChanged(changedSet)
    }
}

// MARK: - Reusable Subview for an Exercise Section (Closure-based updates)
struct ExerciseSectionView: View {
    let exercise: Exercise 
    let sets: [WorkoutSetInput] // Now immutable
    let previousPerformanceForExercise: PreviousSetData? // Added property
    let onAddSet: () -> Void
    let onSetUpdate: (Int, WorkoutSetInput) -> Void // Closure for updating a specific set by index

    var body: some View {
        Section(header: Text(exercise.name).font(.title3).fontWeight(.medium)) {
            HStack {
                Text("Set").frame(maxWidth: .infinity, alignment: .leading)
                Text("Previous").frame(maxWidth: .infinity, alignment: .center)
                Text("+lbs").frame(maxWidth: .infinity, alignment: .center)
                Text("Reps").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(maxWidth: .infinity, alignment: .trailing).opacity(0)
            }.font(.caption).foregroundColor(.gray).padding(.vertical, 2)

            ForEach(sets.indices, id: \.self) { setIndex in
                ExerciseSetRowView(
                    setIndex: setIndex, 
                    setInput: sets[setIndex], // Pass the immutable set data
                    previousSetData: previousPerformanceForExercise, // Pass it down
                    onSetDataChanged: { updatedSetInput in
                        onSetUpdate(setIndex, updatedSetInput)
                    }
                )
            }
            
            Button(action: onAddSet) {
                HStack { Spacer(); Image(systemName: "plus.circle.fill"); Text("Add Set"); Spacer() }
            }.buttonStyle(.borderless).padding(.vertical, 5)
        }
    }
}

struct LogWorkoutView: View {
    // Phase 1 & 2 State Variables
    @State private var isWorkoutStarted: Bool = false
    @State private var startTime: Date? = nil
    @State private var workoutName: String = "Afternoon Workout"
    @State private var showEditMenu: Bool = false // This might be replaced by the toolbar menu directly
    @State private var isExercisePickerVisible: Bool = false
    @State private var selectedExercisesForWorkout: [Exercise] = []
    @State private var workoutSets: [UUID: [WorkoutSetInput]] = [:] // Key is exercise.id

    // Phase 3: Timer State
    @State private var elapsedTime: TimeInterval = 0
    @State private var timerSubscription: Cancellable? = nil

    // Phase 6: State for previous performances
    @State private var previousPerformances: [UUID: PreviousSetData?] = [:] // Store optional PreviousSetData

    // Phase 7: State for the current workout's DB ID
    @State private var currentWorkoutDatabaseId: UUID? = nil
    @State private var isStartingWorkout: Bool = false // Renamed from isSavingWorkout for clarity

    // Phase 7.2: State for workout_exercise DB IDs (mapping Exercise.id to workout_exercises.id)
    @State private var workoutExerciseDbIds: [UUID: UUID] = [:]
    @State private var isAddingExerciseToDb: Bool = false // Optional: for loading state if needed

    // Phase 7.3: State for finishing workout
    @State private var isFinishingWorkout: Bool = false
    @State private var workoutSuccessfullySaved: Bool = false

    // State for Cancel Workout Alert
    @State private var showCancelWorkoutAlert: Bool = false

    // State for Editing Workout Name
    @State private var isEditingWorkoutName: Bool = false
    @State private var temporaryWorkoutName: String = ""

    // State for Finish Workout Error
    @State private var finishWorkoutError: String? = nil

    private let workoutLogger = WorkoutLogger()
    private let client = SupabaseManager.shared.client

    // Timer formatter
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "00:00"
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) { // Changed to leading alignment and zero spacing for header
                if isWorkoutStarted {
                    // Phase 3: Workout Header
                    VStack(alignment: .leading) {
                        HStack {
                            Text(workoutName)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Spacer()
                            // The "..." menu is now in the toolbar
                        }
                        HStack {
                            Image(systemName: "calendar")
                            Text(startTime?.formatted(date: .long, time: .omitted) ?? "Date N/A")
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

                    // Restore the List structure, but with non-binding sets for ExerciseSectionView
                    if selectedExercisesForWorkout.isEmpty {
                        VStack { 
                            Spacer(); Text("No exercises added yet.").font(.headline).foregroundColor(.gray); Text("Tap 'Add Exercises' below to get started.").font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center).padding(.horizontal); Spacer() 
                        }.frame(maxWidth: .infinity)
                    } else {
                        List { 
                            // Iterate selectedExercisesForWorkout using ForEach directly on the array for stable IDs if Exercise is Hashable (it is).
                            // This also gives direct access to the exercise object.
                            ForEach(selectedExercisesForWorkout) { exercise in // Iterate directly over exercises
                                ExerciseSectionView(
                                    exercise: exercise,
                                    sets: workoutSets[exercise.id] ?? [], // Pass current sets as immutable data
                                    previousPerformanceForExercise: previousPerformances[exercise.id] ?? nil, // Pass it here
                                    onAddSet: { addSet(for: exercise.id) },
                                    onSetUpdate: { setIndex, updatedSetInput in
                                        // Update the state in LogWorkoutView
                                        if var setsForExercise = workoutSets[exercise.id],
                                           setsForExercise.indices.contains(setIndex) {
                                            setsForExercise[setIndex] = updatedSetInput
                                            workoutSets[exercise.id] = setsForExercise
                                        }
                                    }
                                )
                            }
                        }
                    }
                    // Text("List of exercises temporarily hidden for debugging compiler.").padding().frame(maxHeight: .infinity) // Remove placeholder

                    Spacer() // Pushes the Add Exercises/Cancel buttons down if list is short
                    VStack {
                        Button("Add Exercises") { isExercisePickerVisible = true }.disabled(isFinishingWorkout || isStartingWorkout).padding().frame(maxWidth: .infinity).background(Color.blue).foregroundColor(.white).cornerRadius(10)
                        Button("Cancel Workout") { 
                            showCancelWorkoutAlert = true // Show confirmation alert
                        }.disabled(isFinishingWorkout || isStartingWorkout).padding().frame(maxWidth: .infinity).background(Color.red.opacity(0.8)).foregroundColor(.white).cornerRadius(10)
                    }.padding()

                } else {
                    // Phase 2 & 7: "Start an Empty Workout" Button
                    Spacer()
                    if isStartingWorkout {
                        ProgressView("Starting Workout...")
                    } else {
                        Button("Start an Empty Workout") {
                            Task {
                                isStartingWorkout = true
                                let createdWorkoutId = await createNewWorkoutInDatabase()
                                if let workoutId = createdWorkoutId { 
                                    self.currentWorkoutDatabaseId = workoutId
                                    isWorkoutStarted = true
                                    startTime = Date()
                                    elapsedTime = 0 
                                    startTimer()
                                } else {
                                    print("Failed to create workout in database. Cannot start workout UI.")
                                    // TODO: Show error to user
                                }
                                isStartingWorkout = false
                            }
                        }
                        .font(.headline).padding().frame(maxWidth: .infinity).background(Color.blue).foregroundColor(.white).cornerRadius(10).padding(.horizontal, 40)
                    }
                    Spacer()
                    if workoutSuccessfullySaved {
                        Text("Workout saved successfully!")
                            .foregroundColor(.green)
                            .padding()
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    workoutSuccessfullySaved = false
                                }
                            }
                    }
                }
            }
            .navigationTitle(isWorkoutStarted ? "Workout" : "Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            // Remove temporary commenting for toolbar
            .toolbar { 
                 if isWorkoutStarted {
                    ToolbarItem(placement: .navigationBarLeading) { Button(action: { print("Timer options tapped") }) { Image(systemName: "timer") }.disabled(isFinishingWorkout || isStartingWorkout) }
                    ToolbarItem(placement: .principal) { Text(workoutName).font(.headline) }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Menu {
                                Button("Edit Workout Name") { 
                                    temporaryWorkoutName = workoutName // Pre-fill
                                    isEditingWorkoutName = true 
                                }
                                Button("Adjust Start/End Time") { print("Adjust time tapped") } // Placeholder
                                Button("Add Photo") { print("Add photo tapped") } // Placeholder
                                Button("Add Note") { print("Add note tapped") } // Placeholder
                            } label: { Image(systemName: "ellipsis.circle") }.disabled(isFinishingWorkout || isStartingWorkout)
                            
                            if isFinishingWorkout { ProgressView() }
                            else { Button("Finish") { Task { await finishWorkout() } }.fontWeight(.semibold).disabled(isStartingWorkout) }
                        }
                    }
                }
            }
            // Phase 4: Present ExercisesView as a sheet
            .sheet(isPresented: $isExercisePickerVisible) {
                ExercisesView(onSave: { returnedExercises in
                    Task {
                        isAddingExerciseToDb = true // Optional: for UI feedback
                        for exercise in returnedExercises {
                            if !selectedExercisesForWorkout.contains(where: { $0.id == exercise.id }) {
                                // Add to UI first for responsiveness
                                selectedExercisesForWorkout.append(exercise)
                                workoutSets[exercise.id] = [WorkoutSetInput()]
                                
                                // Then save to DB and fetch previous performance
                                await addExerciseToCurrentWorkoutInDatabase(exercise: exercise)
                                await fetchPreviousPerformance(for: exercise.id)
                            }
                        }
                        isAddingExerciseToDb = false
                    }
                    isExercisePickerVisible = false 
                })
            }
            // Phase 7: Cancel Workout Alert
            .alert("Cancel Workout?", isPresented: $showCancelWorkoutAlert) {
                Button("Confirm Cancel", role: .destructive) {
                    Task {
                        await cancelWorkoutConfirmed()
                    }
                }
                Button("Keep Working", role: .cancel) { }
            } message: {
                Text("Are you sure you want to cancel this workout? All unsaved progress will be lost.")
            }
            // Alert for Editing Workout Name
            .alert("Edit Workout Name", isPresented: $isEditingWorkoutName) {
                TextField("Workout Name", text: $temporaryWorkoutName)
                Button("Save") {
                    if !temporaryWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        workoutName = temporaryWorkoutName.trimmingCharacters(in: .whitespacesAndNewlines)
                        // DB update will happen on Finish or could be done immediately here
                    } else {
                        // Optionally, show an error if name is empty, or just don't save
                        print("Workout name cannot be empty.")
                    }
                    isEditingWorkoutName = false // Dismiss alert
                }
                Button("Cancel", role: .cancel) {
                    isEditingWorkoutName = false // Dismiss alert
                }
            } message: {
                Text("Enter a new name for your workout.")
            }
            // Alert for Finish Workout Error
            .alert("Save Error", isPresented: Binding(get: { finishWorkoutError != nil }, set: { if !$0 { finishWorkoutError = nil } })) {
                Button("OK") { finishWorkoutError = nil } // Dismisses the alert
            } message: {
                Text(finishWorkoutError ?? "An unknown error occurred while saving your workout. Please try again.")
            }
        }
    }

    // Phase 7.3: Finish Workout Logic
    func finishWorkout() async {
        guard let currentWorkoutDbId = currentWorkoutDatabaseId, let userId = try? await client.auth.session.user.id else {
            print("Error finishing workout: Missing workout ID or User ID.")
            DispatchQueue.main.async { finishWorkoutError = "Could not save workout. Missing critical data." }
            return
        }
        isFinishingWorkout = true
        finishWorkoutError = nil // Clear previous errors

        struct WorkoutSetPayload: Encodable {
            let workout_exercise_id: UUID
            let set_number: Int
            let weight: Double
            let reps: Int
            let user_id: UUID
            // let rest_seconds: Int? // Add if you track this
        }

        var setsToInsert: [WorkoutSetPayload] = []

        for exercise in selectedExercisesForWorkout {
            guard let workoutExerciseId = workoutExerciseDbIds[exercise.id] else {
                print("Warning: Missing workout_exercise_id for exercise \(exercise.name). Sets for this exercise will not be saved.")
                continue // Skip sets for this exercise if its link ID is missing
            }

            if let setsForExercise = workoutSets[exercise.id] {
                for (index, setInput) in setsForExercise.enumerated() {
                    if setInput.isCompleted, 
                       let weight = Double(setInput.weight), weight > 0,
                       let reps = Int(setInput.reps), reps > 0 {
                        
                        setsToInsert.append(
                            WorkoutSetPayload(
                                workout_exercise_id: workoutExerciseId,
                                set_number: index + 1,
                                weight: weight,
                                reps: reps,
                                user_id: userId
                            )
                        )
                    } else {
                        print("Skipping incomplete or invalid set \(index + 1) for \(exercise.name)")
                    }
                }
            }
        }

        do {
            if !setsToInsert.isEmpty {
                try await client.database.from("workout_sets").insert(setsToInsert).execute()
                print("Successfully inserted \(setsToInsert.count) sets.")
            }

            // Update the workout record with end_time (and potentially notes)
            struct WorkoutUpdatePayload: Encodable {
                let notes: String // Use current workoutName for notes
                let end_time: Date 
            }
            let updatePayload = WorkoutUpdatePayload(notes: workoutName, end_time: Date())
            try await client.database.from("workouts").update(updatePayload).eq("id", value: currentWorkoutDbId).execute()
            print("Successfully updated workout with end_time and notes: \(workoutName).")

            // Reset state after successful save
            DispatchQueue.main.async {
                self.stopTimer()
                self.isWorkoutStarted = false
                self.startTime = nil
                self.elapsedTime = 0
                self.currentWorkoutDatabaseId = nil
                self.selectedExercisesForWorkout = []
                self.workoutSets = [:]
                self.previousPerformances = [:]
                self.workoutExerciseDbIds = [:]
                self.workoutName = "Afternoon Workout" // Reset to default
                self.workoutSuccessfullySaved = true
                self.isFinishingWorkout = false
            }

        } catch {
            print("Error finishing workout: \(error.localizedDescription)")
            print("Full error details: \(error)")
            DispatchQueue.main.async {
                self.finishWorkoutError = "Failed to save workout: \(error.localizedDescription)" // Set error for alert
                self.isFinishingWorkout = false
            }
        }
    }

    // Phase 7.2: Function to add an exercise to the current workout in DB
    func addExerciseToCurrentWorkoutInDatabase(exercise: Exercise) async {
        guard let currentWorkoutDbId = currentWorkoutDatabaseId else {
            print("Error: Cannot add exercise to DB. currentWorkoutDatabaseId is nil.")
            return
        }
        guard let userId = try? await client.auth.session.user.id else {
            print("Error: Cannot add exercise to DB. User not authenticated.")
            return
        }

        struct WorkoutExerciseInsert: Encodable {
            let workout_id: UUID
            let exercise_id: UUID
            let user_id: UUID
            let order_index: Int
        }
        struct WorkoutExerciseResponse: Decodable { 
            let id: UUID
        }

        // Determine order_index. Since the exercise has just been added to selectedExercisesForWorkout,
        // its index should be the last one.
        let orderIndex = selectedExercisesForWorkout.firstIndex(where: { $0.id == exercise.id }) ?? (selectedExercisesForWorkout.count > 0 ? selectedExercisesForWorkout.count - 1 : 0)

        let payload = WorkoutExerciseInsert(
            workout_id: currentWorkoutDbId,
            exercise_id: exercise.id,
            user_id: userId,
            order_index: orderIndex // Corrected and simplified
        )

        do {
            let newWorkoutExerciseResponse: [WorkoutExerciseResponse] = try await client.database
                .from("workout_exercises")
                .insert(payload, returning: .representation)
                .select("id")
                .execute()
                .value

            if let firstResponse = newWorkoutExerciseResponse.first {
                DispatchQueue.main.async {
                    workoutExerciseDbIds[exercise.id] = firstResponse.id
                    print("Successfully added exercise '\(exercise.name)' to workout, workout_exercise_id: \(firstResponse.id)")
                }
            } else {
                print("Failed to decode workout_exercise response or response was empty for exercise: \(exercise.name)")
            }
        } catch {
            print("Error inserting workout_exercise for '\(exercise.name)': \(error.localizedDescription)")
            print("Full error: \(error)")
        }
    }

    // Phase 7: Function to create the workout in the database, now returns UUID?
    func createNewWorkoutInDatabase() async -> UUID? {
        guard let userId = try? await client.auth.session.user.id else {
            print("Cannot create workout: User not authenticated.")
            return nil
        }
        
        let workoutDate = Date() 
        struct WorkoutInsert: Encodable {
            let user_id: UUID
            let date: Date
            let notes: String // Using workoutName as initial notes
        }
        struct WorkoutResponse: Decodable {
            let id: UUID
            // Include other fields if needed, e.g., date from server if preferred
        }
        let payload = WorkoutInsert(user_id: userId, date: workoutDate, notes: workoutName)

        do {
            let newWorkoutResponse: [WorkoutResponse] = try await client.database
                .from("workouts")
                .insert(payload, returning: .representation)
                .select("id")
                .execute()
                .value
            
            if let firstWorkout = newWorkoutResponse.first {
                print("Successfully created workout with DB ID: \(firstWorkout.id)")
                return firstWorkout.id // Return the ID
            } else {
                 print("Failed to decode workout response or response was empty.")
                 return nil
            }
        } catch {
            print("Error creating new workout in database: \(error.localizedDescription)")
            print("Full error details: \(error)")
            return nil
        }
    }

    func addSet(for exerciseId: UUID) {
        workoutSets[exerciseId, default: []].append(WorkoutSetInput())
    }

    // Phase 6: Function to fetch previous performance
    func fetchPreviousPerformance(for exerciseId: UUID) async {
        guard let userId = try? await client.auth.session.user.id else {
            print("Cannot fetch previous performance: User not authenticated.")
            DispatchQueue.main.async { previousPerformances[exerciseId] = nil }
            return
        }

        struct RpcParams: Encodable {
            let p_exercise_id: UUID
            let p_user_id: UUID
        }

        do {
            let params = RpcParams(p_exercise_id: exerciseId, p_user_id: userId)
            let result: [PreviousSetData] = try await client.rpc(
                "get_previous_performance", 
                params: params
            )
            .execute()
            .value
            
            DispatchQueue.main.async {
                if let firstResult = result.first { 
                    previousPerformances[exerciseId] = firstResult
                } else {
                    previousPerformances[exerciseId] = nil 
                }
            }
        } catch {
            print("Error fetching previous performance for exercise \(exerciseId): \(error)")
            DispatchQueue.main.async {
                previousPerformances[exerciseId] = nil 
            }
        }
    }

    func startTimer() {
        // Invalidate any existing timer
        timerSubscription?.cancel()
        
        guard let validStartTime = startTime else { return }

        timerSubscription = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { _ in
            elapsedTime = Date().timeIntervalSince(validStartTime)
        }
    }

    func stopTimer() {
        timerSubscription?.cancel()
        timerSubscription = nil
    }

    // Phase 7: Cancel Workout Logic
    func cancelWorkoutConfirmed() async {
        print("Cancel workout confirmed.")
        stopTimer()
        
        if let workoutIdToCancel = currentWorkoutDatabaseId {
            await deleteWorkoutFromDatabase(workoutId: workoutIdToCancel)
        }
        
        // Reset state on main thread
        DispatchQueue.main.async {
            isWorkoutStarted = false
            startTime = nil
            elapsedTime = 0
            currentWorkoutDatabaseId = nil
            selectedExercisesForWorkout = []
            workoutSets = [:]
            previousPerformances = [:]
            workoutExerciseDbIds = [:]
            workoutName = "Afternoon Workout" // Reset to default
            isFinishingWorkout = false // Ensure this is reset if cancellation happens during a finish attempt
            isStartingWorkout = false // Ensure this is reset
            workoutSuccessfullySaved = false // Clear any pending save success message
        }
    }

    func deleteWorkoutFromDatabase(workoutId: UUID) async {
        print("Attempting to delete workout ID: \(workoutId) from database.")
        do {
            try await client.database.from("workouts").delete().eq("id", value: workoutId).execute()
            print("Successfully deleted workout ID: \(workoutId) from database.")
        } catch {
            print("Error deleting workout ID: \(workoutId) from database: \(error.localizedDescription)")
            // Optionally, inform the user that cleanup might have failed but proceed with UI reset.
        }
    }
}

// Preview might need adjustment as the view evolves
struct LogWorkoutView_Previews: PreviewProvider {
    static var previews: some View {
        LogWorkoutView()
    }
} 
