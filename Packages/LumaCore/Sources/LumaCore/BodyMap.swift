import Foundation

// MARK: - Body map

/// A point in the figure's own units: a box `BodyMap.width` wide and `BodyMap.height` tall.
public struct BodyPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// One cubic segment of an outline.
public struct BodyCurve: Equatable, Sendable {
    public let control1: BodyPoint
    public let control2: BodyPoint
    public let end: BodyPoint
}

public enum BodySide: String, CaseIterable, Sendable {
    case front, back
    public var title: String { self == .front ? "Front" : "Back" }
}

/// A part of the figure: a muscle group's area on one side of the body, as closed outlines.
public struct BodyRegion: Sendable {
    public let muscle: Muscle
    /// One outline for each place the muscle shows; left and right are separate outlines.
    public let outlines: [[BodyPoint]]
}

/// Luma's own figure: a stylised body, front and back, with an area for each muscle group. Every
/// outline is a closed smooth curve through its points. Only the right half is written down; the left
/// is its mirror image.
public enum BodyMap {
    public static let width: Double = 200
    public static let height: Double = 434
    private static let centre = width / 2

    private static func points(_ flat: [Double]) -> [BodyPoint] {
        stride(from: 0, to: flat.count - 1, by: 2).map { BodyPoint(x: flat[$0], y: flat[$0 + 1]) }
    }

    private static func mirrored(_ outline: [BodyPoint]) -> [BodyPoint] {
        outline.map { BodyPoint(x: 2 * centre - $0.x, y: $0.y) }
    }

    /// A part that straddles the centre line, from the half written down: the top centre point round
    /// to the bottom centre point, then back up the other side.
    private static func whole(_ half: [BodyPoint]) -> [BodyPoint] {
        half + Array(mirrored(Array(half.dropFirst().dropLast())).reversed())
    }

    private static func region(_ muscle: Muscle, _ flat: [Double]) -> BodyRegion {
        let right = points(flat)
        return BodyRegion(muscle: muscle, outlines: [right, mirrored(right)])
    }

    /// The body itself, under the muscle areas: head and trunk, then an arm and a leg on each side.
    public static let silhouette: [[BodyPoint]] = {
        let arm = points(armData)
        let leg = points(legData)
        return [whole(points(headData)), whole(points(trunkData)), arm, mirrored(arm), leg, mirrored(leg)]
    }()

    private static let headData: [Double] = [
        100, 7, 108, 8.5, 114.5, 15, 116.5, 26, 115.5, 37, 111, 46, 105, 51.5, 100, 53,
    ]

    private static let trunkData: [Double] = [
        100, 44, 108.5, 46, 110, 57, 123, 64.5, 138, 69.5, 143, 82, 139.5, 100, 136, 120,
        131, 145, 127.5, 165, 129.5, 183, 134, 196, 138, 210, 140.5, 222, 124, 231, 100, 229,
    ]

    private static let armData: [Double] = [
        139, 69, 150, 71.5, 158.5, 81, 161, 97, 161, 120, 163.5, 148, 167, 165, 172, 186,
        175, 210, 176, 232, 179, 247, 178, 261, 172, 268.5, 166, 262.5, 164.5, 247, 163.5, 232,
        158.5, 205, 153.5, 181, 151, 165, 147.5, 140, 144.5, 116, 140, 101, 136, 84,
    ]

    private static let legData: [Double] = [
        131, 197, 138, 210, 141.5, 226, 143, 248, 140, 285, 134, 311, 135.5, 326, 139.5, 346,
        137, 371, 128.5, 399, 129.5, 410, 136.5, 420.5, 133, 427, 118.5, 427, 113, 421, 117, 409,
        118.5, 399, 114, 372, 112.5, 348, 114.5, 327, 116, 311, 111.5, 285, 105.5, 250, 101.5, 230,
        108, 205,
    ]

