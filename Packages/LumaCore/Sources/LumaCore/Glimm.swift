import Foundation

// MARK: - Glimm
//
// The companion as a character: its moods, its wardrobe, a taste of its own and the small things it
// remembers. What state it is in still comes from the facts (`Buddy.look`); how that state is worn
// is Glimm's own choice, made here and nowhere else: nobody dresses it, and no screen shows its
// wardrobe. Nothing here draws: the figure is drawn from the outfit's `code` by LumaKit, which knows
// each cut by its shape name.

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

    /// The outfit with one piece in its slot, and a hat it cannot be worn with left off. For showing
    /// a piece on the figure; what Glimm wears is picked whole, by `GlimmStylist.outfit`.
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
        return o.tidied()
    }

    /// Things that cannot be worn together: a hat under a hood that is up, and headphones over
    /// anything but a bare head, a headband or a visor. The hat is what stays off.
    func tidied() -> GlimmOutfit {
        var o = self
        let shape: (GlimmItem?) -> String? = { $0.flatMap { GlimmWardrobe.style($0.style)?.shape } }
        if shape(o.top) == "coat" { o.head = nil }
        if shape(o.accessory) == "headphones", let hat = shape(o.head), hat != "headband", hat != "visor" { o.head = nil }
        return o
    }
}

// MARK: - Taste

/// What Glimm has grown fond of along the way: a score for each colour and each cut, raised when
/// something kind was said about what it had on. What it liked from the start (`GlimmNature`) and
/// the colour it is into for now (`GlimmStylist.phase`) are not kept here: they are not learnt.
public struct GlimmTaste: Codable, Equatable, Sendable {
    /// "palette:coral" and "style:zip-hoodie" to a score between −`bound` and `bound`.
    public var scores: [String: Double] = [:]
    /// The outfits rated, by key: 1 liked, −1 not.
    public var ratings: [String: Int] = [:]
    /// The rated outfits in the order they were first rated, oldest first.
    public var order: [String] = []

    public static let bound = 6.0
    public static let step = 0.65
    public static let kept = 300

    public init() {}

    public func rating(of outfit: GlimmOutfit) -> Int { ratings[outfit.key] ?? 0 }

    public func score(_ item: GlimmItem) -> Double {
        (scores["palette:" + item.palette] ?? 0) + (scores["style:" + item.style] ?? 0)
    }

    /// What was thought of an outfit. Saying the same thing twice changes nothing; a change of mind
    /// takes the first answer back before applying the second.
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

    private mutating func move(_ feature: String, by delta: Double) {
        let next = min(GlimmTaste.bound, max(-GlimmTaste.bound, (scores[feature] ?? 0) + delta))
        if abs(next) < 0.0001 { scores.removeValue(forKey: feature) } else { scores[feature] = next }
    }

    /// What it has grown fond of, strongest first, by name: colours, then cuts.
    public var fondOf: [String] {
        let liked = scores.filter { $0.value > 0.3 }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        let colours = liked.filter { $0.key.hasPrefix("palette:") }.compactMap { GlimmWardrobe.palette(String($0.key.dropFirst(8)))?.name }
        let cuts = liked.filter { $0.key.hasPrefix("style:") }.compactMap { GlimmWardrobe.style(String($0.key.dropFirst(6)))?.name }
        return colours + cuts
    }
}

// MARK: - A taste of its own

/// What Glimm liked before it learnt anything: colourful trainers, big hoodies, useful pockets and
/// its thinking cardigan, in the colours it is known by. Fixed, so it has favourites from the first
/// day and they stay its favourites.
public enum GlimmNature {
    static let leanings: [String: Double] = [
        "palette:coral": 1.5, "palette:teal": 1.2, "palette:lilac": 1.2, "palette:butter": 0.8, "palette:sky": 0.5, "palette:tangerine": 0.4,
        "palette:navy": -0.3, "palette:charcoal": -0.6,
        "style:zip-hoodie": 1.5, "style:trainers": 1.4, "style:cloud-hoodie": 1.2, "style:joggers": 1.0, "style:crossbody": 1.0,
        "style:high-tops": 0.9, "style:sweatshirt": 0.8, "style:cargos": 0.8, "style:cardigan": 0.8, "style:retro-shoes": 0.7,
        "style:bomber": 0.6, "style:backpack": 0.6,
    ]

