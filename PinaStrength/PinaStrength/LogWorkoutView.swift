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
    let formatRestTime: (Int) -> String

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

    var body: some View {
        VStack(alignment: .center, spacing: 4) { // Use VStack to stack row and timer
            HStack(spacing: 10) {
                Text("\(setIndex + 1)").frame(minWidth: 30, alignment: .leading)
                Button(action: { onFillFromPrevious(exerciseId, setInput.id) }) {
                    if let prev = previousSetData { Text("\(String(format: "%.1f", prev.weight)) x \(prev.reps)").font(.caption).foregroundColor(.blue)
                    } else { Text("-").font(.caption).foregroundColor(.gray) }
                }.frame(maxWidth: .infinity, alignment: .center).buttonStyle(.plain)
                
                Text(setInput.weight.isEmpty ? weightPlaceholder : setInput.weight)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center).padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                    .background(isActiveField(for: .lbs) ? Color.yellow.opacity(0.3) : Color(UIColor.systemGray6)).cornerRadius(6)
                    .foregroundColor(setInput.weight.isEmpty ? .gray : .primary)
                    .onTapGesture { onRequestKeyboard(exerciseId, setInput.id, .lbs) }

                Text(setInput.reps.isEmpty ? repsPlaceholder : setInput.reps)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center).padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                    .background(isActiveField(for: .reps) ? Color.yellow.opacity(0.3) : Color(UIColor.systemGray6)).cornerRadius(6)
                    .foregroundColor(setInput.reps.isEmpty ? .gray : .primary)
                    .onTapGesture { onRequestKeyboard(exerciseId, setInput.id, .reps) }

                Image(systemName: setInput.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(setInput.isCompleted ? .green : .gray).frame(minWidth: 30, alignment: .trailing)
                    .onTapGesture { onToggleCompletion(exerciseId, setInput.id) }
            }
            //.padding(.vertical, 4) // Padding moved to VStack or managed by List

            // Display Rest Timer below this specific set if it's the one being rested after
            if isRestTimerGloballyActive && 
               activeRestTimerExerciseId == self.exerciseId && 
               lastCompletedSetId == self.setInput.id {
                HStack {
                    //Spacer() // Removed Spacer to allow timer to be more left-aligned or centered as per design
                    Image(systemName: "timer")
                    Text(formatRestTime(currentRestTimeRemaining))
                        .font(.callout) // Slightly smaller than .title3 for in-row display
                        .foregroundColor(.orange)
                        .onTapGesture {
                            // TODO: Phase 2 - Tapping timer could open adjustment options
                            print("Timer tapped for set \(setInput.id) of exercise \(exerciseId)")
                        }
                    //Spacer()
                }
                .padding(.top, 2) // Small padding to separate from the set row above
            }
        }
        .padding(.vertical, 4) // Apply vertical padding to the whole VStack cell
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
    let formatRestTime: (Int) -> String 

    let onAddSet: () -> Void
    let onRequestKeyboard: (UUID, UUID, FieldType) -> Void
    let onToggleCompletion: (UUID, UUID) -> Void
    let onFillFromPrevious: (UUID, UUID) -> Void

    var body: some View {
        Section(header: Text(exercise.name).font(.title3).fontWeight(.medium)) {
            HStack {
                Text("Set").frame(maxWidth: .infinity, alignment: .leading)
                Text("Previous").frame(maxWidth: .infinity, alignment: .center)
                Text("+lbs").frame(maxWidth: .infinity, alignment: .center)
                Text("Reps").frame(maxWidth: .infinity, alignment: .center)
                Image(systemName: "checkmark").frame(maxWidth: .infinity, alignment: .trailing).opacity(0)
            }.font(.caption).foregroundColor(.gray).padding(.vertical, 2)

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
                    formatRestTime: formatRestTime,
                    onRequestKeyboard: onRequestKeyboard,
                    onToggleCompletion: onToggleCompletion,
                    onFillFromPrevious: onFillFromPrevious
                ).id(setInputData.id)
            }
            Button(action: onAddSet) {
                HStack { Spacer(); Image(systemName: "plus.circle.fill"); Text("Add Set"); Spacer() }
            }.buttonStyle(.borderless).padding(.vertical, 5)
        }
    }
}

// MARK: - LogWorkoutView (Initiates workout sessions)
struct LogWorkoutView: View {
    @EnvironmentObject var workoutStarterService: WorkoutStarterService
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

    var body: some View {
        NavigationView {
            VStack {
                Text("Workout Templates/Quick Start (Future UI)")
                    .font(.title2)
                    .padding()
                
                Spacer()
                
                if isStartingWorkout {
                    ProgressView("Preparing Workout...")
                } else {
                    Button("Start an Empty Workout") {
                        Task {
                            isStartingWorkout = true
                            let newWorkoutName = "New Workout" 
                            let newStartTime = Date()
                            let workoutId = await createNewWorkoutInDatabase(name: newWorkoutName, date: newStartTime)
                            
                            if let id = workoutId {
                                self.presentingWorkoutData = ActiveWorkoutSessionData(id: id, workoutName: newWorkoutName, startTime: newStartTime)
                            } else {
                                print("Failed to create workout in DB. Cannot start session.")
                                // TODO: Show an error alert to the user
                            }
                            isStartingWorkout = false
                        }
                    }
                    .font(.headline).padding().frame(maxWidth: .infinity).background(Color.blue).foregroundColor(.white).cornerRadius(10).padding(.horizontal, 40)
                }
                Spacer()
                
                if showWorkoutSavedMessage {
                    Text("Workout saved successfully!")
                        .foregroundColor(.green).padding()
                        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showWorkoutSavedMessage = false } }
                }
            }
            .navigationTitle("Start Workout")
            .onChange(of: workoutStarterService.routineToStart) { routine in
                // Ensure no workout session is already being presented
                guard presentingWorkoutData == nil else {
                    print("LogWorkoutView: Another workout session is already pending or active. Ignoring new routine request.")
                    workoutStarterService.clearWorkoutRequest() // Clear request to prevent re-triggering
                    return
                }

                if let routineToStart = routine, let exercisesToStart = workoutStarterService.routineExercisesToStart {
                    Task {
                        isStartingWorkout = true // Show progress indicator
                        let newStartTime = Date()
                        // Create the workout in the database using routine name
                        let workoutId = await createNewWorkoutInDatabase(name: routineToStart.name, date: newStartTime)
                        
                        if let id = workoutId {
                            // Set the data to present the full-screen cover, passing exercises to preload
                            self.presentingWorkoutData = ActiveWorkoutSessionData(
                                id: id, 
                                workoutName: routineToStart.name, 
                                startTime: newStartTime,
                                exercisesToPreload: exercisesToStart // Pass the exercises
                            )
                        } else {
                            print("Failed to create workout in DB for routine. Cannot start session.")
                            // TODO: Show an error alert to the user
                        }
                        isStartingWorkout = false
                        workoutStarterService.clearWorkoutRequest() // Clear request after processing
                    }
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
                    }
                }
            )
        }
    }

    func createNewWorkoutInDatabase(name: String, date: Date) async -> UUID? {
        guard let userId = try? await client.auth.session.user.id else {
            print("Cannot create workout: User not authenticated."); return nil
        }
        struct WorkoutInsert: Encodable { let user_id: UUID; let date: Date; let notes: String }
        struct WorkoutResponse: Decodable { let id: UUID }
        let payload = WorkoutInsert(user_id: userId, date: date, notes: name)
        do {
            let newWorkoutResponse: [WorkoutResponse] = try await client.database.from("workouts").insert(payload, returning: .representation).select("id").execute().value
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
