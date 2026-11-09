// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import Foundation
import SwiftUI
import Combine

/// Nonisolated helpers so tests can exercise resolution and probing on any thread.
enum ContainerProbe {
    static let containerRoot = "/var/mobile/Containers/Data/Application"
    /// Injectable so unit tests can verify probe behavior without worse_query.
    static var handler: ((URL) throws -> [String])?

    static func resolveTarget(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return URL(fileURLWithPath: containerRoot) }
        if trimmed.hasPrefix("/") {
            guard trimmed == containerRoot || trimmed.hasPrefix(containerRoot + "/") else { return nil }
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }
        let pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return URL(fileURLWithPath: containerRoot + "/" + trimmed)
    }
}

/// Probes read/write access to an installed app's data container under
/// /var/mobile/Containers/Data/Application using the same worse_query
/// sandbox-extension mechanism as MobileGestalt access.
@MainActor
final class ContainerAccessTester: ObservableObject {
    @Published var input = ""
    @Published private(set) var isRunning = false
    @Published private(set) var steps: [ContainerTestStep] = []
    @Published private(set) var containers: [String] = []

    struct ContainerTestStep: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let passed: Bool
    }

    func scan() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        #if targetEnvironment(simulator)
        fail(L("Device access is unavailable in the Simulator."))
        #else
        var status: Int64 = -1
        for root in [ContainerProbe.containerRoot, "/private" + ContainerProbe.containerRoot] {
            if let paths = bad_query_list_children(root, &status), !paths.isEmpty {
                containers = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted()
                log(L("Containers found"), String(containers.count), passed: true)
                return
            }
        }
        fail(L("Could not enumerate application containers (code (status))."))
        #endif
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        steps = []
        defer { isRunning = false }
        guard let target = ContainerProbe.resolveTarget(input) else {
            fail(L("Enter a container UUID or a full path under ") + ContainerProbe.containerRoot)
            return
        }
        #if targetEnvironment(simulator)
        fail(L("Device access is unavailable in the Simulator."))
        #else
        let handle = bad_query(target.path, false)
        guard handle >= 0 else {
            fail(L("Application container access was denied (code (handle))."))
            return
        }
        let probe = target.appendingPathComponent("GestaltX-container-test-" + UUID().uuidString + ".txt")
        let payload = Data("GestaltX container write test \(UUID().uuidString)".utf8)
        log(L("Target"), target.path, passed: true)
        if let probeHandler = ContainerProbe.handler {
            do {
                let lines = try probeHandler(target)
                for line in lines { log(L("Probe"), line, passed: true) }
                setResult(L("Container read/write test passed"), passed: true)
            } catch {
                fail(error.localizedDescription)
            }
            return
        }
        guard handle >= 0 else {
            fail(handle == -255
                 ? L("The target path does not exist. Check the container UUID.")
                 : L("Access was denied. Check the OS version and App Group signing."))
            return
        }
        log(L("Sandbox extension acquired"), "handle \(handle)", passed: true)
        do {
            try payload.write(to: probe)
            let written = try Data(contentsOf: probe)
            guard written == payload else { throw GestaltFailure("Readback mismatch.") }
            log(L("Write and readback verified"), "\(payload.count) bytes", passed: true)
            try FileManager.default.removeItem(at: probe)
            guard !FileManager.default.fileExists(atPath: probe.path) else { throw GestaltFailure("Probe removal failed.") }
            log(L("Probe file removed"), probe.lastPathComponent, passed: true)
            setResult(L("Container read/write test passed"), passed: true)
        } catch {
            try? FileManager.default.removeItem(at: probe)
            fail(error.localizedDescription)
        }
        bad_query_release(handle)
        log(L("Sandbox extension released"), "handle \(handle)", passed: true)
        #endif
    }

    private func log(_ title: String, _ detail: String = "", passed: Bool) {
        steps.append(ContainerTestStep(title: title, detail: detail, passed: passed))
    }
    private func fail(_ message: String) {
        steps.append(ContainerTestStep(title: L("Test failed"), detail: message, passed: false))
    }
    private func setResult(_ message: String, passed: Bool) {
        steps.append(ContainerTestStep(title: message, detail: "", passed: passed))
    }
}

struct ContainerAccessTestView: View {
    @StateObject private var tester = ContainerAccessTester()
    var body: some View {
        Form {
            Section {
                Button { Task { await tester.scan() } } label: {
                    Label(L("Find Application Containers"), systemImage: "magnifyingglass")
                }.disabled(tester.isRunning)
                TextField(L("Container UUID or full path (empty = the Application directory itself)"), text: $tester.input)
                    .font(.system(.subheadline, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { Task { await tester.run() } } label: {
                    Label(L(tester.isRunning ? "Testing…" : "Run Read/Write Test"), systemImage: "play.fill")
                }.disabled(tester.isRunning)
            } footer: {
                Text(L("Finds UUID directories, then probes write, verified readback, and cleanup in the selected application container."))
            }
            if !tester.containers.isEmpty {
                Section(L("Application Container UUIDs")) {
                    ForEach(tester.containers, id: .self) { uuid in
                        Button(uuid) { tester.input = uuid }
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            ForEach(tester.steps) { step in
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: step.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(step.passed ? Color.green : Color.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).fontWeight(.medium)
                            if !step.detail.isEmpty {
                                Text(step.detail).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Container Access Test"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
