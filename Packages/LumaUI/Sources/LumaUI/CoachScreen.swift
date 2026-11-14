import SwiftUI
import PhotosUI
import LumaCore
import LumaKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Photo plumbing shared by the coach and the fuel log

/// Photos picked or taken for a message or a log entry, held as JPEG data with a thumbnail.
struct PickedPhoto: Identifiable, Equatable {
    let id = UUID()
    let data: Data
    let thumbnail: UIImage

    init?(data: Data) {
        guard let prepared = CoachEngine.prepare(data), let image = UIImage(data: prepared) else { return nil }
        self.data = prepared
        self.thumbnail = image.preparingThumbnail(of: CGSize(width: 240, height: 240 * image.size.height / max(1, image.size.width))) ?? image
    }

    static func == (a: PickedPhoto, b: PickedPhoto) -> Bool { a.id == b.id }
}

/// Loads the photos chosen in a `PhotosPicker` and appends them, up to `limit` in total.
@MainActor
func loadPicked(_ items: [PhotosPickerItem], into photos: Binding<[PickedPhoto]>, limit: Int = CoachEngine.maxPhotos) async {
    for item in items {
        guard photos.wrappedValue.count < limit else { break }
        if let data = try? await item.loadTransferable(type: Data.self), let p = PickedPhoto(data: data) {
            photos.wrappedValue.append(p)
        }
    }
}

/// The system camera, for taking a photo of a meal, label or whiteboard on the spot.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = CameraPicker.isAvailable ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) { parent.onImage(data) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// A strip of attached photos with remove buttons, and buttons to add from the library or camera.
struct PhotoStrip: View {
    @Binding var photos: [PickedPhoto]
    var limit: Int = CoachEngine.maxPhotos
    var size: CGFloat = 64
    @State private var picked: [PhotosPickerItem] = []
    @State private var showCamera = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(photos) { p in
                    Image(uiImage: p.thumbnail).resizable().scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                photos.removeAll { $0.id == p.id }
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Luma.frost)
                                    .frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.7)))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                        }
                }
                if photos.count < limit {
                    PhotosPicker(selection: $picked, maxSelectionCount: limit - photos.count, matching: .images) {
                        addTile("photo.on.rectangle.angled", "Library")
                    }
                    Button { showCamera = true } label: { addTile("camera.fill", "Camera") }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await loadPicked(items, into: $photos, limit: limit)
                picked = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in if let p = PickedPhoto(data: data), photos.count < limit { photos.append(p) } }
                .ignoresSafeArea()
        }
    }

    private func addTile(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
            Text(label).font(LumaFont.label(9))
        }
        .foregroundStyle(Luma.mist)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Luma.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

// MARK: - Coach tab

struct CoachScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @State private var draft = ""
    @State private var photos: [PickedPhoto] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showLibrary = false
    @FocusState private var focused: Bool

    var body: some View {
        CoachBody(coach: env.coach, draft: $draft, photos: $photos, picked: $picked, showCamera: $showCamera, showLibrary: $showLibrary, focused: $focused)
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: router.coachPrompt) { _, prompt in
                guard let prompt else { return }
                router.coachPrompt = nil
                if env.coach.hasKey { env.coach.send(prompt) } else { draft = prompt; router.sheet = .coachSetup }
            }
            .onAppear {
                if let prompt = router.coachPrompt {
                    router.coachPrompt = nil
                    if env.coach.hasKey { env.coach.send(prompt) } else { draft = prompt }
                }
            }
    }
}

private struct CoachBody: View {
    @ObservedObject var coach: CoachEngine
    @Binding var draft: String
    @Binding var photos: [PickedPhoto]
    @Binding var picked: [PhotosPickerItem]
    @Binding var showCamera: Bool
    @Binding var showLibrary: Bool
    var focused: FocusState<Bool>.Binding
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    private let starters = [
        "How recovered am I, and what should I do today?",
        "Plan my training for the next seven days around my classes.",
        "What is moving my recovery up or down?",
        "Am I ready for a HYROX? Which format?",
        "Review my last week of training and sleep.",
    ]

