import CoreGraphics
import Foundation

enum SekaiPolygonTessellator {
    private struct Vertex: Equatable {
        let coordinate: SekaiCoordinate
        let point: CGPoint
    }

    static func triangles(for rings: [[SekaiCoordinate]], elevation: Double = 0.003) -> [PackedParticle] {
        guard let first = rings.first else { return [] }
        let outerCoordinates = normalizedRing(first)
        guard outerCoordinates.count >= 3 else { return [] }
        let referenceLongitude = circularLongitudeCenter(outerCoordinates)
        let referenceLatitude = outerCoordinates.map(\.latitude).reduce(0, +) / Double(outerCoordinates.count)
        let longitudeScale = max(cos(referenceLatitude * .pi / 180), 0.08)

        func vertices(_ coordinates: [SekaiCoordinate]) -> [Vertex] {
            coordinates.map { coordinate in
                let longitude = unwrappedLongitude(coordinate.longitude, near: referenceLongitude)
                return Vertex(
                    coordinate: coordinate,
                    point: CGPoint(
                        x: (longitude - referenceLongitude) * longitudeScale,
                        y: coordinate.latitude - referenceLatitude
                    )
                )
            }
        }

        var polygon = oriented(vertices(outerCoordinates), counterClockwise: true)
        for ring in rings.dropFirst() {
            let holeCoordinates = normalizedRing(ring)
            guard holeCoordinates.count >= 3 else { continue }
            polygon = bridge(hole: oriented(vertices(holeCoordinates), counterClockwise: false), into: polygon)
        }
        let indices = earClip(polygon)
        return indices.map { PackedParticle(polygon[$0].coordinate, elevation: elevation) }
    }

    static func outline(for rings: [[SekaiCoordinate]], elevation: Double = 0.004) -> [PackedParticle] {
        rings.flatMap { ring -> [PackedParticle] in
            let coordinates = normalizedRing(ring)
            guard coordinates.count > 1 else { return [] }
            return coordinates.indices.flatMap { index in
                let next = coordinates[(index + 1) % coordinates.count]
                return [
                    PackedParticle(coordinates[index], elevation: elevation),
                    PackedParticle(next, elevation: elevation)
                ]
            }
        }
    }

    static func circle(
        center: SekaiCoordinate,
        radiusKilometers: Double,
        segments: Int = 128
    ) -> [SekaiCoordinate] {
        guard radiusKilometers > 0 else { return [] }
        let angularDistance = radiusKilometers / 6_371.0088
        let latitude = center.latitude * .pi / 180
        let longitude = center.longitude * .pi / 180
        return (0..<max(segments, 16)).map { index in
            let bearing = Double(index) / Double(max(segments, 16)) * .pi * 2
            let destinationLatitude = asin(
                sin(latitude) * cos(angularDistance)
                + cos(latitude) * sin(angularDistance) * cos(bearing)
            )
            let destinationLongitude = longitude + atan2(
                sin(bearing) * sin(angularDistance) * cos(latitude),
                cos(angularDistance) - sin(latitude) * sin(destinationLatitude)
            )
            return SekaiCoordinate(
                latitude: destinationLatitude * 180 / .pi,
                longitude: destinationLongitude * 180 / .pi
            )
        }
    }

    private static func normalizedRing(_ ring: [SekaiCoordinate]) -> [SekaiCoordinate] {
        var result: [SekaiCoordinate] = []
        for coordinate in ring where result.last != coordinate {
            result.append(coordinate)
        }
        if result.count > 1, result.first == result.last { result.removeLast() }
        return result
    }

    private static func oriented(_ vertices: [Vertex], counterClockwise: Bool) -> [Vertex] {
        let isCounterClockwise = signedArea(vertices) > 0
        return isCounterClockwise == counterClockwise ? vertices : Array(vertices.reversed())
    }

    private static func signedArea(_ vertices: [Vertex]) -> Double {
        guard vertices.count > 2 else { return 0 }
        return vertices.indices.reduce(into: 0.0) { area, index in
            let next = vertices[(index + 1) % vertices.count]
            area += Double(vertices[index].point.x * next.point.y - next.point.x * vertices[index].point.y)
        } * 0.5
    }

