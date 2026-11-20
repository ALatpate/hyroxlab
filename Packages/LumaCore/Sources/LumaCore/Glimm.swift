import Foundation

// MARK: - Glimm
//
// The companion as a character: its moods, its wardrobe, the taste it learns and the small things it
// remembers. What state it is in still comes from the facts (`Buddy.look`); this file decides how
// that state is worn and kept. Nothing here draws: the figure is drawn from the outfit's `code` by
// LumaKit, which knows each cut by its shape name.

/// The moods Glimm can show. A state of the day maps onto one (`BuddyMood.glimm`); a reply in a chat
/// may name any of them.
public enum GlimmMood: String, Codable, CaseIterable, Sendable {
    case joyful, steady, tired, asleep, sleepy, focused, proud, celebrating, resting, thirsty, hungry, curious, cheeky, surprised
}

public extension BuddyMood {
    /// The mood a state of the day is shown in.
    var glimm: GlimmMood {
        switch self {
        case .waiting: return .curious
        case .training: return .focused
        case .sleeping: return .asleep
        case .celebrating: return .celebrating
        case .worked: return .proud
        case .unwell: return .resting
        case .sleepy: return .sleepy
        case .thirsty: return .thirsty
        case .hungry: return .hungry
        case .drained: return .tired
        case .steady: return .steady
        case .charged: return .joyful
        }
    }
}

// MARK: - The wardrobe

public enum GlimmSlot: String, Codable, CaseIterable, Sendable {
    case top, bottom, feet, head, accessory

    public var title: String {
        switch self {
        case .top: return "Tops"
        case .bottom: return "Bottoms"
        case .feet: return "Shoes"
        case .head: return "Hats"
        case .accessory: return "Extras"
        }
    }
}

/// What an outfit is for. A cut belongs to one; the day asks for one.
public enum GlimmContext: String, Codable, CaseIterable, Sendable {
    case everyday, training, relax, sleep, celebration, cooking, rain, cold, focus, sun, adventure

    public var title: String {
        switch self {
        case .everyday: return "Everyday"
        case .training: return "Training"
        case .relax: return "Taking it easy"
        case .sleep: return "Bedtime"
        case .celebration: return "Celebrating"
        case .cooking: return "Kitchen"
        case .rain: return "Rain"
        case .cold: return "Cold day"
        case .focus: return "Focus"
        case .sun: return "Sunny day"
        case .adventure: return "Out and about"
        }
    }
}

/// One cut of clothing: a hoodie, a pair of joggers, a beanie.
public struct GlimmStyle: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let slot: GlimmSlot
    /// The name the drawing knows the cut by.
    public let shape: String
    public let context: GlimmContext
    /// 0 (a vest) to 5 (a puffer).
    public let warmth: Int
}

public struct GlimmPalette: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// "RRGGBB".
    public let hex: String
}

public enum GlimmWardrobe {
    public static let patterns = ["plain", "stripes", "dots", "checks", "stars", "sprinkles"]

    public static let palettes: [GlimmPalette] = [
        ("coral", "Coral", "FF766B"), ("teal", "Teal", "36BFB0"), ("lilac", "Lilac", "B5A0EF"), ("butter", "Butter", "F5D77A"),
        ("sky", "Sky", "7DBFEA"), ("rose", "Rose", "EE96BD"), ("cobalt", "Cobalt", "6375E7"), ("sage", "Sage", "9ABB91"),
        ("tangerine", "Tangerine", "F6A05A"), ("plum", "Plum", "A778BB"), ("cream", "Cream", "F4E6C8"), ("navy", "Navy", "344968"),
        ("mint", "Mint", "A6DEC7"), ("cherry", "Cherry", "D75C76"), ("ochre", "Ochre", "CFA050"), ("charcoal", "Charcoal", "566274"),
    ].map { GlimmPalette(id: $0.0, name: $0.1, hex: $0.2) }

