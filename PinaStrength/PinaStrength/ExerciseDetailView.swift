import SwiftUI
import Supabase
// If you decide to use the new Charts framework, you might need:
// import Charts 

// MARK: - Helper Data Structures for Detail View

struct WorkoutSetHistoryItem: Identifiable, Decodable, Hashable {
    let id: UUID // workout_sets.id
    let workoutId: UUID // workouts.id
    let workoutDate: Date
    let workoutNotes: String?
    let setNumber: Int
    let weight: Double
    let reps: Int
    let restSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case workoutDate = "workout_date"
        case workoutNotes = "workout_notes"
        case setNumber = "set_number"
        case weight
        case reps
        case restSeconds = "rest_seconds"
    }

    // Calculated property for Est. 1RM (Brzycki formula)
    var estimatedOneRepMax: Double {
        guard reps > 0 else { return weight } // Avoid division by zero or nonsensical calculation for 0 reps
        guard reps < 37 else { return 0 } // Formula becomes less accurate and can yield negative/weird results for very high reps
        return weight / (1.0278 - (0.0278 * Double(reps)))
    }
}

// MARK: - ViewModel

@MainActor // Ensure UI updates are on the main thread
class ExerciseDetailViewModel: ObservableObject {
    @Published var exerciseHistory: [WorkoutSetHistoryItem] = []
    @Published var isLoadingHistory: Bool = true
    @Published var historyError: String? = nil

    private let exerciseID: UUID
    private let client = SupabaseManager.shared.client

    init(exerciseID: UUID) {
        self.exerciseID = exerciseID
    }

    func fetchExerciseHistory() async {
        isLoadingHistory = true
        historyError = nil
        
        guard let userId = try? await client.auth.session.user.id else {
            historyError = "User not authenticated."
            isLoadingHistory = false
            return
        }

        struct RpcParams: Encodable {
            let ex_id: UUID
            let uid: UUID
        }

        do {
            let params = RpcParams(ex_id: self.exerciseID, uid: userId)
            let fetchedData: [WorkoutSetHistoryItem] = try await client.rpc(
                "get_exercise_history",
                 params: params
            )
            .execute()
            .value
            
            let sortedHistory = fetchedData.sorted {
                if $0.workoutDate != $1.workoutDate {
                    return $0.workoutDate > $1.workoutDate
                } else {
                    return $0.setNumber < $1.setNumber
                }
            }
            self.exerciseHistory = sortedHistory
            self.isLoadingHistory = false
        } catch {
            self.historyError = error.localizedDescription
            self.isLoadingHistory = false
            print("Error fetching exercise history via RPC: \(error)")
        }
    }
}

// MARK: - Main Detail View Enum for Tabs

enum ExerciseDetailTab: String, CaseIterable, Identifiable {
    case about = "About"
    case history = "History"
    case charts = "Charts"
    case records = "Records"
    var id: String { self.rawValue }
}

// MARK: - Main Exercise Detail View

struct ExerciseDetailView: View {
    @Environment(\.dismiss) var dismiss
    let exercise: Exercise // Passed in from ExercisesView

    @StateObject private var viewModel: ExerciseDetailViewModel
    @State private var selectedTab: ExerciseDetailTab = .about
    
    init(exercise: Exercise) {
        self.exercise = exercise
        _viewModel = StateObject(wrappedValue: ExerciseDetailViewModel(exerciseID: exercise.id))
    }

