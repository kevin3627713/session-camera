import SwiftUI
import Photos
import UIKit

@main struct PhotosNavigationProbeApp: App {
    @StateObject private var model = ProbeModel()
    var body: some Scene {
        WindowGroup { ProbeHome(model: model) }
    }
}

@MainActor final class ProbeModel: ObservableObject {
    @Published var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var albums: [ProbeAlbum] = []
    @Published var album: ProbeAlbum?
    @Published var assetID = ""
    @Published var identifiers: ProbeIdentifiers?
    @Published var candidateID = "A"
    @Published var route = ProbeRoute.share
    @Published var customURL = ""
    @Published var useCustom = false
    @Published var busy = false
    @Published var message = ""
    @Published var records: [ProbeRecord] = []
    private var loaded = false
    private var selectionNonce = UUID()
    private let store = UserDefaults.standard
    private let observations = ["尚未填写", "无反应", "只进入相册总列表", "只进入目标相册", "在所有照片中打开大图",
                                "在目标相册网格定位照片", "在目标相册中打开大图", "其他"]
    var observationChoices: [String] { observations }
    var candidates: [ProbeCandidate] { identifiers.map(ProbeCandidate.all) ?? [] }
    var currentCandidate: ProbeCandidate? { candidates.first { $0.id == candidateID } }
    var currentURL: URL? {
        let url = useCustom ? URL(string: customURL.trimmingCharacters(in: .whitespacesAndNewlines)) : currentCandidate?.url
        return url.flatMap { ProbeCandidate.permitted($0) ? $0 : nil }
    }

