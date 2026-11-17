import SwiftUI
import LumaCore
import LumaKit
#if canImport(UIKit)
import UIKit
#endif

/// Wraps children onto as many lines as they need (chips, tags).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}

// MARK: - Fuel tab

struct FuelScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @State private var day: String = ""
    @State private var expanded: UUID?

    private var active: String { day.isEmpty ? env.today : day }

    var body: some View {
        let totals = env.fuelTotals(on: active)
        let target = env.fuelTargets(on: active)
        let entries = env.fuelEntries(on: active)
        let food = entries.filter { $0.kind != .water && $0.kind != .supplement }
        LumaTabScreen(title: "Fuel", subtitle: target.dayClass.title, tone: .fuel) {
            LumaIconButton(symbol: "chart.bar.fill") { router.push(.fuelHistory) }
        } content: {
            DayStepper(day: Binding(get: { active }, set: { day = $0 }), earliest: LDate.adding(-365, to: env.today), today: env.today)
            EnergyHero(totals: totals, target: target)
            HStack(spacing: 8) {
                LumaQuickAction(symbol: "camera.fill", title: "Photo", tint: Luma.mint) { router.sheet = .fuelAdd(.photo) }
                LumaQuickAction(symbol: "square.and.pencil", title: "Type", tint: Luma.mint) { router.sheet = .fuelAdd(.meal) }
                LumaQuickAction(symbol: "pills.fill", title: "Tablets", tint: Luma.mint) { router.sheet = .fuelAdd(.supplement) }
            }
            WaterCard(totals: totals, target: target, day: active)
            SupplementChecklist(day: active)
            BodyTeaser()

            LumaSection(title: "Eaten", action: food.isEmpty ? nil : "\(food.count) logged", onAction: {})
            if food.isEmpty {
                LumaCard {
                    LumaEmpty(symbol: "fork.knife", title: active == env.today ? "Nothing logged yet today" : "Nothing logged this day",
                              message: "Take a photo of your plate or a nutrition label, or type what you ate. Luma works out the numbers.",
                              action: "Log a meal") { router.sheet = .fuelAdd(.photo) }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(food) { e in
                        FuelEntryCard(entry: e, expanded: expanded == e.id) {
                            withAnimation(LumaMotion.snap) { expanded = expanded == e.id ? nil : e.id }
                        }
                    }
                }
            }
            if totals.caffeineMg > 0 || totals.alcoholG > 0 {
                StatGrid {
                    StatCell(label: "Caffeine", value: String(format: "%.0f", totals.caffeineMg), unit: "mg",
                             note: "Sensible daily limit \(Int(target.caffeineLimitMg)) mg", color: totals.caffeineMg > target.caffeineLimitMg ? Luma.amber : Luma.frost)
                    StatCell(label: "Alcohol", value: String(format: "%.0f", totals.alcoholG), unit: "g",
                             note: totals.alcoholG > 0 ? "About \(String(format: "%.1f", totals.alcoholG / 10)) units" : nil)
                }
            }
            FuelMatchCard(day: active)
            FuelCuesCard(day: active)
            Button { router.push(.dose) } label: {
                LumaRow(symbol: "clock.badge.questionmark", symbolColor: Luma.dusk, title: "How much and how late",
                        subtitle: "Caffeine, alcohol, your last meal and bedtime against the morning after", chevron: true)
                    .background(LumaPanel(radius: 22))
            }
            .buttonStyle(.plain)
            Button {
                router.askCoach("Look at my food log for the last 7 days against my targets and training. What should I change?")
            } label: {
                Label("Ask the coach about my fuelling", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(LumaSecondaryButtonStyle())
        }
    }
}

/// Energy eaten against the day's target, with the three macros beside it.
struct EnergyHero: View {
    let totals: FuelTotals
    let target: FuelTargets
    @State private var shown: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                LumaRing(progress: target.kcal > 0 ? shown / target.kcal : 0, lineWidth: 12, colors: [Luma.aqua, Luma.mint])
                VStack(spacing: -2) {
                    Text(LFormat.grouped(totals.kcal)).font(LumaFont.numeral(38, .heavy)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                    LumaLabel("of \(LFormat.grouped(target.kcal)) kcal")
                }
            }
            .frame(width: 138, height: 138)
            VStack(spacing: 11) {
                macro("Protein", totals.proteinG, target.proteinG, Luma.coral)
                macro("Carbs", totals.carbsG, target.carbsG, Luma.amber)
                macro("Fat", totals.fatG, target.fatG, Luma.sky)
            }
        }
        .padding(.vertical, 4)
        .onAppear { withAnimation(LumaMotion.reveal) { shown = totals.kcal } }
        .onChange(of: totals.kcal) { _, new in withAnimation(LumaMotion.update) { shown = new } }
    }

    private func macro(_ label: String, _ value: Double, _ goal: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                LumaLabel(label)
                Spacer()
                Text("\(Int(value.rounded()))").font(LumaFont.numeral(19, .semibold)).foregroundStyle(Luma.frost)
                Text("/ \(Int(goal.rounded())) g").font(LumaFont.body(11.5)).foregroundStyle(Luma.smoke)
            }
            LumaBar(value: value, total: goal, color: color, height: 6)
        }
    }
}

