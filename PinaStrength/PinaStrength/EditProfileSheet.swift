import SwiftUI

struct EditProfileSheet: View {
    @Environment(\.dismiss) var dismiss
    let user: SupaUser
    var onSave: (String?, String?) -> Void
    
    @State private var name: String
    @State private var avatarURL: String
    
    init(user: SupaUser, onSave: @escaping (String?, String?) -> Void) {
        self.user = user
        self.onSave = onSave
        _name = State(initialValue: user.name)
        _avatarURL = State(initialValue: user.avatarURL ?? "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Information") {
                    TextField("Display name", text: $name)
                    TextField("Avatar URL", text: $avatarURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            name.isEmpty ? nil : name,
                            avatarURL.isEmpty ? nil : avatarURL
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
            }
        }
    }
} 