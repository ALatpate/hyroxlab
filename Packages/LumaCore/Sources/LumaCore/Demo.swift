import Foundation

/// Deterministic generator (SplitMix64) so demo data is identical on every run and platform.
public struct SeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    public mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
    public mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }

    /// Standard normal (Box–Muller).
    public mutating func gauss() -> Double {
        let u = max(unit(), 1e-12), v = unit()
        return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
    }
}

/// A synthetic athlete: about four months of nights, days and sessions with realistic structure
/// (a weekly rhythm, a slow fitness trend, late nights at weekends, one off-colour spell), used by the
/// development gallery, the screenshots and the unit tests. Never mixed with real data.
public final class LumaDemoSource: LumaDataSource {
    public let days: [LDay]
    public let sleeps: [LSleep]
    public let workouts: [LWorkout]
    public let checkIns: [CheckIn]
    public let today: String
    private let calendar: Calendar

    public init(dayCount: Int = 120, today: Date = Date(), calendar: Calendar = LDate.calendar) {
        self.calendar = calendar
        self.today = LDate.key(today, calendar: calendar)
        var rng = SeededRNG(seed: 0x4C55_4D41)
        var days: [LDay] = [], sleeps: [LSleep] = [], workouts: [LWorkout] = [], checkIns: [CheckIn] = []
        var fatigue = 50.0
        var priorStrain = 45.0
        var alcoholLastNight = false
        let keys = LDate.range(ending: self.today, count: dayCount, calendar: calendar)

        for (i, key) in keys.enumerated() {
            let progress = Double(i) / Double(max(1, dayCount - 1))
            let wd = LDate.weekday(key, calendar: calendar)
            let fromEnd = dayCount - 1 - i
            let unwell = dayCount > 40 && (21...24).contains(fromEnd)
            guard let midnight = LDate.startOfDay(key, calendar: calendar)?.timeIntervalSince1970 else { continue }

            // ---- Night that ended this morning
            let weekendNight = wd == 6 || wd == 7        // Friday and Saturday nights end on Sat / Sun
            let bed = (weekendNight ? -15.0 : -62.0) + rng.gauss() * 22 + (alcoholLastNight ? 35 : 0)
            let wake = (weekendNight ? 470.0 : 392.0) + rng.gauss() * 16
            let start = midnight + bed * 60, end = midnight + wake * 60
            let stages = LumaDemoSource.stages(start: start, end: end, restless: alcoholLastNight || unwell, rng: &rng)
            let block = LSleep(start: start, end: end, day: key, stages: stages)
            let asleep = block.asleepMin
            let efficiency = asleep / block.inBedMin * 100

            let hrvBase = 56 + 8 * progress
            let rhrBase = 54 - 3 * progress
            var hrv = hrvBase - (fatigue - 50) * 0.28 + (asleep - 440) * 0.035 + rng.gauss() * 4.2
            var rhr = rhrBase + (fatigue - 50) * 0.09 - (asleep - 440) * 0.008 + rng.gauss() * 1.1
            var resp = 14.3 + rng.gauss() * 0.28
            var temp = rng.gauss() * 0.16
            if alcoholLastNight { hrv *= 0.84; rhr += 3.4; resp += 0.4; temp += 0.2 }
            if unwell { hrv *= 0.72; rhr += 6.2; resp += 1.3; temp += 0.75 }
            let recovery = LStat.clamp(58 + (hrv - hrvBase) * 1.5 - (rhr - rhrBase) * 2.1 + (asleep - 440) * 0.07
                                       - (priorStrain - 55) * 0.2 + rng.gauss() * 3, 6, 98)
            sleeps.append(LSleep(start: start, end: end, day: key, efficiency: efficiency, restingHR: rhr.rounded(),
                                 hrv: hrv, stages: stages))
            if wd == 7 && rng.unit() < 0.3 {
                let ns = midnight + 14.4 * 3600 + rng.range(0, 1800)
                sleeps.append(LSleep(start: ns, end: ns + rng.range(20, 34) * 60, day: key, efficiency: 88, isNap: true))
            }

            // ---- The day's training
            var planned: [(sport: String, minutes: Double, intensity: Double, startHour: Double)] = []
            let skip = rng.unit() < 0.08 || unwell
            switch wd {
            case 1: planned.append(("Conditioning", rng.range(50, 60), 0.74, 6.5))
            case 2: planned.append(("Strength", rng.range(55, 65), 0.56, 6.5))
            case 3: if rng.unit() < 0.7 { planned.append(("Running", rng.range(32, 45), 0.62, 18.2)) }
            case 4: planned.append(("HYROX", rng.range(55, 70), 0.82, 6.5))
            case 5: planned.append(("Strength", rng.range(50, 60), 0.58, 6.5))
            case 6: planned.append((i % 21 < 7 ? "HYROX" : "Running", i % 21 < 7 ? rng.range(78, 92) : rng.range(55, 75), i % 21 < 7 ? 0.88 : 0.68, 9.5))
            default: break
            }
            var dayStrain = rng.range(24, 36)
            var count = 0
            if !skip {
                for p in planned {
                    let ws = midnight + p.startHour * 3600 + rng.range(-600, 600)
                    let maxHR = 187.0
                    let avg = (rhrBase + (maxHR - rhrBase) * p.intensity + rng.gauss() * 3).rounded()
                    let peak = min(maxHR, avg + rng.range(14, 26)).rounded()
                    let strain = LStat.clamp(22 + p.intensity * 62 + (p.minutes - 55) * 0.35 + rng.gauss() * 3, 20, 95)
                    var distance: Double?
                    if p.sport == "Running" {
                        let pace = 352 - 34 * progress + (0.7 - p.intensity) * 60 + rng.gauss() * 6
                        distance = p.minutes * 60 / pace * 1000
                    } else if p.sport == "HYROX" && p.minutes > 76 {
                        distance = 8000
                    }
                    workouts.append(LWorkout(start: ws, end: ws + p.minutes * 60, sport: p.sport, source: "strap",
                                             kcal: (p.minutes * (6 + p.intensity * 9)).rounded(), avgHR: avg, maxHR: peak,
                                             strain: strain, distanceM: distance, zonePct: LumaDemoSource.zones(p.intensity, rng: &rng),
                                             editable: false))
                    dayStrain = max(dayStrain, strain + rng.range(0, 4))
                    count += 1
                }
            }
            let steps = Int(6200 + dayStrain * 78 + rng.gauss() * 900)
            days.append(LDay(day: key, sleepMin: asleep, sleepEfficiency: efficiency, deepMin: block.minutes(.deep),
                             remMin: block.minutes(.rem), lightMin: block.minutes(.light),
                             disturbances: stages.filter { $0.kind == .awake }.count, restingHR: rhr.rounded(),
                             hrv: hrv, sdnn: hrv * 1.35, recovery: recovery.rounded(), strain: dayStrain, workouts: count,
                             skinTempDev: temp, skinTemp: 33.8 + temp, respRate: resp, steps: max(1800, steps),
                             activeKcal: (260 + dayStrain * 9.5 + rng.gauss() * 40).rounded()))

            // ---- Evening check-in, which shapes tomorrow's night
            var tags: [CheckInTag] = []
            let drinks = (wd == 6 && rng.unit() < 0.55) || (wd == 5 && rng.unit() < 0.2)
            if drinks { tags.append(.alcohol) }
            if rng.unit() < 0.16 { tags.append(.lateCaffeine) }
            if rng.unit() < 0.2 { tags.append(.stretching) }
            if wd == 7 && rng.unit() < 0.4 { tags.append(.sauna) }
            if unwell { tags.append(.sick) }
            checkIns.append(CheckIn(day: key, tags: tags, energy: Int(LStat.clamp((recovery / 22).rounded(), 1, 5)),
                                    soreness: Int(LStat.clamp(((priorStrain - 20) / 16).rounded(), 1, 5))))
            alcoholLastNight = drinks
            fatigue += (dayStrain - fatigue) / 5
            priorStrain = dayStrain
        }
        self.days = days
        self.sleeps = sleeps
        self.workouts = workouts.sorted { $0.start > $1.start }
        self.checkIns = checkIns
    }