struct WaterCard: View {
    let totals: FuelTotals
    let target: FuelTargets
    let day: String
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "drop.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.sky)
                    LumaLabel("Water")
                    Spacer()
                    Text(String(format: "%.1f", totals.waterMl / 1000)).font(LumaFont.numeral(26)).foregroundStyle(Luma.frost).contentTransition(.numericText())
                    Text("of \(String(format: "%.1f", target.waterMl / 1000)) L").font(LumaFont.body(12.5)).foregroundStyle(Luma.smoke)
                }
                LumaBar(value: totals.waterMl, total: target.waterMl, color: Luma.sky)
                HStack(spacing: 8) {
                    ForEach([250.0, 330, 500, 750], id: \.self) { ml in
                        LumaQuickAction(symbol: "plus", title: "\(Int(ml))", tint: Luma.sky) {
                            env.logWater(ml, at: stamp())
                            LumaHaptics.success()
                        }
                    }
                }
            }
        }
    }

    /// Now for today; midday for a past day.
    private func stamp() -> Date {
        day == env.today ? Date() : (LDate.date(day) ?? Date())
    }
}

/// Today's supplement stack as a tick list.
struct SupplementChecklist: View {
    let day: String
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter

    var body: some View {
        let stack = env.supplements.filter { $0.active }
        let extras = env.fuelEntries(on: day).filter { e in e.kind == .supplement && !stack.contains { $0.dose.name == e.title } }
        VStack(alignment: .leading, spacing: 12) {
            LumaSection(title: "Supplements", action: "Manage") { router.push(.supplements) }
            if stack.isEmpty && extras.isEmpty {
                LumaCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No stack yet").font(LumaFont.heading(16)).foregroundStyle(Luma.frost)
                        LumaNote("Add what you take regularly and tick it off each day, or log a one-off from a photo of the bottle.")
                        Button("Add supplements") { router.sheet = .fuelAdd(.supplement) }.buttonStyle(LumaSecondaryButtonStyle(compact: true))
                    }
                }
            } else {
                LumaGroup {
                    ForEach(stack) { s in
                        let taken = env.supplementTaken(s, on: day)
                        let trial = env.trialNote(for: s.dose.name, on: day)
                        Button {
                            if taken == nil { LumaHaptics.success() } else { LumaHaptics.select() }
                            if let t = taken { env.delete(t) } else { env.logSupplement(s.dose, at: day == env.today ? Date() : (LDate.date(day) ?? Date())) }
                        } label: {
                            HStack(spacing: 13) {
                                LumaTick(on: taken != nil, size: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.dose.name).font(LumaFont.body(15, .medium)).foregroundStyle(Luma.frost)
                                    Text("\(s.dose.text) · \(s.timing.title)").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                                    if let trial {
                                        Text(trial.text).font(LumaFont.body(12.5, .medium)).foregroundStyle(trial.on ? Luma.mint : Luma.amber)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer()
                                if let t = taken { Text(LumaText.time(t.at.timeIntervalSince1970)).font(LumaFont.body(12)).foregroundStyle(Luma.smoke) }
                            }
                            .padding(.vertical, 11).padding(.horizontal, 16).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(extras) { e in
                        LumaRow(symbol: "pills.fill", symbolColor: Luma.mint, title: e.title, subtitle: e.supplement?.text) {
                            Button { env.delete(e) } label: { Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Luma.smoke) }.buttonStyle(.plain)
                        }
                    }
                    Button { router.push(.trials) } label: {
                        LumaRow(symbol: "testtube.2", symbolColor: Luma.mint, title: "Supplement trials",
                                subtitle: env.openTrial.map { "\($0.supplement) is on trial" } ?? "Find out whether one does anything for you", chevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A logged meal: tap to open its items, with where the numbers came from.
struct FuelEntryCard: View {
    let entry: FuelEntry
    let expanded: Bool
    let onTap: () -> Void
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title).font(LumaFont.body(15.5, .semibold)).foregroundStyle(Luma.frost).multilineTextAlignment(.leading)
                        Text("\(LumaText.time(entry.at.timeIntervalSince1970)) · \(entry.source.title)").font(LumaFont.body(12)).foregroundStyle(entry.source.isEstimate ? Luma.amber : Luma.smoke)
                        HStack(spacing: 10) {
                            chip("P", entry.proteinG, Luma.coral)
                            chip("C", entry.carbsG, Luma.amber)
                            chip("F", entry.fatG, Luma.sky)
                        }
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(entry.kcal.rounded()))").font(LumaFont.numeral(26)).foregroundStyle(Luma.frost)
                        Text("kcal").font(LumaFont.body(11)).foregroundStyle(Luma.smoke)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                LumaDivider()
                ForEach(entry.items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(LumaFont.body(14, .medium)).foregroundStyle(Luma.frost)
                            if !item.quantity.isEmpty { Text(item.quantity).font(LumaFont.body(12)).foregroundStyle(Luma.smoke) }
                        }
                        Spacer()
                        Text("\(Int(item.kcal.rounded())) kcal · P \(Int(item.proteinG.rounded())) · C \(Int(item.carbsG.rounded())) · F \(Int(item.fatG.rounded()))")
                            .font(LumaFont.numeral(14, .medium)).foregroundStyle(Luma.mist)
                    }
                }
                if !entry.note.isEmpty { LumaNote(entry.note) }
                HStack {
                    Button(role: .destructive) { env.delete(entry) } label: { Label("Delete", systemImage: "trash").font(LumaFont.body(13.5, .semibold)) }
                        .foregroundStyle(Luma.coral).buttonStyle(.plain)
                    Spacer()
                    Button {
                        var copy = entry
                        copy.id = UUID(); copy.at = Date(); copy.photos = []
                        env.log(copy)
                        LumaHaptics.success()
                    } label: { Label("Log again now", systemImage: "arrow.clockwise").font(LumaFont.body(13.5, .semibold)) }
                        .foregroundStyle(Luma.mint).buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(LumaPanel(radius: 22))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let name = entry.photos.first, let data = env.photoData(name), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
            Image(systemName: entry.kind == .drink ? "cup.and.saucer.fill" : (entry.kind == .snack ? "carrot.fill" : "fork.knife"))
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Luma.mint)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Luma.mint.opacity(0.13)))
        }
    }

    private func chip(_ letter: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(letter).font(LumaFont.label(10)).foregroundStyle(color)
            Text("\(Int(grams.rounded()))").font(LumaFont.numeral(15, .semibold)).foregroundStyle(Luma.mist)
        }
    }
}

