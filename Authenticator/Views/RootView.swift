import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model

    @State private var showsAddSheet = false
    @State private var showsCameraSheet = false
    @State private var showsExportSheet = false
    @State private var showsFileImporter = false
    @State private var showsPhotosPicker = false
    @State private var importResult: ImportCoordinator.Result?
    @State private var detailAccount: Account?
    @State private var photoItem: PhotosPickerItem?
    @State private var isDropTargeted = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var model = model

        Group {
            if model.lock.isLocked {
                LockScreenView()
            } else {
                mainInterface(model: model)
            }
        }
        .frame(minWidth: 380, minHeight: 460)
        .sheet(isPresented: $showsAddSheet) { AddAccountSheet() }
        .sheet(isPresented: $showsCameraSheet) { CameraScanSheet() }
        .sheet(isPresented: $showsExportSheet) { ExportSheet() }
        .sheet(item: $importResult) { result in
            ImportResultSheet(result: result)
        }
        .sheet(item: $detailAccount) { account in
            AccountDetailView(account: account)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: ImageLoading.supportedContentTypes,
            allowsMultipleSelection: true
        ) { outcome in
            handleFileImport(outcome)
        }
        // No `photoLibrary:` argument on purpose — the default picker runs out of
        // process and needs no Photos authorization.
        .photosPicker(
            isPresented: $showsPhotosPicker,
            selection: $photoItem,
            matching: .images
        )
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await handlePhotoPick(item) }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onReceive(AppCommands.publisher) { command in
            handle(command)
        }
    }

    // MARK: - Main interface

    private func mainInterface(model: AppModel) -> some View {
        @Bindable var model = model

        return VStack(spacing: 0) {
            SearchField(text: $model.searchText, isFocused: $searchFocused)
            Divider()
            AccountListView(onShowDetail: { detailAccount = $0 })
        }
        .toolbar { toolbarContent }
        .overlay(alignment: .bottom) { statusBanner }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Scan with Camera…") { showsCameraSheet = true }
                Button("Import from Image…") { showsFileImporter = true }
                // A plain Button, not a PhotosPicker: macOS builds Menu content as an
                // NSMenu, where only button-like items are interactive. The picker
                // itself is attached to the main view below.
                Button("Choose from Photos…") { showsPhotosPicker = true }
                Button("Paste Setup Link…") { showsAddSheet = true }
            } label: {
                Label("Add Account", systemImage: "plus")
            } primaryAction: {
                showsAddSheet = true
            }
            .help("Add an account")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                showsExportSheet = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(model.accounts.isEmpty)
            .help("Export accounts as QR codes")
        }
        ToolbarItem(placement: .automatic) {
            Button {
                model.lock.lock()
            } label: {
                Label("Lock", systemImage: "lock")
            }
            .help("Lock now")
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let message = model.statusMessage {
            Text(message)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { model.statusMessage = nil }
                }
        }
    }

    // MARK: - Import handling

    private func handle(_ command: AppCommands.Command) {
        switch command {
        case .addAccount: showsAddSheet = true
        case .scanCamera: showsCameraSheet = true
        case .importImage: showsFileImporter = true
        case .export: showsExportSheet = true
        case .focusSearch: searchFocused = true
        case .copySelectedCode:
            if let selection = model.selection,
               let account = model.accounts.first(where: { $0.id == selection }) {
                model.copyCode(for: account)
            }
        }
    }

    private func handleFileImport(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case .success(let urls):
            Task {
                let images = urls.flatMap { ImageLoading.images(at: $0) }
                importResult = await ImportCoordinator.accounts(fromImages: images)
            }
        case .failure(let error):
            model.errorMessage = error.localizedDescription
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                model.errorMessage = "That photo could not be read."
                return
            }
            let images = ImageLoading.images(from: data)
            importResult = await ImportCoordinator.accounts(fromImages: images)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        Task {
            var images: [CGImage] = []
            for provider in providers {
                images.append(contentsOf: await ImageLoading.images(from: provider))
            }
            guard !images.isEmpty else {
                model.errorMessage = "That file did not contain a readable image."
                return
            }
            importResult = await ImportCoordinator.accounts(fromImages: images)
        }
    }
}

/// Lets the sheet-presenting `.sheet(item:)` modifier carry an import result.
extension ImportCoordinator.Result: Identifiable {
    public var id: String {
        accounts.map(\.identityKey).joined(separator: "|") + problems.joined(separator: "|")
    }
}
