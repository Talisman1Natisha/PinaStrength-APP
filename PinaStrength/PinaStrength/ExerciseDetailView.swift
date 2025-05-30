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

@MainActor
class ExerciseDetailViewModel: ObservableObject {
    @Published var exerciseHistory: [WorkoutSetHistoryItem] = []
    @Published var records: [ExerciseRecord] = []
    @Published var isLoadingHistory: Bool = true
    @Published var isLoadingRecords: Bool = true
    @Published var historyError: String? = nil
    @Published var recordsError: String? = nil
    @Published var selectedTab: ExerciseDetailTab = .about

    private let exerciseID: UUID
    private let client = SupabaseManager.shared.client
    
    struct ExerciseRecord: Identifiable {
        let id = UUID()
        let recordType: String
        let weight: Double
        let reps: Int
        let workoutDate: Date
    }

    init(exerciseID: UUID) {
        self.exerciseID = exerciseID
    }
    
    func fetchAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchExerciseHistory() }
            group.addTask { await self.fetchRecords() }
        }
    }

    func fetchExerciseHistory() async {
        isLoadingHistory = true
        historyError = nil
        
        guard let userId = try? await client.auth.session.user.id else {
            historyError = "User not authenticated."
            isLoadingHistory = false
            return
        }

        struct HistoryParams: Encodable {
            let p_user: UUID
            let p_exercise: UUID
            let p_limit: Int
        }
        
        struct HistoryResponse: Decodable {
            let workout_id: UUID
            let workout_date: Date
            let set_number: Int
            let weight: Double
            let reps: Int
        }

        do {
            let params = HistoryParams(
                p_user: userId,
                p_exercise: exerciseID,
                p_limit: 50
            )
            
            let response: [HistoryResponse] = try await client.rpc(
                "get_exercise_history",
                 params: params
            )
            .execute()
            .value
            
            // Convert to WorkoutSetHistoryItem format
            let historyItems = response.map { item in
                WorkoutSetHistoryItem(
                    id: UUID(), // Generate a unique ID for the view
                    workoutId: item.workout_id,
                    workoutDate: item.workout_date,
                    workoutNotes: nil, // We don't have notes from this RPC
                    setNumber: item.set_number,
                    weight: item.weight,
                    reps: item.reps,
                    restSeconds: nil // We don't have rest seconds from this RPC
                )
            }
            
            self.exerciseHistory = historyItems
            self.isLoadingHistory = false
        } catch {
            self.historyError = error.localizedDescription
            self.isLoadingHistory = false
            print("Error fetching exercise history: \(error)")
        }
    }
    
    func fetchRecords() async {
        isLoadingRecords = true
        recordsError = nil
        
        guard let userId = try? await client.auth.session.user.id else {
            recordsError = "User not authenticated."
            isLoadingRecords = false
            return
        }

        struct RecordsParams: Encodable {
            let p_user: UUID
            let p_exercise: UUID
        }
        
        struct RecordsResponse: Decodable {
            let record_type: String
            let weight: Double
            let reps: Int
            let workout_id: UUID
            let workout_date: Date
        }

        do {
            let params = RecordsParams(
                p_user: userId,
                p_exercise: exerciseID
            )
            
            let response: [RecordsResponse] = try await client.rpc(
                "get_exercise_records",
                params: params
            )
            .execute()
            .value
            
            self.records = response.map { item in
                ExerciseRecord(
                    recordType: item.record_type,
                    weight: item.weight,
                    reps: item.reps,
                    workoutDate: item.workout_date
                )
            }
            self.isLoadingRecords = false
        } catch {
            self.recordsError = error.localizedDescription
            self.isLoadingRecords = false
            print("Error fetching records: \(error)")
        }
    }
}

// MARK: - Main Detail View Enum for Tabs

enum ExerciseDetailTab: String, CaseIterable, Identifiable {
    case about = "About"
    case history = "History"
    case records = "Records"
    var id: String { self.rawValue }
}

// MARK: - Main Exercise Detail View

struct ExerciseDetailView: View {
    @Environment(\.dismiss) var dismiss
    let exercise: Exercise

    @StateObject private var viewModel: ExerciseDetailViewModel
    
