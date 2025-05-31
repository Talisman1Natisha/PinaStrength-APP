import SwiftUI

struct AICoachChatView: View {
    @StateObject private var vm = AICoachViewModel()
    @State private var input = ""
    @FocusState private var isInputFocused: Bool
    @EnvironmentObject var workoutStarterService: WorkoutStarterService
    @EnvironmentObject var tabSelection: TabSelection
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Error banner
                if vm.hasError {
                    ErrorBanner(
                        message: vm.errorMessage,
                        isOffline: vm.isOffline,
                        onRetry: {
                            Task {
                                await vm.retryLastMessage()
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Array(vm.messages.enumerated()), id: \.offset) { index, msg in
                                ChatBubble(message: msg, viewModel: vm)
                                    .id(index)
                            }
                            
                            if vm.isThinking {
                                ThinkingIndicator()
                                    .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: vm.messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(vm.messages.count - 1, anchor: .bottom)
                        }
                    }
                    .onChange(of: vm.isThinking) { thinking in
                        if thinking {
                            withAnimation {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Input area
                HStack(spacing: 12) {
                    TextField("Ask me anything about fitness...", text: $input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemGray6))
                        )
                        .focused($isInputFocused)
                        .onSubmit {
                            if !input.isEmpty && !vm.isThinking {
                                Task {
                                    await vm.send(input)
                                    input = ""
                                }
                            }
                        }
                    
                    Button(action: {
                        if !input.isEmpty && !vm.isThinking {
                            Task {
                                await vm.send(input)
                                input = ""
                            }
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(input.isEmpty || vm.isThinking ? .gray : .blue)
                    }
                    .disabled(input.isEmpty || vm.isThinking)
                }
                .padding()
            }
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        vm.clearConversation()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                isInputFocused = true
            }
        }
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    let isOffline: Bool
    let onRetry: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: onRetry) {
                Text("Retry")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.red)
    }
}

