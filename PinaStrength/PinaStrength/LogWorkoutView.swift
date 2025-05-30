import SwiftUI
import Supabase
import Combine // Import Combine for the timer

// MARK: - Shared Data Structs (Moved to top-level for wider access)
// This struct will be used to manage set data in the UI for the current workout session.
struct WorkoutSetInput: Identifiable, Equatable, Hashable {
    let id = UUID() // For ForEach loops
    var weight: String = ""   // Using String for TextField binding
    var reps: String = ""     // Using String for TextField binding
    var isCompleted: Bool = false // For the checkmark UI
    // We can add properties for 'previous' values later (Phase 5/6)
    // var previousWeight: String? = nil 
    // var previousReps: String? = nil

    // Conform to Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Ensure Equatable considers all relevant properties
    static func == (lhs: WorkoutSetInput, rhs: WorkoutSetInput) -> Bool {
        return lhs.id == rhs.id &&
               lhs.weight == rhs.weight &&
               lhs.reps == rhs.reps &&
               lhs.isCompleted == rhs.isCompleted
    }
}

// Struct to hold data from the RPC
struct PreviousSetData: Decodable, Equatable {
    let weight: Double
    let reps: Int
}

// For Custom Keyboard Management (globally accessible)
struct KeyboardTargetInfo: Identifiable {
    let id = UUID() // For Identifiable conformance
    let exerciseId: UUID
    let setId: UUID
    let fieldType: FieldType
}
enum FieldType { case lbs, reps }

// MARK: - Reusable Subviews (ExerciseSetRowView, ExerciseSectionView)
// These might also become top-level or stay here if only LogWorkoutView/ActiveWorkoutSessionView use them directly.
// For now, keeping them in this file for context, but outside LogWorkoutView struct.

// Rest Timer Bar View
struct RestTimerBarView: View {
    let total: TimeInterval
    let remaining: TimeInterval
    var onTap: (() -> Void)? = nil
    
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(.systemGray5))
            GeometryReader { geo in
                Capsule()
                    .fill(Color(.systemBlue).opacity(0.9))
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 1), value: remaining)
            }
            .mask(Capsule())
            Text(timeString)
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)
        }
        .frame(height: 14)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
    
    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(remaining / total)
    }
    
    private var timeString: String {
        let secs = Int(max(remaining, 0))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }
}

// Rest Summary Chip View
struct RestSummaryChipView: View {
    let duration: TimeInterval
    
    var body: some View {
        Text(Self.format(duration))
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.systemGray5)))
            .frame(height: 24)
    }
    
    private static func format(_ t: TimeInterval) -> String {
        let secs = Int(t.rounded())
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}

struct ExerciseSetRowView: View { 
    let exerciseId: UUID 
    let setIndex: Int
    let setInput: WorkoutSetInput 
    let previousSetData: PreviousSetData?
    let activeKeyboardInfo: KeyboardTargetInfo? 
    
    // Timer display properties (received from ExerciseSectionView)
    let isRestTimerGloballyActive: Bool
    let activeRestTimerExerciseId: UUID?
    let lastCompletedSetId: UUID?
    let currentRestTimeRemaining: Int
    let restTimerTotal: Int // Added to track total duration
    let formatRestTime: (Int) -> String
    let completedRestDurations: [UUID: TimeInterval] // Track completed rest durations
    let onShowRestKeyboard: (() -> Void)? // Callback to show rest keyboard
    let onBecameActive: ((UUID) -> Void)? // Callback when row becomes active

    let onRequestKeyboard: (UUID, UUID, FieldType) -> Void
    let onToggleCompletion: (UUID, UUID) -> Void
    let onFillFromPrevious: (UUID, UUID) -> Void

    private var weightPlaceholder: String {
        if setInput.weight.isEmpty, let prevWeight = previousSetData?.weight { return String(format: "%.1f", prevWeight) } 
        return "Lbs"
    }
    private var repsPlaceholder: String {
        if setInput.reps.isEmpty, let prevReps = previousSetData?.reps { return String(prevReps) }
        return "Reps"
    }
    
    private var isRowFocused: Bool {
        guard let activeInfo = activeKeyboardInfo else { return false }
        return activeInfo.exerciseId == self.exerciseId && activeInfo.setId == self.setInput.id
    }
    
