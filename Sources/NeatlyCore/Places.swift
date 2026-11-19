import Foundation
import ImageIO
import CoreLocation

/// Where a photo was taken: the phone writes GPS into the photo, Apple's map service turns it into a place
/// ("Galata Tower", "Istanbul"). This is the one lookup that sends something about a file: its coordinates, to Apple.
/// So it runs only when online lookups are on (the same switch as the paper lookup, and never with --offline).
enum Places {
    /// The photo's GPS position, if it has one.
    static func coordinate(_ url: URL) -> CLLocationCoordinate2D? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let g = p[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var lat = (g[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
              var lon = (g[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue else { return nil }
        if (g[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (g[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        guard (-90...90).contains(lat), (-180...180).contains(lon), !(lat == 0 && lon == 0) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// A short, human place: a landmark if the photo was taken right at one, else the town or city, else the region.
    /// "landmark" is only filled when Apple names a point of interest there.
    struct Place: Sendable { var landmark: String?; var city: String?; var region: String?; var country: String?
        /// A landmark only if it's short ("Galata Tower", "Big Ben"); "Parc naturel régional du Verdon" gives way to the town.
        var best: String? { (landmark.flatMap { $0.split(separator: " ").count <= 3 ? $0 : nil }) ?? city ?? region ?? country }
        var description: String { [landmark, city, country].compactMap { $0 }.joined(separator: ", ") }
    }

    nonisolated(unsafe) private static var cache: [String: Place] = [:]
    private static let lock = NSLock()

    static func place(at c: CLLocationCoordinate2D) async -> Place? {
        let key = String(format: "%.3f,%.3f", c.latitude, c.longitude)   // ~100 m: photos from one spot ask once
        if let hit = lock.withLock({ cache[key] }) { return hit }
        guard let marks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude),
                                                                          preferredLocale: Locale(identifier: "en_US")),
              let m = marks.first else { return nil }
        // In Türkiye a city is a province: Apple calls Istanbul's districts (Fatih, Kadıköy) the "locality".
        let provinceIsCity = ["TR"].contains(m.isoCountryCode ?? "")
        // "Banff National Park" → "Banff": short enough for a name, still says where.
        let landmark = m.areasOfInterest?.first.map { $0.replacingOccurrences(of: " National Park", with: "") }
        let p = Place(landmark: landmark, city: provinceIsCity ? (m.administrativeArea ?? m.locality) : (m.locality ?? m.subAdministrativeArea),
                      region: m.administrativeArea, country: m.country)
        lock.withLock { cache[key] = p }
        return p
    }
}