    /// id | name | slot | shape | context | warmth
    private static let table = """
    cloud-hoodie|Cloud hoodie|top|hoodie|relax|3
    zip-hoodie|Zip hoodie|top|zip|relax|3
    sweatshirt|Oversized sweatshirt|top|crew|relax|3
    running-vest|Running vest|top|tank|training|0
    everyday-tee|Everyday tee|top|tee|everyday|1
    bomber|Pocket bomber|top|bomber|everyday|3
    raincoat|Raincoat|top|coat|rain|4
    puffer|Puffer jacket|top|puffer|cold|5
    cardigan|Button cardigan|top|cardigan|focus|3
    denim-jacket|Denim jacket|top|denim|everyday|3
    overalls|Play overalls|top|overall|everyday|2
    sport-jersey|Sport jersey|top|jersey|training|1
    rugby-shirt|Rugby shirt|top|polo|everyday|2
    windbreaker|Windbreaker|top|windbreaker|training|2
    fleece|Half-zip fleece|top|fleece|cold|4
    turtleneck|Ribbed turtleneck|top|knit|cold|4
    bowling-shirt|Bowling shirt|top|shirt|everyday|1
    island-shirt|Island shirt|top|aloha|sun|1
    coach-jacket|Coach jacket|top|coach|everyday|3
    varsity|Varsity jacket|top|varsity|celebration|3
    pyjamas|Pyjama top|top|pyjama|sleep|2
    lounge-top|Lounge top|top|lounge|relax|2
    chef-coat|Chef coat|top|chef|cooking|2
    explorer-vest|Explorer vest|top|explorer|adventure|2
    shorts|Easy shorts|bottom|shorts|training|0
    joggers|Soft joggers|bottom|joggers|relax|2
    cargos|Cargo trousers|bottom|cargo|adventure|3
    leggings|Running leggings|bottom|leggings|training|1
    widelegs|Wide-leg trousers|bottom|wide|everyday|2
    jeans|Tiny jeans|bottom|jeans|everyday|3
    chinos|Chinos|bottom|chino|focus|2
    trackpants|Track pants|bottom|track|training|2
    sleep-pants|Sleep pants|bottom|sleep|sleep|2
    skirt|Pleated skirt|bottom|skirt|everyday|1
    runners|Running shoes|feet|runners|training|1
    trainers|Chunky trainers|feet|chunky|everyday|2
    high-tops|High-top trainers|feet|high|everyday|2
    hiking-boots|Hiking boots|feet|hike|adventure|4
    wellies|Wellies|feet|welly|rain|4
    sandals|Sandals|feet|sandal|sun|0
    slippers|Fluffy slippers|feet|slipper|sleep|3
    court-shoes|Court shoes|feet|court|training|1
    retro-shoes|Retro trainers|feet|retro|everyday|2
    trail-shoes|Trail shoes|feet|trail|adventure|3
    beanie|Sprout beanie|head|beanie|cold|4
    cap|Baseball cap|head|cap|everyday|1
    bucket|Bucket hat|head|bucket|sun|1
    headband|Sport headband|head|headband|training|0
    earmuffs|Earmuffs|head|earmuffs|cold|4
    chef-hat|Chef hat|head|chef|cooking|1
    beret|Little beret|head|beret|focus|2
    visor|Running visor|head|visor|training|0
    sunhat|Sun hat|head|sunhat|sun|1
    partyhat|Party hat|head|party|celebration|1
    scarf|Knitted scarf|accessory|scarf|cold|4
    crossbody|Mini crossbody|accessory|bag|everyday|1
    glasses|Round glasses|accessory|glasses|focus|0
    backpack|Adventure pack|accessory|backpack|adventure|1
    bowtie|Little bow tie|accessory|bow|celebration|0
    watch|Sport watch|accessory|watch|training|0
    headphones|Headphones|accessory|headphones|focus|1
    medal|Celebration medal|accessory|medal|celebration|0
    bandana|Bandana|accessory|bandana|adventure|1
    pin|Little star pin|accessory|pin|everyday|0
    """

    public static let styles: [GlimmStyle] = table.split(separator: "\n").compactMap { row in
        let f = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard f.count == 6, let slot = GlimmSlot(rawValue: f[2]), let context = GlimmContext(rawValue: f[4]), let warmth = Int(f[5]) else { return nil }
        return GlimmStyle(id: f[0], name: f[1], slot: slot, shape: f[3], context: context, warmth: warmth)
    }

