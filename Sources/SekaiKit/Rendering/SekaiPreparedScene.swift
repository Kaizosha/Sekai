import CoreGraphics
import Foundation

struct SekaiPreparedParticleBatch: Sendable {
    let layerID: String
    let vertices: [PackedParticle]
    let styleOverride: SekaiParticleStyle?
}

struct SekaiPreparedSurfaceBatch: Sendable {
    let layerID: String
    let fillVerticesByLevelOfDetail: [[PackedParticle]]
    let lineVerticesByLevelOfDetail: [[PackedParticle]]
    let styleOverride: SekaiBoundaryStyle?
}

struct SekaiPreparedLineBatch: Sendable {
    let id: String
    let vertices: [PackedParticle]
    let styleOverride: SekaiRouteStyle?
}

enum SekaiPreparedPointMaterial: Equatable, Sendable {
    case annotation(SekaiAnnotationStyle?)
    case routeEndpoint(SekaiRouteStyle?)
    case heat(weight: Double)
}

struct SekaiPreparedPointBatch: Sendable {
    let id: String
    var vertices: [PackedParticle]
    let material: SekaiPreparedPointMaterial
}

struct SekaiPreparedLabel: Identifiable, Sendable {
    let id: String
    let layerID: String
    let text: String
    let coordinate: SekaiCoordinate
    let priority: Double
    let styleOverride: SekaiLabelStyle?
    let selection: SekaiSelection
}

enum SekaiPreparedDrawReference: Sendable {
    case particles(Int)
    case surface(Int)
    case line(Int)
    case points(Int)
}

private enum SekaiPickGeometry: Sendable {
    case point(SekaiCoordinate, radius: Double)
    case line([SekaiCoordinate], radius: Double)
    case polygon([[SekaiCoordinate]])
}

private struct SekaiPickTarget: Sendable {
    let selection: SekaiSelection
    let geometry: SekaiPickGeometry
    let priority: Double
}

struct SekaiPickResult: Sendable {
    let selection: SekaiSelection
    let coordinate: SekaiCoordinate
}

struct SekaiLayerVisualStyles {
    var particles: [String: SekaiParticleStyle] = [:]
    var boundaries: [String: SekaiBoundaryStyle] = [:]
    var labels: [String: SekaiLabelStyle] = [:]

    init(layers: [SekaiLayer]) {
        for layer in layers {
            switch layer {
            case let .particles(id, _, style?): particles[id] = style
            case let .boundaries(id, _, style?): boundaries[id] = style
            case let .labels(id, _, style?): labels[id] = style
            default: break
            }
        }
    }
}

final class SekaiPreparedScene: @unchecked Sendable {
    let particleBatches: [SekaiPreparedParticleBatch]
    let surfaceBatches: [SekaiPreparedSurfaceBatch]
    let lineBatches: [SekaiPreparedLineBatch]
    let pointBatches: [SekaiPreparedPointBatch]
    let labels: [SekaiPreparedLabel]
    let drawOrder: [SekaiPreparedDrawReference]
    let logicalParticleCount: Int
    private let pickTargets: [SekaiPickTarget]
    private let selectableAtlasFeatureIDs: Set<SekaiFeatureID>

    private init(
        particleBatches: [SekaiPreparedParticleBatch],
        surfaceBatches: [SekaiPreparedSurfaceBatch],
        lineBatches: [SekaiPreparedLineBatch],
        pointBatches: [SekaiPreparedPointBatch],
        labels: [SekaiPreparedLabel],
        drawOrder: [SekaiPreparedDrawReference],
        pickTargets: [SekaiPickTarget],
        selectableAtlasFeatureIDs: Set<SekaiFeatureID>
    ) {
        self.particleBatches = particleBatches
        self.surfaceBatches = surfaceBatches
        self.lineBatches = lineBatches
        self.pointBatches = pointBatches
        self.labels = labels
        self.drawOrder = drawOrder
        self.pickTargets = pickTargets
        self.selectableAtlasFeatureIDs = selectableAtlasFeatureIDs
        logicalParticleCount = particleBatches.reduce(0) { $0 + $1.vertices.count }
    }