    var body: some View {
        ZStack {
            LumaBackdrop(tone: .hrv)
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if !coach.hasKey {
                                setupCard
                            } else if coach.messages.isEmpty {
                                welcome
                            }
                            ForEach(coach.messages) { m in
                                CoachMessageView(message: m, coach: coach, activity: m.id == coach.messages.last?.id ? coach.activity : nil)
                                    .id(m.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, Luma.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .offset(y: -LumaLaunch.scrollOffset)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: coach.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: coach.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                composer
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await loadPicked(items, into: $photos)
                picked = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in if let p = PickedPhoto(data: data), photos.count < CoachEngine.maxPhotos { photos.append(p) } }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $picked, maxSelectionCount: max(1, CoachEngine.maxPhotos - photos.count), matching: .images)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Coach").font(LumaFont.title(30)).foregroundStyle(Luma.frost)
            Spacer()
            if !coach.messages.isEmpty {
                LumaIconButton(symbol: "square.and.pencil") { coach.newChat() }
            }
            LumaIconButton(symbol: "slider.horizontal.3") { router.sheet = .coachSetup }
        }
        .padding(.horizontal, Luma.gutter)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var setupCard: some View {
        LumaCard(tint: Luma.aqua.opacity(0.6)) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 22, weight: .semibold)).foregroundStyle(Luma.aqua)
                Text("A coach that knows your numbers").font(LumaFont.title(22)).foregroundStyle(Luma.frost)
                LumaNote("Connect your own Anthropic API key and the coach can read your recovery, sleep, training and food log, plan your week, and log meals and supplements from a photo or a sentence. Your key stays in this phone's keychain; requests go straight from the phone to Anthropic.")
                Button("Connect your key") { router.sheet = .coachSetup }.buttonStyle(LumaPrimaryButtonStyle())
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask anything about your training, recovery, sleep or food. Send photos of meals, labels, supplements or the gym whiteboard and I will log them.")
                .font(LumaFont.body(15)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
            ForEach(starters, id: \.self) { s in
                Button {
                    coach.send(s)
                } label: {
                    HStack {
                        Text(s).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.aqua)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(LumaPanel(radius: 18))
                }
                .buttonStyle(.plain)
            }
            if !env.profile.shareHealthWithCoach {
                LumaNote("Sharing health data with the coach is off, so it can only use what you tell it. Turn it on in the coach settings.")
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(photos) { p in
                            Image(uiImage: p.thumbnail).resizable().scaledToFill().frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { photos.removeAll { $0.id == p.id } } label: {
                                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Luma.frost)
                                            .frame(width: 20, height: 20).background(Circle().fill(Color.black.opacity(0.7)))
                                    }
                                    .buttonStyle(.plain).offset(x: 5, y: -5)
                                }
                        }
                    }
                    .padding(.top, 6).padding(.horizontal, 4)
                }
                .scrollIndicators(.hidden)
            }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button { showCamera = true } label: { Label("Take a photo", systemImage: "camera") }
                    Button { showLibrary = true } label: { Label("Choose photos", systemImage: "photo.on.rectangle") }
                } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(Luma.frost)
                        .frame(width: 44, height: 44).background(Circle().fill(Color.white.opacity(0.08)))
                }
                TextField("Message the coach", text: $draft, prompt: Text("Message the coach").foregroundStyle(Luma.smoke), axis: .vertical)
                    .font(LumaFont.body(16)).foregroundStyle(Luma.frost).lineLimit(1...6)
                    .focused(focused)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Luma.line, lineWidth: 1))
                Button {
                    if coach.working {
                        coach.stop()
                    } else if coach.hasKey {
                        coach.send(draft, photos: photos.map { $0.data })
                        draft = ""
                        photos = []
                    } else {
                        router.sheet = .coachSetup
                    }
                } label: {
                    Image(systemName: coach.working ? "stop.fill" : "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(Luma.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(coach.working || !draft.trimmingCharacters(in: .whitespaces).isEmpty || !photos.isEmpty ? Luma.volt : Luma.smoke))
                }
                .buttonStyle(.plain)
                .disabled(!coach.working && draft.trimmingCharacters(in: .whitespaces).isEmpty && photos.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, focused.wrappedValue ? 8 : 84)
        .background(Luma.night.opacity(0.6))
    }
}

// MARK: - Messages