    private static let styleByID = Dictionary(styles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    private static let paletteByID = Dictionary(palettes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    public static func style(_ id: String) -> GlimmStyle? { styleByID[id] }
    public static func palette(_ id: String) -> GlimmPalette? { paletteByID[id] }
    public static func styles(in slot: GlimmSlot) -> [GlimmStyle] { styles.filter { $0.slot == slot } }

    /// The patterns a slot comes in: every one for a top, plain for the rest.
    public static func patterns(in slot: GlimmSlot) -> [String] { slot == .top ? patterns : ["plain"] }

    /// Everything that can be worn in a slot: each cut in each colour, and a top in each pattern.
    public static func items(in slot: GlimmSlot) -> [GlimmItem] {
        var out: [GlimmItem] = []
        for style in styles(in: slot) {
            for palette in palettes {
                for pattern in patterns(in: slot) { out.append(GlimmItem(style: style.id, palette: palette.id, pattern: pattern)) }
            }
        }
        return out
    }

    /// How many things there are to wear.
    public static var count: Int { GlimmSlot.allCases.reduce(0) { $0 + styles(in: $1).count * palettes.count * patterns(in: $1).count } }
}

/// One thing to wear: a cut, in a colour, in a pattern.
public struct GlimmItem: Codable, Hashable, Sendable, Identifiable {
    public var style: String
    public var palette: String
    public var pattern: String

    public init(style: String, palette: String, pattern: String = "plain") {
        self.style = style; self.palette = palette; self.pattern = pattern
    }

    public var id: String { "\(style)__\(palette)__\(pattern)" }

    /// From "style__palette__pattern"; nil unless the wardrobe holds all three.
    public init?(id: String) {
        let f = id.components(separatedBy: "__")
        guard f.count == 3, let style = GlimmWardrobe.style(f[0]), GlimmWardrobe.palette(f[1]) != nil,
              GlimmWardrobe.patterns(in: style.slot).contains(f[2]) else { return nil }
        self.init(style: f[0], palette: f[1], pattern: f[2])
    }

    public var slot: GlimmSlot? { GlimmWardrobe.style(style)?.slot }
    public var isKnown: Bool {
        guard let s = GlimmWardrobe.style(style) else { return false }
        return GlimmWardrobe.palette(palette) != nil && GlimmWardrobe.patterns(in: s.slot).contains(pattern)
    }

    /// "coral zip hoodie", "striped teal everyday tee".
    public var name: String {
        let cut = (GlimmWardrobe.style(style)?.name ?? style).lowercased()
        let colour = (GlimmWardrobe.palette(palette)?.name ?? palette).lowercased()
        let marks: [String: String] = ["stripes": "striped ", "dots": "dotted ", "checks": "checked ", "stars": "starry ", "sprinkles": "sprinkled "]
        return (marks[pattern] ?? "") + colour + " " + cut
    }

    /// What the drawing is given: "shape:RRGGBB:pattern".
    var code: String {
        guard let s = GlimmWardrobe.style(style), let p = GlimmWardrobe.palette(palette) else { return "-" }
        return "\(s.shape):\(p.hex):\(pattern)"
    }
}

/// What Glimm has on: a top, a bottom and shoes always; a hat and an extra when it wears them.
public struct GlimmOutfit: Codable, Equatable, Sendable {
    public var top: GlimmItem
    public var bottom: GlimmItem
    public var feet: GlimmItem
    public var head: GlimmItem?
    public var accessory: GlimmItem?

    public init(top: GlimmItem, bottom: GlimmItem, feet: GlimmItem, head: GlimmItem? = nil, accessory: GlimmItem? = nil) {
        self.top = top; self.bottom = bottom; self.feet = feet; self.head = head; self.accessory = accessory
    }

    /// The look Glimm is known by: a coral zip hoodie, teal joggers, lilac trainers and a lilac bag.
    public static let signature = GlimmOutfit(top: GlimmItem(style: "zip-hoodie", palette: "coral"), bottom: GlimmItem(style: "joggers", palette: "teal"),
                                              feet: GlimmItem(style: "trainers", palette: "lilac"), accessory: GlimmItem(style: "crossbody", palette: "lilac"))

    public subscript(slot: GlimmSlot) -> GlimmItem? {
        switch slot {
        case .top: return top
        case .bottom: return bottom
        case .feet: return feet
        case .head: return head
        case .accessory: return accessory
        }
    }

    public var items: [GlimmItem] { [top, bottom, feet] + [head, accessory].compactMap { $0 } }

    /// Every piece is one the wardrobe holds, in the slot it is worn in.
    public var isValid: Bool {
        top.isKnown && top.slot == .top && bottom.isKnown && bottom.slot == .bottom && feet.isKnown && feet.slot == .feet
            && (head.map { $0.isKnown && $0.slot == .head } ?? true) && (accessory.map { $0.isKnown && $0.slot == .accessory } ?? true)
    }

    /// What the drawing is given: "top|bottom|feet|head|accessory", "-" where nothing is worn.
    public var code: String { [top.code, bottom.code, feet.code, head?.code ?? "-", accessory?.code ?? "-"].joined(separator: "|") }

    /// The outfit as one string, for telling two apart.
    public var key: String { GlimmSlot.allCases.map { self[$0]?.id ?? "" }.joined(separator: "|") }

    /// "A coral zip hoodie, teal soft joggers and lilac chunky trainers, with a lilac mini crossbody."
    public var name: String {
        var said = "A \(top.name), \(bottom.name) and \(feet.name)"
        let extras = [head, accessory].compactMap { $0?.name }
        if !extras.isEmpty { said += ", with a " + extras.joined(separator: " and a ") }
        return said + "."
    }

    /// The outfit with one piece put on in its slot, and anything it cannot be worn with taken off.
    public func wearing(_ item: GlimmItem) -> GlimmOutfit {
        guard item.isKnown, let slot = item.slot else { return self }
        var o = self
        switch slot {
        case .top: o.top = item
        case .bottom: o.bottom = item
        case .feet: o.feet = item
        case .head: o.head = item
        case .accessory: o.accessory = item
        }
        return o.tidied(keeping: slot)
    }

    /// The outfit without its hat or its extra. The other three are always worn.
    public func without(_ slot: GlimmSlot) -> GlimmOutfit {
        var o = self
        if slot == .head { o.head = nil }
        if slot == .accessory { o.accessory = nil }
        return o
    }

    /// Things that cannot be worn together: a hat under a hood that is up, and headphones over
    /// anything but a bare head, a headband or a visor. The piece just put on is the one kept.
    func tidied(keeping kept: GlimmSlot? = nil) -> GlimmOutfit {
        var o = self
        let shape: (GlimmItem?) -> String? = { $0.flatMap { GlimmWardrobe.style($0.style)?.shape } }
        if shape(o.top) == "coat", o.head != nil {
            // The raincoat's hood is up and no hat fits under it. A hat just put on is the wish, so the
            // coat gives way to a hoodie of its own colour; otherwise the hat stays off.
            if kept == .head { o.top = GlimmItem(style: "zip-hoodie", palette: o.top.palette, pattern: o.top.pattern) } else { o.head = nil }
        }
        if shape(o.accessory) == "headphones", let hat = shape(o.head), hat != "headband", hat != "visor" {
            if kept == .head { o.accessory = nil } else { o.head = nil }
        }
        return o
    }
}

// MARK: - Taste

/// What Glimm has learnt about the clothes its person likes: a score for each colour and each cut,
/// moved by a like or a dislike of an outfit, and a little by a piece picked by hand.
public struct GlimmTaste: Codable, Equatable, Sendable {
    /// "palette:coral" and "style:zip-hoodie" to a score between −`bound` and `bound`.
    public var scores: [String: Double] = [:]
    /// The outfits rated, by key: 1 liked, −1 not.
    public var ratings: [String: Int] = [:]
    /// The rated outfits in the order they were first rated, oldest first.
    public var order: [String] = []

    public static let bound = 6.0
    public static let step = 0.65
    public static let nudge = 0.2
    public static let kept = 300

    public init() {}

    public func rating(of outfit: GlimmOutfit) -> Int { ratings[outfit.key] ?? 0 }

    public func score(_ item: GlimmItem) -> Double {
        (scores["palette:" + item.palette] ?? 0) + (scores["style:" + item.style] ?? 0)
    }

    /// A like or a dislike of an outfit. Saying the same thing twice changes nothing; changing one's
    /// mind takes the first answer back before applying the second.
    public mutating func rate(_ outfit: GlimmOutfit, like: Bool) {
        let key = outfit.key
        let value = like ? 1 : -1
        let previous = ratings[key] ?? 0
        guard value != previous else { return }
        let delta = Double(value - previous) * GlimmTaste.step
        var features: Set<String> = []
        for item in outfit.items {
            features.insert("style:" + item.style)
            features.insert("palette:" + item.palette)
        }
        for f in features { move(f, by: delta) }
        if previous == 0 { order.append(key) }
        ratings[key] = value
        while order.count > GlimmTaste.kept { ratings.removeValue(forKey: order.removeFirst()) }
    }

    /// A piece picked by hand says a little about what is liked.
    public mutating func chose(_ item: GlimmItem) {
        move("style:" + item.style, by: GlimmTaste.nudge)
        move("palette:" + item.palette, by: GlimmTaste.nudge)
    }

    private mutating func move(_ feature: String, by delta: Double) {
        let next = min(GlimmTaste.bound, max(-GlimmTaste.bound, (scores[feature] ?? 0) + delta))
        if abs(next) < 0.0001 { scores.removeValue(forKey: feature) } else { scores[feature] = next }
    }

    /// The colours leant towards and away from, strongest first, by name.
    public func colours(liked: Bool) -> [String] {
        scores.filter { $0.key.hasPrefix("palette:") && (liked ? $0.value > 0.3 : $0.value < -0.3) }
            .sorted { liked ? ($0.value, $1.key) > ($1.value, $0.key) : ($0.value, $0.key) < ($1.value, $1.key) }
            .compactMap { GlimmWardrobe.palette(String($0.key.dropFirst(8)))?.name }
    }

    /// The cuts leant towards, strongest first, by name.
    public func cuts(liked: Bool) -> [String] {
        scores.filter { $0.key.hasPrefix("style:") && (liked ? $0.value > 0.3 : $0.value < -0.3) }
            .sorted { liked ? ($0.value, $1.key) > ($1.value, $0.key) : ($0.value, $0.key) < ($1.value, $1.key) }
            .compactMap { GlimmWardrobe.style(String($0.key.dropFirst(6)))?.name }
    }
}

// MARK: - Getting dressed

public enum GlimmStylist {
    /// How often, out of 1, a piece is picked with no regard to its score: a little exploring keeps
    /// the wardrobe from narrowing to a few favourites.
    public static let exploring = 0.14

    /// What a state of the day asks to be dressed for. A plain day is dressed for work in working
    /// hours and for getting out at the weekend, and now and then for the season.
    public static func context(for mood: BuddyMood, day: String, hour: Int, weekday: Int, month: Int) -> GlimmContext {
        switch mood {
        case .training: return .training
        case .sleeping, .sleepy: return .sleep
        case .celebrating: return .celebration
        case .worked, .unwell, .drained: return .relax
        case .hungry: return .cooking
        case .waiting, .thirsty, .steady, .charged:
            if let season = season(day: day, month: month) { return season }
            // 1 is Sunday, 7 Saturday.
            let weekend = weekday == 1 || weekday == 7
            if !weekend, hour >= 9, hour < 17 { return .focus }
            if weekend, hour >= 9, hour < 18, mood == .charged { return .adventure }
            return .everyday
        }
    }

    /// On some days the season picks the clothes: wrapped up in winter, a raincoat now and then, sun
    /// hats in summer. Which days is fixed by the date, so the day keeps its look. Glimm has no way
    /// to know the weather, and its lines never claim to.
    static func season(day: String, month: Int) -> GlimmContext? {
        var rng = SeededRNG(seed: seed("season|" + day))
        let roll = rng.unit()
        switch month {
        case 11, 12, 1, 2: return roll < 0.45 ? .cold : (roll < 0.6 ? .rain : nil)
        case 6, 7, 8: return roll < 0.4 ? .sun : (roll < 0.48 ? .rain : nil)
        default: return roll < 0.2 ? .rain : (roll < 0.3 ? .cold : nil)
        }
    }

    /// Whether a cut may be worn for a setting at all: nothing warm or loose to train in, and night
    /// clothes at night.
    public static func allowed(_ style: GlimmStyle, in context: GlimmContext) -> Bool {
        switch context {
        case .training:
            if style.warmth > 2 { return false }
            if style.slot == .head { return ["headband", "visor", "cap"].contains(style.shape) }
            if style.slot == .accessory { return ["watch", "pin"].contains(style.shape) }
            if style.slot == .feet { return ["runners", "court", "trail", "retro"].contains(style.shape) }
            if style.slot == .bottom { return style.shape != "skirt" && style.shape != "sleep" && style.shape != "jeans" }
            return style.shape != "pyjama"
        case .sleep:
            switch style.slot {
            case .top: return ["pyjama", "lounge", "crew"].contains(style.shape)
            case .bottom: return ["sleep", "joggers"].contains(style.shape)
            case .feet: return style.shape == "slipper"
            case .head, .accessory: return false
            }
        default:
            // Night clothes and slippers stay at home.
            return !["pyjama", "sleep", "slipper"].contains(style.shape)
        }
    }

    /// How well a piece suits: the setting first, then what has been learnt, what was worn lately,
    /// and the time of year.
    public static func score(_ item: GlimmItem, style: GlimmStyle, context: GlimmContext, taste: GlimmTaste, recentTops: [String], month: Int,
                             prefer: String? = nil) -> Double {
        var s: Double = style.context == context ? 5 : (style.context == .everyday ? 1 : 0)
        s += taste.score(item)
        if style.slot == .top, recentTops.contains(item.style + "__" + item.palette) { s -= 4 }
        if [.everyday, .focus, .relax, .adventure].contains(context) {
            let lean: Double = [11, 12, 1, 2].contains(month) ? 0.5 : ([6, 7, 8].contains(month) ? -0.5 : 0)
            s += lean * Double(style.warmth - 2)
        }
        if let prefer, item.palette == prefer { s += 6 }
        return s
    }

    /// An outfit for a setting. The same day, setting and `salt` always give the same outfit, so the
    /// app and its widgets agree and a day keeps its look; asking for another raises the salt.
    public static func outfit(context: GlimmContext, taste: GlimmTaste = GlimmTaste(), recentTops: [String] = [], day: String, salt: Int = 0, month: Int,
                              prefer: String? = nil) -> GlimmOutfit {
        var rng = SeededRNG(seed: seed("\(day)|\(context.rawValue)|\(salt)"))
        var picked: [GlimmSlot: GlimmItem] = [:]
        for slot in GlimmSlot.allCases {
            // A hat and an extra are not worn every time, and never to bed.
            if slot == .head || slot == .accessory {
                if context == .sleep { continue }
                let bare = slot == .head ? 0.45 : 0.3
                if rng.unit() < bare { continue }
            }
            var styles = GlimmWardrobe.styles(in: slot).filter { allowed($0, in: context) }
            if styles.isEmpty {
                if slot == .head || slot == .accessory { continue }
                styles = GlimmWardrobe.styles(in: slot)
            }
            var candidates: [(GlimmItem, Double)] = []
            for style in styles {
                for palette in GlimmWardrobe.palettes {
                    let item = GlimmItem(style: style.id, palette: palette.id)
                    let s = score(item, style: style, context: context, taste: taste, recentTops: recentTops, month: month, prefer: prefer)
                    candidates.append((item, exp(min(10, s) / 2.1)))
                }
            }
            guard !candidates.isEmpty else { continue }
            var choice = candidates[LNum.int((rng.unit() * Double(candidates.count)).rounded(.down)) % candidates.count].0
            if rng.unit() >= exploring {
                let total = candidates.reduce(0) { $0 + $1.1 }
                var ticket = rng.unit() * max(total, 0.001)
                for (item, weight) in candidates {
                    ticket -= weight
                    if ticket <= 0 { choice = item; break }
                }
            }
            if slot == .top {
                // Plain most of the time; a pattern is a treat.
                let roll = rng.unit()
                if roll >= 0.5 {
                    let marked = GlimmWardrobe.patterns.filter { $0 != "plain" }
                    choice.pattern = marked[LNum.int(((roll - 0.5) * 2 * Double(marked.count)).rounded(.down)) % marked.count]
                }
            }
            picked[slot] = choice
        }
        let fallback = GlimmOutfit.signature
        return GlimmOutfit(top: picked[.top] ?? fallback.top, bottom: picked[.bottom] ?? fallback.bottom, feet: picked[.feet] ?? fallback.feet,
                           head: picked[.head], accessory: picked[.accessory]).tidied()
    }

    /// A number for a string that is the same on every run and every device (FNV-1a).
    static func seed(_ text: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }
}

// MARK: - What it keeps

/// Something Glimm was asked to remember. Nothing is kept that its person did not confirm.
public struct GlimmMemory: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var at: Date
    /// "told" when it was written in by hand, "chat" when Glimm suggested it in a chat and it was agreed to.
    public var source: String

    public init(id: String, text: String, at: Date, source: String) {
        self.id = id; self.text = text; self.at = at; self.source = source
    }
}

/// One line of a chat with Glimm.
public struct GlimmTurn: Codable, Equatable, Sendable {
    public var mine: Bool
    public var text: String
    public var at: Date