    init(exercise: Exercise) {
        self.exercise = exercise
        _viewModel = StateObject(wrappedValue: ExerciseDetailViewModel(exerciseID: exercise.id))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header with exercise name and dismiss button
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(exercise.name)
                            .font(.title2.weight(.bold))
                            .lineLimit(1)
                        
                        if let bodyPart = exercise.bodyPart, let category = exercise.category {
                            Text("\(bodyPart) • \(category)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.gray.opacity(0.6))
                            .background(Circle().fill(Color(.systemBackground)))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                Picker("Select Tab", selection: $viewModel.selectedTab) {
                    ForEach(ExerciseDetailTab.allCases) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 16)

                // Content based on selected tab
                Group {
                    switch viewModel.selectedTab {
                    case .about:
                        AboutTabView(exercise: exercise)
                    case .history:
                        HistoryTabView(
                            history: viewModel.exerciseHistory,
                            isLoading: viewModel.isLoadingHistory,
                            error: viewModel.historyError
                        )
                    case .records:
                        RecordsTabView(
                            records: viewModel.records,
                            history: viewModel.exerciseHistory,
                            isLoading: viewModel.isLoadingRecords,
                            error: viewModel.recordsError
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarHidden(true)
            .task {
                await viewModel.fetchAll()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - About Tab

struct AboutTabView: View {
    let exercise: Exercise
    
    private var iconName: String {
        switch exercise.category?.lowercased() {
        case "barbell": return "figure.strengthtraining.traditional"
        case "dumbbell": return "dumbbell.fill"
        case "cable": return "cable.connector"
        case "machine": return "gearshape.fill"
        case "bodyweight": return "figure.arms.open"
        case "kettlebell": return "figure.strengthtraining.functional"
        case "bands": return "bandage.fill"
        default: return "figure.walk"
        }
    }
    
    private var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "barbell": return .blue
        case "dumbbell": return .purple
        case "cable": return .orange
        case "machine": return .red
        case "bodyweight": return .green
        case "kettlebell": return .indigo
        case "bands": return .pink
        default: return .gray
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Exercise Image Section
                if let imageUrl = exercise.imageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 250)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.2))
                    .frame(maxWidth: .infinity)
                            .frame(height: 250)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(1.5)
                            )
                    }
                } else {
                    // Fallback icon when no image
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: [categoryColor.opacity(0.2), categoryColor.opacity(0.1)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: iconName)
                                .font(.system(size: 60))
                                .foregroundColor(categoryColor)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
                
                // Exercise Details Cards
                VStack(spacing: 16) {
                    if let bodyPart = exercise.bodyPart, !bodyPart.isEmpty {
                        InfoCard(
                            icon: "figure.strengthtraining.traditional",
                            title: "Body Part",
                            value: bodyPart,
                            color: .blue
                        )
                    }
                    
                if let category = exercise.category, !category.isEmpty {
                        InfoCard(
                            icon: "tag.fill",
                            title: "Category",
                            value: category,
                            color: categoryColor
                        )
                    }
                    
                if let equipment = exercise.equipment, !equipment.isEmpty {
                        InfoCard(
                            icon: "dumbbell.fill",
                            title: "Equipment",
                            value: equipment,
                            color: .orange
                        )
                    }
                }

                // Instructions Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "list.number")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text("Instructions")
                            .font(.title2.weight(.bold))
                    }
                    
                if let instructions = exercise.instructions, !instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                    let instructionLines = instructions.split(whereSeparator: \.isNewline)
                    if !instructionLines.isEmpty {
                                ForEach(Array(instructionLines.enumerated()), id: \.offset) { index, line in
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(index + 1)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.white)
                                            .frame(width: 24, height: 24)
                                            .background(Circle().fill(Color.blue))
                                        
                                        Text(String(line))
                                            .font(.body)
                                            .foregroundColor(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                            } else {
                                Text(instructions)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray6))
                                    )
                            }
                    }
                } else {
                    Text("No instructions provided for this exercise.")
                            .font(.body)
                        .foregroundColor(.secondary)
                            .italic()
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [5]))
                            )
                    }
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

// Helper view for info cards
struct InfoCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
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

// MARK: - Records Tab (Polished States)

struct RecordsTabView: View {
    let records: [ExerciseDetailViewModel.ExerciseRecord]
    let history: [WorkoutSetHistoryItem]
    let isLoading: Bool
    let error: String?

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
            } else if records.isEmpty && history.isEmpty {
                VStack {
                    Spacer()
                    Text("No Records Yet")
                        .font(.headline)
                        .padding(.bottom, 5)
                    Text("Perform this exercise to see your personal records here.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Personal Records from backend
                        if !records.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Personal Records")
                                    .font(.title2.weight(.bold))
                                    .padding(.bottom, 8)
                                
                                ForEach(records) { record in
                                    VStack(spacing: 16) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(record.recordType)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                
                                                Text("\(String(format: "%.1f", record.weight)) lbs × \(record.reps) reps")
                                                    .font(.title3.weight(.semibold))
                                                    .foregroundColor(.blue)
                                            }
                                            
                                            Spacer()
                                            
                                            VStack(alignment: .trailing, spacing: 4) {
                                                Image(systemName: "trophy.fill")
                                                    .font(.system(size: 28))
                                                    .foregroundColor(.yellow)
                                                
                                                Text(record.workoutDate, style: .date)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                    }
                    .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(Color(.systemBackground))
                                                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                        )
                                    }
                                }
    }
}

                        // Rep Records Table (from history)
                        if !history.isEmpty {
                            repRecordsTable
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var repRecordsTable: some View {
        VStack(alignment: .leading) {
            Text("Rep Records")
                .font(.title2.weight(.bold))
                .padding(.bottom, 8)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Reps")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 50, alignment: .leading)
                    
                    Text("Best Performance")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Est. 1RM")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                
                // Rows
                ForEach(1...10, id: \.self) { repCount in
                    let record = getRecord(forReps: repCount)
                    
                    HStack {
                        Text("\(repCount)")
                            .font(.body.weight(.medium))
                            .frame(width: 50, alignment: .leading)
                        
                        Text(record.bestPerformance)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(record.predicted1RM)
                            .font(.body.weight(.medium))
                            .foregroundColor(.blue)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(repCount % 2 == 0 ? Color(.systemGray6).opacity(0.3) : Color.clear)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
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
                bestPerformance: "\(String(format: "%.1f", bestSet.weight)) lbs",
                predicted1RM: "\(String(format: "%.1f", bestSet.estimatedOneRepMax)) lbs"
            )
        } else {
            return RepRecord(reps: repsTarget, bestPerformance: "-", predicted1RM: "-")
        }
    }
    
    struct RepRecord: Identifiable {
        let id = UUID()
        let reps: Int
        var bestPerformance: String
        var predicted1RM: String
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