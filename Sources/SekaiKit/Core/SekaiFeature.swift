import Foundation

/// A stable identifier from Sekai's atlas or a host-defined layer.
public struct SekaiFeatureID: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
}

public enum SekaiFeatureKind: String, Codable, CaseIterable, Sendable {
    case continent
    case sovereign
    case country
    case territory
    case dependency
    case disputed
    case subdivision
    case city
    case lake
    case river
    case custom
}

/// A discoverable atlas feature with hierarchy, localization, and geometry metadata.
public struct SekaiFeature: Codable, Identifiable, Equatable, Sendable {
    public var id: SekaiFeatureID
    public var name: String
    public var longName: String
    public var kind: SekaiFeatureKind
    public var continent: String
    public var region: String
    public var subregion: String
    public var sovereignID: SekaiFeatureID?
    public var countryID: SekaiFeatureID?
    public var isoA2: String?
    public var isoA3: String?
    public var labelCoordinate: SekaiCoordinate
    public var bounds: SekaiCoordinateBounds
    public var minimumZoom: Double
    public var particleCount: Int
    public var localizedNames: [String: String]
    public var worldviewClassifications: [String: String]

    public init(
        id: SekaiFeatureID,
        name: String,
        longName: String? = nil,
        kind: SekaiFeatureKind,
        continent: String = "",
        region: String = "",
        subregion: String = "",
        sovereignID: SekaiFeatureID? = nil,
        countryID: SekaiFeatureID? = nil,
        isoA2: String? = nil,
        isoA3: String? = nil,
        labelCoordinate: SekaiCoordinate,
        bounds: SekaiCoordinateBounds,
        minimumZoom: Double = 0,
        particleCount: Int = 0,
        localizedNames: [String: String] = [:],
        worldviewClassifications: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.longName = longName ?? name
        self.kind = kind
        self.continent = continent
        self.region = region
        self.subregion = subregion
        self.sovereignID = sovereignID
        self.countryID = countryID
        self.isoA2 = isoA2
        self.isoA3 = isoA3
        self.labelCoordinate = labelCoordinate
        self.bounds = bounds
        self.minimumZoom = minimumZoom
        self.particleCount = particleCount
        self.localizedNames = localizedNames
        self.worldviewClassifications = worldviewClassifications
    }

    public func localizedName(locale: Locale = .current) -> String {
        let language = locale.language.languageCode?.identifier.lowercased() ?? "en"
        return localizedNames[language] ?? name
    }
}

/// Political point-of-view metadata bundled by Natural Earth.
public struct SekaiWorldview: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue.lowercased() }
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public static let international = Self(rawValue: "iso")
    public static let unitedStates = Self(rawValue: "us")
    public static let china = Self(rawValue: "cn")
    public static let india = Self(rawValue: "in")
}

/// A structured atlas filter used by particles, boundaries, labels, and hit testing.
public enum SekaiRegionFilter: Codable, Hashable, Sendable {
    case allLand
    case continent(String)
    case sovereign(SekaiFeatureID)
    case country(SekaiFeatureID)
    case mapUnit(SekaiFeatureID)
    case features(Set<SekaiFeatureID>)
}

public enum SekaiSelection: Codable, Hashable, Sendable {
    case atlas(SekaiFeatureID)
    case annotation(String)
    case route(String)
    case custom(layerID: String, featureID: String)
}

public enum SekaiDiagnosticSeverity: String, Codable, Sendable {
    case information
    case warning
    case error
}

public struct SekaiDiagnostic: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var severity: SekaiDiagnosticSeverity
    public var message: String

    public init(id: String, severity: SekaiDiagnosticSeverity, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}
