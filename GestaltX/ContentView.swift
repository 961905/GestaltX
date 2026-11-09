// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import SwiftUI
import UniformTypeIdentifiers

struct SharedFile: Identifiable { let id = UUID(); let url: URL }

struct ContentView: View {
    @StateObject private var model = GestaltManager()
    @State private var importsFile = false
    @State private var sharesFile: SharedFile?
    @State private var showsChanges = false
    @State private var asksRespring = false
    @State private var selectedTab = 0
    @State private var didStart = false
    @State private var didAutoRead = false
    #if targetEnvironment(simulator)
    @State private var previewCategory: CapabilityCategory?
    #endif
    @AppStorage("GestaltX.acceptedWelcome.v1") private var acceptedWelcome = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { tools }
                .tabItem { Label(L("Tools"), systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { FieldsView() }
                .tabItem { Label(L("Fields"), systemImage: "slider.horizontal.3") }.tag(1)
            NavigationStack { BackupsView(share: { sharesFile = SharedFile(url: $0) }) }
                .tabItem { Label(L("Backups"), systemImage: "clock.arrow.circlepath") }.tag(2)
            NavigationStack { AboutView() }
                .tabItem { Label(L("About"), systemImage: "info.circle") }.tag(3)
        }
        .environmentObject(model)
        .tint(.blue)
        #if targetEnvironment(simulator)
        .sheet(item: $previewCategory) { category in
            NavigationStack { CategoryView(category: category) }.environmentObject(model)
        }
        #endif
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.propertyList, .xml, .data]) { result in
            switch result {
            case .success(let url): Task { await model.open(url) }
            case .failure(let error): model.message = error.localizedDescription
            }
        }
        .sheet(isPresented: Binding(get: { !acceptedWelcome && !isPreviewSession }, set: { _ in })) {
            WelcomeView { acceptedWelcome = true }
        }
        .sheet(item: $sharesFile) { ShareSheet(url: $0.url) }
        .sheet(isPresented: $showsChanges) { ChangeReviewView().environmentObject(model) }
        .fullScreenCover(isPresented: $model.isRespringing) { NeoSpringView() }
        .alert(L("GestaltX"), isPresented: Binding(get: { model.message != nil && !showsChanges }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .alert(L("Respring now?"), isPresented: $asksRespring) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Respring")) { model.isRespringing = true }
        } message: { Text(L("This will attempt to restart SpringBoard using NeoSpring.")) }
        .onChange(of: acceptedWelcome) { _, accepted in
            if accepted && !isPreviewSession { Task { await autoRead() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && model.isRespringing { model.isRespringing = false }
        }
        .task {
            guard !didStart else { return }
            didStart = true
            await model.reloadBackups()
            #if targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--preview-document"), arguments.indices.contains(flag + 1) {
                await model.open(URL(fileURLWithPath: arguments[flag + 1]))
            }
            if let flag = arguments.firstIndex(of: "--preview-tab"), arguments.indices.contains(flag + 1), let tab = Int(arguments[flag + 1]) {
                selectedTab = tab
            }
            if arguments.contains("--preview-review") {
                model.choices["pencil"] = .enable
                showsChanges = true
            }
            if let flag = arguments.firstIndex(of: "--preview-category"), arguments.indices.contains(flag + 1) {
                previewCategory = CapabilityCategory(rawValue: arguments[flag + 1])
            }
            if arguments.contains("--preview-document") || arguments.contains("--preview-tab") { return }
            #endif
            if acceptedWelcome { await autoRead() }
        }
    }

    private var isPreviewSession: Bool {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--preview-tab") || arguments.contains("--preview-document")
        #else
        return false
        #endif
    }

    private func autoRead() async {
        guard !didAutoRead else { return }
        didAutoRead = true
        await model.connect(showErrorAlert: false)
    }

    private var tools: some View {
        Form {
            Section(L("Device")) {
                LabeledContent(L("Model"), value: model.hasDocument ? model.displayedName : UIDevice.current.model)
                LabeledContent("iOS", value: "\(UIDevice.current.systemVersion) (\(VersionSupport.label))")
                LabeledContent(L("Status"), value: L(model.hasDocument ? (model.sourceIsDevice ? "Connected" : "Local File") : (model.isBusy ? "Reading…" : "Not Loaded")))
                if let document = model.working {
                    LabeledContent("CacheExtra", value: String(document.extra.count))
                }
            }
            Section {
                Button { Task { await model.connect() } } label: {
                    Label(L(model.isBusy ? "Reading…" : model.hasDocument ? "Read Again" : "Read MobileGestalt"), systemImage: "arrow.clockwise")
                }.disabled(model.isBusy || model.changeCount > 0)
                Button { importsFile = true } label: { Label(L("Import Plist"), systemImage: "doc.badge.plus") }
                    .disabled(model.isBusy || model.changeCount > 0)
            }
            Section("MobileGestalt") {
                ForEach(CapabilityCategory.allCases) { category in
                    NavigationLink { CategoryView(category: category) } label: {
                        Label(L(category.rawValue), systemImage: category.symbol)
                    }
                    .disabled(!model.hasDocument || model.isBusy)
                }
            }
            Section {
                NavigationLink { ContainerAccessTestView() } label: {
                    Label(L("Container Access Test"), systemImage: "shippingbox")
                }
            }
            Section(L("Actions")) {
                Button { showsChanges = true } label: {
                    HStack {
                        Label(L("Apply Changes"), systemImage: "checkmark")
                        Spacer()
                        if model.changeCount > 0 { Text(String(model.changeCount)).foregroundStyle(.secondary) }
                    }
                }.disabled(model.changeCount == 0 || model.isBusy)
                Button(L("Discard Changes"), role: .destructive) { model.clearStaged() }
                    .disabled(model.changeCount == 0 || model.isBusy)
                Button { Task { await model.backup() } } label: { Label(L("Create Backup"), systemImage: "externaldrive.badge.plus") }
                    .disabled(!model.hasDocument || model.isBusy)
                Button {
                    if let url = model.exportDocument() { sharesFile = SharedFile(url: url) }
                } label: { Label(L("Export Plist"), systemImage: "square.and.arrow.up") }
                    .disabled(!model.hasDocument || model.isBusy)
                Button { asksRespring = true } label: { Label(L("Respring"), systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }
                    .disabled(model.isBusy)
            }
            if model.needsRespring {
                Section { Label(L("Some changes require a device restart."), systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
            }
            Section { NavigationLink { SessionLogView() } label: { Label(L("Log"), systemImage: "text.alignleft") } }
        }
        .navigationTitle("GestaltX")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if model.isBusy { ProgressView() } } }
    }
}

struct CategoryView: View {
    let category: CapabilityCategory
    @EnvironmentObject private var model: GestaltManager
    var body: some View {
        Form {
            if category == .display {
                Section {
                    Picker(L("Dynamic Island Layout"), selection: $model.subtype) {
                        Text(L("Keep Current")).tag(0)
                        Text("iPhone 14 Pro · 2556").tag(2556)
                        Text("iPhone 14 Pro Max · 2796").tag(2796)
                        Text("iPhone 16 Pro · 2622").tag(2622)
                        Text("iPhone 16 Pro Max · 2868").tag(2868)
                    }
                    .onChange(of: model.subtype) { _, value in if value != 0 { model.choices["dynamicIsland"] = .keep } }
                }
            }
            if category == .device {
                Section(L("Device Identity")) {
                    Toggle(L("Change Model Name"), isOn: $model.changesName)
                    if model.changesName {
                        TextField(L("Model Name"), text: $model.modelName).autocorrectionDisabled()
                        Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if category == .intelligence {
                Section {
                    Picker(L("Region Code"), selection: $model.regionCodeID) {
                        ForEach(RegionPreset.all) { Text(L($0.title)).tag($0.id) }
                    }
                    if model.regionCodeID != "keep" { Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary) }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Usually, changing the region code is enough. There is no need to change Sales Region."))
                        Text(L("* If you previously changed Sales Region, restore your device's original sales region and apply it first."))
                    }
                }
                Section {
                    Picker(L("Sales Region"), selection: $model.regionID) {
                        ForEach(RegionPreset.all) { Text(L($0.title)).tag($0.id) }
                    }
                    if model.regionID != "keep" { Text(L("Restart the device after changing the region.")).font(.caption).foregroundStyle(.secondary) }
                } footer: {
                    Text(L("Changing the sales-region suffix may cause verification tools to report a mismatch with factory information."))
                }
            }
            Section(L("Presets")) {
                ForEach(Capability.all.filter { $0.category == category }) { capability in
                    VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: Binding(
                        get: { model.choices[capability.id] ?? .keep },
                        set: {
                            model.choices[capability.id] = $0
                            if capability.id == "dynamicIsland" && $0 != .keep { model.subtype = 0 }
                        }
                    )) {
                        ForEach(PresetChoice.allCases) { Text(L($0.title)).tag($0) }
                    } label: {
                        HStack(spacing: 6) {
                            Text(L(capability.title))
                            if capability.caution {
                                Image(systemName: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
                                    .accessibilityLabel(L("Experimental"))
                            }
                        }
                    }.pickerStyle(.menu)
                    if (model.choices[capability.id] ?? .keep) != .keep {
                        Text(L(capability.effectHint)).font(.caption).foregroundStyle(.secondary)
                    }
                    }
                }
            }
            if category == .ipad || category == .advanced {
                Section { Text(L("Experimental settings. Back up before applying.")).font(.footnote).foregroundStyle(.secondary) }
            }
            if model.changeCount > 0 {
                Section { NavigationLink(L("Review Changes")) { ChangeReviewView(isSheet: false) } }
            }
        }
        .navigationTitle(L(category.rawValue)).disabled(model.isBusy)
    }
}

struct FieldsView: View {
    @EnvironmentObject private var model: GestaltManager
    @State private var search = ""
    @State private var draft: FieldDraft?
    @State private var deletesKey: String?
    private var keys: [String] {
        (model.preview?.extra.keys.sorted() ?? []).filter { key in
            search.isEmpty || key.localizedCaseInsensitiveContains(search) || valueText(key).localizedCaseInsensitiveContains(search)
        }
    }
    private func valueText(_ key: String) -> String {
        guard let value = model.preview?.extra[key] else { return "" }
        let type = PlistValueKind.detect(value)
        if type == .data { return String(format: L("%lld bytes"), Int64((value as? Data)?.count ?? 0)) }
        return type.text(for: value)
    }
    var body: some View {
        List {
            if !model.hasDocument {
                ContentUnavailableView(L("No Document Open"), systemImage: "doc.text.magnifyingglass", description: Text(L("Read or import a plist in Tools.")))
            } else {
                Section {
                    ForEach(keys, id: \.self) { key in
                        Button {
                            guard let value = model.preview?.extra[key] else { return }
                            let kind = PlistValueKind.detect(value)
                            draft = FieldDraft(originalKey: key, key: key, kind: kind, text: kind.text(for: value))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(key).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.primary).lineLimit(2)
                                    Spacer(minLength: 4)
                                    if let value = model.preview?.extra[key] {
                                        Text(L(PlistValueKind.detect(value).rawValue)).font(.caption2).foregroundStyle(Color.gestaltAccent)
                                    }
                                }
                                Text(valueText(key)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 5)
                        }
                        .swipeActions(allowsFullSwipe: false) { Button(L("Delete")) { deletesKey = key }.tint(.red) }
                    }
                } header: { Text("CacheExtra") }
                if keys.isEmpty { ContentUnavailableView.search(text: search) }
            }
        }
        .navigationTitle(L("Fields"))
        .searchable(text: $search, prompt: L("Search keys and values"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { draft = FieldDraft() } label: { Image(systemName: "plus").accessibilityLabel(L("Add Field")) }
                    .disabled(!model.hasDocument || model.isBusy)
            }
        }
        .sheet(item: $draft) { FieldEditorView(draft: $0).environmentObject(model) }.disabled(model.isBusy)
        .alert(L("Delete this field?"), isPresented: Binding(get: { deletesKey != nil }, set: { if !$0 { deletesKey = nil } })) {
            Button(L("Cancel"), role: .cancel) { deletesKey = nil }
            Button(L("Delete"), role: .destructive) { if let key = deletesKey { model.removeField(key) }; deletesKey = nil }
        } message: { Text(L("The deletion is staged. The device file changes only after you apply.")) }
    }
}