    // MARK: Generators

    static func stages(start: Double, end: Double, restless: Bool, rng: inout SeededRNG) -> [LStage] {
        var out: [LStage] = []
        var t = start
        func add(_ kind: LStageKind, _ minutes: Double) {
            guard t < end else { return }
            let e = min(end, t + minutes * 60)
            if let last = out.last, last.kind == kind { out[out.count - 1].end = e } else { out.append(LStage(start: t, end: e, kind: kind)) }
            t = e
        }
        add(.awake, rng.range(4, 13))
        var cycle = 0
        while t < end {
            let late = Double(cycle) / 4.5
            add(.light, rng.range(12, 26))
            add(.deep, max(4, rng.range(28, 44) * (1 - late * 0.75)))
            add(.light, rng.range(10, 22))
            add(.rem, rng.range(9, 15) + late * rng.range(14, 24))
            if rng.unit() < (restless ? 0.85 : 0.4) { add(.awake, restless ? rng.range(3, 11) : rng.range(1, 4)) }
            cycle += 1
        }
        return out
    }

    static func zones(_ intensity: Double, rng: inout SeededRNG) -> [Double] {
        // Centre of mass moves from zone 2 to zone 4 as intensity rises.
        let centre = 1 + intensity * 3.4
        var w = (0..<5).map { z -> Double in exp(-pow(Double(z) - centre, 2) / 1.3) * rng.range(0.85, 1.15) }
        let total = w.reduce(0, +)
        w = w.map { ($0 / total * 96).rounded() }
        return w
    }