// MARK: - Chat Bubble View
struct ChatBubble: View {
    let message: AIMessage
    let viewModel: AICoachViewModel
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }
            
            content
            
            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch message.type {
        case .user(let text):
            Text(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(20)
                .contextMenu {
                    Button(action: {
                        UIPasteboard.general.string = text
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            
        case .assistantText(let text):
            Text(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(20)
                .contextMenu {
                    Button(action: {
                        UIPasteboard.general.string = text
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            
        case .error(let text):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text(text)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(20)
            
        case .routine(let routine):
            AIRoutineCard(routine: routine, viewModel: viewModel)
            
        case .recovery(let plan):
            RecoveryPlanCard(plan: plan)
        }
    }
}

// MARK: - Recovery Plan Card
struct RecoveryPlanCard: View {
    let plan: RecoveryPlan
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.headline)
                    Text(plan.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            
            Divider()
            
            // Activities list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(plan.activities.enumerated()), id: \.offset) { index, activity in
                    HStack(alignment: .top) {
                        Image(systemName: iconForActivity(activity.type))
                            .font(.caption)
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                                .font(.subheadline.weight(.medium))
                            Text(activity.duration)
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text(activity.instructions)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    private func iconForActivity(_ type: RecoveryActivityType) -> String {
        switch type {
        case .stretch: return "figure.flexibility"
        case .rest: return "bed.double.fill"
        case .mobility: return "figure.walk"
        case .foam_roll: return "circle.grid.2x2.fill"
        }
    }
}

// MARK: - Routine Card for AI-generated routines
struct AIRoutineCard: View {
    let routine: AIRoutineResponse
    let viewModel: AICoachViewModel
    @EnvironmentObject var workoutStarterService: WorkoutStarterService
    @EnvironmentObject var tabSelection: TabSelection
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(.headline)
                    Text("\(routine.exercises.count) exercises")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.yellow)
            }
            
            Divider()
            
            // Exercise list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(routine.exercises.prefix(3).enumerated()), id: \.offset) { index, exercise in
                    HStack {
                        Text("\(index + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.subheadline.weight(.medium))
                            Text("\(exercise.sets) sets × \(exercise.reps) reps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let equipment = exercise.equipment {
                            Text(equipment)
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(.systemGray5)))
                        }
                    }
                }
                
                if routine.exercises.count > 3 {
                    Text("+ \(routine.exercises.count - 3) more exercises")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            Divider()
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    // Start workout immediately
                    Task {
                        await startWorkoutFromAIRoutine(routine)
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Now")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                
                Button(action: {
                    // Save as routine
                    Task {
                        await saveAIRoutineAsTemplate(routine)
                    }
                }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue, lineWidth: 1.5)
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    // Helper functions for starting workout and saving routine
    private func startWorkoutFromAIRoutine(_ routine: AIRoutineResponse) async {
        // First, we need to match AI exercise names to database exercises
        let supabase = SupabaseManager.shared.client
        
        do {
            guard let userId = try? await supabase.auth.session.user.id else {
                print("User not authenticated")
                return
            }
            
            // Fetch global exercises and user's custom exercises with complete data
            let allExercises: [Exercise] = try await supabase
                .from("exercises")
                .select("*") // Fetch all fields including imageUrl, instructions, bodyPart, etc.
                .or("is_global.eq.true,created_by_user_id.eq.\(userId)")
                .execute()
                .value
            
            // Match AI exercise names to database exercises
            var matchedExercises: [(exercise: Exercise, aiInfo: AIRoutineResponse.AIExercise)] = []
            var unmatchedExercises: [String] = []
            
            for aiExercise in routine.exercises {
                // Try exact match first
                if let matched = allExercises.first(where: { 
                    $0.name.lowercased() == aiExercise.name.lowercased() 
                }) {
                    matchedExercises.append((matched, aiExercise))
                } else {
                    // Try partial match
                    if let matched = allExercises.first(where: { 
                        $0.name.lowercased().contains(aiExercise.name.lowercased()) ||
                        aiExercise.name.lowercased().contains($0.name.lowercased())
                    }) {
                        matchedExercises.append((matched, aiExercise))
                    } else {
                        unmatchedExercises.append(aiExercise.name)
                    }
                }
            }
            
            // If we have unmatched exercises, show a message but continue
            if !unmatchedExercises.isEmpty {
                print("Some exercises couldn't be matched: \(unmatchedExercises.joined(separator: ", "))")
            }
            
            // Create workout with matched exercises
            if !matchedExercises.isEmpty {
                // Convert to RoutineExerciseDetailItem format with set templates
                let exerciseDetails = matchedExercises.enumerated().map { index, match in
                    // Create set templates based on AI recommendation
                    let setTemplates = (0..<match.aiInfo.sets).map { setIndex in
                        RoutineSetTemplateInput(
                            id: UUID(),
                            routineExerciseId: UUID(), // Temporary UUID for AI-generated routines
                            userId: UUID(), // Temporary UUID for AI-generated routines
                            setNumber: setIndex + 1,
                            targetReps: String(match.aiInfo.reps),
                            targetWeight: nil, // User will fill this in
                            targetRestSeconds: "90" // Default rest time
                        )
                    }
                    
                    return RoutineExerciseDetailItem(
                        id: UUID(),
                        routineId: UUID(), // Temporary UUID for AI-generated routines
                        exerciseId: match.exercise.id,
                        exerciseName: match.exercise.name,
                        userId: UUID(), // Temporary UUID for AI-generated routines
                        orderIndex: index,
                        setTemplates: setTemplates
                    )
                }
                
                // Create a temporary routine
                let tempRoutine = RoutineListItem(
                    id: UUID(),
                    userId: UUID(), // Temporary UUID for AI-generated routines
                    name: routine.name,
                    description: nil,
                    updatedAt: Date()
                )
                
                // Use WorkoutStarterService to start the workout
                workoutStarterService.requestWorkoutStart(with: tempRoutine, details: exerciseDetails)
                tabSelection.selectedTab = .log
                
                // Add a success message before dismissing
                if unmatchedExercises.isEmpty {
                    print("Starting workout with all \(matchedExercises.count) exercises!")
                } else {
                    print("Starting workout with \(matchedExercises.count) exercises. \(unmatchedExercises.count) exercises couldn't be found.")
                }
                
                dismiss()
            } else {
                // No exercises could be matched
                print("Error: None of the recommended exercises could be found in the database.")
            }
        } catch {
            print("Error starting workout from AI routine: \(error)")
        }
    }
    
    private func saveAIRoutineAsTemplate(_ routine: AIRoutineResponse) async {
        let supabase = SupabaseManager.shared.client
        
        do {
            // Get user ID
            guard let userId = try? await supabase.auth.session.user.id else {
                print("User not authenticated")
                return
            }
            
            // Create the routine first
            struct RoutineInsert: Encodable {
                let user_id: UUID
                let name: String
            }
            
            let routinePayload = RoutineInsert(user_id: userId, name: routine.name)
            
            struct RoutineResponse: Decodable {
                let id: UUID
            }
            
            let newRoutineResponse: [RoutineResponse] = try await supabase
                .from("routines")
                .insert(routinePayload, returning: .representation)
                .select("id")
                .execute()
                .value
            
            guard let routineId = newRoutineResponse.first?.id else {
                print("Failed to create routine")
                return
            }
            
            // Fetch complete exercise data to match names
            let allExercises: [Exercise] = try await supabase
                .from("exercises")
                .select("*") // Fetch all fields for complete exercise data
                .or("is_global.eq.true,created_by_user_id.eq.\(userId)")
                .execute()
                .value
            
            // Match and insert routine exercises
            for (index, aiExercise) in routine.exercises.enumerated() {
                if let matched = allExercises.first(where: { 
                    $0.name.lowercased() == aiExercise.name.lowercased() ||
                    $0.name.lowercased().contains(aiExercise.name.lowercased()) ||
                    aiExercise.name.lowercased().contains($0.name.lowercased())
                }) {
                    // Insert routine_exercise
                    struct RoutineExerciseInsert: Encodable {
                        let routine_id: UUID
                        let exercise_id: UUID
                        let user_id: UUID
                        let order_index: Int
                    }
                    
                    let exercisePayload = RoutineExerciseInsert(
                        routine_id: routineId,
                        exercise_id: matched.id,
                        user_id: userId,
                        order_index: index
                    )
                    
                    struct RoutineExerciseResponse: Decodable {
                        let id: UUID
                    }
                    
                    let exerciseResponse: [RoutineExerciseResponse] = try await supabase
                        .from("routine_exercises")
                        .insert(exercisePayload, returning: .representation)
                        .select("id")
                        .execute()
                        .value
                    
                    if let routineExerciseId = exerciseResponse.first?.id {
                        // Insert set templates
                        struct SetInsert: Encodable {
                            let routine_exercise_id: UUID
                            let user_id: UUID
                            let set_number: Int
                            let target_reps: String
                            let target_rest_seconds: Int
                        }
                        
                        var setInserts: [SetInsert] = []
                        for setNum in 1...aiExercise.sets {
                            setInserts.append(SetInsert(
                                routine_exercise_id: routineExerciseId,
                                user_id: userId,
                                set_number: setNum,
                                target_reps: String(aiExercise.reps),
                                target_rest_seconds: 90 // Default rest
                            ))
                        }
                        
                        if !setInserts.isEmpty {
                            try await supabase
                                .from("routine_exercise_sets")
                                .insert(setInserts)
                                .execute()
                        }
                    }
                }
            }
            
            // Post notification to refresh routines
            NotificationCenter.default.post(name: .routineChanged, object: nil)
            
            print("Routine saved successfully!")
            
            // Show success in chat - just dismiss for now
            // The success will be shown when the user comes back
            
        } catch {
            print("Error saving routine: \(error)")
        }
    }
}

// MARK: - Thinking Indicator
struct ThinkingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGray5))
            .cornerRadius(20)
            
            Spacer(minLength: 60)
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Preview
struct AICoachChatView_Previews: PreviewProvider {
    static var previews: some View {
        AICoachChatView()
            .environmentObject(WorkoutStarterService())
            .environmentObject(TabSelection())
    }
} 