    public init(mine: Bool, text: String, at: Date) { self.mine = mine; self.text = text; self.at = at }
}

/// Everything Glimm keeps between one day and the next.
public struct GlimmState: Codable, Equatable, Sendable {
    public var taste = GlimmTaste()
    /// An outfit kept on until it is let go.
    public var lock: GlimmOutfit?
    /// What was picked for a setting today, by hand or by asking for another, by `GlimmContext` name.
    public var chosen: [String: GlimmOutfit] = [:]
    /// How many times another outfit was asked for today, by setting.
    public var salts: [String: Int] = [:]
    /// The day `chosen` and `salts` hold for.
    public var day = ""
    /// The tops of the last few days, as "style__palette", so they are not worn again at once.
    public var recentTops: [String] = []
    public var memories: [GlimmMemory] = []
    /// The lines said lately, by id, so one is not said twice running.
    public var said: [String] = []
    public var chat: [GlimmTurn] = []
    /// Glimm keeps its words to itself: it still moves, and still answers when spoken to.
    public var quiet = false

    public static let memoryLimit = 60
    public static let memoryLength = 200
    public static let chatKept = 16
    public static let saidKept = 24

    public init() {}

    enum CodingKeys: String, CodingKey { case taste, lock, chosen, salts, day, recentTops, memories, said, chat, quiet }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taste = try c.decodeIfPresent(GlimmTaste.self, forKey: .taste) ?? GlimmTaste()
        lock = try c.decodeIfPresent(GlimmOutfit.self, forKey: .lock)
        chosen = try c.decodeIfPresent([String: GlimmOutfit].self, forKey: .chosen) ?? [:]
        salts = try c.decodeIfPresent([String: Int].self, forKey: .salts) ?? [:]
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        recentTops = try c.decodeIfPresent([String].self, forKey: .recentTops) ?? []
        memories = try c.decodeIfPresent([GlimmMemory].self, forKey: .memories) ?? []
        said = try c.decodeIfPresent([String].self, forKey: .said) ?? []
        chat = try c.decodeIfPresent([GlimmTurn].self, forKey: .chat) ?? []
        quiet = try c.decodeIfPresent(Bool.self, forKey: .quiet) ?? false
        // A piece the wardrobe no longer holds is not kept on.
        if let kept = lock, !kept.isValid { lock = nil }
        chosen = chosen.filter { $0.value.isValid }
    }

