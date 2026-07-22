import Foundation
import SekaiKit

public enum SekaiGeoJSONError: Error, Sendable {
    case invalidRoot
    case unsupportedGeometry(String)
    case invalidCoordinates
}

/// A structured GeoJSON decoder that converts features into native Sekai layers.
public enum SekaiGeoJSON {
    public static func decode(_ data: Data, layerID: String = "sekai.geojson") throws -> SekaiLayerGroup {
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
            let id = (feature["id"] as? String) ?? "\(layerID).\(index)"
            let title = (feature["properties"] as? [String: Any])?["name"] as? String
            switch type {
            case "Point":
                annotations.append(SekaiAnnotation(id: id, coordinate: try coordinate(geometry["coordinates"]), title: title))
            case "MultiPoint":
                let values = geometry["coordinates"] as? [Any] ?? []
                annotations += try values.enumerated().map {
                    SekaiAnnotation(id: "\(id).\($0.offset)", coordinate: try coordinate($0.element), title: title)
                }
            case "LineString":
                polylines.append(SekaiPolyline(id: id, coordinates: try coordinates(geometry["coordinates"])))
            case "MultiLineString":
                let values = geometry["coordinates"] as? [Any] ?? []
                polylines += try values.enumerated().map {
                    SekaiPolyline(id: "\(id).\($0.offset)", coordinates: try coordinates($0.element))
                }
            case "Polygon":
                polygons.append(SekaiPolygon(id: id, rings: try rings(geometry["coordinates"])))
            case "MultiPolygon":
                let values = geometry["coordinates"] as? [Any] ?? []
                polygons += try values.enumerated().map {
                    SekaiPolygon(id: "\(id).\($0.offset)", rings: try rings($0.element))
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
}
