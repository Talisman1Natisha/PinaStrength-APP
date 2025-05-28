import SwiftUI

struct RoutineCard: View {
    let routine: RoutineGridItem
    @State private var showDeleteAlert = false
    let onDelete: (() -> Void)?
    
    init(routine: RoutineGridItem, onDelete: (() -> Void)? = nil) {
        self.routine = routine
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Routine name
            Text(routine.name)
                .font(.title3.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Exercise preview (first 3 exercises)
            Text(exercisePreview)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Last performed
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(relativeDate)
                    .font(.footnote)
            }
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .contextMenu {
            Button {
                // TODO: Implement edit functionality
                print("Edit routine: \(routine.name)")
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                showDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Routine?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete \"\(routine.name)\"? This action cannot be undone.")
        }
    }
    
    private var exercisePreview: String {
        // Get first 3 exercise names from the routine
        let exercises = routine.exercises?.prefix(3) ?? []
        let names = exercises.compactMap { $0.exercise?.name }
        
        if names.isEmpty {
            return "No exercises"
        }
        
        return names.joined(separator: ", ")
    }
    
    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: routine.updatedAt, relativeTo: Date())
    }
}

// Preview
struct RoutineCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            RoutineCard(
                routine: RoutineGridItem(
                    id: UUID(),
                    name: "Chest and Triceps Copy",
                    updatedAt: Date().addingTimeInterval(-25 * 24 * 60 * 60), // 25 days ago
                    user_id: UUID(),
                    created_at: Date(),
                    exercises: []
                ),
                onDelete: {
                    print("Delete routine")
                }
            )
            
            RoutineCard(
                routine: RoutineGridItem(
                    id: UUID(),
                    name: "Evening Workout",
                    updatedAt: Date().addingTimeInterval(-24 * 60 * 60), // Yesterday
                    user_id: UUID(),
                    created_at: Date(),
                    exercises: []
                ),
                onDelete: nil
            )
        }
        .padding()
    }
} 