    public static func score(_ item: GlimmItem) -> Double {
        (leanings["palette:" + item.palette] ?? 0) + (leanings["style:" + item.style] ?? 0)
    }

    /// A cut it has always reached for.
    public static func isFavourite(_ item: GlimmItem) -> Bool { (leanings["style:" + item.style] ?? 0) >= 1 }

    /// The colours and the cuts it has always liked, strongest first, by name.
    public static let favourites: (colours: [String], cuts: [String]) = {
        let liked = leanings.filter { $0.value >= 1 }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        return (liked.filter { $0.key.hasPrefix("palette:") }.compactMap { GlimmWardrobe.palette(String($0.key.dropFirst(8)))?.name },
                liked.filter { $0.key.hasPrefix("style:") }.compactMap { GlimmWardrobe.style(String($0.key.dropFirst(6)))?.name })
    }()
}

/// How the day feels to it, which shows in what it reaches for: louder colours and more pattern on
/// a strong day, gentler ones and plainer cloth on a low one.
public enum GlimmFeel: String, Codable, CaseIterable, Sendable {
    case bright, even, soft

    /// From the day's recovery score, by the bands the recovery ring uses; even when there is none.
    public init(recovery score: Double?) {
        guard let score else { self = .even; return }
        switch RecoveryBand.of(score) {
        case .high: self = .bright
        case .moderate: self = .even
        case .low: self = .soft
        }
    }

    static let loud: Set<String> = ["coral", "teal", "butter", "cobalt", "tangerine", "cherry"]
    static let gentle: Set<String> = ["lilac", "sky", "rose", "sage", "cream", "mint"]

    /// What the feeling adds to a colour's pull.
    func pull(_ palette: String) -> Double {
        switch self {
        case .bright: return GlimmFeel.loud.contains(palette) ? 1 : (GlimmFeel.gentle.contains(palette) ? 0 : -0.5)
        case .soft: return GlimmFeel.gentle.contains(palette) ? 1 : (GlimmFeel.loud.contains(palette) ? -0.5 : 0)
        case .even: return 0
        }
    }

    /// How often, out of 1, a top comes with a pattern.
    var patterned: Double {
        switch self {
        case .bright: return 0.62
        case .even: return 0.5
        case .soft: return 0.3
        }
    }
}

/// Why Glimm has on what it has on.
public enum GlimmWhy: Hashable, Sendable {
    /// It changed its mind today.
    case changed
    /// The top it had on to train in on the day of a new best.
    case lucky
    /// The day asked for it: training, bed, a celebration, the kitchen, rain, cold, sun, getting out, work.
    case setting(GlimmContext)
    /// The colour it is into for now, by palette id.
    case phase(String)
    /// One of the cuts it has always liked, by style id.
    case favourite(String)
    /// It felt like it.
    case fancy
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

    /// The settings whose clothes are for that setting alone: party clothes for a new best, a chef's
    /// coat for the kitchen, night clothes for bed. Worn on any other day they would say something
    /// about the day that is not so.
    public static let occasions: Set<GlimmContext> = [.celebration, .cooking, .sleep]

    /// How often, out of 1, a piece is taken from those made for the setting when there are any: every
    /// time for an occasion, and a little under half the time otherwise, the rest being its own idea
    /// (which still leans towards the setting).
    public static func dressing(_ context: GlimmContext) -> Double { occasions.contains(context) ? 1 : 0.45 }

