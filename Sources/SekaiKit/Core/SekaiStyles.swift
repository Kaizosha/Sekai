import Foundation

public struct SekaiColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = Self(red: 0, green: 0, blue: 0)
    public static let white = Self(red: 1, green: 1, blue: 1)
    public static let red = Self(red: 1, green: 0.18, blue: 0.16)
    public static let cyan = Self(red: 0.2, green: 0.82, blue: 1)
    public static let magenta = Self(red: 1, green: 0.35, blue: 0.9)

    func normalized() -> Self {
        Self(
            red: min(max(red.isFinite ? red : 0, 0), 1),
            green: min(max(green.isFinite ? green : 0, 0), 1),
            blue: min(max(blue.isFinite ? blue : 0, 0), 1),
            alpha: min(max(alpha.isFinite ? alpha : 1, 0), 1)
        )
    }
}

public enum SekaiGlassMaterial: String, Codable, CaseIterable, Sendable {
    case regular
    case clear
}

public enum SekaiAdaptiveColor: Codable, Equatable, Sendable {
    case fixed(SekaiColor)
    case appearance(light: SekaiColor, dark: SekaiColor)

    public static let mapDefault = Self.appearance(light: .black, dark: .white)
}

public struct SekaiGlobeStyle: Codable, Equatable, Sendable {
    public var material: SekaiGlassMaterial
    public var surfaceColor: SekaiColor
    public var opacity: Double
    public var lighting: Double
    public var darkness: Double
    public var rimWidth: Double
    public var rimOpacity: Double
    public var glowColor: SekaiColor
    public var glowIntensity: Double

    public init(
        material: SekaiGlassMaterial = .clear,
        surfaceColor: SekaiColor = .init(red: 1, green: 1, blue: 1, alpha: 0.18),
        opacity: Double = 1,
        lighting: Double = 1,
        darkness: Double = 0,
        rimWidth: Double = 1,
        rimOpacity: Double = 0.34,
        glowColor: SekaiColor = .white,
        glowIntensity: Double = 0.25
    ) {
        self.material = material
        self.surfaceColor = surfaceColor
        self.opacity = opacity
        self.lighting = lighting
        self.darkness = darkness
        self.rimWidth = rimWidth
        self.rimOpacity = rimOpacity
        self.glowColor = glowColor
        self.glowIntensity = glowIntensity
    }

    public static let standard = Self()
}

public enum SekaiParticleDensity: Codable, Equatable, Hashable, Sendable {
    case automatic
    case fraction(Double)
    case count(Int)
    case maximum
}

public struct SekaiParticleStyle: Codable, Equatable, Sendable {
    public var color: SekaiAdaptiveColor
    public var density: SekaiParticleDensity
    public var size: Double
    public var opacity: Double
    public var brightness: Double
    public var highlight: Double
    public var refraction: Double
    public var depthFade: Double
    public var minimumPixelDiameter: Double

    public init(
        color: SekaiAdaptiveColor = .mapDefault,
        density: SekaiParticleDensity = .automatic,
        size: Double = 0.72,
        opacity: Double = 1,
        brightness: Double = 1,
        highlight: Double = 0.7,
        refraction: Double = 0.55,
        depthFade: Double = 0.28,
        minimumPixelDiameter: Double = 1
    ) {
        self.color = color
        self.density = density
        self.size = size
        self.opacity = opacity
        self.brightness = brightness
        self.highlight = highlight
        self.refraction = refraction
        self.depthFade = depthFade
        self.minimumPixelDiameter = minimumPixelDiameter
    }

    public static let standard = Self()
}

public struct SekaiBoundaryStyle: Codable, Equatable, Sendable {
    public var fillColor: SekaiAdaptiveColor
    public var fillOpacity: Double
    public var strokeColor: SekaiAdaptiveColor
    public var strokeOpacity: Double
    public var strokeWidth: Double
    public var highlight: Double
    public var refraction: Double

    public init(
        fillColor: SekaiAdaptiveColor = .mapDefault,
        fillOpacity: Double = 0.26,
        strokeColor: SekaiAdaptiveColor = .mapDefault,
        strokeOpacity: Double = 0.82,
        strokeWidth: Double = 0.65,
        highlight: Double = 0.65,
        refraction: Double = 0.5
    ) {
        self.fillColor = fillColor
        self.fillOpacity = fillOpacity
        self.strokeColor = strokeColor
        self.strokeOpacity = strokeOpacity
        self.strokeWidth = strokeWidth
        self.highlight = highlight
        self.refraction = refraction
    }

    public static let standard = Self()
}

public struct SekaiAnnotationStyle: Codable, Equatable, Sendable {
    public var color: SekaiColor
    public var size: Double
    public var elevation: Double
    public var opacity: Double
    public var halo: Double
    public var core: Double
    public var highlight: Double