    private static let front: [BodyRegion] = [
        region(.traps, [
            111.5, 59.5, 123.5, 66.5, 136, 70.5, 127, 73, 117, 72.5, 111, 68,
        ]),
        region(.shoulders, [
            140.5, 72, 150, 73.5, 157, 82.5, 159.5, 97, 157.5, 107, 152, 103.5, 145, 96, 139.5, 84,
        ]),
        region(.chest, [
            101.2, 77, 117, 74.5, 133, 76.5, 137.5, 86, 138, 98, 130.5, 109, 116, 113, 101.2, 110.5,
        ]),
        region(.biceps, [
            148, 110.5, 153.5, 108.5, 158.5, 113.5, 159.5, 130, 161.8, 150, 159, 160.5, 153, 161.5, 149.5, 150,
            146.8, 130,
        ]),
        region(.forearms, [
            153.5, 169, 160.5, 167, 166.5, 172, 170.3, 186, 173.3, 210, 174, 229, 166, 230, 160.5, 206,
            155.5, 184,
        ]),
        region(.abs, [
            101.2, 116.5, 112, 116, 116.5, 119.5, 116.5, 131, 112, 133.5, 101.2, 133.5,
        ]),
        region(.abs, [
            101.2, 136.5, 112, 136.5, 116.5, 139, 116.5, 151, 112, 153.5, 101.2, 153.5,
        ]),
        region(.abs, [
            101.2, 156.5, 112, 156.5, 116, 159, 115.5, 171, 111.5, 173.5, 101.2, 173.5,
        ]),
        region(.abs, [
            101.2, 176.5, 111, 176.5, 114.5, 180, 112.5, 194, 107, 204, 101.2, 208,
        ]),
        region(.obliques, [
            119.5, 119, 130, 114.5, 134.5, 124, 129.5, 146, 126, 166, 128, 184, 132.5, 197, 136, 208,
            124, 212, 112.5, 209, 117.5, 184, 119, 152,
        ]),
        region(.quads, [
            118, 224, 131, 218, 139.8, 229, 141.5, 250, 138.5, 284, 132.5, 303.5, 124.5, 307, 118, 302.5,
            114, 285, 111.5, 262, 112.5, 240,
        ]),
        region(.adductors, [
            103.8, 233, 109.5, 227.5, 110, 245, 109.2, 262, 111.2, 281, 107.5, 262, 105, 247,
        ]),
        region(.calves, [
            118, 329, 131.5, 327, 137.8, 346, 135.3, 371, 127.5, 395, 121, 395, 115.7, 372, 114.2, 348,
        ]),
    ]

    private static let back: [BodyRegion] = [
        region(.traps, [
            101.2, 48.5, 108.5, 51.5, 111.5, 60, 125, 66.5, 137, 71, 128, 78.5, 118.5, 90, 110.5, 108,
            101.2, 128,
        ]),
        region(.shoulders, [
            140.5, 72, 150, 73.5, 157, 82.5, 159.5, 97, 157.5, 107, 152, 103.5, 145, 96, 139.5, 84,
        ]),
        region(.upperBack, [
            120.5, 94, 129.5, 81.5, 136.5, 85, 138, 98, 132, 109, 120.5, 113, 113.5, 111,
        ]),
        region(.lats, [
            113.5, 116, 123, 117, 135, 112.5, 134.5, 122, 130, 145, 126, 166, 120, 181, 115.5, 186,
            114.8, 172, 112.8, 152, 107.5, 137, 104.5, 131,
        ]),
        region(.lowerBack, [
            101.2, 140, 106.5, 141.5, 110.5, 154, 112.5, 176, 114, 190, 110, 199.5, 101.2, 202,
        ]),
        region(.obliques, [
            118, 190, 126, 172.5, 128.5, 186, 132, 199, 122, 203.5, 115, 201.5,
        ]),
        region(.triceps, [
            148, 110.5, 153.5, 108.5, 158.5, 113.5, 159.5, 130, 161.8, 150, 159, 160.5, 153, 161.5, 149.5, 150,
            146.8, 130,
        ]),
        region(.forearms, [
            153.5, 169, 160.5, 167, 166.5, 172, 170.3, 186, 173.3, 210, 174, 229, 166, 230, 160.5, 206,
            155.5, 184,
        ]),
        region(.glutes, [
            101.2, 206, 114, 203, 129, 204.5, 136.5, 211.5, 139.8, 224, 138, 235.5, 128.5, 243.5, 114, 245.5,
            103.5, 240.5, 101.2, 228,
        ]),
        region(.hamstrings, [
            107.5, 248, 115, 251, 128, 249, 141, 242, 141.5, 256, 138.5, 284, 133, 304.5, 118.5, 305.5,
            113.5, 285, 108.5, 263,
        ]),
        region(.calves, [
            116.5, 324, 126, 321, 134.5, 324, 138, 344, 135.5, 368, 129, 386, 122, 386, 115.8, 368,
            114, 346,
        ]),
    ]

    public static func regions(_ side: BodySide) -> [BodyRegion] { side == .front ? front : back }

    /// The muscle groups that show on a side.
    public static func muscles(on side: BodySide) -> [Muscle] {
        var seen: [Muscle] = []
        for r in regions(side) where !seen.contains(r.muscle) { seen.append(r.muscle) }
        return seen
    }

    /// The smooth closed curve through an outline's points: where it starts, then one cubic segment
    /// to each next point and a last one back to the start.
    public static func curve(_ outline: [BodyPoint]) -> (start: BodyPoint, segments: [BodyCurve]) {
        let n = outline.count
        guard n >= 3 else { return (outline.first ?? BodyPoint(x: 0, y: 0), []) }
        var segments: [BodyCurve] = []
        for i in 0..<n {
            let before = outline[(i + n - 1) % n]
            let from = outline[i]
            let to = outline[(i + 1) % n]
            let after = outline[(i + 2) % n]
            let c1 = BodyPoint(x: from.x + (to.x - before.x) / 6, y: from.y + (to.y - before.y) / 6)
            let c2 = BodyPoint(x: to.x - (after.x - from.x) / 6, y: to.y - (after.y - from.y) / 6)
            segments.append(BodyCurve(control1: c1, control2: c2, end: to))
        }
        return (outline[0], segments)
    }
}