/// What to eat around the day's main session.
struct FuelCuesCard: View {
    let day: String
    @EnvironmentObject private var env: LumaEnv

    var body: some View {
        let sessions = env.planned.filter { $0.day == day && $0.status == .planned && $0.kind != .rest }
        if let main = sessions.max(by: { $0.durationMin < $1.durationMin }) {
            LumaCard {
                VStack(alignment: .leading, spacing: 10) {
                    LumaLabel("Fuelling \(main.title.lowercased())")
                    ForEach(FuelPlanner.sessionCues(massKg: env.profile.weightKg, intensity: main.intensity, durationMin: main.durationMin), id: \.self) { cue in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Circle().fill(Luma.mint).frame(width: 5, height: 5).offset(y: -2)
                            Text(cue).font(LumaFont.body(14)).foregroundStyle(Luma.mist).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Add sheet

/// One sheet for every way of logging: photos, a typed description or your own numbers for food;
/// the stack, a photo of the bottle or a typed dose for supplements; quick amounts for water.
struct FuelAddSheet: View {
    let mode: FuelAddMode
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @Environment(\.dismiss) private var dismiss

    @State private var tab = 0
    @State private var photos: [PickedPhoto] = []
    @State private var text = ""
    @State private var kind: FuelKind = .meal
    @State private var at = Date()
    @State private var draft: FuelEntry?
    @State private var doses: [SupplementDose] = []
    @State private var busy = false
    @State private var error: String?
    @State private var addToStack = false

    var body: some View {
        LumaSheet(title: tab == 0 ? "Log food" : (tab == 1 ? "Log supplements" : "Log water"), tone: .fuel) {
            LumaSegmented(selection: $tab, options: [(0, "Food"), (1, "Tablets"), (2, "Water")], tint: Luma.mint)
            if tab == 0 { foodTab } else if tab == 1 { supplementTab } else { waterTab }
        }
        .onAppear {
            tab = mode == .supplement ? 1 : (mode == .water ? 2 : 0)
        }
    }

    // MARK: Food

    @ViewBuilder
    private var foodTab: some View {
        if let entry = draft {
            FuelReview(entry: Binding(get: { entry }, set: { draft = $0 }), photos: photos) {
                var saved = draft ?? entry
                saved.at = at
                saved.kind = kind
                saved.photos = photos.map { env.savePhoto($0.data) }
                env.log(saved)
                LumaHaptics.success()
                dismiss()
            } onBack: { draft = nil }
        } else {
            LumaLabel("Photos of the meal or its label (up to \(CoachEngine.maxPhotos))")
            PhotoStrip(photos: $photos, size: 76)
            LumaField(title: photos.isEmpty ? "Describe it: “2 eggs on sourdough, flat white”" : "Add detail (optional): “ate half”, “no dressing”", text: $text, axis: .vertical)
            HStack(spacing: 10) {
                LumaSegmented(selection: $kind, options: [(FuelKind.meal, "Meal"), (.snack, "Snack"), (.drink, "Drink")], tint: Luma.frost)
                DatePicker("", selection: $at, displayedComponents: [.hourAndMinute]).labelsHidden().colorScheme(.dark)
            }
            if let error { Text(error).font(LumaFont.body(13.5)).foregroundStyle(Luma.coral).fixedSize(horizontal: false, vertical: true) }
            Button {
                Task { await readFood() }
            } label: {
                if busy { HStack(spacing: 10) { ProgressView().tint(Luma.ink); Text("Working it out") } } else { Label("Work out the numbers", systemImage: "sparkles") }
            }
            .buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint))
            .disabled(busy || (photos.isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty))
            if busy { ReadingRows(caption: photos.isEmpty ? "Working out the numbers" : "Reading your photo", rows: 3) }
            Button("Enter the numbers myself") {
                draft = FuelEntry(at: at, kind: kind, title: text.isEmpty ? "Meal" : text, items: [FuelItem(name: text.isEmpty ? "Item" : text)], source: .typed)
            }
            .buttonStyle(LumaSecondaryButtonStyle())
            if !env.coach.hasKey {
                LumaNote("Working out numbers from photos or a description uses the coach. Connect your key in the Coach tab, or enter the numbers yourself.")
            }
            recent
        }
    }

    @ViewBuilder
    private var recent: some View {
        let seen = Dictionary(grouping: env.fuel.filter { $0.kind == .meal || $0.kind == .snack || $0.kind == .drink }, by: { $0.title })
        let top = seen.sorted { $0.value.count > $1.value.count }.prefix(6).compactMap { $0.value.max { $0.at < $1.at } }
        if !top.isEmpty {
            LumaSection(title: "Log again")
            LumaGroup {
                ForEach(top) { e in
                    Button {
                        var copy = e
                        copy.id = UUID(); copy.at = at; copy.photos = []
                        env.log(copy)
                        LumaHaptics.success()
                        dismiss()
                    } label: {
                        LumaRow(symbol: "arrow.clockwise", symbolColor: Luma.mint, title: e.title,
                                subtitle: "\(Int(e.kcal.rounded())) kcal · \(Int(e.proteinG.rounded())) g protein")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func readFood() async {
        guard env.coach.hasKey else { error = "Connect your key in the Coach tab to work out numbers automatically, or enter them yourself."; return }
        busy = true; error = nil
        do {
            var entry = try await env.coach.readFood(text: text, photos: photos.map { $0.data })
            entry.at = at
            draft = entry
        } catch let e {
            error = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
        }
        busy = false
    }

    // MARK: Supplements

    @ViewBuilder
    private var supplementTab: some View {
        let stack = env.supplements.filter { $0.active }
        if !stack.isEmpty {
            LumaLabel("Your stack: tap to log")
            FlowLayout(spacing: 8) {
                ForEach(stack) { s in
                    let taken = env.supplementTaken(s, on: env.today) != nil
                    LumaChip(title: "\(s.dose.name) · \(s.dose.text)", symbol: taken ? "checkmark" : nil, isOn: taken, tint: Luma.mint) {
                        if let t = env.supplementTaken(s, on: env.today) { env.delete(t) } else { env.logSupplement(s.dose) }
                    }
                }
            }
        }
        LumaSection(title: "Something else")
        LumaLabel("Photo of the bottle, blister pack or facts panel")
        PhotoStrip(photos: $photos, size: 76)
        LumaField(title: "Or type it: “Vitamin D 2000 IU, 2 omega-3 capsules”", text: $text, axis: .vertical)
        if let error { Text(error).font(LumaFont.body(13.5)).foregroundStyle(Luma.coral).fixedSize(horizontal: false, vertical: true) }
        if doses.isEmpty {
            Button {
                Task { await readSupplements() }
            } label: {
                if busy { HStack(spacing: 10) { ProgressView().tint(Luma.ink); Text("Reading") } } else { Label("Read it", systemImage: "sparkles") }
            }
            .buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint))
            .disabled(busy || (photos.isEmpty && text.trimmingCharacters(in: .whitespaces).isEmpty))
            if busy { ReadingRows(caption: "Reading the label", rows: 2) }
            if !env.coach.hasKey {
                LumaNote("Reading labels uses the coach. Without a key, add supplements to your stack by hand from Supplements, then tick them here.")
            }
        } else {
            LumaGroup {
                ForEach(Array(doses.enumerated()), id: \.offset) { i, d in
                    LumaRow(symbol: "pills.fill", symbolColor: Luma.mint, title: d.name, subtitle: d.text) {
                        Button { doses.remove(at: i) } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Luma.smoke) }.buttonStyle(.plain)
                    }
                }
            }
            Toggle(isOn: $addToStack) { Text("Also add to my regular stack").font(LumaFont.body(15)).foregroundStyle(Luma.frost) }.tint(Luma.volt)
            Button("Log \(doses.count) supplement\(doses.count == 1 ? "" : "s")") {
                for d in doses {
                    env.logSupplement(d, source: photos.isEmpty ? .typed : .label)
                    if addToStack, !env.supplements.contains(where: { $0.dose.name == d.name }) { env.supplements.append(SupplementPlan(dose: d)) }
                }
                LumaHaptics.success()
                dismiss()
            }
            .buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint))
        }
    }

    private func readSupplements() async {
        guard env.coach.hasKey else { error = "Connect your key in the Coach tab to read labels automatically."; return }
        busy = true; error = nil
        do { doses = try await env.coach.readSupplements(text: text, photos: photos.map { $0.data }) }
        catch let e { error = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }
        busy = false
    }

    // MARK: Water

    @ViewBuilder
    private var waterTab: some View {
        let totals = env.fuelTotals(on: env.today), target = env.fuelTargets(on: env.today)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(String(format: "%.1f", totals.waterMl / 1000)).font(LumaFont.numeral(64, .heavy)).foregroundStyle(Luma.frost).contentTransition(.numericText())
            Text("of \(String(format: "%.1f", target.waterMl / 1000)) L today").font(LumaFont.body(15)).foregroundStyle(Luma.mist)
        }
        LumaBar(value: totals.waterMl, total: target.waterMl, color: Luma.sky, height: 10)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach([250.0, 330, 500, 750], id: \.self) { ml in
                Button {
                    env.logWater(ml)
                    LumaHaptics.success()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "drop.fill").foregroundStyle(Luma.sky)
                        Text("\(Int(ml)) ml").font(LumaFont.numeral(24)).foregroundStyle(Luma.frost)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18).background(LumaPanel(radius: 20))
                }
                .buttonStyle(.plain)
            }
        }
        LumaNote("The target covers your body mass plus an allowance for today's training.")
    }
}