struct FieldEditorView: View {
    @State var draft: FieldDraft
    @State private var error: String?
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Key")) {
                    TextField(L("Field Key"), text: $draft.key).font(.system(.subheadline, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section(L("Value")) {
                    Picker(L("Type"), selection: $draft.kind) { ForEach(PlistValueKind.allCases) { Text(L($0.rawValue)).tag($0) } }
                    TextEditor(text: $draft.text).font(.system(.subheadline, design: .monospaced))
                        .frame(minHeight: 150).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if draft.kind == .array || draft.kind == .dictionary {
                    Section { Text(L("Use an XML plist fragment, including the array or dict tags. Nested data and numeric types are preserved.")).font(.footnote).foregroundStyle(.secondary) }
                } else if draft.kind == .data {
                    Section { Text(L("Data values use Base64 encoding.")).font(.footnote).foregroundStyle(.secondary) }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(L(draft.originalKey == nil ? "Add Field" : "Edit Field"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Stage")) {
                        do { try model.stage(draft); dismiss() } catch { self.error = error.localizedDescription }
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}

struct ChangeReviewView: View {
    var isSheet = true
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    @State private var asksApply = false
    var body: some View {
        Group {
            if isSheet { NavigationStack { contents } } else { contents }
        }
    }
    private var contents: some View {
        List {
            Section {
                Label(L(model.sourceIsDevice ? "Write to this device" : "Save local document"), systemImage: model.sourceIsDevice ? "iphone" : "doc.text")
                Text(L(model.sourceIsDevice ? "A backup is created before writing. The result is read back and compared." : "This edits the opened file in GestaltX. Export it to save a copy; the system file is not changed."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let message = model.message { Section { Text(message).font(.footnote).foregroundStyle(.red) } }
            ForEach(model.changeKeys, id: \.self) { key in
                Section {
                    Text(key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    valueRow("Before", value: model.snapshot?.document.extra[key])
                    valueRow("After", value: model.preview?.extra[key])
                    if let capability = Capability.all.first(where: { $0.keys.contains(key) }) {
                        Text(L(capability.effectHint)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button(L(model.sourceIsDevice ? "Apply to Device" : "Save Local Changes")) { asksApply = true }
                    .fontWeight(.semibold).disabled(model.changeCount == 0 || model.isBusy)
                Button(L("Discard Changes"), role: .destructive) { model.clearStaged(); dismiss() }.disabled(model.isBusy)
            }
        }
        .navigationTitle(L("Review Changes")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet { ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { dismiss() }.disabled(model.isBusy) } }
            ToolbarItem(placement: .topBarTrailing) { if model.isBusy { ProgressView() } }
        }
        .alert(L("Apply these changes?"), isPresented: $asksApply) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Apply")) { Task { await model.apply(); if model.changeCount == 0 { dismiss() } } }
        } message: { Text(L(model.sourceIsDevice ? "Incorrect system values can affect device behavior. A verified backup will be kept. No respring is triggered automatically." : "The current local document will be backed up before saving your edits.")) }
    }
    private func valueRow(_ title: String, value: Any?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value.map { PlistValueKind.detect($0).text(for: $0) } ?? L("Not present"))
                .font(.system(.caption, design: .monospaced)).lineLimit(6).textSelection(.enabled)
        }
    }
}

struct BackupsView: View {
    let share: (URL) -> Void
    @EnvironmentObject private var model: GestaltManager
    @State private var restores: BackupRecord?
    @State private var deletes: BackupRecord?
    var body: some View {
        List {
            Section {
                Button { Task { await model.backup() } } label: { Label(L("Create Backup"), systemImage: "plus.circle.fill") }
                    .disabled(!model.hasDocument || model.isBusy)
            }
            if model.backups.isEmpty {
                ContentUnavailableView(L("No Backups"), systemImage: "externaldrive.badge.timemachine", description: Text(L("A backup is created before each write.")))
            }
            ForEach(model.backups) { record in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: record.source == .device ? "iphone" : "doc.text").foregroundStyle(Color.gestaltAccent)
                            Text(L(record.reason)).fontWeight(.medium)
                            Spacer()
                        }
                        Text(record.date, format: .dateTime.year().month().day().hour().minute().second()).font(.subheadline)
                        Text(L(record.source == .device ? "Device Backup" : "Local File Backup") + " · " + ByteCountFormatter.string(fromByteCount: Int64(record.byteCount), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(L("Open")) { Task { await model.openBackup(record) } }
                            Spacer()
                            Button(L("Export")) { Task { if let url = await model.exportBackup(record) { share(url) } } }
                            Spacer()
                            Button(L("Restore")) { restores = record }
                                .disabled(!model.hasDocument || (model.sourceIsDevice && record.source != .device))
                        }.font(.subheadline).buttonStyle(.borderless).padding(.top, 6)
                    }.padding(.vertical, 6)
                }.swipeActions(allowsFullSwipe: false) { Button(L("Delete")) { deletes = record }.tint(.red) }
            }
        }
        .navigationTitle(L("Backups")).disabled(model.isBusy)
        .task { await model.reloadBackups() }
        .refreshable { await model.reloadBackups() }
        .alert(L("Restore this backup?"), isPresented: Binding(get: { restores != nil }, set: { if !$0 { restores = nil } })) {
            Button(L("Cancel"), role: .cancel) { restores = nil }
            Button(L("Restore")) { if let record = restores { Task { await model.restore(record) } }; restores = nil }
        } message: { Text(L("The current document is backed up first. Device restores are verified after writing.")) }
        .alert(L("Delete this backup?"), isPresented: Binding(get: { deletes != nil }, set: { if !$0 { deletes = nil } })) {
            Button(L("Cancel"), role: .cancel) { deletes = nil }
            Button(L("Delete"), role: .destructive) { if let record = deletes { Task { await model.deleteBackup(record) } }; deletes = nil }
        } message: { Text(L("This removes the local backup permanently. It does not change the device file.")) }
    }
}

struct SessionLogView: View {
    @EnvironmentObject private var model: GestaltManager
    var body: some View {
        ScrollView {
            Text(model.logs.isEmpty ? L("No activity yet.") : model.logs.joined(separator: "\n"))
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                .environment(\.layoutDirection, .leftToRight)
        }
        .navigationTitle(L("Session Log"))
        .toolbar { Button(L("Clear")) { model.clearLog() } }
    }
}

struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image("AppMark").resizable().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)).accessibilityHidden(true)
    }
}
extension Color { static let gestaltAccent = Color.blue }
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
