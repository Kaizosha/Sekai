import Foundation

public enum SekaiCodeExporter {
    /// A minimal, compilable SwiftUI integration using Sekai's production defaults.
    public static let minimalIntegration = """
    import SekaiKit
    import SwiftUI

    struct GlobeView: View {
        @State private var camera = SekaiCamera.standard
        @State private var selection: SekaiSelection?

        var body: some View {
            Sekai(camera: $camera, selection: $selection) {
                SekaiLayer.landParticles()
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }
    """

    public static func integration(
        filter: SekaiRegionFilter,
        density: SekaiParticleDensity,
        includesBoundaries: Bool = false
    ) -> String {
        let filterCode = code(for: filter)
        let densityCode = code(for: density)
        let boundary = includesBoundaries
            ? "\n            SekaiLayer.regionBoundaries(filter: \(filterCode))"
            : ""
        return """
        import SekaiKit
        import SwiftUI

        struct GlobeView: View {
            @State private var camera = SekaiCamera.standard
            @State private var selection: SekaiSelection?
            private var particles: SekaiParticleStyle {
                var value = SekaiParticleStyle.standard
                value.density = \(densityCode)
                return value
            }

            var body: some View {
                Sekai(camera: $camera, selection: $selection) {
                    SekaiLayer.landParticles(filter: \(filterCode), style: particles)\(boundary)
                }
            }
        }
        """
    }

    private static func code(for filter: SekaiRegionFilter) -> String {
        switch filter {
        case .allLand: ".allLand"
        case let .continent(value): ".continent(\"\(escaped(value))\")"
        case let .sovereign(value): ".sovereign(\"\(escaped(value.rawValue))\")"
        case let .country(value): ".country(\"\(escaped(value.rawValue))\")"
        case let .mapUnit(value): ".mapUnit(\"\(escaped(value.rawValue))\")"
        case let .features(values):
            ".features([\(values.sorted { $0.rawValue < $1.rawValue }.map { "\"\(escaped($0.rawValue))\"" }.joined(separator: ", "))])"
        }
    }

    private static func code(for density: SekaiParticleDensity) -> String {
        switch density {
        case .automatic: ".automatic"
        case let .fraction(value): ".fraction(\(value))"
        case let .count(value): ".count(\(value))"
        case .maximum: ".maximum"
        }
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
