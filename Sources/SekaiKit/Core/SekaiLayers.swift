import Foundation

public struct SekaiAnnotation: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var coordinate: SekaiCoordinate
    public var title: String?
    public var subtitle: String?
    public var style: SekaiAnnotationStyle?
    public var priority: Double
    public var clusterGroup: String?
    public var isDraggable: Bool

    public init(
        id: String,
        coordinate: SekaiCoordinate,
        title: String? = nil,
        subtitle: String? = nil,
        style: SekaiAnnotationStyle? = nil,
        priority: Double = 0,
        clusterGroup: String? = nil,
        isDraggable: Bool = false
    ) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.priority = priority
        self.clusterGroup = clusterGroup
        self.isDraggable = isDraggable
    }
}

public struct SekaiRoute: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var from: SekaiCoordinate
    public var to: SekaiCoordinate
    public var curve: SekaiRouteCurve
    public var style: SekaiRouteStyle?
    public var title: String?

    public init(
        id: String,
        from: SekaiCoordinate,
        to: SekaiCoordinate,
        curve: SekaiRouteCurve = .greatCircle,
        style: SekaiRouteStyle? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.curve = curve
        self.style = style
        self.title = title
    }
}

public struct SekaiPolyline: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var coordinates: [SekaiCoordinate]
    public var style: SekaiRouteStyle

    public init(id: String, coordinates: [SekaiCoordinate], style: SekaiRouteStyle = .standard) {
        self.id = id
        self.coordinates = coordinates
        self.style = style
    }
}

public struct SekaiPolygon: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var rings: [[SekaiCoordinate]]
    public var style: SekaiBoundaryStyle

    public init(id: String, rings: [[SekaiCoordinate]], style: SekaiBoundaryStyle = .standard) {
        self.id = id
        self.rings = rings
        self.style = style
    }
}

public struct SekaiCircle: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var center: SekaiCoordinate
    public var radiusKilometers: Double
    public var style: SekaiBoundaryStyle

    public init(
        id: String,
        center: SekaiCoordinate,
        radiusKilometers: Double,
        style: SekaiBoundaryStyle = .standard
    ) {
        self.id = id
        self.center = center
        self.radiusKilometers = max(0, radiusKilometers)
        self.style = style
    }
}

public struct SekaiHeatPoint: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var coordinate: SekaiCoordinate
    public var weight: Double

    public init(id: String, coordinate: SekaiCoordinate, weight: Double = 1) {
        self.id = id
        self.coordinate = coordinate
        self.weight = weight
    }
}

public enum SekaiPhysicalFeature: String, Codable, CaseIterable, Sendable {
    case coastlines
    case lakes
    case rivers
    case subdivisions
    case cities
    case disputedBoundaries
}

public enum SekaiLayer: Codable, Identifiable, Equatable, Sendable {
    case particles(id: String, filter: SekaiRegionFilter, style: SekaiParticleStyle?)
    case boundaries(id: String, filter: SekaiRegionFilter, style: SekaiBoundaryStyle?)
    case physical(id: String, features: Set<SekaiPhysicalFeature>)
    case annotations(id: String, values: [SekaiAnnotation])
    case routes(id: String, values: [SekaiRoute])
    case polylines(id: String, values: [SekaiPolyline])
    case polygons(id: String, values: [SekaiPolygon])
    case circles(id: String, values: [SekaiCircle])
    case heatmap(id: String, values: [SekaiHeatPoint])
    case labels(id: String, filter: SekaiRegionFilter, style: SekaiLabelStyle?)
    case texture(id: String, resourceName: String, opacity: Double)
    case userLocation(id: String, annotation: SekaiAnnotation)

    public var id: String {
        switch self {
        case let .particles(id, _, _), let .boundaries(id, _, _), let .physical(id, _),
            let .annotations(id, _), let .routes(id, _), let .polylines(id, _),
            let .polygons(id, _), let .circles(id, _), let .heatmap(id, _),
            let .labels(id, _, _), let .texture(id, _, _), let .userLocation(id, _):
            id
        }
    }
}

public protocol SekaiMapContent: Sendable {
    var sekaiLayers: [SekaiLayer] { get }
}

extension SekaiLayer: SekaiMapContent {
    public var sekaiLayers: [SekaiLayer] { [self] }
}

public struct SekaiLayerGroup: SekaiMapContent {
    public var sekaiLayers: [SekaiLayer]
    public init(_ layers: [SekaiLayer]) { sekaiLayers = layers }
}

@resultBuilder
public enum SekaiContentBuilder {
    public static func buildExpression<C: SekaiMapContent>(_ expression: C) -> [SekaiLayer] {
        expression.sekaiLayers
    }

    public static func buildBlock(_ components: [SekaiLayer]...) -> [SekaiLayer] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [SekaiLayer]?) -> [SekaiLayer] {
        component ?? []
    }

    public static func buildEither(first component: [SekaiLayer]) -> [SekaiLayer] { component }
    public static func buildEither(second component: [SekaiLayer]) -> [SekaiLayer] { component }
    public static func buildArray(_ components: [[SekaiLayer]]) -> [SekaiLayer] {
        components.flatMap { $0 }
    }
}

public extension SekaiLayer {
    static func landParticles(
        id: String = "sekai.land.particles",
        filter: SekaiRegionFilter = .allLand,
        style: SekaiParticleStyle? = nil
    ) -> Self {
        .particles(id: id, filter: filter, style: style)
    }

    static func regionBoundaries(
        id: String = "sekai.regions.boundaries",
        filter: SekaiRegionFilter = .allLand,
        style: SekaiBoundaryStyle? = nil
    ) -> Self {
        .boundaries(id: id, filter: filter, style: style)
    }
}