    /// Smooth deterministic noise in −1…1 for a timestamp.
    static func noise(_ t: Double, _ salt: Double) -> Double {
        sin(t / 197 + salt) * 0.5 + sin(t / 61 + salt * 2.3) * 0.3 + sin(t / 23 + salt * 5.1) * 0.2
    }

    func bpm(at t: Double) -> Double {
        let key = LDate.key(Date(timeIntervalSince1970: t), calendar: calendar)
        let rhr = days.first { $0.day == key }?.restingHR ?? 52
        if let w = workouts.first(where: { t >= $0.start && t <= $0.end + 240 }) {
            let avg = w.avgHR ?? 140, peak = w.maxHR ?? 170
            if t > w.end { return avg - (avg - 92) * (t - w.end) / 240 }
            let f = (t - w.start) / max(1, w.end - w.start)
            let warm = min(1, f / 0.12)
            let surge: Double = sin(f * Double.pi * 7) * (peak - avg) * 0.55
            let floor: Double = rhr + 28
            let climb: Double = (avg - floor + (peak - avg) * 0.35 * f) * warm
            let value: Double = floor + climb + surge * warm + Self.noise(t, 1) * 3
            return min(peak, value)
        }
        if let s = sleeps.first(where: { t >= $0.start && t <= $0.end }) {
            let f = (t - s.start) / max(1, s.end - s.start)
            return rhr + 7 * (1 - f) * (1 - f) + 2 * sin(f * Double.pi * 9) + Self.noise(t, 2) * 1.6 - 1
        }
        let hour = (t - (LDate.startOfDay(key, calendar: calendar)?.timeIntervalSince1970 ?? t)) / 3600
        let active = 12 + 9 * sin((hour - 7) / 15 * Double.pi)
        return rhr + max(6, active) + Self.noise(t, 3) * 6 + (hour > 12.4 && hour < 13.2 ? 9 : 0)
    }

    // MARK: LumaDataSource

    public func loadDays() async -> [LDay] { days }
    public func loadSleeps(days n: Int) async -> [LSleep] { sleeps }
    public func loadWorkouts(days n: Int) async -> [LWorkout] { workouts }

    public func heartRate(from: Double, to: Double, bucketSeconds: Int) async -> [LHRPoint] {
        let now = Date().timeIntervalSince1970
        let step = Double(max(15, bucketSeconds))
        var out: [LHRPoint] = []
        var t = from
        while t < min(to, now) {
            let a = bpm(at: t), b = bpm(at: t + step / 2), c = bpm(at: t + step * 0.9)
            out.append(LHRPoint(t: t, bpm: (a + b + c) / 3, lo: min(a, b, c) - 2, hi: max(a, b, c) + 3))
            t += step
        }
        return out
    }

    public func hrvSeries(from: Double, to: Double) async -> [LPoint] {
        guard let s = sleeps.first(where: { !$0.isNap && $0.end > from && $0.start < to }), let hrv = s.hrv else { return [] }
        var out: [LPoint] = []
        var t = max(from, s.start)
        while t < min(to, s.end) {
            let f = (t - s.start) / max(1, s.end - s.start)
            out.append(LPoint(t: t, v: hrv * (0.82 + 0.3 * f) + Self.noise(t, 4) * 9))
            t += 600
        }
        return out
    }

