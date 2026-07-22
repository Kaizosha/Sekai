import SekaiKit
import SwiftUI

/// The single reference UI shipped with Sekai.
public struct SekaiDemo: View {
    @State private var camera = SekaiCamera.standard
    @State private var style = SekaiDemoDefaults.style
    @State private var interaction = SekaiInteractionOptions(autoRotationSpeed: 0.08)
    @State private var options = SekaiInspectorOptions(performance: .exact)
    @State private var selection: SekaiSelection?
    @State private var metrics = SekaiRenderMetrics()
    @State private var showsInspector = true

    public init() {}

    public var body: some View {
        NavigationStack {
            Sekai(
                camera: $camera,
                selection: $selection,
                style: style,
                interaction: interaction,
                performance: options.performance,
                metrics: $metrics
            ) {
                if options.presentation != .boundaries {
                    SekaiLayer.landParticles(filter: options.filter, style: style.particles)
                }
                if options.presentation != .particles {
                    SekaiLayer.regionBoundaries(filter: options.filter, style: style.boundaries)
                }
                if options.showsRoutes {
                    SekaiLayer.routes(id: "demo.routes", values: SekaiDemoDefaults.routes)
                }
                if options.showsAnnotations {
                    SekaiLayer.annotations(id: "demo.places", values: SekaiDemoDefaults.annotations)
                }
                if options.showsLabels {
                    SekaiLayer.labels(id: "demo.labels", filter: options.filter, style: style.labels)
                }
                if options.showsGeometryExamples {
                    SekaiLayer.polygons(id: "demo.polygons", values: SekaiDemoDefaults.polygons)
                    SekaiLayer.circles(id: "demo.circles", values: SekaiDemoDefaults.circles)
                }
                if options.showsHeatmap {
                    SekaiLayer.heatmap(id: "demo.heat", values: SekaiDemoDefaults.heatPoints)
                }
            }
            .padding()
            .navigationTitle("Sekai")
            #if os(iOS) || os(macOS)
            .navigationSubtitle("by Kaizōsha")
            #endif
            .toolbar {
                Button("Customize", systemImage: "slider.horizontal.3") { showsInspector = true }
            }
        }
        .sheet(isPresented: $showsInspector) {
            SekaiInspector(
                camera: $camera,
                style: $style,
                interaction: $interaction,
                options: $options,
                selection: $selection,
                metrics: metrics
            ) {
                camera = .standard
                style = SekaiDemoDefaults.style
                interaction = .init(autoRotationSpeed: 0.08)
                options = .init(performance: .exact)
                selection = nil
            }
            .safeAreaInset(edge: .bottom) {
                #if os(tvOS)
                Text("kaizosha.org/sekai")
                    .foregroundStyle(.secondary)
                    .padding()
                #else
                ShareLink(item: SekaiCodeExporter.minimalIntegration) {
                    Label("Copy Implementation", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                #if os(visionOS)
                .buttonStyle(.borderedProminent)
                #else
                .buttonStyle(.glassProminent)
                #endif
                .padding()
                #endif
            }
            #if os(iOS) || os(visionOS)
            .presentationDetents([.fraction(0.1), .medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            #endif
            .interactiveDismissDisabled()
        }
    }
}

private enum SekaiDemoDefaults {
    static var style: SekaiStyle {
        var value = SekaiStyle.standard
        value.particles.density = .maximum
        value.particles.size = 0.55
        value.particles.color = .fixed(.black)
        value.globe.surfaceColor = SekaiColor(red: 1, green: 1, blue: 1, alpha: 0.18)
        value.annotations.color = .red
        return value
    }

    static let chicago = SekaiCoordinate(latitude: 41.8781, longitude: -87.6298)
    static let tokyo = SekaiCoordinate(latitude: 35.6762, longitude: 139.6503)
    static let paris = SekaiCoordinate(latitude: 48.8566, longitude: 2.3522)
    static let annotations = [
        SekaiAnnotation(id: "chicago", coordinate: chicago, title: "Chicago"),
        SekaiAnnotation(id: "tokyo", coordinate: tokyo, title: "Tokyo"),
        SekaiAnnotation(id: "paris", coordinate: paris, title: "Paris")
    ]
    static let routes = [
        SekaiRoute(id: "chicago-tokyo", from: chicago, to: tokyo),
        SekaiRoute(id: "paris-tokyo", from: paris, to: tokyo)
    ]
    static let polygons = [
        SekaiPolygon(
            id: "pacific-zone",
            rings: [[
                .init(latitude: 18, longitude: -165),
                .init(latitude: 38, longitude: -145),
                .init(latitude: 25, longitude: -122),
                .init(latitude: 6, longitude: -142)
            ]],
            style: .init(
                fillColor: .fixed(.cyan),
                fillOpacity: 0.2,
                strokeColor: .fixed(.cyan),
                strokeOpacity: 0.85,
                strokeWidth: 1.5
            )
        )
    ]
    static let circles = [
        SekaiCircle(
            id: "chicago-range",
            center: chicago,
            radiusKilometers: 1_200,
            style: .init(
                fillColor: .fixed(.red),
                fillOpacity: 0.12,
                strokeColor: .fixed(.red),
                strokeOpacity: 0.8,
                strokeWidth: 1.2
            )
        )
    ]
    static let heatPoints = [
        SekaiHeatPoint(id: "chicago", coordinate: chicago, weight: 0.65),
        SekaiHeatPoint(id: "tokyo", coordinate: tokyo, weight: 1),
        SekaiHeatPoint(id: "paris", coordinate: paris, weight: 0.8)
    ]
}