    public init(
        color: SekaiColor = .red,
        size: Double = 1,
        elevation: Double = 0.025,
        opacity: Double = 1,
        halo: Double = 0.24,
        core: Double = 0.45,
        highlight: Double = 0.8
    ) {
        self.color = color
        self.size = size
        self.elevation = elevation
        self.opacity = opacity
        self.halo = halo
        self.core = core
        self.highlight = highlight
    }

    public static let standard = Self()
}

public enum SekaiRouteCurve: Codable, Equatable, Sendable {
    case greatCircle
    case rhumb
    case custom([SekaiCoordinate])
}

public enum SekaiLinePattern: Codable, Equatable, Sendable {
    case solid
    case dashed(length: Double, gap: Double)
}

public struct SekaiRouteStyle: Codable, Equatable, Sendable {
    public var color: SekaiColor
    public var width: Double
    public var elevation: Double
    public var opacity: Double
    public var highlight: Double
    public var pattern: SekaiLinePattern
    public var progress: Double
    public var endpointSize: Double

    public init(
        color: SekaiColor = .magenta,
        width: Double = 1,
        elevation: Double = 0.12,
        opacity: Double = 0.9,
        highlight: Double = 0.75,
        pattern: SekaiLinePattern = .solid,
        progress: Double = 1,
        endpointSize: Double = 0.05
    ) {
        self.color = color
        self.width = width
        self.elevation = elevation
        self.opacity = opacity
        self.highlight = highlight
        self.pattern = pattern
        self.progress = progress
        self.endpointSize = endpointSize
    }

    public static let standard = Self()
}

public struct SekaiLabelStyle: Codable, Equatable, Sendable {
    public var color: SekaiAdaptiveColor
    public var minimumZoom: Double
    public var maximumCount: Int
    public var collisionPadding: Double

    public init(
        color: SekaiAdaptiveColor = .mapDefault,
        minimumZoom: Double = 1,
        maximumCount: Int = 80,
        collisionPadding: Double = 4
    ) {
        self.color = color
        self.minimumZoom = minimumZoom
        self.maximumCount = maximumCount
        self.collisionPadding = collisionPadding
    }
}

public struct SekaiEnvironmentStyle: Codable, Equatable, Sendable {
    public var backgroundColor: SekaiColor
    public var showsStars: Bool
    public var starDensity: Double
    public var atmosphereColor: SekaiColor
    public var atmosphereIntensity: Double
    public var atmosphereThickness: Double
    public var sunLatitude: Double
    public var sunLongitude: Double
    public var ambientLight: Double
    public var showsDayNightTerminator: Bool

    public init(
        backgroundColor: SekaiColor = .init(red: 0, green: 0, blue: 0, alpha: 0),
        showsStars: Bool = false,
        starDensity: Double = 0.35,
        atmosphereColor: SekaiColor = .cyan,
        atmosphereIntensity: Double = 0,
        atmosphereThickness: Double = 0.04,
        sunLatitude: Double = 28,
        sunLongitude: Double = -35,
        ambientLight: Double = 0.7,
        showsDayNightTerminator: Bool = false
    ) {
        self.backgroundColor = backgroundColor
        self.showsStars = showsStars
        self.starDensity = starDensity
        self.atmosphereColor = atmosphereColor
        self.atmosphereIntensity = atmosphereIntensity
        self.atmosphereThickness = atmosphereThickness
        self.sunLatitude = sunLatitude
        self.sunLongitude = sunLongitude
        self.ambientLight = ambientLight
        self.showsDayNightTerminator = showsDayNightTerminator
    }

    public static let standard = Self()
}

public struct SekaiStyle: Codable, Equatable, Sendable {
    public var globe: SekaiGlobeStyle
    public var particles: SekaiParticleStyle
    public var boundaries: SekaiBoundaryStyle
    public var annotations: SekaiAnnotationStyle
    public var routes: SekaiRouteStyle
    public var labels: SekaiLabelStyle
    public var environment: SekaiEnvironmentStyle

    public init(
        globe: SekaiGlobeStyle = .standard,
        particles: SekaiParticleStyle = .standard,
        boundaries: SekaiBoundaryStyle = .standard,
        annotations: SekaiAnnotationStyle = .standard,
        routes: SekaiRouteStyle = .standard,
        labels: SekaiLabelStyle = .init(),
        environment: SekaiEnvironmentStyle = .standard
    ) {
        self.globe = globe
        self.particles = particles
        self.boundaries = boundaries
        self.annotations = annotations
        self.routes = routes
        self.labels = labels
        self.environment = environment
    }

    public static let standard = Self()
}