struct CoachMessageView: View {
    let message: CoachMessage
    @ObservedObject var coach: CoachEngine
    let activity: String?
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        if message.role == .user {
            VStack(alignment: .trailing, spacing: 8) {
                if !message.photos.isEmpty { photoRow }
                if !message.text.isEmpty {
                    Text(message.text).font(LumaFont.body(15.5)).foregroundStyle(Luma.frost)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Luma.raised))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 44)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !message.text.isEmpty {
                    MarkdownText(text: message.text, color: message.failed ? Luma.coral : Luma.frost)
                }
                ForEach(message.cards) { card in
                    CoachCardView(card: card, messageID: message.id, coach: coach)
                }
                if let activity {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Luma.aqua)
                        Text(activity).font(LumaFont.body(13.5, .medium)).foregroundStyle(Luma.mist)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var photoRow: some View {
        HStack(spacing: 6) {
            ForEach(message.photos.prefix(4), id: \.self) { name in
                if let data = env.photoData(name), let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if message.photos.count > 4 {
                Text("+\(message.photos.count - 4)").font(LumaFont.numeral(20)).foregroundStyle(Luma.mist).frame(width: 44)
            }
        }
    }
}

struct CoachCardView: View {
    let card: CoachCard
    let messageID: UUID
    @ObservedObject var coach: CoachEngine
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        switch card {
        case .chart(let raw, let days):
            if let metric = LMetric(rawValue: raw) {
                let s = env.series(metric, count: days)
                LumaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        LumaLabel("\(metric.title) · last \(days) days")
                        LumaLineChart(values: s.values, labels: s.keys.map { LumaText.shortDay($0) }, color: metric.tone.color,
                                      band: env.analysis.baselines.baseline(for: metric).map { $0.low...$0.high }, height: 150,
                                      format: { metric.format($0) })
                    }
                }
            }
        case .logged(let ids):
            let entries = env.fuel.filter { ids.contains($0.id) }
            if !entries.isEmpty {
                LumaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Logged", systemImage: "checkmark.circle.fill").font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.mint)
                            Spacer()
                            Button("Undo") { coach.undo(card, in: messageID) }.font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.mist).buttonStyle(.plain)
                        }
                        ForEach(entries) { e in FuelEntryLine(entry: e) }
                    }
                }
            }
        case .planned(let ids):
            let sessions = env.planned.filter { ids.contains($0.id) && $0.status != .removed }.sorted { $0.day < $1.day }
            if !sessions.isEmpty {
                LumaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("On your calendar", systemImage: "calendar.badge.checkmark").font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.volt)
                            Spacer()
                            Button("Undo") { coach.undo(card, in: messageID) }.font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.mist).buttonStyle(.plain)
                        }
                        ForEach(sessions) { p in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: p.kind.sport.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Luma.frost)
                                    .frame(width: 30, height: 30).background(Circle().fill(Color.white.opacity(0.08)))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.title).font(LumaFont.body(15, .semibold)).foregroundStyle(Luma.frost)
                                    Text("\(LumaText.dayTitle(p.day, today: env.today)) · \(p.durationMin) min · \(p.intensity.title)")
                                        .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                                }
                            }
                        }
                        Button("Open the calendar") { router.tab = .train }.font(LumaFont.body(13, .semibold)).foregroundStyle(Luma.volt).buttonStyle(.plain)
                    }
                }
            }
        case .note(let fact):
            Label("Noted: \(fact)", systemImage: "bookmark.fill").font(LumaFont.body(13)).foregroundStyle(Luma.mist)
        case .done(let text):
            Label(text, systemImage: "checkmark.circle.fill").font(LumaFont.body(13, .medium)).foregroundStyle(Luma.mint)
        }
    }
}

/// One logged entry on a single line: what it was and its energy and protein.
struct FuelEntryLine: View {
    let entry: FuelEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.title).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost).lineLimit(2)
            Spacer(minLength: 6)
            switch entry.kind {
            case .water:
                Text("\(Int(entry.waterMl ?? 0)) ml").font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.sky)
            case .supplement:
                Text(entry.supplement?.text ?? "").font(LumaFont.numeral(17, .semibold)).foregroundStyle(Luma.mint)
            default:
                Text("\(Int(entry.kcal.rounded())) kcal · \(Int(entry.proteinG.rounded())) g protein").font(LumaFont.numeral(16, .semibold)).foregroundStyle(Luma.mist)
            }
        }
    }
}

// MARK: - Markdown

/// Renders the coach's replies: paragraphs, bullets, numbered steps and headings, with inline
/// emphasis. Tables fall back to plain lines.
struct MarkdownText: View {
    let text: String
    var color: Color = Luma.frost