    var body: some View {
        NavigationView { // NavigationView for the modal's own title and potential toolbar items
            VStack(spacing: 0) {
                Picker("Select Tab", selection: $selectedTab) {
                    ForEach(ExerciseDetailTab.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case .about:
                        AboutTabView(exercise: exercise)
                    case .history:
                        HistoryTabView(history: viewModel.exerciseHistory, isLoading: viewModel.isLoadingHistory, error: viewModel.historyError)
                    case .charts:
                        ChartsTabView(history: viewModel.exerciseHistory, isLoading: viewModel.isLoadingHistory, error: viewModel.historyError)
                    case .records:
                        RecordsTabView(history: viewModel.exerciseHistory, isLoading: viewModel.isLoadingHistory, error: viewModel.historyError)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.fetchExerciseHistory()
            }
        }
    }
}

// MARK: - About Tab

struct AboutTabView: View {
    let exercise: Exercise

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Placeholder for Exercise Image
                // Image(systemName: "photo") // Or fetch an actual image if URL is available
                //     .resizable()
                //     .scaledToFit()
                //     .frame(height: 200)
                //     .cornerRadius(10)
                //     .padding(.bottom)
                Text("Image Placeholder")
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    .padding(.bottom)

                if let bodyPart = exercise.bodyPart, !bodyPart.isEmpty {
                    HStack {
                        Text("Body Part:").fontWeight(.semibold)
                        Text(bodyPart)
                    }
                }
                if let category = exercise.category, !category.isEmpty {
                    HStack {
                        Text("Category:").fontWeight(.semibold)
                        Text(category)
                    }
                }
                if let equipment = exercise.equipment, !equipment.isEmpty {
                     HStack {
                        Text("Equipment:").fontWeight(.semibold)
                        Text(equipment)
                    }
                }

                Text("Instructions").font(.title2).fontWeight(.semibold)
                if let instructions = exercise.instructions, !instructions.isEmpty {
                    // Attempt to number lines if instructions are newline separated
                    let instructionLines = instructions.split(whereSeparator: \.isNewline)
                    if !instructionLines.isEmpty {
                        ForEach(instructionLines.indices, id: \.self) { index in
                            Text("\(index + 1). \(instructionLines[index])")
                                .padding(.bottom, 2)
                        }
                    } else {
                         Text(instructions) // Fallback if not easily splittable or single line
                    }
                } else {
                    Text("No instructions provided for this exercise.")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

// MARK: - History Tab (Polished States)

struct HistoryTabView: View {
    let history: [WorkoutSetHistoryItem]
    let isLoading: Bool
    let error: String?

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading History...")
                    Spacer()
                }
            } else if let error {
                VStack {
                    Spacer()
                    Text("Failed to load history: \(error)")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else if history.isEmpty {
                VStack {
                    Spacer()
                    Text("No History Yet")
                        .font(.headline)
                        .padding(.bottom, 5)
                    Text("Perform this exercise to see your history here.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(Dictionary(grouping: history, by: { $0.workoutDate }).sorted(by: { $0.key > $1.key }), id: \.key) { date, setsInWorkout in
                        Section(header: Text("\(date, style: .date) - \(setsInWorkout.first?.workoutNotes ?? "No notes")")) {
                            ForEach(setsInWorkout) { setItem in
                                HStack {
                                    Text("Set \(setItem.setNumber):")
                                    Spacer()
                                    Text("\(String(format: "%.1f", setItem.weight)) lbs x \(setItem.reps) reps")
                                    if let rest = setItem.restSeconds {
                                        Text(" (\(rest)s rest)")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Charts Tab (Polished States)

struct ChartsTabView: View {
    let history: [WorkoutSetHistoryItem]
    let isLoading: Bool
    let error: String?

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading Chart Data...")
                    Spacer()
                }
            } else if let error {
                VStack {
                    Spacer()
                    Text("Failed to load chart data: \(error)")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else if history.isEmpty {
                VStack {
                    Spacer()
                    Text("No Chart Data Yet")
                        .font(.headline)
                        .padding(.bottom, 5)
                    Text("Perform this exercise multiple times to see your progress charted here.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        chartSection(title: "Best Set (Est. 1RM)", dataPoints: processForBestSet1RM())
                        chartSection(title: "Max Weight Lifted", dataPoints: processForMaxWeight())
                        chartSection(title: "Total Volume", dataPoints: processForTotalVolume())
                    }
                    .padding()
                }
            }
        }
    }

    private func chartSection(title: String, dataPoints: [(Date, Double)]) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            if dataPoints.count < 2 { 
                Text("Not enough data for chart.")
                    .foregroundColor(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Text("Chart Placeholder for \(title) - \(dataPoints.count) data points")
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                    .overlay( Text("Data: \(dataPoints.map { "(\($0.0.formatted(date: .numeric, time: .omitted)), \(String(format: "%.1f", $0.1)))" }.joined(separator: ", "))").font(.caption2).padding(5), alignment: .bottomLeading)
            }
        }
    }
    
    private func processForBestSet1RM() -> [(Date, Double)] {
        Dictionary(grouping: history, by: { Calendar.current.startOfDay(for: $0.workoutDate) })
            .mapValues { setsInDay in
                setsInDay.map { $0.estimatedOneRepMax }.max() ?? 0
            }
            .sorted(by: { $0.key < $1.key })
            .map { ($0.key, $0.value) }
    }

    private func processForMaxWeight() -> [(Date, Double)] {
        Dictionary(grouping: history, by: { Calendar.current.startOfDay(for: $0.workoutDate) })
            .mapValues { setsInDay in
                setsInDay.map { $0.weight }.max() ?? 0
            }
            .sorted(by: { $0.key < $1.key })
            .map { ($0.key, $0.value) }
    }

    private func processForTotalVolume() -> [(Date, Double)] {
        Dictionary(grouping: history, by: { Calendar.current.startOfDay(for: $0.workoutDate) })
            .mapValues { setsInDay in
                setsInDay.reduce(0) { $0 + ($1.weight * Double($1.reps)) }
            }
            .sorted(by: { $0.key < $1.key })
            .map { ($0.key, $0.value) }
    }
}

// MARK: - Records Tab (Polished States)

struct RecordsTabView: View {
    let history: [WorkoutSetHistoryItem]
    let isLoading: Bool
    let error: String?

    struct RepRecord: Identifiable {
        let id = UUID()
        let reps: Int
        var bestPerformance: String
        var predicted1RM: String
    }

    var body: some View {
        Group {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading Records...")
                    Spacer()
                }
            } else if let error {
                VStack {
                    Spacer()
                    Text("Failed to load records: \(error)")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                }
            } else if history.isEmpty {
                // For records, even with no history, we show the table structure with placeholders.
                // So, the "empty" state means showing the table with dashes.
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("No Record Data Yet")
                            .font(.headline)
                            .padding(.bottom, 5)
                        Text("Perform this exercise to see your personal records here.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 20)
                        personalRecordsSection // Will show dashes
                        repRecordsTable      // Will show dashes
                    }
                    .padding()
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        personalRecordsSection
                        repRecordsTable
                    }
                    .padding()
                }
            }
        }
    }

    private var personalRecordsSection: some View {
        VStack(alignment: .leading) {
            Text("Personal Records").font(.title2).fontWeight(.semibold)
            if history.isEmpty {
                Text("Max 1RM (Est.): -").padding(.top, 2)
                Text("Heaviest Set: -").padding(.top, 2)
                Text("Max Volume (Single Set): -").padding(.top, 2)
            } else {
                let max1RM = history.map { $0.estimatedOneRepMax }.max() ?? 0
                let heaviestSet = history.max(by: { $0.weight < $1.weight })
                let maxVolumeSet = history.max(by: { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) })

                Text("Max 1RM (Est.): \(String(format: "%.1f", max1RM)) lbs").padding(.top, 2)
                if let heaviest = heaviestSet {
                    Text("Heaviest Set: \(String(format: "%.1f", heaviest.weight)) lbs x \(heaviest.reps) reps").padding(.top, 2)
                } else {
                    Text("Heaviest Set: -").padding(.top, 2)
                }
                if let maxVol = maxVolumeSet {
                    Text("Max Volume (Single Set): \(String(format: "%.1f", maxVol.weight * Double(maxVol.reps))) lbs (\(String(format: "%.1f", maxVol.weight))x\(maxVol.reps))").padding(.top, 2)
                } else {
                    Text("Max Volume (Single Set): -").padding(.top, 2)
                }
            }
        }
    }

    private var repRecordsTable: some View {
        VStack(alignment: .leading) {
            Text("Rep Records").font(.title2).fontWeight(.semibold).padding(.bottom, 5)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
                GridRow {
                    Text("Reps").fontWeight(.bold)
                    Text("Best Performance").fontWeight(.bold)
                    Text("Predicted 1RM").fontWeight(.bold)
                }
                Divider()
                ForEach(1...10, id: \.self) { repCount in
                    let record = getRecord(forReps: repCount)
                    GridRow {
                        Text("\(repCount)")
                        Text(record.bestPerformance)
                        Text(record.predicted1RM)
                    }
                    if repCount < 10 { Divider() }
                }
            }
        }
    }

    private func getRecord(forReps repsTarget: Int) -> RepRecord {
        guard !history.isEmpty else {
            return RepRecord(reps: repsTarget, bestPerformance: "-", predicted1RM: "-")
        }

        let setsForRepTarget = history.filter { $0.reps == repsTarget }
        if let bestSet = setsForRepTarget.max(by: { $0.weight < $1.weight }) {
            return RepRecord(
                reps: repsTarget,
                bestPerformance: "\(String(format: "%.1f", bestSet.weight)) lbs x \(bestSet.reps)",
                predicted1RM: "\(String(format: "%.1f", bestSet.estimatedOneRepMax)) lbs"
            )
        } else {
            return RepRecord(reps: repsTarget, bestPerformance: "-", predicted1RM: "-")
        }
    }
}


// MARK: - Preview (Optional)

// struct ExerciseDetailView_Previews: PreviewProvider {
// static var previews: some View {
//     // You'll need a mock Exercise object to preview this view.
//     // Example:
//     let sampleExercise = Exercise(
//         id: UUID(), 
//         name: "Sample Exercise", 
//         bodyPart: "Chest", 
//         category: "Barbell", 
//         instructions: "1. Do this.\n2. Then do that.", 
//         createdByUser_id: nil,
//         equipment: "Barbell"
//     )
//     ExerciseDetailView(exercise: sampleExercise)
// }
// } 