    public func route(for workout: LWorkout) async -> [LCoord] {
        guard workout.kind == .run, let d = workout.distanceM else { return [] }
        return Self.loop(distanceM: d, salt: workout.start)
    }

    /// A closed loop of roughly `distanceM` around central Dublin's canal and squares.
    public static func loop(distanceM: Double, salt: Double) -> [LCoord] {
        let lat0 = 53.3318, lon0 = -6.2526
        let radiusM = distanceM / (2 * Double.pi) / 1.12
        let n = 220
        let phase = salt.truncatingRemainder(dividingBy: 6.28)
        return (0...n).map { i in
            let a = Double(i) / Double(n) * 2 * Double.pi
            let r = radiusM * (1 + 0.24 * sin(2 * a + phase) + 0.12 * sin(5 * a + phase * 2) + 0.05 * sin(11 * a))
            return LCoord(lat: lat0 + r * sin(a) / 111_320, lon: lon0 + r * cos(a) * 1.25 / (111_320 * cos(lat0 * Double.pi / 180)))
        }
    }

    public func stress(day: String) async -> LStressDay? {
        guard let midnight = LDate.startOfDay(day, calendar: calendar)?.timeIntervalSince1970 else { return nil }
        let nowHour = day == today ? calendar.component(.hour, from: Date()) : 23
        var hours: [LStressHour] = []
        for h in 6...22 where h <= nowHour {
            let t = midnight + Double(h) * 3600
            let training = workouts.contains { $0.start < t + 3600 && $0.end > t }
            let shape = 0.7 + 0.9 * exp(-pow(Double(h) - 11, 2) / 9) + 0.6 * exp(-pow(Double(h) - 16, 2) / 5)
            let level = training ? nil : LStat.clamp(shape + Self.noise(t, 5) * 0.5, 0.1, 2.9)
            hours.append(LStressHour(hour: h, level: level, meanHR: bpm(at: t + 1800)))
        }
        let levels = hours.compactMap { $0.level }
        return LStressDay(hours: hours, mean: LStat.mean(levels), highMinutes: levels.filter { $0 >= 2 }.count * 60)
    }

    public func heartRateRecovery(for workout: LWorkout, maxHR: Double) async -> LHRRecovery? {
        guard let avg = workout.avgHR else { return nil }
        let end = min(maxHR, avg + 8)
        return LHRRecovery(endHR: end, drop1: (22 + (maxHR - end) * 0.3).rounded(), drop2: (38 + (maxHR - end) * 0.4).rounded())
    }

    public func saveWorkout(_ workout: LWorkout, replacing old: LWorkout?) async {}
    public func deleteWorkout(_ workout: LWorkout) async {}
}

/// Demo content for the parts of Luma the athlete fills in: routine, plan, fuel, supplements, lifts.
public enum LumaDemoContent {
    public static func profile() -> LProfile {
        var p = LProfile()
        p.name = "Alex"; p.birthYear = 1992; p.heightCm = 180; p.weightKg = 78; p.maxHR = 187
        p.fiveKSeconds = 24 * 60 + 40; p.gym = "Forge Fitness"; p.shareHealthWithCoach = true
        p.setupVersion = LProfile.currentSetupVersion
        return p
    }

    public static func routine() -> [RoutineSlot] {
        [RoutineSlot(weekday: 1, kind: .gymClass, title: "Conditioning class", startMinutes: 390),
         RoutineSlot(weekday: 2, kind: .strength, title: "Strength class", startMinutes: 390),
         RoutineSlot(weekday: 4, kind: .hyrox, title: "HYROX class", startMinutes: 390, durationMin: 65),
         RoutineSlot(weekday: 5, kind: .strength, title: "Strength class", startMinutes: 390),
         RoutineSlot(weekday: 6, kind: .longRun, title: "Long run", startMinutes: 570, durationMin: 70)]
    }

    public static func planned(today: String) -> [PlannedSession] {
        let start = LDate.adding(-28, to: LDate.weekStart(today))
        var out = Schedule.materialize(routine: routine(), existing: [], from: start, days: 49)
        let wed = LDate.adding(2, to: LDate.weekStart(today))
        out.append(PlannedSession(day: wed, kind: .easyRun, title: "Easy run", detail: "40 min in zone 2. Keep it conversational.",
                                  durationMin: 40, origin: .coach, startMinutes: 1080, targetPaceSPerKm: 345))
        let sat = LDate.adding(12, to: LDate.weekStart(today))
        out.append(PlannedSession(day: sat, kind: .simulation, title: "Half simulation", detail: "4 × (1 km run + station) at race effort.",
                                  durationMin: 50, origin: .coach, startMinutes: 570))
        return out
    }

