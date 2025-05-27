//
//  SupabaseManager.swift
//  PinaStrength
//
//  Created by Natanim Tilahun Abebe on 5/25/25.
//

import Foundation
import Supabase

class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://ohafcyimcowonnvocvwr.supabase.co")!,  // ← change this
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9oYWZjeWltY293b25udm9jdndyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgxOTcwNzYsImV4cCI6MjA2Mzc3MzA3Nn0.RgZ6Ai2_HrzA6pnoBkgmjkpZz4qU8r37od0YGalpK74"  // ← change this
        )
    }
}
