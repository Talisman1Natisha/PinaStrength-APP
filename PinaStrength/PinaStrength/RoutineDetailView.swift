import SwiftUI
import Supabase

// We can reuse RoutineSetTemplateInput from CreateEditRoutineView.swift
// If it's not in a shared location, we might need to redefine or move it.
// For now, assuming it's accessible or we'll redefine a similar one here.

// MARK: - New Subview for a single Set Template display row
struct RoutineSetTemplateDisplayRow: View {
    let setTemplate: RoutineSetTemplateInput
    let setDisplayNumber: Int

    var body: some View {
        HStack {
            Text("Set \(setDisplayNumber):")
            VStack(alignment: .leading) {
                if let weight = setTemplate.targetWeight, !weight.isEmpty {
                    Text("Weight: \(weight)")
                } else if let reps = setTemplate.targetReps, !reps.isEmpty { // Show something if only reps exist
                    Text("Weight: -") // Placeholder if only reps exist
                }
                
                if let reps = setTemplate.targetReps, !reps.isEmpty {
                    Text("Reps: \(reps)")
                }
                
                if let rest = setTemplate.targetRestSeconds, !rest.isEmpty {
                    Text("Rest: \(rest)s")
                }
                
                if (setTemplate.targetWeight?.isEmpty ?? true) && 
                   (setTemplate.targetReps?.isEmpty ?? true) && 
                   (setTemplate.targetRestSeconds?.isEmpty ?? true) {
                    Text("No targets set").italic().foregroundColor(.gray)
                }
            }
            Spacer() // Push content to left
        }
        .font(.subheadline) // Apply a consistent font for the set details
    }
}

struct RoutineDetailView: View {
    let routine: RoutineListItem // Passed from RoutinesView

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workoutStarterService: WorkoutStarterService // Inject service
    @EnvironmentObject var tabSelection: TabSelection // Inject tab selection

    @State private var routineExercises: [RoutineExerciseDetailItem] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    private let client = SupabaseManager.shared.client

    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter(); formatter.allowedUnits = [.hour, .minute]; formatter.unitsStyle = .abbreviated; return formatter.string(from: interval) ?? ""
    }

    var body: some View {
        NavigationView { // For toolbar with Dismiss button if presented as a sheet
            VStack(alignment: .leading) {
                if isLoading {
                    ProgressView("Loading routine details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red).padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Exercises in \"\(routine.name)\"")
                        .font(.title2).bold()
                        .padding([.horizontal, .top])

                    if routineExercises.isEmpty {
                        Text("No exercises found in this routine.")
                            .foregroundColor(.secondary).padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                // Header Section for Workout Info
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(routine.name).font(.largeTitle).fontWeight(.bold) // Use routine.name directly for header
                                    HStack { Image(systemName: "calendar"); Text(routine.updatedAt, style: .date).font(.caption) } // Show last updated as primary date here
                                }.padding()

                                Divider()

                                ForEach(routineExercises.sorted(by: { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) })) { exerciseItem in
                                    VStack(alignment: .leading) {
                                        Text(exerciseItem.exerciseName).font(.title3).fontWeight(.medium).padding(.top)
                                        if exerciseItem.setTemplates.isEmpty {
                                            Text("No set templates defined.").font(.caption).foregroundColor(.gray).padding(.bottom)
                                        } else {
                                            ForEach(Array(exerciseItem.setTemplates.enumerated()), id: \.element.id) { index, setTemplate in
                                                RoutineSetTemplateDisplayRow(setTemplate: setTemplate, setDisplayNumber: index + 1)
                                                    .padding(.leading) // Indent sets slightly
                                                    .padding(.vertical, 2)
                                            }
                                            .padding(.bottom)
                                        }
                                    }
                                    .padding(.horizontal)
                                    Divider()
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        workoutStarterService.requestWorkoutStart(with: routine, details: routineExercises)
                        tabSelection.selectedTab = .log // Switch to Log tab
                        dismiss() // Dismiss this detail view
                    }) {
                        Text("Start Workout with this Routine")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding()
                }
            }
            .navigationTitle(routine.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { // Or .navigationBarLeading if presented as fullScreenCover
                    Button("Done") { dismiss() } // If presented as a sheet
                }
            }
            .task {
                await fetchRoutineDetails()
            }
        }
    }

    // Helper for fetching routine_exercises with exercise names
    private struct RoutineExerciseWithName: Decodable, Identifiable {
        let id: UUID // routine_exercises.id
        let exercise_id: UUID
        let order_index: Int?
        let exercises: ExerciseName // Joined data from exercises table
        struct ExerciseName: Decodable { let name: String }
    }

    // Helper for fetching routine_exercise_sets
    // Reusing RoutineSetTemplateInput from CreateEditRoutineView if accessible and matches schema
    // Otherwise, define a local one for decoding.
    // For this example, let's assume RoutineSetTemplateInput is available and matches the DB columns for routine_exercise_sets
    // if not, you'd define a struct like: 
    // struct FetchedSetTemplate: Decodable, Identifiable { let id: UUID, let set_number: Int, let target_reps: String?, ... }

    func fetchRoutineDetails() async {
        isLoading = true
        errorMessage = nil

        do {
            // 1. Fetch routine_exercises joined with exercises (for name)
            let routineExercisesData: [RoutineExerciseWithName] = try await client.database
                .from("routine_exercises")
                .select("id, exercise_id, order_index, exercises(name)") // Foreign key join
                .eq("routine_id", value: routine.id)
                .order("order_index", ascending: true)
                .execute()
                .value
            
            var tempRoutineExercises: [RoutineExerciseDetailItem] = []

            // 2. For each routine_exercise, fetch its set templates
            for reData in routineExercisesData {
                let setTemplatesData: [RoutineSetTemplateInput] = try await client.database
                    .from("routine_exercise_sets")
                    // Ensure selected columns match RoutineSetTemplateInput or create a specific decoding struct
                    .select("id, target_reps, target_weight, target_rest_seconds, set_number") 
                    .eq("routine_exercise_id", value: reData.id)
                    .order("set_number", ascending: true)
                    .execute()
                    .value
                
                // The RoutineSetTemplateInput needs to be decodable with these fields
                // If RoutineSetTemplateInput is not directly decodable from this, map it.
                // For now, assuming direct decodability or that RoutineSetTemplateInput is adapted.
                
                let detailItem = RoutineExerciseDetailItem(
                    id: reData.id,
                    exerciseId: reData.exercise_id,
                    exerciseName: reData.exercises.name,
                    orderIndex: reData.order_index,
                    setTemplates: setTemplatesData
                )
                tempRoutineExercises.append(detailItem)
            }
            
            DispatchQueue.main.async {
                self.routineExercises = tempRoutineExercises
                self.isLoading = false
            }

        } catch {
            DispatchQueue.main.async {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                print("Error fetching routine details: \(error)")
            }
        }
    }
}

// MARK: - Preview
// struct RoutineDetailView_Previews: PreviewProvider {
//     static var previews: some View {
//         RoutineDetailView(routine: RoutineListItem(id: UUID(), name: "Sample Routine", updatedAt: Date()))
//     }
// } 