    public static func supplements() -> [SupplementPlan] {
        [SupplementPlan(dose: SupplementDose(name: "Creatine monohydrate", amount: 5, unit: "g"), timing: .morning),
         SupplementPlan(dose: SupplementDose(name: "Vitamin D3", amount: 2000, unit: "IU"), timing: .morning),
         SupplementPlan(dose: SupplementDose(name: "Omega-3", amount: 2, unit: "capsule"), timing: .morning),
         SupplementPlan(dose: SupplementDose(name: "Electrolytes", amount: 1, unit: "scoop"), timing: .preSession),
         SupplementPlan(dose: SupplementDose(name: "Magnesium glycinate", amount: 400, unit: "mg"), timing: .evening)]
    }

    public static func fuel(today: Date = Date(), calendar: Calendar = LDate.calendar) -> [FuelEntry] {
        var out: [FuelEntry] = []
        var rng = SeededRNG(seed: 77)
        let start = calendar.startOfDay(for: today)
        func at(_ dayOffset: Int, _ hour: Double) -> Date { start.addingTimeInterval(Double(dayOffset) * 86_400 + hour * 3600) }
        for offset in -20...0 {
            let scale = rng.range(0.88, 1.12)
            out.append(FuelEntry(at: at(offset, 7.6), kind: .meal, title: "Overnight oats, banana, whey", items: [
                FuelItem(name: "Rolled oats", quantity: "70 g", kcal: 265 * scale, proteinG: 9, carbsG: 46 * scale, fatG: 5),
                FuelItem(name: "Whey protein", quantity: "1 scoop", kcal: 120, proteinG: 24, carbsG: 3, fatG: 1.5),
                FuelItem(name: "Banana", quantity: "1 medium", kcal: 105, proteinG: 1, carbsG: 27, fatG: 0.3),
            ], source: .typed))
            out.append(FuelEntry(at: at(offset, 8.1), kind: .drink, title: "Flat white", items: [
                FuelItem(name: "Flat white", quantity: "1 cup", kcal: 110, proteinG: 6, carbsG: 9, fatG: 6, caffeineMg: 130)], source: .quick))
            if offset < 0 || calendar.component(.hour, from: today) >= 13 {
                out.append(FuelEntry(at: at(offset, 13.1), kind: .meal, title: "Chicken, rice and greens", items: [
                    FuelItem(name: "Grilled chicken thigh", quantity: "180 g", kcal: 330 * scale, proteinG: 42, carbsG: 0, fatG: 17),
                    FuelItem(name: "Basmati rice", quantity: "220 g cooked", kcal: 290 * scale, proteinG: 6, carbsG: 63 * scale, fatG: 1),
                    FuelItem(name: "Tenderstem broccoli", quantity: "100 g", kcal: 35, proteinG: 3, carbsG: 4, fatG: 0.4, fiberG: 3),
                ], source: .photo))
            }
            if offset < 0 {
                out.append(FuelEntry(at: at(offset, 16.4), kind: .snack, title: "Skyr and berries", items: [
                    FuelItem(name: "Skyr", quantity: "200 g", kcal: 130, proteinG: 22, carbsG: 8, fatG: 0.4),
                    FuelItem(name: "Mixed berries", quantity: "80 g", kcal: 40, proteinG: 0.6, carbsG: 9, fatG: 0.3)], source: .label))
                out.append(FuelEntry(at: at(offset, 19.7), kind: .meal, title: "Salmon, potatoes, salad", items: [
                    FuelItem(name: "Salmon fillet", quantity: "160 g", kcal: 330 * scale, proteinG: 34, carbsG: 0, fatG: 21),
                    FuelItem(name: "Baby potatoes", quantity: "300 g", kcal: 230 * scale, proteinG: 6, carbsG: 52 * scale, fatG: 0.4),
                    FuelItem(name: "Olive oil dressing", quantity: "1 tbsp", kcal: 110, proteinG: 0, carbsG: 0, fatG: 12)], source: .typed))
            }
            let waters = offset < 0 ? 5 : 3
            for w in 0..<waters {
                out.append(FuelEntry(at: at(offset, 7.5 + Double(w) * 2.8), kind: .water, title: "Water", waterMl: 500, source: .quick))
            }
            for s in supplements() where s.timing == .morning || offset < 0 {
                out.append(FuelEntry(at: at(offset, s.timing == .evening ? 21.5 : 7.7), kind: .supplement, title: s.dose.name,
                                     supplement: s.dose, source: .quick))
            }
        }
        return out
    }

