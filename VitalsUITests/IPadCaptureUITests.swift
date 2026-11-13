import XCTest

/// Drives iPad captures. XCTest rotates the device (nothing else can, headless);
/// `scripts/capture-ipad.sh` takes each screenshot with `simctl io` while this
/// test waits, so frames are the full framebuffer rather than XCTest's cropped,
/// rotated ones. Runs only on an iPad.
///
/// `IPAD_JOBS` is a comma list of `<scene>:<portrait|landscape>`, `IPAD_SYNC` a
/// folder shared with the script: this writes `<job>.ready` and waits for
/// `<job>.done`. Without them (a gh-sim run) it shoots the default jobs and
/// attaches the frames, which XCTest may crop or rotate.
final class IPadCaptureUITests: XCTestCase {
    func testCapture() throws {
        let env = ProcessInfo.processInfo.environment
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        let jobs = env["IPAD_JOBS"] ?? [
            "premium:portrait", "premium:landscape",
            "premiumDashboard:portrait", "premiumDashboard:landscape",
            "netDeficit:portrait", "macroDashboard:portrait",
            "macroHistory:portrait", "macroHistory:landscape",
            "premiumActive:portrait", "bodyProfile:portrait",
            "bodyProfile:landscape", "settingsPro:landscape",
        ].joined(separator: ",")
        let sync = env["IPAD_SYNC"]
        continueAfterFailure = true
        for job in jobs.split(separator: ",").map(String.init) {
            let parts = job.split(separator: ":").map(String.init)
            guard parts.count == 2 else { continue }
            XCUIDevice.shared.orientation = parts[1] == "landscape" ? .landscapeLeft : .portrait
            let app = XCUIApplication()
            app.terminate()
            app.launchEnvironment["VITALS_SCREENSHOT_MODE"] = "1"
            app.launchArguments = ["-ScreenshotScene", parts[0]]
            app.launch()
            // Rotation can land after launch; settle before the frame is taken.
            sleep(UInt32(env["IPAD_WAIT"].flatMap(UInt32.init) ?? 10))
            XCUIDevice.shared.orientation = parts[1] == "landscape" ? .landscapeLeft : .portrait
            sleep(3)
            let name = "\(parts[0])-\(parts[1])"
            guard let sync else {
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
                continue
            }
            FileManager.default.createFile(atPath: "\(sync)/\(name).ready", contents: nil)
            let deadline = Date.now.addingTimeInterval(120)
            while !FileManager.default.fileExists(atPath: "\(sync)/\(name).done"), Date.now < deadline {
                sleep(1)
            }
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