    /// Whether two states would dress it the same: everything `outfit(for:day:month:)` reads. What it
    /// has said or been told does not change its clothes.
    public func dressesAs(_ other: GlimmState) -> Bool {
        taste == other.taste && lock == other.lock && chosen == other.chosen && salts == other.salts && day == other.day
            && recentTops == other.recentTops
    }

    /// What Glimm wears for a setting on a day: the outfit kept on, else the one picked today, else
    /// the stylist's.
    public func outfit(for context: GlimmContext, day: String, month: Int) -> GlimmOutfit {
        if let lock { return lock }
        if day == self.day, let picked = chosen[context.rawValue] { return picked }
        let salt = day == self.day ? (salts[context.rawValue] ?? 0) : 0
        return GlimmStylist.outfit(context: context, taste: taste, recentTops: recentTops, day: day, salt: salt, month: month)
    }

    /// A new day: what was picked yesterday no longer holds, and yesterday's top goes on the list of
    /// what was worn lately. Does nothing on the same day.
    public mutating func turn(to day: String, month: Int) {
        guard day != self.day else { return }
        if !self.day.isEmpty {
            let worn = outfit(for: .everyday, day: self.day, month: month).top
            recentTops = Array((recentTops + [worn.style + "__" + worn.palette]).suffix(6))
        }
        chosen = [:]
        salts = [:]
        self.day = day
    }

