import AppKit

// `ferry <command>` from a terminal runs the CLI; LaunchServices launches the menu bar app with no arguments.
let arguments = Array(CommandLine.arguments.dropFirst())
if let first = arguments.first, !first.hasPrefix("-psn_") {
    // Replies from Ferry.app arrive on the main run loop, so the CLI runs off the main thread.
    Task.detached { exit(await FerryCLI.make().run(arguments)) }
    RunLoop.main.run()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