/// Review and correct an entry before it is saved: every number is editable.
struct FuelReview: View {
    @Binding var entry: FuelEntry
    let photos: [PickedPhoto]
    let onSave: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if entry.source.isEstimate {
                LumaPill(text: "Estimate: check the amounts", color: Luma.amber, symbol: "eye")
            } else if entry.source == .label {
                LumaPill(text: "Read from the label", color: Luma.mint, symbol: "checkmark")
            }
            LumaField(title: "Name", text: $entry.title)
            HStack(spacing: 0) {
                total("kcal", entry.kcal, Luma.frost)
                total("Protein", entry.proteinG, Luma.coral)
                total("Carbs", entry.carbsG, Luma.amber)
                total("Fat", entry.fatG, Luma.sky)
            }
            .padding(.vertical, 12).background(LumaPanel(radius: 18))
            ForEach($entry.items) { $item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("Item", text: $item.name).font(LumaFont.body(15.5, .semibold)).foregroundStyle(Luma.frost)
                        Button { entry.items.removeAll { $0.id == item.id } } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Luma.smoke)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("Amount", text: $item.quantity, prompt: Text("Amount").foregroundStyle(Luma.smoke)).font(LumaFont.body(13.5)).foregroundStyle(Luma.mist)
                    HStack(spacing: 8) {
                        NumberField(label: "kcal", value: $item.kcal)
                        NumberField(label: "P g", value: $item.proteinG)
                        NumberField(label: "C g", value: $item.carbsG)
                        NumberField(label: "F g", value: $item.fatG)
                    }
                }
                .padding(14).background(LumaPanel(radius: 18))
            }
            Button {
                entry.items.append(FuelItem(name: "Item"))
            } label: { Label("Add an item", systemImage: "plus").font(LumaFont.body(14, .semibold)).foregroundStyle(Luma.mint) }
            .buttonStyle(.plain)
            if !entry.note.isEmpty { LumaNote(entry.note) }
            Button("Save to log", action: onSave).buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint)).disabled(entry.items.isEmpty)
            Button("Back", action: onBack).buttonStyle(LumaSecondaryButtonStyle())
        }
    }

    private func total(_ label: String, _ v: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(v.rounded()))").font(LumaFont.numeral(26)).foregroundStyle(color).contentTransition(.numericText())
            LumaLabel(label)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A compact numeric field with its unit as a caption.
