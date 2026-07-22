import Foundation
import SekaiKit

public enum SekaiGeoJSONError: Error, Sendable {
    case invalidRoot
    case unsupportedGeometry(String)
    case invalidCoordinates
}

public struct SekaiGeoJSONDefaults: Sendable {
    public var annotation: SekaiAnnotationStyle
    public var line: SekaiRouteStyle
    public var polygon: SekaiBoundaryStyle

    public init(
        annotation: SekaiAnnotationStyle = .standard,
        line: SekaiRouteStyle = .standard,
        polygon: SekaiBoundaryStyle = .standard
    ) {
        self.annotation = annotation
        self.line = line
        self.polygon = polygon
    }

    public static let standard = Self()
}

/// A structured GeoJSON decoder that converts features into native Sekai layers.
public enum SekaiGeoJSON {
    public static func decode(
        _ data: Data,
        layerID: String = "sekai.geojson"
    ) throws -> SekaiLayerGroup {
        try decode(data, layerID: layerID, defaults: .standard)
    }

    public static func decode(
        _ data: Data,
        layerID: String = "sekai.geojson",
        defaults: SekaiGeoJSONDefaults
    ) throws -> SekaiLayerGroup {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { throw SekaiGeoJSONError.invalidRoot }
        let features: [[String: Any]]
        switch root["type"] as? String {
        case "FeatureCollection": features = root["features"] as? [[String: Any]] ?? []
        case "Feature": features = [root]
        default: features = [["type": "Feature", "geometry": root]]
        }

        var annotations: [SekaiAnnotation] = []
        var polylines: [SekaiPolyline] = []
        var polygons: [SekaiPolygon] = []
        for (index, feature) in features.enumerated() {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String else { continue }
            let id = featureID(feature["id"]) ?? "\(layerID).\(index)"
            let properties = feature["properties"] as? [String: Any] ?? [:]
            let title = properties["name"] as? String
            let annotationStyle = annotationStyle(properties, fallback: defaults.annotation)
            let lineStyle = lineStyle(properties, fallback: defaults.line)
            let polygonStyle = polygonStyle(properties, fallback: defaults.polygon)
            switch type {
            case "Point":
                annotations.append(SekaiAnnotation(
                    id: id,
                    coordinate: try coordinate(geometry["coordinates"]),
                    title: title,
                    style: annotationStyle
                ))
            case "MultiPoint":
                let values = geometry["coordinates"] as? [Any] ?? []
                annotations += try values.enumerated().map {
                    SekaiAnnotation(
                        id: "\(id).\($0.offset)",
                        coordinate: try coordinate($0.element),
                        title: title,
                        style: annotationStyle
                    )
                }
            case "LineString":
                polylines.append(SekaiPolyline(
                    id: id,
                    coordinates: try coordinates(geometry["coordinates"]),
                    style: lineStyle
                ))
            case "MultiLineString":
                let values = geometry["coordinates"] as? [Any] ?? []
                polylines += try values.enumerated().map {
                    SekaiPolyline(
                        id: "\(id).\($0.offset)",
                        coordinates: try coordinates($0.element),
                        style: lineStyle
                    )
                }
            case "Polygon":
                polygons.append(SekaiPolygon(
                    id: id,
                    rings: try rings(geometry["coordinates"]),
                    style: polygonStyle
                ))
            case "MultiPolygon":
                let values = geometry["coordinates"] as? [Any] ?? []
                polygons += try values.enumerated().map {
                    SekaiPolygon(
                        id: "\(id).\($0.offset)",
                        rings: try rings($0.element),
                        style: polygonStyle
                    )
                }
            default: throw SekaiGeoJSONError.unsupportedGeometry(type)
            }
        }
        var layers: [SekaiLayer] = []
        if !polygons.isEmpty { layers.append(.polygons(id: "\(layerID).polygons", values: polygons)) }
        if !polylines.isEmpty { layers.append(.polylines(id: "\(layerID).lines", values: polylines)) }
        if !annotations.isEmpty { layers.append(.annotations(id: "\(layerID).points", values: annotations)) }
        return SekaiLayerGroup(layers)
    }

    private static func coordinate(_ value: Any?) throws -> SekaiCoordinate {
        guard let pair = value as? [Double], pair.count >= 2 else { throw SekaiGeoJSONError.invalidCoordinates }
        return SekaiCoordinate(latitude: pair[1], longitude: pair[0])
    }

    private static func coordinates(_ value: Any?) throws -> [SekaiCoordinate] {
        guard let values = value as? [Any] else { throw SekaiGeoJSONError.invalidCoordinates }
        return try values.map { try coordinate($0) }
    }

    private static func rings(_ value: Any?) throws -> [[SekaiCoordinate]] {
        guard let values = value as? [Any] else { throw SekaiGeoJSONError.invalidCoordinates }
        return try values.map { try coordinates($0) }
    }

    private static func featureID(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func annotationStyle(
        _ properties: [String: Any],
        fallback: SekaiAnnotationStyle
    ) -> SekaiAnnotationStyle {
        var style = fallback
        if let color = color(properties["marker-color"] ?? properties["color"]) { style.color = color }
        if let size = markerSize(properties["marker-size"] ?? properties["size"]) { style.size = max(size, 0) }
        if let opacity = number(properties["marker-opacity"] ?? properties["opacity"]) { style.opacity = opacity }
        return style
    }

    private static func lineStyle(
        _ properties: [String: Any],
        fallback: SekaiRouteStyle
    ) -> SekaiRouteStyle {
        var style = fallback
        if let color = color(properties["stroke"] ?? properties["color"]) { style.color = color }
        if let width = number(properties["stroke-width"] ?? properties["width"]) { style.width = max(width, 0) }
        if let opacity = number(properties["stroke-opacity"] ?? properties["opacity"]) { style.opacity = opacity }
        return style
    }

    private static func polygonStyle(
        _ properties: [String: Any],
        fallback: SekaiBoundaryStyle
    ) -> SekaiBoundaryStyle {
        var style = fallback
        if let fill = color(properties["fill"]) { style.fillColor = .fixed(fill) }
        if let opacity = number(properties["fill-opacity"]) { style.fillOpacity = opacity }
        if let stroke = color(properties["stroke"]) { style.strokeColor = .fixed(stroke) }
        if let opacity = number(properties["stroke-opacity"]) { style.strokeOpacity = opacity }
        if let width = number(properties["stroke-width"]) { style.strokeWidth = max(width, 0) }
        return style
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func markerSize(_ value: Any?) -> Double? {
        if let number = number(value) { return number }
        guard let value = (value as? String)?.lowercased() else { return nil }
        return switch value {
        case "small": 0.75
        case "medium": 1
        case "large": 1.5
        default: nil
        }
    }

    private static func color(_ value: Any?) -> SekaiColor? {
        guard var text = value as? String else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8,
              let raw = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let red = Double((raw >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let green = Double((raw >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let blue = Double((raw >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let alpha = hasAlpha ? Double(raw & 0xff) / 255 : 1
        return SekaiColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