    static func prepare(
        key: SekaiSceneKey,
        defaultStyle: SekaiStyle
    ) -> SekaiPreparedScene {
        let atlas = SekaiAtlas.bundled
        var particles: [SekaiPreparedParticleBatch] = []
        var surfaces: [SekaiPreparedSurfaceBatch] = []
        var lines: [SekaiPreparedLineBatch] = []
        var points: [SekaiPreparedPointBatch] = []
        var labels: [SekaiPreparedLabel] = []
        var picks: [SekaiPickTarget] = []
        var selectableFeatureIDs: Set<SekaiFeatureID> = []
        var drawOrder: [SekaiPreparedDrawReference] = []

        for layer in key.sourceLayers {
            switch layer {
            case let .particles(id, filter, override):
                let density = override?.density ?? defaultStyle.particles.density
                particles.append(SekaiPreparedParticleBatch(
                    layerID: id,
                    vertices: atlas.packedParticles(
                        matching: filter,
                        density: density,
                        automaticLimit: key.automaticParticleLimit
                    ),
                    styleOverride: override
                ))
                drawOrder.append(.particles(particles.count - 1))
                selectableFeatureIDs.formUnion(atlas.features(matching: filter).map(\.id))

            case let .boundaries(id, filter, override):
                surfaces.append(SekaiPreparedSurfaceBatch(
                    layerID: id,
                    fillVerticesByLevelOfDetail: (0...2).map {
                        atlas.packedBoundaryFillVertices(matching: filter, levelOfDetail: $0)
                    },
                    lineVerticesByLevelOfDetail: (0...2).map {
                        atlas.packedBoundaryVertices(matching: filter, levelOfDetail: $0)
                    },
                    styleOverride: override
                ))
                drawOrder.append(.surface(surfaces.count - 1))
                selectableFeatureIDs.formUnion(atlas.features(matching: filter).map(\.id))

            case let .annotations(layerID, values):
                for annotation in values {
                    let style = annotation.style ?? defaultStyle.annotations
                    let previousCount = points.count
                    appendPoint(
                        PackedParticle(annotation.coordinate, elevation: style.elevation),
                        id: layerID,
                        material: .annotation(annotation.style),
                        to: &points
                    )
                    if points.count > previousCount { drawOrder.append(.points(points.count - 1)) }
                    picks.append(SekaiPickTarget(
                        selection: .annotation(annotation.id),
                        geometry: .point(annotation.coordinate, radius: max(18, style.size * 12)),
                        priority: 1_000 + annotation.priority
                    ))
                }

            case let .userLocation(layerID, annotation):
                let style = annotation.style ?? defaultStyle.annotations
                let previousCount = points.count
                appendPoint(
                    PackedParticle(annotation.coordinate, elevation: style.elevation),
                    id: layerID,
                    material: .annotation(annotation.style),
                    to: &points
                )
                if points.count > previousCount { drawOrder.append(.points(points.count - 1)) }
                picks.append(SekaiPickTarget(
                    selection: .annotation(annotation.id),
                    geometry: .point(annotation.coordinate, radius: max(22, style.size * 14)),
                    priority: 2_000 + annotation.priority
                ))

            case let .routes(layerID, values):
                for route in values {
                    let resolvedStyle = route.style ?? defaultStyle.routes
                    let completeCoordinates = routeCoordinates(route)
                    let coordinates = visibleRouteCoordinates(
                        completeCoordinates,
                        progress: resolvedStyle.progress
                    )
                    let vertices = patternedRouteVertices(
                        coordinates,
                        style: resolvedStyle,
                        totalSegmentCount: max(completeCoordinates.count - 1, 1)
                    )
                    lines.append(SekaiPreparedLineBatch(
                        id: "\(layerID).\(route.id)",
                        vertices: vertices,
                        styleOverride: route.style
                    ))
                    drawOrder.append(.line(lines.count - 1))
                    if resolvedStyle.endpointSize > 0,
                       let first = completeCoordinates.first,
                       let last = completeCoordinates.last {
                        let endpointMaterial = SekaiPreparedPointMaterial.routeEndpoint(route.style)
                        let previousCount = points.count
                        appendPoint(PackedParticle(first, elevation: 0.006), id: "\(layerID).\(route.id).endpoints", material: endpointMaterial, to: &points)
                        appendPoint(PackedParticle(last, elevation: 0.006), id: "\(layerID).\(route.id).endpoints", material: endpointMaterial, to: &points)
                        if points.count > previousCount { drawOrder.append(.points(points.count - 1)) }
                    }
                    if coordinates.count > 1 {
                        picks.append(SekaiPickTarget(
                            selection: .route(route.id),
                            geometry: .line(coordinates, radius: max(14, resolvedStyle.width * 5)),
                            priority: 700
                        ))
                    }
                }

            case let .polylines(layerID, values):
                for line in values where line.coordinates.count > 1 {
                    lines.append(SekaiPreparedLineBatch(
                        id: "\(layerID).\(line.id)",
                        vertices: constantElevationLineVertices(line.coordinates, style: line.style),
                        styleOverride: line.style
                    ))
                    drawOrder.append(.line(lines.count - 1))
                    picks.append(SekaiPickTarget(
                        selection: .custom(layerID: layerID, featureID: line.id),
                        geometry: .line(line.coordinates, radius: max(14, line.style.width * 5)),
                        priority: 650
                    ))
                }

            case let .polygons(layerID, values):
                for polygon in values {
                    surfaces.append(SekaiPreparedSurfaceBatch(
                        layerID: "\(layerID).\(polygon.id)",
                        fillVerticesByLevelOfDetail: [SekaiPolygonTessellator.triangles(for: polygon.rings)],
                        lineVerticesByLevelOfDetail: [SekaiPolygonTessellator.outline(for: polygon.rings)],
                        styleOverride: polygon.style
                    ))
                    drawOrder.append(.surface(surfaces.count - 1))
                    picks.append(SekaiPickTarget(
                        selection: .custom(layerID: layerID, featureID: polygon.id),
                        geometry: .polygon(polygon.rings),
                        priority: 500
                    ))
                }

            case let .circles(layerID, values):
                for circle in values {
                    let ring = SekaiPolygonTessellator.circle(
                        center: circle.center,
                        radiusKilometers: circle.radiusKilometers
                    )
                    surfaces.append(SekaiPreparedSurfaceBatch(
                        layerID: "\(layerID).\(circle.id)",
                        fillVerticesByLevelOfDetail: [SekaiPolygonTessellator.triangles(for: [ring])],
                        lineVerticesByLevelOfDetail: [SekaiPolygonTessellator.outline(for: [ring])],
                        styleOverride: circle.style
                    ))
                    drawOrder.append(.surface(surfaces.count - 1))
                    picks.append(SekaiPickTarget(
                        selection: .custom(layerID: layerID, featureID: circle.id),
                        geometry: .polygon([ring]),
                        priority: 500
                    ))
                }

            case let .heatmap(layerID, values):
                for heatPoint in values {
                    let weight = min(max(heatPoint.weight, 0), 1)
                    let previousCount = points.count
                    appendPoint(
                        PackedParticle(heatPoint.coordinate, elevation: 0.008),
                        id: "\(layerID).heat.\(Int((weight * 7).rounded()))",
                        material: .heat(weight: Double(Int((weight * 7).rounded())) / 7),
                        to: &points
                    )
                    if points.count > previousCount { drawOrder.append(.points(points.count - 1)) }
                    picks.append(SekaiPickTarget(
                        selection: .custom(layerID: layerID, featureID: heatPoint.id),
                        geometry: .point(heatPoint.coordinate, radius: 20 + weight * 22),
                        priority: 600 + weight
                    ))
                }

            case let .labels(layerID, filter, override):
                labels += atlas.features(matching: filter).map { feature in
                    SekaiPreparedLabel(
                        id: "\(layerID).\(feature.id.rawValue)",
                        layerID: layerID,
                        text: feature.localizedName(),
                        coordinate: feature.labelCoordinate,
                        priority: Double(feature.particleCount),
                        styleOverride: override,
                        selection: .atlas(feature.id)
                    )
                }

            case let .physical(id, features):
                guard !features.isDisjoint(with: [.coastlines, .subdivisions, .disputedBoundaries]) else { break }
                surfaces.append(SekaiPreparedSurfaceBatch(
                    layerID: id,
                    fillVerticesByLevelOfDetail: [[], [], []],
                    lineVerticesByLevelOfDetail: (0...2).map {
                        atlas.packedBoundaryVertices(matching: .allLand, levelOfDetail: $0)
                    },
                    styleOverride: nil
                ))
                drawOrder.append(.surface(surfaces.count - 1))

            case .texture:
                break
            }
        }

        if !selectableFeatureIDs.isEmpty { atlas.prepareSpatialIndex() }
        return SekaiPreparedScene(
            particleBatches: particles,
            surfaceBatches: surfaces,
            lineBatches: lines,
            pointBatches: points,
            labels: labels,
            drawOrder: drawOrder,
            pickTargets: picks,
            selectableAtlasFeatureIDs: selectableFeatureIDs
        )
    }

