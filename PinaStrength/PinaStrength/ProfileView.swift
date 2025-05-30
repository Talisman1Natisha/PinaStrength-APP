//
//  ProfileView.swift
//  PinaStrength
//
//  Created by user on 5/25/25.
//

import Foundation
import SwiftUI

struct ProfileView: View {
    @StateObject private var vm = ProfileViewModel()
    @State private var showEdit = false
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationStack {
            if vm.loading {
                ProgressView("Loading profile...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 12) {
                            AsyncImage(url: URL(string: vm.user?.avatarURL ?? "")) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundColor(.gray)
                            }
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                            
                            Text(vm.user?.name ?? "—")
                                .font(.title2.weight(.semibold))
                            
                            Text(vm.user?.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                        
                        // Stats
                        HStack(spacing: 40) {
                            StatView(label: "Workouts", value: vm.workoutCount)
                            StatView(label: "Routines", value: vm.routineCount)
                        }
                        .padding(.horizontal, 40)
                        
                        // Actions
                        VStack(spacing: 12) {
                            Button(action: { showEdit = true }) {
                                Label("Edit Profile", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(10)
                            }
                            
                            Button(action: {
                                // TODO: Implement password reset flow
                                print("Change password tapped")
                            }) {
                                Label("Change Password", systemImage: "key")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(10)
                            }
                            
                            Button(role: .destructive, action: {
                                Task {
                                    try? await vm.signOut()
                                    await authManager.signOut()
                                }
                            }) {
                                Label("Sign Out", systemImage: "arrow.right.square")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemRed).opacity(0.1))
                                    .foregroundColor(.red)
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
                .navigationTitle("Profile")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            Task { await vm.refresh() }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let user = vm.user {
                EditProfileSheet(user: user) { name, avatar in
                    Task {
                        try? await vm.update(name: name, avatarURL: avatar)
                    }
                }
            }
        }
    }
}

private struct StatView: View {
    let label: String
    let value: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title.weight(.bold))
                .foregroundColor(.primary)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
