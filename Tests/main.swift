import Foundation

var failures = 0

func check(_ ok: Bool, _ what: String, file: String = #file, line: Int = #line) {
    if !ok {
        print("FAIL \(what) (\(file):\(line))")
        failures += 1
    }
}

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u.standardizedFileURL
}

func make(_ root: URL, _ paths: [String]) {
    let fm = FileManager.default
    for p in paths {
        let u = root.appendingPathComponent(p)
        if p.hasSuffix("/") {
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        } else {
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(p.utf8).write(to: u)
        }
    }
}

runLayoutTests()
runFilesTests()
runSearchTests()
runSafetyTests()
runInstalledProgramsTests()
runTaskListTests()
runProgramChoiceTests()
runLetterboxTests()

if failures == 0 { print("ALL PASSED") } else { print("\(failures) FAILED"); exit(1) }