    func pick(at point: CGPoint, context: SekaiProjectionContext) -> SekaiPickResult? {
        for target in pickTargets.sorted(by: { $0.priority > $1.priority }) {
            switch target.geometry {
            case let .point(coordinate, radius):
                if let projected = context.project(coordinate),
                   hypot(point.x - projected.point.x, point.y - projected.point.y) <= radius {
                    return SekaiPickResult(selection: target.selection, coordinate: coordinate)
                }

            case let .line(coordinates, radius):
                for pair in zip(coordinates, coordinates.dropFirst()) {
                    guard let start = context.project(pair.0), let end = context.project(pair.1) else { continue }
                    if sekaiDistance(from: point, toSegmentStart: start.point, end: end.point) <= radius {
                        return SekaiPickResult(selection: target.selection, coordinate: pair.0)
                    }
                }

            case let .polygon(rings):
                guard let coordinate = context.unproject(point),
                      Self.contains(coordinate, rings: rings) else { continue }
                return SekaiPickResult(selection: target.selection, coordinate: coordinate)
            }
        }

        guard !selectableAtlasFeatureIDs.isEmpty,
              let coordinate = context.unproject(point),
              let feature = SekaiAtlas.bundled.feature(
                  nearest: coordinate,
                  among: selectableAtlasFeatureIDs
              ) else { return nil }
        return SekaiPickResult(selection: .atlas(feature.id), coordinate: coordinate)
    }