    /// Whether a cut may be worn for a setting at all: an occasion's clothes on that occasion only;
    /// nothing made for sun on a cold or a wet day or in the cold months, and nothing made for cold on
    /// a sunny day or in the warm ones (no sun hat with a scarf); nothing warm or loose to train in;
    /// and night clothes at night.
    public static func allowed(_ style: GlimmStyle, in context: GlimmContext, month: Int? = nil) -> Bool {
        if occasions.contains(style.context), style.context != context { return false }
        let cold = context == .cold || context == .rain || [11, 12, 1, 2].contains(month ?? 0)
        let warm = context == .sun || [6, 7, 8].contains(month ?? 0)
        if style.context == .sun, cold { return false }
        if style.context == .cold, warm { return false }
        switch context {
        case .training:
            if style.warmth > 2 { return false }
            if style.slot == .head { return ["headband", "visor", "cap"].contains(style.shape) }
            if style.slot == .accessory { return ["watch", "pin"].contains(style.shape) }
            if style.slot == .feet { return ["runners", "court", "trail", "retro"].contains(style.shape) }
            if style.slot == .bottom { return style.shape != "skirt" && style.shape != "jeans" }
            return true
        case .sleep:
            switch style.slot {
            case .top: return ["pyjama", "lounge", "crew"].contains(style.shape)
            case .bottom: return ["sleep", "joggers"].contains(style.shape)
            case .feet: return style.shape == "slipper"
            case .head, .accessory: return false
            }
        default:
            return true
        }
    }

    // MARK: What it likes

    /// The days a phase lasts.
    public static let phaseDays = 9
    /// What being in a phase adds to a colour's pull.
    public static let phasePull = 2.4
    /// How often, out of 1, it trains in its lucky top once it has one.
    public static let luckyShare = 0.4

    /// The colour Glimm is into for now. Phases come and go with the calendar alone, a few days at a
    /// time: it has one from the first day, and nobody sets it.
    public static func phase(day: String) -> GlimmPalette {
        let run = (dayNumber(day) ?? 0) / phaseDays
        var rng = SeededRNG(seed: seed("phase|\(run)"))
        let all = GlimmWardrobe.palettes
        return all[LNum.int((rng.unit() * Double(all.count)).rounded(.down)) % all.count]
    }

    /// A day's place in the run of days, from its "YYYY-MM-DD" key (1970-01-01 is 0): the same
    /// wherever it is worked out, with no calendar or time zone in it.
    static func dayNumber(_ day: String) -> Int? {
        let f = day.split(separator: "-").compactMap { Int($0) }
        guard f.count == 3, (1...12).contains(f[1]), (1...31).contains(f[2]) else { return nil }
        let y = f[1] <= 2 ? f[0] - 1 : f[0]
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * ((f[1] + 9) % 12) + 2) / 5 + f[2] - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// How much Glimm likes a piece for itself, whatever the day asks for: what it has always liked,
    /// what it has grown fond of, and the colour it is into for now.
    public static func liking(_ item: GlimmItem, taste: GlimmTaste, phase: String?) -> Double {
        GlimmNature.score(item) + taste.score(item) + (item.palette == phase ? phasePull : 0)
    }

    /// How well a piece suits: the setting first, then its own liking, how the day feels, what was
    /// worn lately, and the time of year.
    public static func score(_ item: GlimmItem, style: GlimmStyle, context: GlimmContext, taste: GlimmTaste, recentTops: [String], month: Int,
                             prefer: String? = nil, phase: String? = nil, feel: GlimmFeel = .even) -> Double {
        var s: Double = style.context == context ? 5 : (style.context == .everyday ? 1 : 0)
        s += liking(item, taste: taste, phase: phase) + feel.pull(item.palette)
        if style.slot == .top, recentTops.contains(item.style + "__" + item.palette) { s -= 4 }
        if [.everyday, .focus, .relax, .adventure].contains(context) {
            let lean: Double = [11, 12, 1, 2].contains(month) ? 0.5 : ([6, 7, 8].contains(month) ? -0.5 : 0)
            s += lean * Double(style.warmth - 2)
        }
        if let prefer, item.palette == prefer { s += 6 }
        return s
    }