    /// Another outfit for a setting, kept for the rest of the day. `prefer` is a colour asked for.
    @discardableResult
    public mutating func another(for context: GlimmContext, day: String, month: Int, prefer: String? = nil) -> GlimmOutfit {
        turn(to: day, month: month)
        let before = outfit(for: context, day: day, month: month)
        var salt = (salts[context.rawValue] ?? 0) + 1
        var next = GlimmStylist.outfit(context: context, taste: taste, recentTops: recentTops, day: day, salt: salt, month: month, prefer: prefer)
        // The same clothes again would not be another outfit.
        var tries = 0
        while next == before, tries < 6 {
            salt += 1
            tries += 1
            next = GlimmStylist.outfit(context: context, taste: taste, recentTops: recentTops, day: day, salt: salt, month: month, prefer: prefer)
        }
        salts[context.rawValue] = salt
        chosen[context.rawValue] = next
        if lock != nil { lock = next }
        return next
    }

    /// One piece put on by hand, for the rest of the day; a little is learnt from the pick.
    @discardableResult
    public mutating func wear(_ item: GlimmItem, for context: GlimmContext, day: String, month: Int) -> GlimmOutfit {
        turn(to: day, month: month)
        let next = outfit(for: context, day: day, month: month).wearing(item)
        chosen[context.rawValue] = next
        if lock != nil { lock = next }
        taste.chose(item)
        return next
    }