    private static func appendPoint(
        _ point: PackedParticle,
        id: String,
        material: SekaiPreparedPointMaterial,
        to batches: inout [SekaiPreparedPointBatch]
    ) {
        if let index = batches.firstIndex(where: { $0.id == id && $0.material == material }) {
            batches[index].vertices.append(point)
        } else {
            batches.append(SekaiPreparedPointBatch(id: id, vertices: [point], material: material))
        }
    }

    private static func routeCoordinates(_ route: SekaiRoute) -> [SekaiCoordinate] {
        switch route.curve {
        case let .custom(values):
            return values
        case .rhumb:
            let longitudeDelta = SekaiCoordinate.normalizedLongitude(route.to.longitude - route.from.longitude)
            let startLatitude = min(max(route.from.latitude, -89.999_999), 89.999_999) * .pi / 180
            let endLatitude = min(max(route.to.latitude, -89.999_999), 89.999_999) * .pi / 180
            let startMercator = log(tan(.pi / 4 + startLatitude / 2))
            let endMercator = log(tan(.pi / 4 + endLatitude / 2))
            return (0...128).map { index in
                let fraction = Double(index) / 128
                let mercatorLatitude = startMercator + (endMercator - startMercator) * fraction
                return SekaiCoordinate(
                    latitude: (2 * atan(exp(mercatorLatitude)) - .pi / 2) * 180 / .pi,
                    longitude: route.from.longitude + longitudeDelta * fraction
                )
            }
        case .greatCircle:
            let start = SekaiVector3(route.from)
            let end = SekaiVector3(route.to)
            return (0...128).map {
                SekaiVector3.slerp(start, end, progress: Double($0) / 128).coordinate
            }
        }
    }

