import Foundation

/// Writes `content` to `outputURL`.
///
/// If a sandbox permission error occurs the file is written to the system
/// temporary directory instead, and a console message tells the user exactly
/// which `cp` command copies it into the project.  All other errors are
/// rethrown as-is.
///
/// Returns the URL where the file was actually written.
@discardableResult
func writeGeneratedFile(_ content: String, to outputURL: URL) throws -> URL {
    do {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existed = FileManager.default.fileExists(atPath: outputURL.path)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        print("\n✓ \(existed ? "Updated" : "Created") → \(outputURL.path)")
        return outputURL
    } catch let error as NSError
        where error.domain == NSCocoaErrorDomain
           && [NSFileWriteNoPermissionError,
               NSFileReadNoPermissionError].contains(error.code) {
        return try writeToTemp(content, filename: outputURL.lastPathComponent,
                               intendedPath: outputURL.path)
    }
}

// MARK: - Private

private func writeToTemp(_ content: String, filename: String, intendedPath: String) throws -> URL {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try content.write(to: tempURL, atomically: true, encoding: .utf8)
    print("""

    ╔─────────────────────────────────────────────────────────────────────╗
    │  SwiftL10n — sandbox write blocked                                  │
    ╠─────────────────────────────────────────────────────────────────────╣
    │                                                                     │
    │  Could not write to:                                                │
    │    \(intendedPath)
    │                                                                     │
    │  Reason: the App Sandbox prevents apps from writing to paths        │
    │  outside their container.                                           │
    │                                                                     │
    │  ✓ File saved to a temp location:                                   │
    │    \(tempURL.path)
    │                                                                     │
    │  ── What you should do ─────────────────────────────────────────── │
    │                                                                     │
    │  Step 1 — Copy the file into your project (run in Terminal):        │
    │                                                                     │
    │    cp "\(tempURL.path)" \\
    │       "\(intendedPath)"
    │                                                                     │
    │  Step 2 — To avoid this every time, use the CLI tool in an Xcode   │
    │  build phase instead of .task {}. Build phases run before the app  │
    │  is sandboxed, so writes always succeed:                            │
    │                                                                     │
    │    swiftl10n scan --project "$SRCROOT/YourApp"                      │
    │                                                                     │
    │  See the README → "Xcode Build Phase" for the full setup.          │
    │                                                                     │
    ╚─────────────────────────────────────────────────────────────────────╝
    """)
    return tempURL
}