    /// An outfit for a setting, picked whole by Glimm. The same day, setting, feeling and `salt`
    /// always give the same outfit, so the app and its widgets agree and a day keeps its look; a
    /// change of mind raises the salt. `lucky` is its lucky top, by item id: on some training days
    /// it is simply what goes on.
    public static func outfit(context: GlimmContext, taste: GlimmTaste = GlimmTaste(), recentTops: [String] = [], day: String, salt: Int = 0, month: Int,
                              prefer: String? = nil, feel: GlimmFeel = .even, lucky: String? = nil) -> GlimmOutfit {
        var rng = SeededRNG(seed: seed("\(day)|\(context.rawValue)|\(salt)"))
        let into = phase(day: day).id
        var picked: [GlimmSlot: GlimmItem] = [:]
        for slot in GlimmSlot.allCases {
            // A hat and an extra are not worn every time, and never to bed. A new best nearly always gets both.
            if slot == .head || slot == .accessory {
                if context == .sleep { continue }
                let bare = context == .celebration ? 0.12 : (slot == .head ? 0.45 : 0.3)
                if rng.unit() < bare { continue }
            }
            var styles = GlimmWardrobe.styles(in: slot).filter { allowed($0, in: context, month: month) }
            if styles.isEmpty {
                if slot == .head || slot == .accessory { continue }
                styles = GlimmWardrobe.styles(in: slot)
            }
            var candidates: [(item: GlimmItem, weight: Double, fits: Bool)] = []
            for style in styles {
                for palette in GlimmWardrobe.palettes {
                    let item = GlimmItem(style: style.id, palette: palette.id)
                    let s = score(item, style: style, context: context, taste: taste, recentTops: recentTops, month: month, prefer: prefer,
                                  phase: into, feel: feel)
                    candidates.append((item, exp(min(10, s) / 2.1), style.context == context))
                }
            }
            guard !candidates.isEmpty else { continue }
            // Much of what it wears for a setting is made for it; the rest is its own idea. The roll is
            // made either way, so the day's other pieces do not hang on whether anything fits.
            let dress = rng.unit()
            let fitting = candidates.filter { $0.fits }
            let pool = (!fitting.isEmpty && dress < dressing(context)) ? fitting : candidates
            var choice = pool[LNum.int((rng.unit() * Double(pool.count)).rounded(.down)) % pool.count].item
            if rng.unit() >= exploring {
                let total = pool.reduce(0) { $0 + $1.weight }
                var ticket = rng.unit() * max(total, 0.001)
                for candidate in pool {
                    ticket -= candidate.weight
                    if ticket <= 0 { choice = candidate.item; break }
                }
            }
            if slot == .top {
                // Plain much of the time; a pattern is a treat, and more of one on a bright day.
                let roll = rng.unit()
                let plain = 1 - feel.patterned
                if roll >= plain {
                    let marked = GlimmWardrobe.patterns.filter { $0 != "plain" }
                    choice.pattern = marked[LNum.int(((roll - plain) / (1 - plain) * Double(marked.count)).rounded(.down)) % marked.count]
                }
                // Its lucky top is for training in. The roll is made either way, so having one changes
                // nothing else about the day's kit.
                let fate = rng.unit()
                if context == .training, prefer == nil, fate < luckyShare, let piece = lucky.flatMap({ GlimmItem(id: $0) }), piece.slot == .top { choice = piece }
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

/// Something Glimm keeps. What it is told or suggests in a chat is kept only once its person agrees.
/// What it works out by itself, a day at a time, is kept while learning is switched on. Every line can
/// be read and removed.
public struct GlimmMemory: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var at: Date
    /// "told" when it was written in by hand, "chat" when Glimm suggested it in a chat and it was agreed
    /// to, "noticed" when Glimm worked it out by itself.
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
    /// What it changed into today, when it changed its mind, by `GlimmContext` name.
    public var chosen: [String: GlimmOutfit] = [:]
    /// How many times it has changed its mind today, by setting.
    public var salts: [String: Int] = [:]
    /// The day `chosen`, `salts` and `feel` hold for.
    public var day = ""
    /// The tops of the last few days, as "style__palette", so they are not worn again at once.
    public var recentTops: [String] = []
    /// How today feels to it, once the day's recovery is known.
    public var feel = GlimmFeel.even
    /// Its lucky top, by item id: the one it had on to train in on the day of a new best.
    public var lucky: String?
    /// The day the lucky top was last made so.
    public var luckyDay: String?
    public var memories: [GlimmMemory] = []
    /// The lines said lately, by id, so one is not said twice running.
    public var said: [String] = []
    public var chat: [GlimmTurn] = []
    /// Glimm keeps its words to itself: it still moves, and still answers when spoken to.
    public var quiet = false
    /// It adds to its own notebook, a little each day, from what the day held.
    public var learns = true
    /// The lines written for one day, and the day they were last asked for.
    public var lines: GlimmDayLines?
    public var linesAsked: String?
    /// Notes of its own that its person took out, newest last. One is never written again, and the
    /// day's request names them so nothing close to them is written either.
    public var takenOut: [String] = []
    /// How many days it has looked over its person's records with learning on.
    public var daysLearned = 0
    /// How many of its own notes it has crossed out itself, because the days stopped bearing them out.
    public var crossedOut = 0
    /// When its notebook was last looked at. A note written after that is new to its person.
    public var notebookSeen: Date?
    /// Marks of what it suggested remembering and was told not to, so the same thing is not asked
    /// twice. A mark is a number worked out from the words; the words themselves are not kept.
    public var declined: [String] = []

    /// The source of a line it worked out by itself.
    public static let noticed = "noticed"
    public static let noticedLimit = 30
    public static let takenOutKept = 20
    public static let declinedKept = 40

    public static let memoryLimit = 60
    public static let memoryLength = 200
    public static let chatKept = 16
    public static let saidKept = 24

    public init() {}

    // An outfit could once be kept on by hand ("lock"). It is no longer read or written: what it
    // wears is its own choice, and a file that still holds one is read as if it did not.
    enum CodingKeys: String, CodingKey {
        case taste, chosen, salts, day, recentTops, feel, lucky, luckyDay, memories, said, chat, quiet, learns, lines, linesAsked
        case takenOut, daysLearned, crossedOut, notebookSeen, declined
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taste = try c.decodeIfPresent(GlimmTaste.self, forKey: .taste) ?? GlimmTaste()
        chosen = try c.decodeIfPresent([String: GlimmOutfit].self, forKey: .chosen) ?? [:]
        salts = try c.decodeIfPresent([String: Int].self, forKey: .salts) ?? [:]
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        recentTops = try c.decodeIfPresent([String].self, forKey: .recentTops) ?? []
        feel = (try? c.decodeIfPresent(GlimmFeel.self, forKey: .feel)) ?? .even
        lucky = try c.decodeIfPresent(String.self, forKey: .lucky)
        luckyDay = try c.decodeIfPresent(String.self, forKey: .luckyDay)
        memories = try c.decodeIfPresent([GlimmMemory].self, forKey: .memories) ?? []
        said = try c.decodeIfPresent([String].self, forKey: .said) ?? []
        chat = try c.decodeIfPresent([GlimmTurn].self, forKey: .chat) ?? []
        quiet = try c.decodeIfPresent(Bool.self, forKey: .quiet) ?? false
        learns = try c.decodeIfPresent(Bool.self, forKey: .learns) ?? true
        lines = try? c.decodeIfPresent(GlimmDayLines.self, forKey: .lines)
        linesAsked = try c.decodeIfPresent(String.self, forKey: .linesAsked)
        takenOut = try c.decodeIfPresent([String].self, forKey: .takenOut) ?? []
        daysLearned = try c.decodeIfPresent(Int.self, forKey: .daysLearned) ?? 0
        crossedOut = try c.decodeIfPresent(Int.self, forKey: .crossedOut) ?? 0
        notebookSeen = try c.decodeIfPresent(Date.self, forKey: .notebookSeen)
        declined = try c.decodeIfPresent([String].self, forKey: .declined) ?? []
        // A piece the wardrobe no longer holds is not worn.
        chosen = chosen.filter { $0.value.isValid }
    }

    /// Whether two states would dress it the same: everything `outfit(for:day:month:)` reads. What it
    /// has said or been told does not change its clothes.
    public func dressesAs(_ other: GlimmState) -> Bool {
        taste == other.taste && chosen == other.chosen && salts == other.salts && day == other.day && recentTops == other.recentTops
            && feel == other.feel && lucky == other.lucky
    }

    /// What Glimm wears for a setting on a day. Its own pick, always: what it changed into today when
    /// it changed its mind, else what it chose for the day. A day still to come is dressed as it will
    /// be once the day has turned.
    public func outfit(for context: GlimmContext, day: String, month: Int) -> GlimmOutfit {
        if day == self.day, let picked = chosen[context.rawValue] { return picked }
        if !self.day.isEmpty, day > self.day {
            var ahead = self
            ahead.turn(to: day, month: month)
            return ahead.outfit(for: context, day: day, month: month)
        }
        let today = day == self.day
        return GlimmStylist.outfit(context: context, taste: taste, recentTops: recentTops, day: day, salt: today ? (salts[context.rawValue] ?? 0) : 0,
                                   month: month, feel: today ? feel : .even, lucky: lucky)
    }

    /// A new day: yesterday's changes of mind no longer hold, how the day feels is not known yet, and
    /// yesterday's top goes on the list of what was worn lately. Does nothing on the same day.
    public mutating func turn(to day: String, month: Int) {
        guard day != self.day else { return }
        if !self.day.isEmpty {
            let worn = outfit(for: .everyday, day: self.day, month: month).top
            recentTops = Array((recentTops + [worn.style + "__" + worn.palette]).suffix(6))
        }
        chosen = [:]
        salts = [:]
        feel = .even
        self.day = day
    }

    /// A change of mind: another outfit for a setting, worn for the rest of the day. `prefer` is a
    /// colour it has taken a fancy to.
    @discardableResult
    public mutating func another(for context: GlimmContext, day: String, month: Int, prefer: String? = nil) -> GlimmOutfit {
        turn(to: day, month: month)
        let before = outfit(for: context, day: day, month: month)
        var salt = (salts[context.rawValue] ?? 0) + 1
        let (taste, recentTops, feel, lucky) = (self.taste, self.recentTops, self.feel, self.lucky)
        let pick: (Int) -> GlimmOutfit = { salt in
            GlimmStylist.outfit(context: context, taste: taste, recentTops: recentTops, day: day, salt: salt, month: month, prefer: prefer, feel: feel,
                                lucky: lucky)
        }
        var next = pick(salt)
        // The same clothes again would not be a change.
        var tries = 0
        while next == before, tries < 6 {
            salt += 1
            tries += 1
            next = pick(salt)
        }
        salts[context.rawValue] = salt
        chosen[context.rawValue] = next
        return next
    }

    /// A new best came today: the top it trains in today is its lucky one from now on.
    public mutating func noteBest(day: String, month: Int) {
        turn(to: day, month: month)
        guard luckyDay != day else { return }
        lucky = outfit(for: .training, day: day, month: month).top.id
        luckyDay = day
    }

    /// Something kind was said about what it has on: it grows a little fonder of each piece.
    public mutating func enjoyed(_ outfit: GlimmOutfit) { taste.rate(outfit, like: true) }

    /// Why it has on what it has on for a setting. A change of mind and a lucky top are always the
    /// reason; otherwise one of the reasons that hold, the same one all day.
    public func why(_ outfit: GlimmOutfit, for context: GlimmContext, day: String) -> GlimmWhy {
        if day == self.day, chosen[context.rawValue] != nil { return .changed }
        if context == .training, outfit.top.id == lucky { return .lucky }
        var reasons: [GlimmWhy] = []
        // The setting is a reason only when something it has on was made for it.
        if context != .everyday, outfit.items.contains(where: { GlimmWardrobe.style($0.style)?.context == context }) { reasons.append(.setting(context)) }
        let into = GlimmStylist.phase(day: day).id
        if outfit.items.contains(where: { $0.palette == into }) { reasons.append(.phase(into)) }
        if let piece = outfit.items.first(where: { GlimmNature.isFavourite($0) }) { reasons.append(.favourite(piece.style)) }
        guard !reasons.isEmpty else { return .fancy }
        var rng = SeededRNG(seed: GlimmStylist.seed("why|\(day)|\(context.rawValue)"))
        return reasons[LNum.int((rng.unit() * Double(reasons.count)).rounded(.down)) % reasons.count]
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

    /// Takes one line out. One of its own notes taken out by its person is also put on the list of
    /// what not to write again: taking a note out is how it is told that a note was wrong or unwanted.
    public mutating func forget(_ id: String) {
        if let note = memories.first(where: { $0.id == id }), note.source == GlimmState.noticed {
            takenOut = Array((takenOut.filter { $0.lowercased() != note.text.lowercased() } + [note.text]).suffix(GlimmState.takenOutKept))
        }
        memories.removeAll { $0.id == id }
    }

    /// Something it worked out by itself. Kept only while learning is on, never when its person has
    /// taken the same note out before, and only so many: the oldest of its own notes give way, never
    /// what its person told it.
    @discardableResult
    public mutating func notice(_ text: String, now: Date = Date()) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard learns, !takenOut.contains(where: { $0.lowercased() == clean }),
              remember(text, source: GlimmState.noticed, now: now) else { return false }
        // The oldest of its own notes go first, by place and not by name: two notes can share a name.
        var extra = memories.filter { $0.source == GlimmState.noticed }.count - GlimmState.noticedLimit
        guard extra > 0 else { return true }
        var kept: [GlimmMemory] = []
        for memory in memories {
            if extra > 0, memory.source == GlimmState.noticed {
                extra -= 1
            } else {
                kept.append(memory)
            }
        }
        memories = kept
        return true
    }

    /// Its own notes, oldest first.
    public var notebook: [GlimmMemory] { memories.filter { $0.source == GlimmState.noticed } }

    /// One day's learning, applied. The notes it now takes to be out of date are crossed out, by name
    /// so that a notebook changed since the request was written cannot lose the wrong line; then what
    /// is new is written in. Only its own notes can be crossed out, and only so many in a day. Nothing
    /// changes while learning is off. The day counts as a day of learning whether or not it found
    /// anything.
    @discardableResult
    public mutating func learn(noticed: [String], crossingOut ids: [String] = [], now: Date = Date()) -> GlimmLearned {
        guard learns else { return GlimmLearned() }
        daysLearned += 1
        var change = GlimmLearned()
        for id in ids.prefix(GlimmDaily.outdatedLimit) {
            guard let i = memories.firstIndex(where: { $0.id == id && $0.source == GlimmState.noticed }) else { continue }
            change.crossedOut.append(memories[i].text)
            memories.remove(at: i)
        }
        crossedOut += change.crossedOut.count
        for note in noticed.prefix(GlimmDaily.noticedLimit) {
            guard notice(note, now: now), let kept = memories.last else { continue }
            change.added.append(kept.text)
        }
        return change
    }

    /// Its own notes written since its person last looked at the notebook.
    public var unseenNotes: [GlimmMemory] {
        guard let seen = notebookSeen else { return notebook }
        return notebook.filter { $0.at > seen }
    }

    /// Forget everything it worked out by itself and start again: its notes, what it was told not to
    /// write, and its counts. What it was told to remember stays.
    public mutating func clearNotebook() {
        memories.removeAll { $0.source == GlimmState.noticed }
        takenOut = []
        daysLearned = 0
        crossedOut = 0
    }

    /// Something it suggested remembering was turned down: it does not suggest the same again.
    public mutating func decline(_ text: String) {
        let mark = GlimmState.mark(text)
        declined = Array((declined.filter { $0 != mark } + [mark]).suffix(GlimmState.declinedKept))
    }

    public func wasDeclined(_ text: String) -> Bool { declined.contains(GlimmState.mark(text)) }

    /// The mark kept for a suggestion that was turned down: a number worked out from its letters and
    /// digits, the same on every run. It is the number that is kept, not the words.
    static func mark(_ text: String) -> String {
        var words = String.UnicodeScalarView()
        for scalar in text.lowercased().unicodeScalars where CharacterSet.alphanumerics.contains(scalar) { words.append(scalar) }
        return String(GlimmStylist.seed(String(words)), radix: 16)
    }

    public mutating func noteSaid(_ id: String) { said = Array((said + [id]).suffix(GlimmState.saidKept)) }

    public mutating func addTurn(mine: Bool, text: String, now: Date = Date()) {
        chat = Array((chat + [GlimmTurn(mine: mine, text: text, at: now)]).suffix(GlimmState.chatKept))
    }
}
