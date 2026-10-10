import AppKit

// `ferry <command>` from a terminal runs the CLI; LaunchServices launches the menu bar app with no command.
let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first, !command.hasPrefix("-psn_") {
    exit(CLI.run(command, Array(arguments.dropFirst())))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