    private enum Block: Identifiable {
        case paragraph(Int, String), bullet(Int, String), numbered(Int, String, String), heading(Int, String)
        var id: Int {
            switch self {
            case .paragraph(let i, _), .bullet(let i, _), .heading(let i, _): return i
            case .numbered(let i, _, _): return i
            }
        }
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var index = 0
        func flush() {
            if !paragraph.isEmpty { out.append(.paragraph(index, paragraph.joined(separator: " "))); index += 1; paragraph = [] }
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                out.append(.heading(index, line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))); index += 1
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                flush()
                out.append(.bullet(index, String(line.dropFirst(2)))); index += 1
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy({ $0.isNumber }), !line[..<dot].isEmpty,
                      line.index(after: dot) < line.endIndex, line[line.index(after: dot)] == " " {
                flush()
                out.append(.numbered(index, String(line[..<dot]), String(line[line.index(dot, offsetBy: 2)...]))); index += 1
            } else if line.hasPrefix("|") {
                flush()
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { out.append(.paragraph(index, cells.joined(separator: "  ·  "))); index += 1 }
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return out
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(blocks) { block in
                switch block {
                case .paragraph(_, let s):
                    Text(inline(s)).font(LumaFont.body(15.5)).foregroundStyle(color).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                case .heading(_, let s):
                    Text(inline(s)).font(LumaFont.heading(16)).foregroundStyle(color).padding(.top, 4).fixedSize(horizontal: false, vertical: true)
                case .bullet(_, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle().fill(Luma.aqua).frame(width: 5, height: 5).offset(y: -2)
                        Text(inline(s)).font(LumaFont.body(15.5)).foregroundStyle(color).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(_, let n, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(n).font(LumaFont.numeral(16, .bold)).foregroundStyle(Luma.aqua).frame(minWidth: 16, alignment: .trailing)
                        Text(inline(s)).font(LumaFont.body(15.5)).foregroundStyle(color).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - Setup

struct CoachSetupSheet: View {
    @EnvironmentObject private var env: LumaEnv

    var body: some View { CoachSetupBody(coach: env.coach) }
}

private struct CoachSetupBody: View {
    @ObservedObject var coach: CoachEngine
    @EnvironmentObject private var env: LumaEnv
    @State private var key = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        LumaSheet(title: "Coach settings", tone: .hrv) {
            if coach.hasKey {
                LumaGroup {
                    LumaRow(symbol: "checkmark.seal.fill", symbolColor: Luma.mint, title: "Connected to Anthropic",
                            subtitle: "Your key is stored in this phone's keychain.") {
                        Button("Remove") { coach.disconnect() }.font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.coral).buttonStyle(.plain)
                    }
                }
            } else {
                Text("Connect your API key").font(LumaFont.heading(17)).foregroundStyle(Luma.frost)
                LumaNote("Create a key at console.anthropic.com and paste it here. Luma sends requests straight from this phone to Anthropic and you pay Anthropic for what you use.")
                SecureField("sk-ant-…", text: $key, prompt: Text("sk-ant-…").foregroundStyle(Luma.smoke))
                    .font(LumaFont.body(16)).foregroundStyle(Luma.frost).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: Luma.radiusControl, style: .continuous).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: Luma.radiusControl, style: .continuous).strokeBorder(Luma.line, lineWidth: 1))
                if let error { Text(error).font(LumaFont.body(13.5)).foregroundStyle(Luma.coral).fixedSize(horizontal: false, vertical: true) }
                Button {
                    busy = true; error = nil
                    Task {
                        do { try await coach.connect(key: key); key = "" } catch let e { error = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }
                        busy = false
                    }
                } label: {
                    if busy { ProgressView().tint(Luma.ink) } else { Text("Connect") }
                }
                .buttonStyle(LumaPrimaryButtonStyle())
                .disabled(busy || key.trimmingCharacters(in: .whitespaces).count < 10)
            }

            LumaSection(title: "What the coach can see")
            LumaGroup {
                Toggle(isOn: $env.profile.shareHealthWithCoach) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Share my health data").font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                        Text("Lets the coach read your recovery, sleep, heart, training and food data when a question needs it. That data is sent to Anthropic with the question. Off: the coach only knows what you type.")
                            .font(LumaFont.body(12.5)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Luma.volt)
                .padding(.vertical, 12).padding(.horizontal, 16)
            }

            if coach.hasKey {
                LumaSection(title: "Model")
                if coach.models.isEmpty {
                    Button("Load available models") { Task { try? await coach.loadModels() } }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                } else {
                    LumaGroup {
                        ForEach(coach.models) { m in
                            let chosen = env.profile.coachModel ?? AIModel.preferred(coach.models)?.id
                            Button {
                                env.profile.coachModel = m.id
                            } label: {
                                LumaRow(symbol: nil, title: m.name, subtitle: m.id) {
                                    if chosen == m.id { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Luma.volt) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    LumaNote("Larger models reason better and cost more per message; smaller ones answer faster.")
                }
            }

            if !coach.notes.isEmpty {
                LumaSection(title: "What the coach remembers")
                LumaGroup {
                    ForEach(coach.notes, id: \.self) { note in
                        LumaRow(symbol: "bookmark.fill", symbolColor: Luma.aqua, title: note) {
                            Button { coach.forget(note) } label: { Image(systemName: "trash").foregroundStyle(Luma.smoke) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task { if coach.hasKey && coach.models.isEmpty { try? await coach.loadModels() } }
    }
}
