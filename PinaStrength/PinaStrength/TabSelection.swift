import SwiftUI

// Enum to identify your tabs. Adjust cases based on your actual tabs.
enum TabIdentifier: Hashable {
    case log
    case history
    case routines
    case exercises
    case profile
    // Add any other tabs you have
}

class TabSelection: ObservableObject {
    @Published var selectedTab: TabIdentifier = .log // Default to the Log tab
} 