    private static func visibleRouteCoordinates(
        _ coordinates: [SekaiCoordinate],
        progress: Double
    ) -> [SekaiCoordinate] {
        guard coordinates.count > 1 else { return coordinates }
        let clampedProgress = min(max(progress, 0), 1)
        let finalIndex = min(
            Int((Double(coordinates.count - 1) * clampedProgress).rounded(.down)),
            coordinates.count - 1
        )
        return Array(coordinates.prefix(finalIndex + 1))
    }

    private static func patternedRouteVertices(
        _ coordinates: [SekaiCoordinate],
        style: SekaiRouteStyle,
        totalSegmentCount: Int
    ) -> [PackedParticle] {
        guard coordinates.count > 1 else { return [] }
        let visibleSegmentCount = coordinates.count - 1
        let totalSegmentCount = max(totalSegmentCount, visibleSegmentCount)
        return (0..<visibleSegmentCount).flatMap { index -> [PackedParticle] in
            let fraction = (Double(index) + 0.5) / Double(totalSegmentCount)
            let visible: Bool
            switch style.pattern {
            case .solid:
                visible = true
            case let .dashed(length, gap):
                let dash = max(length, 0.0001)
                let space = max(gap, 0)
                let cycle = dash + space
                let position = cycle <= 1 ? fraction.truncatingRemainder(dividingBy: cycle) : Double(index).truncatingRemainder(dividingBy: cycle)
                visible = position <= dash
            }
            guard visible else { return [] }
            let startProgress = Double(index) / Double(totalSegmentCount)
            let endProgress = Double(index + 1) / Double(totalSegmentCount)
            return [
                PackedParticle(coordinates[index], elevation: sin(startProgress * .pi) * style.elevation),
                PackedParticle(coordinates[index + 1], elevation: sin(endProgress * .pi) * style.elevation)
            ]
        }
    }

    private static func constantElevationLineVertices(
        _ coordinates: [SekaiCoordinate],
        style: SekaiRouteStyle
    ) -> [PackedParticle] {
        guard coordinates.count > 1 else { return [] }
        let progress = min(max(style.progress, 0), 1)
        let segmentCount = min(Int((Double(coordinates.count - 1) * progress).rounded(.down)), coordinates.count - 1)
        guard segmentCount > 0 else { return [] }
        return (0..<segmentCount).flatMap {
            [
                PackedParticle(coordinates[$0], elevation: style.elevation),
                PackedParticle(coordinates[$0 + 1], elevation: style.elevation)
            ]
        }
    }

    private static func contains(_ coordinate: SekaiCoordinate, rings: [[SekaiCoordinate]]) -> Bool {
        guard let outer = rings.first, pointInRing(coordinate, ring: outer) else { return false }
        return !rings.dropFirst().contains { pointInRing(coordinate, ring: $0) }
    }