    func load() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if !loaded {
            loaded = true
            if let data = store.data(forKey: "probeRecords"), let saved = try? JSONDecoder().decode([ProbeRecord].self, from: data) {
                records = saved
            }
            route = ProbeRoute(rawValue: store.string(forKey: "probeRoute") ?? "share") ?? .share
            candidateID = store.string(forKey: "probeCandidate") ?? "A"
            customURL = store.string(forKey: "probeCustomURL") ?? ""
        }
        guard status == .authorized else { albums = []; identifiers = nil; return }
        Task {
            let found = await Task.detached { ProbePhotoLibrary.albums() }.value
            albums = found
            if let current = album { album = found.first { $0.id == current.id } }
            else if let id = store.string(forKey: "probeAlbumID") { album = found.first { $0.id == id } }
            if assetID.isEmpty { assetID = store.string(forKey: "probeAssetID") ?? "" }
            if album != nil && !assetID.isEmpty && identifiers == nil { resolveSelection() }
        }
    }

    func authorize() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in Task { @MainActor in self.load() } }
    }
    func select(_ value: ProbeAlbum) {
        selectionNonce = UUID()
        album = value; assetID = ""; identifiers = nil; message = ""
        store.set(value.id, forKey: "probeAlbumID")
        store.removeObject(forKey: "probeAssetID")
    }
    func selectAsset(_ id: String) {
        assetID = id; identifiers = nil
        store.set(id, forKey: "probeAssetID")
        resolveSelection()
    }
    func resolveSelection() {
        guard let album, !assetID.isEmpty else { return }
        let photoID = assetID, albumID = album.id, token = UUID()
        selectionNonce = token; busy = true; message = "正在取得并核对真实标识…"
        Task {
            do {
                let resolved = try await Task.detached(priority: .userInitiated) {
                    try ProbePhotoLibrary.resolve(assetID: photoID, albumID: albumID)
                }.value
                guard selectionNonce == token else { return }
                identifiers = resolved; message = resolved.mappingNotes.joined(separator: "\n")
            } catch {
                guard selectionNonce == token else { return }
                message = error.localizedDescription
            }
            busy = false
        }
    }

    func inspectOnly() {
        guard !busy, let ids = identifiers, let url = currentURL else { return }
        busy = true
        let id = beginRecord(ids, url: url, route: "inspect-only")
        Task {
            let parser = await Task.detached { Self.json(PNInspectURL(url)) }.value
            update(id) { $0.parser = parser }
            message = parser; busy = false
        }
    }

    func run() {
        guard !busy, let ids = identifiers, let url = currentURL else { return }
        busy = true; message = "正在解析与派发…"
        let method = route
        let id = beginRecord(ids, url: url, route: method.rawValue)
        store.set(method.rawValue, forKey: "probeRoute")
        store.set(candidateID, forKey: "probeCandidate")
        store.set(customURL, forKey: "probeCustomURL")
        Task {
            let parser = await Task.detached { Self.json(PNInspectURL(url)) }.value
            update(id) { $0.parser = parser }
            switch method {
            case .standard:
                UIApplication.shared.open(url, options: [:]) { accepted in
                    Task { @MainActor in self.finish(id, Self.json(["accepted": accepted, "method": "UIApplication.open"])) }
                }
            case .direct, .sensitive:
                let result = await Task.detached { Self.json(PNWorkspaceDispatch(url, method == .sensitive)) }.value
                finish(id, result)
            case .share, .shareSensitive:
                PNDispatchThroughShare(url, method == .shareSensitive) { result in
                    let text = Self.json(result)
                    Task { @MainActor in self.finish(id, text) }
                }
            case .frontBoard, .shareFrontBoard:
                let callback: ([AnyHashable: Any]) -> Void = { result in
                    let text = Self.json(result)
                    Task { @MainActor in self.finish(id, text) }
                }
                if method == .shareFrontBoard {
                    PNDispatchFrontBoardThroughShare(url, callback)
                } else {
                    let state = UIApplication.shared.applicationState
                    let context = state == .active ? "application-active" : (state == .background ? "application-background" : "application-inactive")
                    PNFrontBoardDispatch(url, context, callback)
                }
            }
        }
    }

    private func beginRecord(_ ids: ProbeIdentifiers, url: URL, route: String) -> String {
        let id = UUID().uuidString
        let inspectOnly = route == "inspect-only"
        let record = ProbeRecord(id: id, started: ISO8601DateFormatter().string(from: Date()),
                                 candidate: useCustom ? "自定义" : candidateID, route: route,
                                 url: url.absoluteString, identifiers: ids, parser: "等待解析",
                                 dispatch: inspectOnly ? "未执行跳转（仅检查解析）" : "等待派发回调",
                                 observation: inspectOnly ? "未执行（仅检查解析）" : "尚未填写")
        records.insert(record, at: 0); records = Array(records.prefix(30)); save()
        return id
    }

    func clearRecords() {
        guard !busy else { return }
        records = []
        store.removeObject(forKey: "probeRecords")
        message = "测试记录已清空，可以开始新一轮测试。"
    }

    func resetData() {
        guard !busy else { return }
        selectionNonce = UUID()
        for key in ["probeRecords", "probeRoute", "probeCandidate", "probeCustomURL", "probeAlbumID", "probeAssetID"] {
            store.removeObject(forKey: key)
        }
        records = []; album = nil; assetID = ""; identifiers = nil
        candidateID = "A"; route = .share; customURL = ""; useCustom = false
        message = "诊断数据已重置，请重新选择相册和照片。"
    }

    private func finish(_ id: String, _ result: String) {
        update(id) { $0.dispatch = result }
        message = "派发结果已保存；返回后请记录实际打开的页面。"
        busy = false
    }
    func observe(_ id: String, _ value: String) { update(id) { $0.observation = value } }
    private func update(_ id: String, _ edit: (inout ProbeRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        edit(&records[index]); save()
    }
    private func save() { if let data = try? JSONEncoder().encode(records) { store.set(data, forKey: "probeRecords") } }
    nonisolated static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return String(describing: object) }
        return text
    }
    var identifierText: String {
        guard let ids = identifiers else { return "请先选择相册和照片" }
        return "相册：\(ids.albumName)\n相册本机标识：\(ids.albumLocalID)\n相册 UUID：\(ids.albumUUID ?? "不可用")\n相册云标识：\(ids.albumCloudID ?? "不可用")\n照片本机标识：\(ids.assetLocalID)\n照片 UUID：\(ids.assetUUID ?? "不可用")\n照片云标识：\(ids.assetCloudID ?? "不可用")\n\(ids.mappingNotes.joined(separator: "\n"))"
    }
    var linkText: String {
        candidates.map { "\($0.title)\n\($0.url?.absoluteString ?? "所需标识不可用")" }.joined(separator: "\n\n")
    }
    var report: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let history = (try? encoder.encode(records)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "照片跳转诊断 \(version)（build \(build)）\niOS \(UIDevice.current.systemVersion)\nBundle \(Bundle.main.bundleIdentifier ?? "")\n\n\(identifierText)\n\n测试记录：\n\(history)"
    }
}

