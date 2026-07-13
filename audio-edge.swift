import AppKit
import Foundation

let HOST = ProcessInfo.processInfo.environment["AUDIO_HOST"] ?? "https://audio.vaked.dev"

// ──────────────────────────────────────────────────────────────────────────────
// AppDelegate — menu bar app
// ──────────────────────────────────────────────────────────────────────────────

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var player: Process?
    var curl: Process?
    var fifoPath: String = ""
    var isPaused = false
    var tracks: [[String: Any]] = []
    var currentSlug: String = ""
    var currentTitle: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "♪"
        statusItem.button?.toolTip = "AudioEdge"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Loading...", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Import from YouTube…", action: #selector(importDialog), keyEquivalent: "i"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        fetchTracks()
    }

    // ── Track list ──────────────────────────────────────────────────────────

    func fetchTracks() {
        guard let url = URL(string: "\(HOST)/tracks") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data,
                  let tracks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return }
            DispatchQueue.main.async {
                self?.tracks = tracks
                self?.buildMenu()
            }
        }.resume()
    }

    func buildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        // Currently playing
        if !currentTitle.isEmpty {
            let nowItem = NSMenuItem(title: "Now: \(currentTitle)", action: nil, keyEquivalent: "")
            nowItem.isEnabled = false
            menu.addItem(nowItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Controls
        if player != nil {
            let label = isPaused ? "▶ Resume" : "⏸ Pause"
            menu.addItem(NSMenuItem(title: label, action: #selector(togglePause), keyEquivalent: " "))
            menu.addItem(NSMenuItem(title: "⏹ Stop", action: #selector(stopPlayback), keyEquivalent: "s"))
            menu.addItem(NSMenuItem.separator())
        }

        // Tracks
        if tracks.isEmpty {
            menu.addItem(NSMenuItem(title: "No tracks", action: nil, keyEquivalent: ""))
        } else {
            for track in tracks {
                let title = track["title"] as? String ?? "Unknown"
                let artist = track["artist"] as? String ?? ""
                let slug = track["slug"] as? String ?? ""
                let label = artist.isEmpty ? title : "\(title) — \(artist)"

                let item = NSMenuItem(title: label, action: #selector(playTrack(_:)), keyEquivalent: "")
                item.representedObject = slug
                if slug == currentSlug { item.state = .on }
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "🔀 Shuffle", action: #selector(shufflePlay), keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Import from YouTube…", action: #selector(importDialog), keyEquivalent: "i"))
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
    }

    // ── Playback ────────────────────────────────────────────────────────────

    @objc func playTrack(_ sender: NSMenuItem) {
        guard let slug = sender.representedObject as? String else { return }
        stopPlayback()
        startStream(slug: slug)
    }

    @objc func shufflePlay() {
        guard !tracks.isEmpty else { return }
        stopPlayback()
        let random = tracks.randomElement()!
        let slug = random["slug"] as? String ?? ""
        startStream(slug: slug)
    }

    func startStream(slug: String) {
        currentSlug = slug
        currentTitle = ""
        for t in tracks {
            if (t["slug"] as? String) == slug {
                currentTitle = (t["title"] as? String) ?? slug
                break
            }
        }

        let url = "\(HOST)/stream/\(slug)"
        let fifo = "/tmp/audioedge-\(ProcessInfo.processInfo.processIdentifier).opus"
        fifoPath = fifo
        isPaused = false

        // Clean up any old fifo
        let _ = try? FileManager.default.removeItem(atPath: fifo)
        mkfifo(fifo, 0o600)

        // curl → fifo (background)
        curl = Process()
        curl?.launchPath = "/usr/bin/curl"
        curl?.arguments = ["-sSL", "-H", "User-Agent: Mozilla/5.0", url, "-o", fifo]
        curl?.launch()

        // mpv → play from fifo
        let mpvPath = ProcessInfo.processInfo.environment["MPV_PATH"] ?? "/opt/homebrew/bin/mpv"
        player = Process()
        player?.launchPath = mpvPath
        player?.arguments = ["--no-video", "--really-quiet", "--ytdl=no", fifo]
        player?.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.player = nil
                self?.isPaused = false
                self?.statusItem.button?.title = "♪"
                self?.cleanupFifo()
                self?.buildMenu()
            }
        }
        player?.launch()
        statusItem.button?.title = "▶"
        buildMenu()
    }

    @objc func togglePause() {
        guard let p = player, p.isRunning else { return }
        if isPaused {
            p.resume()
            isPaused = false
            statusItem.button?.title = "▶"
        } else {
            p.suspend()
            isPaused = true
            statusItem.button?.title = "⏸"
        }
        buildMenu()
    }

    @objc func stopPlayback() {
        player?.terminate()
        player = nil
        curl?.terminate()
        curl = nil
        isPaused = false
        currentSlug = ""
        currentTitle = ""
        statusItem.button?.title = "♪"
        cleanupFifo()
        buildMenu()
    }

    func cleanupFifo() {
        if !fifoPath.isEmpty {
            let _ = try? FileManager.default.removeItem(atPath: fifoPath)
            fifoPath = ""
        }
    }

    // ── Import ──────────────────────────────────────────────────────────────

    @objc func importDialog() {
        let alert = NSAlert()
        alert.messageText = "Import from YouTube"
        alert.informativeText = "Paste a YouTube URL. Metadata auto-detected. Runs on Cloudflare."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        let urlField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        urlField.placeholderString = "https://youtube.com/watch?v=..."

        if let clip = NSPasteboard.general.string(forType: .string), clip.contains("youtu") {
            urlField.stringValue = clip
        }

        alert.accessoryView = urlField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let ytUrl = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !ytUrl.isEmpty else { return }

        statusItem.button?.title = "⬇"
        performImport(url: ytUrl)
    }

    func performImport(url ytUrl: String) {
        guard let endpoint = URL(string: "\(HOST)/import") else { return }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["url": ytUrl])

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.statusItem.button?.title = "✗"
                    let a = NSAlert()
                    a.messageText = "Import failed"
                    a.informativeText = error.localizedDescription
                    a.runModal()
                } else if let httpResp = resp as? HTTPURLResponse, httpResp.statusCode != 200 {
                    self?.statusItem.button?.title = "✗"
                    let msg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                    let a = NSAlert()
                    a.messageText = "Import failed (HTTP \(httpResp.statusCode))"
                    a.informativeText = msg
                    a.runModal()
                } else if let data = data,
                          let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          result["ok"] as? Bool == true {
                    self?.statusItem.button?.title = "✓"
                    let dur = result["duration"] as? Int ?? 0
                    let mins = dur / 60
                    let secs = dur % 60
                    let a = NSAlert()
                    a.messageText = "Imported!"
                    a.informativeText = "Duration: \(mins):\(String(format: "%02d", secs))\nStream: \(result["streamUrl"] ?? "")"
                    a.runModal()
                } else {
                    self?.statusItem.button?.title = "✗"
                    let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown error"
                    let a = NSAlert()
                    a.messageText = "Import failed"
                    a.informativeText = msg
                    a.runModal()
                }
                self?.statusItem.button?.title = "♪"
                self?.fetchTracks()
            }
        }.resume()
    }

    // ── Actions ─────────────────────────────────────────────────────────────

    @objc func refresh() {
        statusItem.button?.title = "⋯"
        fetchTracks()
    }

    @objc func quit() {
        stopPlayback()
        NSApp.terminate(nil)
    }
}

// ──────────────────────────────────────────────────────────────────────────────
// Auto-start: LaunchAgent
// ──────────────────────────────────────────────────────────────────────────────

func installLaunchAgent() {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>com.vaked.audio-edge</string>
        <key>ProgramArguments</key>
        <array><string>\(Bundle.main.bundlePath)/Contents/MacOS/AudioEdge</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><false/>
    </dict>
    </plist>
    """
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? plist.write(to: dir.appendingPathComponent("com.vaked.audio-edge.plist"), atomically: true, encoding: .utf8)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
installLaunchAgent()
app.run()
