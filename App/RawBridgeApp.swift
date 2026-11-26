import SwiftUI

@main
struct RawBridgeApp: App {
    @StateObject private var library = LibraryViewModel()
    var body: some Scene { WindowGroup { LibraryView(library: library) } }
}
