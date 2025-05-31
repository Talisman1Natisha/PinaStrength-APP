import SwiftUI
import Supabase

// MARK: - Data Models for PastWorkoutDetailView

struct PastWorkoutSetDetail: Identifiable, Decodable, Hashable {
    let id: UUID // workout_sets.id
    let setNumber: Int
    let weight: Double
    let reps: Int
    // Add restSeconds if you fetch and display it

    enum CodingKeys: String, CodingKey {
        case id
        case setNumber = "set_number"
        case weight
        case reps
    }
}

struct PastWorkoutExerciseDetail: Identifiable, Decodable, Hashable {
    let id: UUID // workout_exercises.id
    let exerciseId: UUID // exercises.id
    let exerciseName: String
    var sets: [PastWorkoutSetDetail] = [] // To be populated
    let orderIndex: Int?
    // Add notes for workout_exercise if you fetch it

    // Manual conformance to Decodable if not all properties are directly from one table row
    // Or use intermediate structs for decoding from different queries.
    // For now, assuming we can construct this after fetching.
}

// MARK: - Past Workout Detail View

struct PastWorkoutDetailView: View {
    let workoutLogId: UUID
    // Optional: If HistoryView passes the whole WorkoutLogRow, we can use it directly
    // let initialWorkoutLog: WorkoutLogRow? 

    @State private var workoutInfo: WorkoutLogRow? // To store the main workout details
    @State private var exercisesInWorkout: [PastWorkoutExerciseDetail] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    private let client = SupabaseManager.shared.client

    // Formatter for duration (can be copied from HistoryView or put in a shared place)
    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading) {
            if isLoading {
                ProgressView("Loading workout details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let workout = workoutInfo {
                // Header Section for Workout Info
                VStack(alignment: .leading, spacing: 5) {
                    Text(workout.displayName)
                        .font(.largeTitle).fontWeight(.bold)
                    HStack {
                        Image(systemName: "calendar")
                        Text(workout.date, style: .date)
                    }
                    if let duration = workout.duration {
                        HStack {
                            Image(systemName: "clock")
                            Text("Duration: \(formatDuration(duration))")
                        }
                    }
                    if let notes = workout.notes, !notes.isEmpty, notes != workout.displayName {
                        // Show notes only if they are different from the display name (which might be "Workout")
                        // Or if you want to always show notes if they exist.
                        // For now, this condition avoids redundancy if workoutName was used as notes.
                        // Text("Notes: \(notes)").font(.caption).foregroundColor(.gray)
                    }
                }
                .padding()

                Divider()

                if exercisesInWorkout.isEmpty {
                    Text("No exercises found for this workout.")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(exercisesInWorkout.sorted(by: { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) })) { exerciseDetail in
                            Section(header: Text(exerciseDetail.exerciseName).font(.title3).fontWeight(.medium)) {
                                if exerciseDetail.sets.isEmpty {
                                    Text("No sets logged for this exercise.")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                } else {
                                    ForEach(exerciseDetail.sets.sorted(by: { $0.setNumber < $1.setNumber })) { setDetail in
                                        HStack {
                                            Text("Set \(setDetail.setNumber):")
                                            Spacer()
                                            Text("\(String(format: "%.1f", setDetail.weight)) lbs x \(setDetail.reps) reps")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Workout details not found.") // Should ideally not happen if ID is valid
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(workoutInfo?.displayName ?? "Workout Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fetchWorkoutDetails()
        }
    }

    // Helper struct for fetching workout_exercises along with exercise names
    private struct WorkoutExerciseWithName: Decodable, Identifiable {
        let id: UUID // workout_exercises.id
        let exercise_id: UUID
        let order_index: Int?
        let exercises: ExerciseName // Nested struct for exercise name

        struct ExerciseName: Decodable {
            let name: String
        }
    }

    func fetchWorkoutDetails() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let userId = try? await client.auth.session.user.id else {
                errorMessage = "User not authenticated"
                isLoading = false
                return
            }
            
            // Step 1: Fetch the main workout info
            let mainWorkoutDataArray: [WorkoutLogRow] = try await client.database
                .from("workouts")
                .select("id, notes, date, end_time")
                .eq("id", value: workoutLogId)
                .eq("user_id", value: userId)
                .limit(1) // Fetch at most one record
                .execute()
                .value

            let mainWorkoutData: WorkoutLogRow? = mainWorkoutDataArray.first // Get the first element if it exists

            guard let fetchedWorkoutInfo = mainWorkoutData else {
                errorMessage = "Workout not found (ID: \(workoutLogId))."
                isLoading = false
                return
            }
            self.workoutInfo = fetchedWorkoutInfo

            // Step 2: Fetch workout_exercises joined with exercises (for name)
            let workoutExercisesWithName: [WorkoutExerciseWithName] = try await client.database
                .from("workout_exercises")
                .select("id, exercise_id, order_index, exercises(name)") 
                .eq("workout_id", value: workoutLogId)
                .eq("user_id", value: userId)
                .execute()
                .value
            
            var tempExercisesInWorkout: [PastWorkoutExerciseDetail] = []
            for weWithName in workoutExercisesWithName {
                let setsForThisExercise: [PastWorkoutSetDetail] = try await client.database
                    .from("workout_sets")
                    .select("id, set_number, weight, reps")
                    .eq("workout_exercise_id", value: weWithName.id)
                    .eq("user_id", value: userId)
                    .order("set_number", ascending: true)
                    .execute()
                    .value
                let exerciseDetail = PastWorkoutExerciseDetail(id: weWithName.id, exerciseId: weWithName.exercise_id, exerciseName: weWithName.exercises.name, sets: setsForThisExercise, orderIndex: weWithName.order_index)
                tempExercisesInWorkout.append(exerciseDetail)
            }
            DispatchQueue.main.async {
                self.exercisesInWorkout = tempExercisesInWorkout
                self.isLoading = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                print("Error fetching workout details: \(error)")
            }
        }
    }
}

// MARK: - Preview (Requires a valid UUID)

// struct PastWorkoutDetailView_Previews: PreviewProvider {
//     static var previews: some View {
//         NavigationView {
//             // You need a valid UUID of an existing workout from your DB to preview effectively
//             PastWorkoutDetailView(workoutLogId: UUID())
//         }
//     }
// } 