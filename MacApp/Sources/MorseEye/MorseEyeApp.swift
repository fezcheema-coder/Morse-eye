import AppKit
import SwiftUI

@main
struct MorseEyeApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
        } label: {
            MenuBarLabel().environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Window("Morse Eye Settings", id: "settings") {
            SettingsView()
                .environmentObject(state)
                .environmentObject(state.ollama)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// The menu bar icon. It exists from launch, so it also opens Settings on first run.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: state.menuIcon)
            .task {
                guard !state.settings.onboarded else { return }
                state.settings.onboarded = true
                try? await Task.sleep(for: .milliseconds(600))
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.lastReply.isEmpty {
                answerCard
            }

            VStack(spacing: 2) {
                ForEach(state.settings.prompts) { prompt in
                    MenuRow(title: prompt.title, shortcut: prompt.hotKey?.display, systemImage: "camera.viewfinder") {
                        state.run(prompt.prompt)
                    }
                    .disabled(state.phase == .capturing || state.phase == .thinking)
                }
            }

            HStack {
                Button { state.replay() } label: { Label("Replay", systemImage: "arrow.clockwise") }
                    .disabled(state.lastReply.isEmpty)
                Button { state.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .disabled(state.phase == .idle)
                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()

            HStack {
                Button("Settings…") { openSettings() }
                    .keyboardShortcut(",")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("Morse Eye").font(.headline)
                Text("\(state.statusText) · \(state.provider.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if state.phase == .capturing || state.phase == .thinking {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Last answer").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.lastReply, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy answer")
            }
            Text(state.lastReply)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .textSelection(.enabled)
            Text(state.code.pretty(state.lastReply))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct MenuRow: View {
    let title: String
    let shortcut: String?
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if let shortcut {
                    Text(shortcut).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(hovering ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