struct ProbeHome: View {
    @ObservedObject var model: ProbeModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAlbums = false
    @State private var showPhotos = false
    @State private var copied = false
    @State private var confirmClear = false
    @State private var confirmReset = false
    var body: some View {
        NavigationStack {
            Form {
                if model.status != .authorized {
                    Section("照片访问") {
                        Text("允许完整照片访问后，选择一个相册和其中一张照片进行跳转测试。")
                        if model.status == .notDetermined { Button("允许照片访问", action: model.authorize) }
                        else { Button("打开权限设置") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } }
                    }
                } else {
                    Section("测试目标") {
                        Button { showAlbums = true } label: {
                            Label(model.album?.name ?? "选择相册", systemImage: "rectangle.stack")
                        }
                        Button { showPhotos = true } label: {
                            HStack {
                                if !model.assetID.isEmpty { ProbeThumbnail(assetID: model.assetID).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8)) }
                                Label(model.assetID.isEmpty ? "选择相册中的照片" : "更换目标照片", systemImage: "photo")
                            }
                        }.disabled(model.album == nil)
                        if model.identifiers != nil {
                            Button("复制全部真实标识") { copy(model.identifierText) }
                            DisclosureGroup("查看标识") { Text(model.identifierText).font(.caption.monospaced()).textSelection(.enabled) }
                        }
                    }.disabled(model.busy)
                    if model.identifiers != nil {
                        Section("链接") {
                            Toggle("使用自定义 URL", isOn: $model.useCustom)
                            if model.useCustom {
                                TextEditor(text: $model.customURL).font(.caption.monospaced()).frame(minHeight: 100)
                                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                                Button("填入当前预设链接") { model.customURL = model.currentCandidate?.url?.absoluteString ?? "" }
                            } else {
                                Picker("测试预设", selection: $model.candidateID) {
                                    ForEach(model.candidates) { item in Text(item.title).tag(item.id) }
                                }
                                Text(model.currentCandidate?.detail ?? "").font(.caption).foregroundStyle(.secondary)
                                Text(model.currentCandidate?.url?.absoluteString ?? "所需标识不可用，请尝试其他预设")
                                    .font(.caption.monospaced()).textSelection(.enabled)
                            }
                            Button("复制当前 URL") { if let url = model.currentURL { copy(url.absoluteString) } }.disabled(model.currentURL == nil)
                            Button("复制全部预设 URL") { copy(model.linkText) }
                        }.disabled(model.busy)
                        Section("执行") {
                            Picker("派发方式", selection: $model.route) {
                                ForEach(ProbeRoute.allCases) { item in Text(item.title).tag(item) }
                            }
                            Button("只检查系统解析结果", action: model.inspectOnly).disabled(model.busy || model.currentURL == nil)
                            Button("执行跳转测试", action: model.run).disabled(model.busy || model.currentURL == nil)
                            Text("本轮选择 C，只测试方式 6、7；打开照片后核对返回页面和相邻照片是否属于目标相册。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if model.busy { Section { ProgressView("正在处理…") } }
                if !model.message.isEmpty { Section("状态") { Text(model.message).font(.caption.monospaced()).textSelection(.enabled) } }
                Section("报告") {
                    Button("复制完整诊断报告") { copy(model.report) }
                    ShareLink("分享诊断报告", item: model.report)
                    Text("最近 30 次测试保存在本机，报告包含所选照片和相册的标识。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("数据管理") {
                    Button("清空测试记录", role: .destructive) { confirmClear = true }
                        .disabled(model.busy || model.records.isEmpty)
                    Text("清空历史记录，保留当前相册、照片和链接设置。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("重置全部诊断数据", role: .destructive) { confirmReset = true }
                        .disabled(model.busy)
                    Text("清空历史记录、已选目标和链接设置，恢复默认配置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.records) { record in
                    Section("\(record.candidate) · \(record.routeTitle)") {
                        if record.route == "inspect-only" {
                            Text("仅检查解析，未执行跳转").foregroundStyle(.secondary)
                        } else {
                            Picker("实际页面", selection: Binding(get: {
                                model.records.first { $0.id == record.id }?.observation ?? "尚未填写"
                            }, set: { model.observe(record.id, $0) })) {
                                ForEach(model.observationChoices, id: \.self) { Text($0).tag($0) }
                            }
                        }
                        DisclosureGroup("解析与派发详情") {
                            Text("\(record.started)\n\(record.url)\n\n解析：\n\(record.parser)\n\n派发：\n\(record.dispatch)")
                                .font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("照片跳转诊断")
            .task { model.load() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { model.load() } }
            .sheet(isPresented: $showAlbums) { ProbeAlbumPicker(albums: model.albums) { model.select($0) } }
            .sheet(isPresented: $showPhotos) { if let album = model.album { ProbePhotoPicker(album: album) { model.selectAsset($0) } } }
            .alert("已复制", isPresented: $copied) { Button("好", role: .cancel) {} }
            .confirmationDialog("清空全部测试记录？当前相册和照片会保留。", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空记录", role: .destructive, action: model.clearRecords)
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("重置全部诊断数据？之后需要重新选择相册和照片。", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("重置诊断数据", role: .destructive, action: model.resetData)
                Button("取消", role: .cancel) {}
            }
        }
    }
    private func copy(_ text: String) { UIPasteboard.general.string = text; copied = true }
}

struct ProbeAlbumPicker: View {
    let albums: [ProbeAlbum]
    let select: (ProbeAlbum) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List(albums.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { album in
                Button { select(album); dismiss() } label: {
                    Label(album.name, systemImage: album.smart ? "sparkles.rectangle.stack" : "rectangle.stack")
                }
            }
            .searchable(text: $search, prompt: "搜索相册")
            .navigationTitle("选择相册")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct ProbePhotoPicker: View {
    let album: ProbeAlbum
    let select: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var assets: PHFetchResult<PHAsset>?
    @State private var limit = 120
    var body: some View {
        NavigationStack {
            ScrollView {
                if let assets {
                    if assets.count == 0 { ContentUnavailableView("没有可选照片", systemImage: "photo") }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                        ForEach(0..<min(limit, assets.count), id: \.self) { index in
                            let id = assets.object(at: index).localIdentifier
                            Button { select(id); dismiss() } label: {
                                ProbeThumbnail(assetID: id).aspectRatio(1, contentMode: .fit).clipped()
                            }.buttonStyle(.plain)
                        }
                    }
                    if limit < assets.count { Button("加载更多（\(limit) / \(assets.count)）") { limit += 120 }.padding() }
                } else { ProgressView().padding() }
            }
            .navigationTitle(album.name)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task {
                assets = await Task.detached {
                    guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [album.id], options: nil).firstObject else { return nil as PHFetchResult<PHAsset>? }
                    return PHAsset.fetchAssets(in: collection, options: ProbePhotoLibrary.options())
                }.value
            }
        }
    }
}

struct ProbeThumbnail: View {
    let assetID: String
    @State private var image: UIImage?
    @State private var request = PHInvalidImageRequestID
    @State private var token = UUID()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.secondary.opacity(0.12)
                if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .onAppear(perform: load)
        .onDisappear { token = UUID(); if request != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(request); request = PHInvalidImageRequestID } }
        .onChange(of: assetID) { _, _ in image = nil; load() }
    }
    private func load() {
        if request != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(request) }
        let current = UUID(); token = current
        guard image == nil, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject, !asset.isHidden else { return }
        let options = PHImageRequestOptions(); options.deliveryMode = .opportunistic; options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        request = PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 360, height: 360),
            contentMode: .aspectFill, options: options) { value, info in
                guard (info?[PHImageCancelledKey] as? Bool) != true else { return }
                DispatchQueue.main.async { if token == current { image = value } }
            }
    }
}