    private static func bridge(hole: [Vertex], into outer: [Vertex]) -> [Vertex] {
        guard !hole.isEmpty, !outer.isEmpty else { return outer }
        let holeIndex = hole.indices.max {
            hole[$0].point.x == hole[$1].point.x
                ? hole[$0].point.y < hole[$1].point.y
                : hole[$0].point.x < hole[$1].point.x
        } ?? 0
        let holePoint = hole[holeIndex].point
        let outerIndex = outer.indices.min { first, second in
            let firstDistance = squaredDistance(outer[first].point, holePoint)
            let secondDistance = squaredDistance(outer[second].point, holePoint)
            return firstDistance < secondDistance
        } ?? 0
        let orderedHole = (0..<hole.count).map { hole[(holeIndex + $0) % hole.count] }
        var result = Array(outer[...outerIndex])
        result.append(contentsOf: orderedHole)
        result.append(orderedHole[0])
        result.append(outer[outerIndex])
        if outerIndex + 1 < outer.count { result.append(contentsOf: outer[(outerIndex + 1)...]) }
        return result
    }

    private static func earClip(_ source: [Vertex]) -> [Int] {
        guard source.count >= 3 else { return [] }
        var remaining = Array(source.indices)
        var triangles: [Int] = []
        var attempts = 0
        while remaining.count > 3, attempts < source.count * source.count {
            var removedEar = false
            for position in remaining.indices {
                let previous = remaining[(position - 1 + remaining.count) % remaining.count]
                let current = remaining[position]
                let next = remaining[(position + 1) % remaining.count]
                let a = source[previous].point
                let b = source[current].point
                let c = source[next].point
                guard cross(a, b, c) > 0.000_000_001 else { continue }
                let containsVertex = remaining.contains { candidate in
                    guard candidate != previous, candidate != current, candidate != next else { return false }
                    let point = source[candidate].point
                    guard squaredDistance(point, a) > 0.000_000_001,
                          squaredDistance(point, b) > 0.000_000_001,
                          squaredDistance(point, c) > 0.000_000_001 else { return false }
                    return pointInTriangle(point, a, b, c)
                }
                guard !containsVertex else { continue }
                triangles.append(contentsOf: [previous, current, next])
                remaining.remove(at: position)
                removedEar = true
                break
            }
            if !removedEar {
                attempts += 1
                if let collinear = remaining.indices.first(where: { position in
                    let previous = remaining[(position - 1 + remaining.count) % remaining.count]
                    let current = remaining[position]
                    let next = remaining[(position + 1) % remaining.count]
                    return abs(cross(source[previous].point, source[current].point, source[next].point)) < 0.000_000_001
                }) {
                    remaining.remove(at: collinear)
                } else {
                    break
                }
            }
        }
        if remaining.count == 3 { triangles.append(contentsOf: remaining) }
        return triangles
    }

    private static func pointInTriangle(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        let first = cross(a, b, point)
        let second = cross(b, c, point)
        let third = cross(c, a, point)
        return first >= 0 && second >= 0 && third >= 0
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        Double((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
    }

    private static func squaredDistance(_ first: CGPoint, _ second: CGPoint) -> Double {
        let x = first.x - second.x
        let y = first.y - second.y
        return Double(x * x + y * y)
    }

    private static func circularLongitudeCenter(_ coordinates: [SekaiCoordinate]) -> Double {
        let vector = coordinates.reduce(into: (x: 0.0, y: 0.0)) { result, coordinate in
            let radians = coordinate.longitude * .pi / 180
            result.x += cos(radians)
            result.y += sin(radians)
        }
        return atan2(vector.y, vector.x) * 180 / .pi
    }

    private static func unwrappedLongitude(_ longitude: Double, near reference: Double) -> Double {
        reference + SekaiCoordinate.normalizedLongitude(longitude - reference)
    }
}
