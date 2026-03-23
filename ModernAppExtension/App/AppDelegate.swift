import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Just print and exit gracefully, we just need Finder to register UTIs and Extensions.
        print("GLTFQuickLook App registered. You can close this app.")
        NSApplication.shared.terminate(nil)
    }
}