struct NumberField: View {
    let label: String
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 3) {
            TextField("0", value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(LumaFont.numeral(20, .semibold)).foregroundStyle(Luma.frost)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
            LumaLabel(label)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Supplements

struct SupplementsScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @EnvironmentObject private var router: LumaRouter
    @State private var name = ""
    @State private var amount = 1.0
    @State private var unit = "capsule"
    @State private var timing: SupplementPlan.Timing = .morning

    private let units = ["mg", "g", "mcg", "IU", "ml", "capsule", "tablet", "softgel", "scoop"]

    var body: some View {
        LumaDetailScreen(title: "Supplements", tone: .fuel) {
            Text("Your stack").font(LumaFont.title(26)).foregroundStyle(Luma.frost)
            if env.supplements.isEmpty {
                LumaNote("Nothing here yet. Add what you take regularly below, or log from a photo and choose “add to my stack”.")
            } else {
                LumaGroup {
                    ForEach($env.supplements) { $s in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.dose.name).font(LumaFont.body(15, .medium)).foregroundStyle(s.active ? Luma.frost : Luma.smoke)
                                Text("\(s.dose.text) · \(s.timing.title) · taken \(takenCount(s)) of the last 7 days").font(LumaFont.body(12.5)).foregroundStyle(Luma.mist)
                            }
                            Spacer()
                            Toggle("", isOn: $s.active).labelsHidden().tint(Luma.volt)
                            Button { env.supplements.removeAll { $0.id == s.id } } label: {
                                Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(Luma.smoke)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 16)
                    }
                }
            }
            LumaSection(title: "Add to the stack")
            LumaField(title: "Name, e.g. Creatine monohydrate", text: $name)
            HStack(spacing: 10) {
                NumberField(label: "Amount", value: $amount).frame(width: 96)
                Picker("Unit", selection: $unit) { ForEach(units, id: \.self) { Text($0).tag($0) } }
                    .pickerStyle(.menu).tint(Luma.frost)
                    .frame(maxWidth: .infinity).padding(.vertical, 8).background(LumaPanel(radius: 14))
                Picker("When", selection: $timing) { ForEach(SupplementPlan.Timing.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .pickerStyle(.menu).tint(Luma.frost)
                    .frame(maxWidth: .infinity).padding(.vertical, 8).background(LumaPanel(radius: 14))
            }
            Button("Add") {
                env.supplements.append(SupplementPlan(dose: SupplementDose(name: name.trimmingCharacters(in: .whitespaces), amount: amount, unit: unit), timing: timing))
                name = ""
                LumaHaptics.success()
            }
            .buttonStyle(LumaPrimaryButtonStyle(color: Luma.mint))
            .disabled(name.trimmingCharacters(in: .whitespaces).count < 2 || amount <= 0)
            Button { router.sheet = .fuelAdd(.supplement) } label: { Label("Add from a photo of the label", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                .buttonStyle(LumaSecondaryButtonStyle())
            Button { router.push(.trials) } label: { Label("Run a trial of one", systemImage: "testtube.2").frame(maxWidth: .infinity) }
                .buttonStyle(LumaSecondaryButtonStyle())
            LumaNote("Luma records what you take; it does not judge doses. Check anything new against the label and, if you take medication, with a pharmacist or doctor.")
        }
    }

    private func takenCount(_ s: SupplementPlan) -> Int {
        LDate.range(ending: env.today, count: 7).filter { env.supplementTaken(s, on: $0) != nil }.count
    }
}

// MARK: - History

struct FuelHistoryScreen: View {
    @EnvironmentObject private var env: LumaEnv
    @State private var range = 14

    var body: some View {
        let keys = LDate.range(ending: env.today, count: range)
        let totals = keys.map { env.fuelTotals(on: $0) }
        let logged = totals.filter { $0.entries > 0 }
        let target = env.fuelTargets(on: env.today)
        LumaDetailScreen(title: "Fuel history", tone: .fuel) {
            LumaSegmented(selection: $range, options: [(7, "1W"), (14, "2W"), (30, "1M")], tint: Luma.mint)
            StatGrid {
                StatCell(label: "Average energy", value: LStat.mean(logged.map { $0.kcal }).map { LFormat.grouped($0) } ?? "–", unit: "kcal", note: "On days with a log")
                StatCell(label: "Average protein", value: LStat.mean(logged.map { $0.proteinG }).map { String(format: "%.0f", $0) } ?? "–", unit: "g",
                         note: String(format: "%.1f g per kg", (LStat.mean(logged.map { $0.proteinG }) ?? 0) / max(1, env.profile.weightKg)))
                StatCell(label: "Average water", value: LStat.mean(logged.map { $0.waterMl / 1000 }).map { String(format: "%.1f", $0) } ?? "–", unit: "L")
                StatCell(label: "Days logged", value: "\(logged.count)", unit: "of \(range)")
            }
            chart("Energy", totals.map { $0.entries > 0 ? $0.kcal : nil }, keys, Luma.mint, target.kcal, { LFormat.grouped($0) })
            chart("Protein", totals.map { $0.entries > 0 ? $0.proteinG : nil }, keys, Luma.coral, target.proteinG, { String(format: "%.0f", $0) })
            chart("Carbohydrate", totals.map { $0.entries > 0 ? $0.carbsG : nil }, keys, Luma.amber, nil, { String(format: "%.0f", $0) })
            chart("Water (L)", totals.map { $0.waterMl > 0 ? $0.waterMl / 1000 : nil }, keys, Luma.sky, target.waterMl / 1000, { String(format: "%.1f", $0) })
            LumaNote("Dashed lines are today's targets. Days without a food log are left blank rather than counted as zero.")
        }
    }

    private func chart(_ title: String, _ values: [Double?], _ keys: [String], _ color: Color, _ goal: Double?, _ format: @escaping (Double) -> String) -> some View {
        LumaCard {
            VStack(alignment: .leading, spacing: 10) {
                LumaLabel(title)
                LumaBarChart(bars: values.enumerated().map { i, v in LumaBarChart.Bar(id: i, value: v, color: color, label: LumaText.shortDay(keys[i])) },
                             goal: goal, height: 150, format: format, replay: range)
            }
        }
    }
}

// MARK: - Daily check-in

struct CheckInSheet: View {
    let day: String
    @EnvironmentObject private var env: LumaEnv
    @Environment(\.dismiss) private var dismiss
    @State private var tags: Set<CheckInTag> = []
    @State private var energy: Int?
    @State private var soreness: Int?
    @State private var note = ""

    var body: some View {
        LumaSheet(title: "How was \(LumaText.dayTitle(day, today: env.today).lowercased())?", tone: .hrv) {
            LumaNote("Tick what applied. After a couple of weeks Luma can show what each one does to your next morning.")
            FlowLayout(spacing: 8) {
                ForEach(CheckInTag.allCases) { tag in
                    LumaChip(title: tag.title, symbol: tag.symbol, isOn: tags.contains(tag), tint: Luma.aqua) {
                        if tags.contains(tag) { tags.remove(tag) } else { tags.insert(tag) }
                    }
                }
            }
            scale("Energy today", $energy, ["Flat", "Low", "OK", "Good", "Great"])
            scale("Soreness", $soreness, ["Fresh", "Light", "Some", "Sore", "Very sore"])
            LumaField(title: "Anything else worth noting", text: $note, axis: .vertical)
            Button("Save") {
                env.save(CheckIn(day: day, tags: CheckInTag.allCases.filter { tags.contains($0) }, energy: energy, soreness: soreness, note: note))
                LumaHaptics.success()
                dismiss()
            }
            .buttonStyle(LumaPrimaryButtonStyle())
        }
        .onAppear {
            if let c = env.checkIn(on: day) { tags = Set(c.tags); energy = c.energy; soreness = c.soreness; note = c.note }
        }
    }

    private func scale(_ title: String, _ value: Binding<Int?>, _ labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LumaLabel(title)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        LumaHaptics.select()
                        value.wrappedValue = value.wrappedValue == i ? nil : i
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(i)").font(LumaFont.numeral(20)).foregroundStyle(value.wrappedValue == i ? Luma.ink : Luma.frost)
                            Text(labels[i - 1]).font(LumaFont.label(8.5)).foregroundStyle(value.wrappedValue == i ? Luma.ink : Luma.smoke).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(value.wrappedValue == i ? Luma.aqua : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