    public static func lifts(today: Date = Date()) -> [LiftSession] {
        func sets(_ kg: Double, _ reps: Int, _ n: Int) -> [LiftSet] { (0..<n).map { _ in LiftSet(reps: reps, kg: kg, done: true) } }
        return (0..<8).map { i in
            let d = today.addingTimeInterval(-Double(i) * 3.5 * 86_400 - 9 * 3600)
            let gain = Double(8 - i) * 1.25
            let lower: [LiftExercise] = [
                LiftExercise(name: "Back squat", sets: sets(100 + gain, 5, 4)),
                LiftExercise(name: "Romanian deadlift", sets: sets(90 + gain, 8, 3)),
                LiftExercise(name: "Walking lunge", sets: sets(30, 12, 3)),
                LiftExercise(name: "Sled push", sets: sets(140 + gain * 2, 1, 4)),
            ]
            let upper: [LiftExercise] = [
                LiftExercise(name: "Bench press", sets: sets(75 + gain * 0.6, 5, 4)),
                LiftExercise(name: "Pull-up", sets: sets(10, 6, 4)),
                LiftExercise(name: "Push press", sets: sets(52.5 + gain * 0.5, 6, 3)),
                LiftExercise(name: "Wall ball", sets: sets(6, 25, 3)),
            ]
            let lowerDay = i % 2 == 0
            return LiftSession(start: d, end: d.addingTimeInterval(3300), title: lowerDay ? "Lower body strength" : "Upper body strength",
                               exercises: lowerDay ? lower : upper)
        }
    }
}

/// A clock that only moves when told to: for tests and for building demo race sessions.
public final class ManualClock: MonotonicClock, @unchecked Sendable {
    private var ms: Int64
    public init(startMs: Int64 = 0) { ms = startMs }
    public func nowMs() -> Int64 { ms }
    public func advance(_ seconds: Double) { ms += Int64((seconds * 1000).rounded()) }
}

public extension LumaDemoContent {
    /// Typical station times in seconds for a recreational open-division athlete, used as defaults
    /// until the athlete has benchmarks of their own.
    static func typicalStationSeconds(_ st: Station) -> Double {
        switch st {
        case .skiErg: return 262
        case .sledPush: return 198
        case .sledPull: return 244
        case .burpeeBroadJump: return 302
        case .rowing: return 271
        case .farmersCarry: return 122
        case .sandbagLunges: return 296
        case .wallBalls: return 418
        }
    }

    /// A complete race simulation with plausible splits, recorded through the real split recorder.
    static func simulation(daysAgo: Int, runPace: Double, stationFactor: Double = 1, now: Date = Date()) -> HXSession {
        let clock = ManualClock()
        let plan = RacePlanBuilder.fullRace(format: .openSingles, sex: .male)
        let started = now.addingTimeInterval(-Double(daysAgo) * 86_400 - 5 * 3600)
        var rec = SplitRecorder(session: HXSession(kind: .fullSimulation, format: .openSingles, sex: .male, startedAt: started), plan: plan, clock: clock)
        var rng = SeededRNG(seed: UInt64(daysAgo) &+ 41)
        rec.start()
        var run = 0
        for p in plan {
            let seconds: Double
            let hr: Double
            switch p.kind {
            case .run:
                run += 1
                seconds = runPace * (1 + 0.014 * Double(run)) + rng.gauss() * 4
                hr = 158 + Double(run) * 1.6
            case .roxzone:
                seconds = rng.range(27, 44)
                hr = 160
            case .station:
                seconds = (p.station.map(typicalStationSeconds) ?? 240) * stationFactor * rng.range(0.95, 1.08)
                hr = 166 + rng.range(0, 8)
            default:
                seconds = 60
                hr = 120
            }
            clock.advance(seconds)
            rec.advance(hr: HRSummary(avg: hr, max: hr + 7, min: hr - 14, sampleCount: Int(seconds), expectedCount: Int(seconds), source: .wristOptical))
        }
        var s = rec.session
        s.endedAt = started.addingTimeInterval(s.totalS ?? 0)
        return s
    }
}
