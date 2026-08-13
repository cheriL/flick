import SwiftUI

@main
struct FlickApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("Flick")
        } label: {
            Image(systemName: "character.bubble")
        }
    }
}
