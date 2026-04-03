import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.configureApplication()
        statusBarController = StatusBarController(appState: appState)
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.tearDown()
        statusBarController?.tearDown()
        statusBarController = nil
    }
}