    /// The hat or the extra taken off, for the rest of the day.
    @discardableResult
    public mutating func takeOff(_ slot: GlimmSlot, for context: GlimmContext, day: String, month: Int) -> GlimmOutfit {
        turn(to: day, month: month)
        let next = outfit(for: context, day: day, month: month).without(slot)
        chosen[context.rawValue] = next
        if lock != nil { lock = next }
        return next
    }

    /// Something to remember, as its person wrote it or agreed to it. Trimmed, never twice, and the
    /// oldest give way once there are too many. Returns false when there was nothing new to keep.
    @discardableResult
    public mutating func remember(_ text: String, source: String, now: Date = Date()) -> Bool {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(GlimmState.memoryLength))
        guard !clean.isEmpty, !memories.contains(where: { $0.text.lowercased() == clean.lowercased() }) else { return false }
        let id = "\(LNum.int((now.timeIntervalSince1970 * 1000).rounded()))-\(memories.count)"
        memories.append(GlimmMemory(id: id, text: clean, at: now, source: source))
        memories = Array(memories.suffix(GlimmState.memoryLimit))
        return true
    }

    public mutating func forget(_ id: String) { memories.removeAll { $0.id == id } }

    public mutating func noteSaid(_ id: String) { said = Array((said + [id]).suffix(GlimmState.saidKept)) }

    public mutating func addTurn(mine: Bool, text: String, now: Date = Date()) {
        chat = Array((chat + [GlimmTurn(mine: mine, text: text, at: now)]).suffix(GlimmState.chatKept))
    }
}
