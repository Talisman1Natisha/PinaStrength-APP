import SwiftUI
import Supabase

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Modern Exercise Row View

struct ModernExerciseRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onDelete: ((Exercise) -> Void)?
    
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
        case "barbell": return Color(hex: "#F28C28")
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
        HStack(spacing: 16) {
            // Image or Icon
            ZStack {
                if let imageUrl = exercise.imageUrl, !imageUrl.isEmpty {
                    AsyncImage(url: URL(string: imageUrl)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 50, height: 50)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.5)
                            )
                    }
                } else {
                    // Fallback to icon when no image
                    RoundedRectangle(cornerRadius: 12)
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: iconName)
                                .font(.system(size: 22))
                                .foregroundColor(categoryColor)
                        )
                }
            }
            
            // Exercise info
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if exercise.isCustomExercise {
                        Text("CUSTOM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
                
                HStack(spacing: 8) {
                    if let bodyPart = exercise.bodyPart, !bodyPart.isEmpty {
                        Label(bodyPart, systemImage: "figure.strengthtraining.traditional")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let equipment = exercise.equipment, !equipment.isEmpty {
                        Text("• \(equipment)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Selection indicator or chevron
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Color(hex: "#F28C28"))
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color(hex: "#F28C28") : Color.clear, lineWidth: 2)
        )
        .contextMenu {
            if exercise.isCustomExercise {
                Button(role: .destructive) {
                    onDelete?(exercise)
                } label: {
                    Label("Delete Exercise", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Main Exercises View (Adapted for Selection)

struct ExercisesView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (([Exercise]) -> Void)? = nil
    var isSelectionMode: Bool { onSave != nil }

    @State private var exercises: [Exercise] = []
    @State private var searchText: String = ""
    @State private var selectedBodyPart: String = "All"
    @State private var selectedCategory: String = "All"
    @State private var showCreateModal: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showDeleteConfirmation = false
    @State private var exerciseToDelete: Exercise?
    @State private var isDeleting = false
    
    @State private var currentlySelectedExercises: [Exercise] = []
    @State private var presentedExercise: Exercise? = nil // For sheet presentation
    @State private var fetchTask: Task<Void, Never>? = nil // Track the fetch task

    private let client = SupabaseManager.shared.client
    private let secureDataService = SecureDataService()
    private let bodyParts = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body", "Cardio", "Olympic", "Other"]
    private let categories = ["All", "Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Bands"]

    var filteredExercises: [Exercise] {
        exercises.filter {
            (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)) &&
            (selectedBodyPart == "All" || $0.bodyPart == selectedBodyPart) &&
            (selectedCategory == "All" || $0.category == selectedCategory)
        }.sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filter section with dropdown menus
                    HStack(spacing: 16) {
                        // Body Part Dropdown
                        Menu {
                            ForEach(bodyParts, id: \.self) { part in
                                Button(action: { selectedBodyPart = part }) {
                HStack {
                                        Text(part)
                                        if selectedBodyPart == part {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .foregroundColor(Color(hex: "#F28C28"))
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "figure.arms.open")
                                    .font(.system(size: 14))
                                Text(selectedBodyPart)
                                    .font(.system(size: 14, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(selectedBodyPart == "All" ? .secondary : Color(hex: "#F28C28"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedBodyPart == "All" ? Color(.systemGray4) : Color(hex: "#F28C28").opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        
                        // Category Dropdown
                        Menu {
                            ForEach(categories, id: \.self) { category in
                                Button(action: { selectedCategory = category }) {
                                    HStack {
                                        Text(category)
                                        if selectedCategory == category {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                                .foregroundColor(Color(hex: "#F28C28"))
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "tag")
                                    .font(.system(size: 14))
                                Text(selectedCategory)
                                    .font(.system(size: 14, weight: .medium))
                        Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(selectedCategory == "All" ? .secondary : Color(hex: "#F28C28"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(.systemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedCategory == "All" ? Color(.systemGray4) : Color(hex: "#F28C28").opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    
                    // Content
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#F28C28")))
                        Text("Loading exercises...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        Spacer()
                    } else if let errorMessage = errorMessage {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.red)
                            Text("Error")
                                .font(.title2.weight(.semibold))
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        Spacer()
                    } else if filteredExercises.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No exercises found")
                                .font(.title2.weight(.semibold))
                            Text("Try adjusting your filters or search")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredExercises) { exercise in
                                    ModernExerciseRow(
                                        exercise: exercise,
                                        isSelected: currentlySelectedExercises.contains(where: { $0.id == exercise.id }),
                                        onDelete: { exerciseToDelete in
                                            self.exerciseToDelete = exerciseToDelete
                                            self.showDeleteConfirmation = true
                                        }
                                    )
                                    .onTapGesture {
                                        if isSelectionMode {
                                            toggleSelection(for: exercise)
                                        } else {
                                            presentedExercise = exercise
                                        }
                                    }
                                }
                                .onDelete(perform: deleteExercises)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle(isSelectionMode ? "Select Exercises" : "Exercises")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search exercises")
            .toolbar {
                if isSelectionMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            onSave?(currentlySelectedExercises)
                            dismiss()
                        }) {
                            HStack {
                                Text("Add")
                                if !currentlySelectedExercises.isEmpty {
                                    Text("(\(currentlySelectedExercises.count))")
                                        .foregroundColor(Color(hex: "#F28C28"))
                                }
                            }
                            .fontWeight(.semibold)
                        }
                        .disabled(currentlySelectedExercises.isEmpty && onSave != nil)
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showCreateModal = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundColor(Color(hex: "#F28C28"))
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreateModal) {
                CreateExerciseView { newExercise in
                    exercises.append(newExercise)
                    if isSelectionMode {
                        if !currentlySelectedExercises.contains(where: { $0.id == newExercise.id }) {
                            currentlySelectedExercises.append(newExercise)
                        }
                    }
                    showCreateModal = false
                }
            }
            // Sheet presentation for exercise detail
            .sheet(item: $presentedExercise) { exercise in
                ExerciseDetailView(exercise: exercise)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                // Cancel any existing fetch task
                fetchTask?.cancel()
                
                // Create new fetch task
                fetchTask = Task {
                    await fetchExercises()
                }
            }
            .onDisappear {
                // Cancel the fetch task when view disappears
                fetchTask?.cancel()
                fetchTask = nil
            }
            .alert("Delete Exercise", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    exerciseToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let exercise = exerciseToDelete {
                        Task {
                            await confirmDeleteExercise(exercise)
                        }
                    }
                }
            } message: {
                if let exercise = exerciseToDelete {
                    Text("Are you sure you want to delete '\(exercise.name)'? This action cannot be undone.")
                }
            }
            .overlay {
                if isDeleting {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView("Deleting exercise...")
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                }
            }
        }
    }

    private func toggleSelection(for exercise: Exercise) {
        if let index = currentlySelectedExercises.firstIndex(where: { $0.id == exercise.id }) {
            currentlySelectedExercises.remove(at: index)
        } else {
            currentlySelectedExercises.append(exercise)
        }
    }

    func fetchExercises() async {
        // Check if task is cancelled before starting
        if Task.isCancelled { return }
        
        isLoading = true
        errorMessage = nil
        do {
            guard let userId = try? await client.auth.session.user.id else {
                errorMessage = "User not authenticated"
                isLoading = false
                return
            }
            
            // Check again before making network request
            if Task.isCancelled { 
                isLoading = false
                return 
            }
            
            // Fetch global exercises and user's custom exercises
            let fetchedExercisesData: [Exercise] = try await client
                .from("exercises")
                .select()
                .or("is_global.eq.true,created_by_user_id.eq.\(userId)")
                .execute()
                .value
            
            // Check if cancelled before updating UI
            if Task.isCancelled { 
                isLoading = false
                return 
            }
            
            await MainActor.run {
                self.exercises = fetchedExercisesData
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                // Check if it's a cancellation error
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    // This is just a cancelled request, not a real error
                    // Don't show error message for cancellations
                    self.isLoading = false
                } else {
                    // This is a real error, show it
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    print("Error fetching exercises: \(error)")
                }
            }
        }
    }

    private func deleteExercises(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        let exercise = filteredExercises[index]
        
        // Only allow deletion of custom exercises
        if exercise.isCustomExercise {
            exerciseToDelete = exercise
            showDeleteConfirmation = true
        }
    }
    
    private func confirmDeleteExercise(_ exercise: Exercise) async {
        isDeleting = true
        
        do {
            try await secureDataService.deleteCustomExercise(exerciseId: exercise.id)
            
            // Remove from local array
            DispatchQueue.main.async {
                if let index = self.exercises.firstIndex(where: { $0.id == exercise.id }) {
                    self.exercises.remove(at: index)
                }
                
                // Also remove from selected exercises if it was selected
                if let selectedIndex = self.currentlySelectedExercises.firstIndex(where: { $0.id == exercise.id }) {
                    self.currentlySelectedExercises.remove(at: selectedIndex)
                }
                
                self.exerciseToDelete = nil
                self.isDeleting = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to delete exercise: \(error.localizedDescription)"
                self.exerciseToDelete = nil
                self.isDeleting = false
            }
        }
    }
}

// MARK: - Create Exercise View (Sheet)

struct CreateExerciseView: View {
    @Environment(\.dismiss) var dismiss
    var onSave: (Exercise) -> Void

    @State private var name: String = ""
    @State private var selectedBodyPart: String = "Other" 
    @State private var selectedCategory: String = "Bodyweight" 
    @State private var instructions: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submissionError: String? = nil

    private let client = SupabaseManager.shared.client
    private let bodyParts = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body", "Cardio", "Olympic", "Other"]
    private let categories = ["Barbell", "Dumbbell", "Cable", "Machine", "Bodyweight", "Kettlebell", "Bands"]

    struct NewExercisePayload: Encodable {
        let name: String
        let body_part: String?
        let category: String?
        let instructions: String?
        let created_by_user_id: UUID
        let is_global: Bool = false  // Custom exercises are always private to the user
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header section
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#F28C28").opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 40))
                                .foregroundColor(Color(hex: "#F28C28"))
                        }
                        
                        Text("Create New Exercise")
                            .font(.title2.weight(.bold))
                        
                        Text("Add a custom exercise to your library")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Form fields
                    VStack(spacing: 20) {
                        // Exercise name field
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Exercise Name", systemImage: "pencil")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                            
                            TextField("e.g. Barbell Bench Press", text: $name)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(.systemBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                        }
                        
                        // Body Part and Category pickers
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Body Part", systemImage: "figure.arms.open")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.secondary)
                                
                                Menu {
                                    ForEach(bodyParts, id: \.self) { part in
                                        Button(part) {
                                            selectedBodyPart = part
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedBodyPart)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
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
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Category", systemImage: "tag")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.secondary)
                                
                                Menu {
                                    ForEach(categories, id: \.self) { category in
                                        Button(category) {
                                            selectedCategory = category
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedCategory)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
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
                        }
                        
                        // Instructions field
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Instructions (Optional)", systemImage: "doc.text")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.secondary)
                            
                            ZStack(alignment: .topLeading) {
                                if instructions.isEmpty {
                                    Text("Add step-by-step instructions...")
                                        .foregroundColor(Color(.placeholderText))
                                        .padding(.top, 12)
                                        .padding(.leading, 12)
                                }
                                
                                TextEditor(text: $instructions)
                                    .textFieldStyle(.plain)
                                    .padding(8)
                                    .frame(minHeight: 100)
                                    .scrollContentBackground(.hidden)
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
                    }
                    .padding(.horizontal)
                    
                    // Error message
                    if let submissionError = submissionError {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(submissionError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Action buttons
                    VStack(spacing: 12) {
                Button(action: { Task { await submitExercise() } }) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Save Exercise")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(name.isEmpty ? Color.gray : Color(hex: "#F28C28"))
                        )
                        .foregroundColor(.white)
                .disabled(name.isEmpty || isSubmitting)
                        
                        Button("Cancel") {
                            dismiss()
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray5))
                        )
                        .foregroundColor(.primary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationBarHidden(true)
        }
    }

    func submitExercise() async {
        guard !name.isEmpty else {
            submissionError = "Exercise name cannot be empty."
            return
        }
        isSubmitting = true
        submissionError = nil
        do {
            let userId = try await client.auth.session.user.id
            let payload = NewExercisePayload(
                name: name,
                body_part: selectedBodyPart,
                category: selectedCategory,
                instructions: instructions.isEmpty ? nil : instructions,
                created_by_user_id: userId
            )
            
            // Using the new Supabase API
            let newExercise: Exercise = try await client
                .from("exercises")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            
            // Enqueue for AI enrichment if any fields are missing
            if selectedBodyPart == "Other" || selectedCategory == "Bodyweight" || instructions.isEmpty {
                struct EnrichmentParams: Encodable {
                    let p_id: UUID
                }
                
                // Fire and forget - we don't wait for this
                Task {
                    do {
                        try await client.rpc(
                            "enqueue_exercise_enrichment",
                            params: EnrichmentParams(p_id: newExercise.id)
                        ).execute()
                        print("Exercise queued for AI enrichment")
                    } catch {
                        print("Failed to queue exercise for enrichment: \(error)")
                    }
                }
            }
            
            await MainActor.run {
                onSave(newExercise)
                isSubmitting = false
                dismiss() 
            }
        } catch {
            await MainActor.run {
                submissionError = error.localizedDescription
                isSubmitting = false
                print("Error submitting exercise: \(error)")
            }
        }
    }
}

// MARK: - Preview

struct ExercisesView_Previews: PreviewProvider {
    static var previews: some View {
        ExercisesView()
    }
} 