    private var rowBackground: Color {
        if setInput.isCompleted { 
            return Color(.systemGreen).opacity(0.12) 
        } else if isRowFocused { 
            return Color(.systemBlue).opacity(0.07) 
        } else { 
            return Color(.systemBackground) 
        }
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            // Card container for the set row
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowBackground)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                
                // Set content
                HStack(spacing: 10) {
                    Text("\(setIndex + 1)")
                        .frame(minWidth: 30, alignment: .leading)
                    
                    Button(action: { onFillFromPrevious(exerciseId, setInput.id) }) {
                        if let prev = previousSetData { 
                            Text("\(String(format: "%.1f", prev.weight)) x \(prev.reps)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else { 
                            Text("-")
                                .font(.caption)
                                .foregroundColor(.gray) 
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .buttonStyle(.plain)
                    
                    Text(setInput.weight.isEmpty ? weightPlaceholder : setInput.weight)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                        .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                        .background(isActiveField(for: .lbs) ? Color.yellow.opacity(0.3) : Color(UIColor.systemGray6))
                        .cornerRadius(6)
                        .foregroundColor(setInput.weight.isEmpty ? .gray : .primary)
                        .onTapGesture { 
                            onRequestKeyboard(exerciseId, setInput.id, .lbs)
                            onBecameActive?(setInput.id)
                        }

                    Text(setInput.reps.isEmpty ? repsPlaceholder : setInput.reps)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                        .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                        .background(isActiveField(for: .reps) ? Color.yellow.opacity(0.3) : Color(UIColor.systemGray6))
                        .cornerRadius(6)
                        .foregroundColor(setInput.reps.isEmpty ? .gray : .primary)
                        .onTapGesture { 
                            onRequestKeyboard(exerciseId, setInput.id, .reps)
                            onBecameActive?(setInput.id)
                        }

                    Image(systemName: setInput.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(setInput.isCompleted ? .green : .gray)
                        .frame(minWidth: 30, alignment: .trailing)
                        .onTapGesture { onToggleCompletion(exerciseId, setInput.id) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Display Rest Timer Bar or Summary Chip
            if let completedDuration = completedRestDurations[setInput.id] {
                // Show rest summary chip for completed rest
                RestSummaryChipView(duration: completedDuration)
                    .transition(.scale.combined(with: .opacity))
                    .onAppear {
                        onBecameActive?(setInput.id)
                    }
            } else if isRestTimerGloballyActive && 
                      activeRestTimerExerciseId == self.exerciseId && 
                      lastCompletedSetId == self.setInput.id {
                // Show active rest timer bar
                RestTimerBarView(
                    total: TimeInterval(restTimerTotal),
                    remaining: TimeInterval(currentRestTimeRemaining),
                    onTap: {
                        onShowRestKeyboard?()
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    onBecameActive?(setInput.id)
                }
            }
        }
        .padding(.horizontal, 4)
        .id(setInput.id) // Important for ScrollViewReader
    }
    
    private func isActiveField(for fieldType: FieldType) -> Bool {
        guard let activeInfo = activeKeyboardInfo else { return false }
        return activeInfo.exerciseId == self.exerciseId && activeInfo.setId == self.setInput.id && activeInfo.fieldType == fieldType
    }
}

struct ExerciseSectionView: View {
    let exercise: Exercise 
    let sets: [WorkoutSetInput] 
    let previousPerformanceForExercise: PreviousSetData?
    let activeKeyboardInfo: KeyboardTargetInfo? 
    
    // Timer display properties (to be passed to ExerciseSetRowView)
    let isRestTimerGloballyActive: Bool
    let activeRestTimerExerciseId: UUID?
    let lastCompletedSetId: UUID?
    let currentRestTimeRemaining: Int
    let restTimerTotal: Int // Added to track total duration
    let formatRestTime: (Int) -> String 
    let completedRestDurations: [UUID: TimeInterval] // Track completed rest durations
    let onShowRestKeyboard: (() -> Void)? // Callback to show rest keyboard
    let onBecameActive: ((UUID) -> Void)? // Callback when row becomes active

    let onAddSet: () -> Void
    let onRequestKeyboard: (UUID, UUID, FieldType) -> Void
    let onToggleCompletion: (UUID, UUID) -> Void
    let onFillFromPrevious: (UUID, UUID) -> Void

    var body: some View {
        Section(header: Text(exercise.name).font(.title3).fontWeight(.medium)) {
            // Column headers
            HStack {
                Text("Set").frame(maxWidth: .infinity, alignment: .leading)
                Text("Previous").frame(maxWidth: .infinity, alignment: .center)
                Text("+lbs").frame(maxWidth: .infinity, alignment: .center)
                Text("Reps").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(maxWidth: .infinity, alignment: .trailing).opacity(0)
            }
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            // Set rows with spacing
            VStack(spacing: 8) {
                ForEach(Array(sets.enumerated()), id: \.element.id) { setIndex, setInputData in
                    ExerciseSetRowView(
                        exerciseId: exercise.id, 
                        setIndex: setIndex, 
                        setInput: setInputData, 
                        previousSetData: previousPerformanceForExercise, 
                        activeKeyboardInfo: activeKeyboardInfo, 
                        // Pass timer info to each row
                        isRestTimerGloballyActive: isRestTimerGloballyActive,
                        activeRestTimerExerciseId: activeRestTimerExerciseId,
                        lastCompletedSetId: lastCompletedSetId,
                        currentRestTimeRemaining: currentRestTimeRemaining,
                        restTimerTotal: restTimerTotal, // Pass total duration
                        formatRestTime: formatRestTime,
                        completedRestDurations: completedRestDurations, // Pass completed durations
                        onShowRestKeyboard: onShowRestKeyboard, // Pass callback
                        onBecameActive: onBecameActive, // Pass callback
                        onRequestKeyboard: onRequestKeyboard,
                        onToggleCompletion: onToggleCompletion,
                        onFillFromPrevious: onFillFromPrevious
                    )
                    .id(setInputData.id)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 12)
            
            // Add set button
            Button(action: onAddSet) {
                HStack { 
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                    Text("Add Set")
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 5)
        }
    }
}

// MARK: - LogWorkoutView (Initiates workout sessions)
struct LogWorkoutView: View {
    @EnvironmentObject var workoutStarterService: WorkoutStarterService
    @StateObject private var routineVM = RoutineGridViewModel()
    private let client = SupabaseManager.shared.client

    struct ActiveWorkoutSessionData: Identifiable {
        let id: UUID // workout_id from DB
        var workoutName: String
        var startTime: Date
        var exercisesToPreload: [RoutineExerciseDetailItem]? // Added
    }
    @State private var presentingWorkoutData: ActiveWorkoutSessionData? = nil
    
    @State private var showWorkoutSavedMessage: Bool = false
    @State private var isStartingWorkout: Bool = false
    @State private var showCreateRoutine: Bool = false
    @State private var showAICoach: Bool = false // Add this state
    
    // Grid layout
    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    // Quick Start Section
                    quickStartSection
                    
                    // AI Coach Section - NEW
                    aiCoachSection
                    
                    // Routines Section
                    if !routineVM.routines.isEmpty {
                        routinesSection
                    } else if !routineVM.isLoading {
                        emptyRoutinesPlaceholder
                    }
                    
                    // Loading indicator
                    if routineVM.isLoading && routineVM.routines.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await routineVM.refresh()
            }
            .onChange(of: workoutStarterService.routineToStart) { routine in
                // Ensure no workout session is already being presented
                guard presentingWorkoutData == nil else {
                    print("LogWorkoutView: Another workout session is already pending or active. Ignoring new routine request.")
                    workoutStarterService.clearWorkoutRequest() // Clear request to prevent re-triggering
                    return
                }

                if let routineToStart = routine, let exercisesToStart = workoutStarterService.routineExercisesToStart {
                    Task {
                        // Find the full routine data from our loaded routines
                        if let fullRoutine = routineVM.routines.first(where: { $0.id == routineToStart.id }) {
                            await startWorkoutFromRoutine(fullRoutine, exercises: exercisesToStart)
                        } else {
                            // If not found in our grid, create a minimal RoutineGridItem
                            let minimalRoutine = RoutineGridItem(
                                id: routineToStart.id,
                                name: routineToStart.name,
                                updatedAt: routineToStart.updatedAt,
                                user_id: UUID(), // This won't be used
                                created_at: Date(), // This won't be used
                                exercises: nil
                            )
                            await startWorkoutFromRoutine(minimalRoutine, exercises: exercisesToStart)
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateRoutine) {
                RoutineEditorView()
            }
            .sheet(isPresented: $showAICoach) {
                AICoachChatView()
                    .environmentObject(workoutStarterService)
                    .environmentObject(TabSelection())
            }
            .onReceive(NotificationCenter.default.publisher(for: .routineChanged)) { _ in
                Task {
                    await routineVM.refresh()
                }
            }
            .overlay(alignment: .bottom) {
                if showWorkoutSavedMessage {
                    savedWorkoutToast
                }
            }
        }
        .fullScreenCover(item: $presentingWorkoutData) { workoutData in
            ActiveWorkoutSessionView(
                workoutId: workoutData.id,
                initialWorkoutName: workoutData.workoutName,
                initialStartTime: workoutData.startTime,
                exercisesToPreload: workoutData.exercisesToPreload, // Pass it through
                onDismiss: { didSave in 
                    if didSave {
                        self.showWorkoutSavedMessage = true
                        // Refresh routines to update last performed dates
                        Task {
                            await routineVM.refresh()
                        }
                    }
                }
            )
        }
    }
    
    // MARK: - View Components
    
    private var quickStartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Start")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Button(action: startEmptyWorkout) {
                Text("Start an Empty Workout")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .disabled(isStartingWorkout)
        }
    }
    
    // AI Coach Section - NEW
    private var aiCoachSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Assistant")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Button(action: { showAICoach = true }) {
                HStack(spacing: 16) {
                    Image(systemName: "message.badge.waveform")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chat with AI Coach")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Get personalized workout plans")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Routines Header
            HStack {
                Text("Routines")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Add Routine Button
                Button(action: { showCreateRoutine = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Routine")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                }
                
                // Menu Button (optional)
                Menu {
                    Button("Sort by Name") { }
                    Button("Sort by Date") { }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
            }
            
            // My Routines count
            Text("My Routines (\(routineVM.routines.count))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Routines Grid
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(routineVM.routines) { routine in
                    RoutineCard(routine: routine) {
                        Task {
                            await routineVM.deleteRoutine(routine.id)
                        }
                    }
                    .onTapGesture {
                        Task {
                            await startWorkoutFromRoutine(routine)
                        }
                    }
                }
            }
        }
    }
    
    private var emptyRoutinesPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routines")
                .font(.headline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                
                Text("No routines yet")
                    .font(.headline)
                
                Text("Create your first routine to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button(action: { showCreateRoutine = true }) {
                    HStack {
                        Image(systemName: "plus")
                        Text("Create Routine")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
    
    private var savedWorkoutToast: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Workout saved successfully!")
                .font(.subheadline.weight(.medium))
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 8)
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    showWorkoutSavedMessage = false
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func startEmptyWorkout() {
        Task {
            isStartingWorkout = true
            let newWorkoutName = "New Workout"
            let newStartTime = Date()
            let workoutId = await createNewWorkoutInDatabase(name: newWorkoutName, date: newStartTime)
            
            if let id = workoutId {
                self.presentingWorkoutData = ActiveWorkoutSessionData(
                    id: id, 
                    workoutName: newWorkoutName, 
                    startTime: newStartTime
                )
            } else {
                print("Failed to create workout in DB. Cannot start session.")
                // TODO: Show an error alert to the user
            }
            isStartingWorkout = false
        }
    }
    
    private func startWorkoutFromRoutine(_ routine: RoutineGridItem, exercises: [RoutineExerciseDetailItem]? = nil) async {
        isStartingWorkout = true
        let newStartTime = Date()
        
        // If exercises aren't provided, fetch them from the routine
        let exercisesToUse: [RoutineExerciseDetailItem]
        if let providedExercises = exercises {
            exercisesToUse = providedExercises
        } else {
            // Fetch exercises from the routine
            exercisesToUse = routine.exercises?.compactMap { routineExercise in
                guard let exercise = routineExercise.exercise else { return nil }
                return RoutineExerciseDetailItem(
                    id: routineExercise.id,
                    exerciseId: exercise.id,
                    exerciseName: exercise.name,
                    orderIndex: routineExercise.orderIndex,
                    setTemplates: [] // TODO: Add set templates support
                )
            } ?? []
        }
        
        // Create the workout in the database using routine name
        let workoutId = await createNewWorkoutInDatabase(name: routine.name, date: newStartTime)
        
        if let id = workoutId {
            // Set the data to present the full-screen cover, passing exercises to preload
            self.presentingWorkoutData = ActiveWorkoutSessionData(
                id: id,
                workoutName: routine.name,
                startTime: newStartTime,
                exercisesToPreload: exercisesToUse
            )
        } else {
            print("Failed to create workout in DB for routine. Cannot start session.")
            // TODO: Show an error alert to the user
        }
        isStartingWorkout = false
        workoutStarterService.clearWorkoutRequest() // Clear request after processing
    }

    func createNewWorkoutInDatabase(name: String, date: Date) async -> UUID? {
        guard let userId = try? await client.auth.session.user.id else {
            print("Cannot create workout: User not authenticated."); return nil
        }
        struct WorkoutInsert: Encodable { let user_id: UUID; let date: Date; let notes: String }
        struct WorkoutResponse: Decodable { let id: UUID }
        let payload = WorkoutInsert(user_id: userId, date: date, notes: name)
        do {
            let newWorkoutResponse: [WorkoutResponse] = try await client
                .from("workouts")
                .insert(payload, returning: .representation)
                .select("id")
                .execute()
                .value
            if let firstWorkout = newWorkoutResponse.first {
                print("Successfully created workout with DB ID: \(firstWorkout.id)")
                return firstWorkout.id
            } else {
                print("Failed to decode workout response or response was empty."); return nil
            }
        } catch {
            print("Error creating new workout: \(error.localizedDescription)"); return nil
        }
    }
}

// MARK: - Preview
struct LogWorkoutView_Previews: PreviewProvider {
    static var previews: some View {
        LogWorkoutView().environmentObject(WorkoutStarterService())
    }
} 