    private static func pointInRing(_ coordinate: SekaiCoordinate, ring: [SekaiCoordinate]) -> Bool {
        guard ring.count >= 3 else { return false }
        let x = coordinate.longitude
        let y = coordinate.latitude
        var inside = false
        var previous = ring.last!
        for current in ring {
            let currentX = x + SekaiCoordinate.normalizedLongitude(current.longitude - x)
            let previousX = x + SekaiCoordinate.normalizedLongitude(previous.longitude - x)
            let latitudeDelta = previous.latitude - current.latitude
            let denominator = abs(latitudeDelta) < .leastNonzeroMagnitude
                ? (latitudeDelta < 0 ? -.leastNonzeroMagnitude : .leastNonzeroMagnitude)
                : latitudeDelta
            let intersects = (current.latitude > y) != (previous.latitude > y)
                && x < (previousX - currentX) * (y - current.latitude) / denominator + currentX
            if intersects { inside.toggle() }
            previous = current
        }
        return inside
    }
}

struct SekaiSceneKey: Equatable, Sendable {
    struct ParticleLayer: Equatable, Sendable {
        let id: String
        let filter: SekaiRegionFilter
        let density: SekaiParticleDensity
    }

    let sourceLayers: [SekaiLayer]
    let particleLayers: [ParticleLayer]
    let defaultAnnotationElevation: Double
    let defaultRouteElevation: Double
    let defaultRouteProgress: Double
    let defaultRoutePattern: SekaiLinePattern
    let defaultRouteEndpointSize: Double
    let automaticParticleLimit: Int

    static func == (left: Self, right: Self) -> Bool {
        guard left.particleLayers == right.particleLayers,
              left.defaultAnnotationElevation == right.defaultAnnotationElevation,
              left.defaultRouteElevation == right.defaultRouteElevation,
              left.defaultRouteProgress == right.defaultRouteProgress,
              left.defaultRoutePattern == right.defaultRoutePattern,
              left.defaultRouteEndpointSize == right.defaultRouteEndpointSize,
              left.automaticParticleLimit == right.automaticParticleLimit,
              left.sourceLayers.count == right.sourceLayers.count else { return false }
        return zip(left.sourceLayers, right.sourceLayers).allSatisfy(layerGeometryEquals)
    }

    private static func layerGeometryEquals(_ pair: (SekaiLayer, SekaiLayer)) -> Bool {
        switch pair {
        case let (.particles(leftID, left, _), .particles(rightID, right, _)),
             let (.boundaries(leftID, left, _), .boundaries(rightID, right, _)),
             let (.labels(leftID, left, _), .labels(rightID, right, _)):
            leftID == rightID && left == right
        case let (.annotations(leftID, left), .annotations(rightID, right)):
            leftID == rightID && left == right
        case let (.routes(leftID, left), .routes(rightID, right)):
            leftID == rightID && left == right
        case let (.polylines(leftID, left), .polylines(rightID, right)):
            leftID == rightID && left == right
        case let (.userLocation(leftID, left), .userLocation(rightID, right)):
            leftID == rightID && left == right
        case let (.physical(leftID, left), .physical(rightID, right)):
            leftID == rightID && left == right
        case let (.polygons(leftID, left), .polygons(rightID, right)):
            leftID == rightID && left == right
        case let (.circles(leftID, left), .circles(rightID, right)):
            leftID == rightID && left == right
        case let (.heatmap(leftID, left), .heatmap(rightID, right)):
            leftID == rightID && left == right
        case let (.texture(leftID, leftName, leftOpacity), .texture(rightID, rightName, rightOpacity)):
            leftID == rightID && leftName == rightName && leftOpacity == rightOpacity
        default:
            false
        }
    }
}

actor SekaiSceneCache {
    static let shared = SekaiSceneCache()
    private var entries: [(SekaiSceneKey, SekaiPreparedScene)] = []

    func scene(for key: SekaiSceneKey, style: SekaiStyle) -> SekaiPreparedScene {
        if let index = entries.firstIndex(where: { $0.0 == key }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return entry.1
        }
        let scene = SekaiPreparedScene.prepare(key: key, defaultStyle: style)
        entries.append((key, scene))
        if entries.count > 3 { entries.removeFirst() }
        return scene
    }
}
