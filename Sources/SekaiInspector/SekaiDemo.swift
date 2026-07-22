import SekaiKit
import SwiftUI

/// The single reference UI shipped with Sekai.
public struct SekaiDemo: View {
    @State private var camera = SekaiCamera.standard
    @State private var style = SekaiDemoDefaults.style
    @State private var interaction = SekaiInteractionOptions(autoRotationSpeed: 0.08)
    @State private var options = SekaiInspectorOptions(performance: .exact)
    @State private var showsInspector = true

    public init() {}

    public var body: some View {
        NavigationStack {
            Sekai(camera: $camera, style: style, interaction: interaction, performance: options.performance) {
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
            SekaiInspector(camera: $camera, style: $style, interaction: $interaction, options: $options) {
                camera = .standard
                style = SekaiDemoDefaults.style
                interaction = .init(autoRotationSpeed: 0.08)
                options = .init(performance: .exact)
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
}
