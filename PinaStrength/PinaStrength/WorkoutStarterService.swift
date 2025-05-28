import SwiftUI
import Combine

// This service will help coordinate starting a workout from a routine.
class WorkoutStarterService: ObservableObject {
    @Published var routineToStart: RoutineListItem? = nil
    @Published var routineExercisesToStart: [RoutineExerciseDetailItem]? = nil // Full details needed for sets

    func requestWorkoutStart(with routine: RoutineListItem, details: [RoutineExerciseDetailItem]) {
        // Set these properties to trigger changes in observers (like LogWorkoutView)
        // Ensure this is called on the main thread if it might be triggered from a background task, though UI actions usually are.
        DispatchQueue.main.async {
            self.routineToStart = routine
            self.routineExercisesToStart = details
            print("WorkoutStarterService: Requested to start workout with routine - \(routine.name)")
        }
    }

    func clearWorkoutRequest() {
        DispatchQueue.main.async {
            self.routineToStart = nil
            self.routineExercisesToStart = nil
            print("WorkoutStarterService: Cleared workout request.")
        }
    }
} 