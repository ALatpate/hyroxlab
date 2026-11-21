import Foundation

// MARK: - A route as a GPX file

/// One point of a route as it is written to a file.
public struct GPXPoint: Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    /// Seconds since the session started.
    public var tS: Double
    public var altitudeM: Double?
    public var hr: Double?

    public init(lat: Double, lon: Double, tS: Double, altitudeM: Double? = nil, hr: Double? = nil) {
        self.lat = lat; self.lon = lon; self.tS = tS; self.altitudeM = altitudeM; self.hr = hr
    }
}

/// Writes a recorded route as GPX 1.1, the file other running and mapping apps open. Heart rate goes
/// in the track-point extension those apps read.
public enum GPX {
    /// The points of a run that have a position.
    public static func points(from samples: [RunSample]) -> [GPXPoint] {
        samples.compactMap { s in
            guard let lat = s.lat, let lon = s.lon, valid(lat: lat, lon: lon) else { return nil }
            return GPXPoint(lat: lat, lon: lon, tS: s.tS, altitudeM: s.altitudeM, hr: s.hr)
        }
    }

    public static func valid(lat: Double, lon: Double) -> Bool {
        lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180 && !(lat == 0 && lon == 0)
    }

    /// The file's text, or nil when there are fewer than two points to draw a line between.
    public static func document(name: String, startedAt: Date, points: [GPXPoint]) -> String? {
        let usable = points.filter { valid(lat: $0.lat, lon: $0.lon) }
        guard usable.count >= 2 else { return nil }
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime]
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<gpx version=\"1.1\" creator=\"Luma\" xmlns=\"http://www.topografix.com/GPX/1/1\""
        out += " xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\">\n"
        out += "  <metadata><time>\(stamp.string(from: startedAt))</time></metadata>\n"
        out += "  <trk>\n    <name>\(escaped(name))</name>\n    <type>running</type>\n    <trkseg>\n"
        for p in usable {
            out += "      <trkpt lat=\"\(String(format: "%.6f", p.lat))\" lon=\"\(String(format: "%.6f", p.lon))\">"
            if let alt = p.altitudeM, alt.isFinite { out += "<ele>\(String(format: "%.1f", alt))</ele>" }
            out += "<time>\(stamp.string(from: startedAt.addingTimeInterval(max(0, p.tS))))</time>"
            if let hr = p.hr, hr.isFinite, hr > 0 {
                out += "<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>\(LNum.int(hr.rounded()))</gpxtpx:hr>"
                out += "</gpxtpx:TrackPointExtension></extensions>"
            }
            out += "</trkpt>\n"
        }
        out += "    </trkseg>\n  </trk>\n</gpx>\n"
        return out
    }

    /// A file name that says what and when: "Luma Outdoor run 2026-11-21.gpx".
    public static func fileName(name: String, day: String) -> String {
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : " " }
        let tidy = String(safe).split(separator: " ").joined(separator: " ")
        return "Luma \(tidy.isEmpty ? "run" : tidy) \(day).gpx"
    }

    static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
