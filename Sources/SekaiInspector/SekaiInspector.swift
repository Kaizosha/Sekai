import SekaiKit
import SwiftUI

public enum SekaiInspectorSource: String, Codable, CaseIterable, Sendable {
    case allLand = "All Land"
    case continent = "Continent"
    case country = "Country"
    case mapUnit = "Map Unit"
}

public enum SekaiInspectorPresentation: String, Codable, CaseIterable, Sendable {
    case particles = "Particles"
    case boundaries = "Boundaries"
    case both = "Both"
}

public struct SekaiInspectorOptions: Equatable, Sendable {
    public var filter: SekaiRegionFilter
    public var presentation: SekaiInspectorPresentation
    public var performance: SekaiPerformancePolicy
    public var showsAnnotations: Bool
    public var showsRoutes: Bool

    public init(
        filter: SekaiRegionFilter = .allLand,
        presentation: SekaiInspectorPresentation = .particles,
        performance: SekaiPerformancePolicy = .adaptive(),
        showsAnnotations: Bool = true,
        showsRoutes: Bool = true
    ) {
        self.filter = filter
        self.presentation = presentation
        self.performance = performance
        self.showsAnnotations = showsAnnotations
        self.showsRoutes = showsRoutes
    }
}

/// A reusable development inspector for tuning a Sekai instance.
public struct SekaiInspector: View {
    @Binding private var camera: SekaiCamera
    @Binding private var style: SekaiStyle
    @Binding private var interaction: SekaiInteractionOptions
    @Binding private var options: SekaiInspectorOptions
    private let reset: () -> Void

    public init(
        camera: Binding<SekaiCamera>,
        style: Binding<SekaiStyle>,
        interaction: Binding<SekaiInteractionOptions>,
        options: Binding<SekaiInspectorOptions>,
        reset: @escaping () -> Void = {}
    ) {
        _camera = camera
        _style = style
        _interaction = interaction
        _options = options
        self.reset = reset
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("MAP") {
                    Picker("Source", selection: source) {
                        ForEach(SekaiInspectorSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    switch source.wrappedValue {
                    case .continent:
                        Picker("Continent", selection: continent) {
                            ForEach(SekaiAtlas.bundled.continents, id: \.self) { Text($0).tag($0) }
                        }
                    case .country:
                        Picker("Country", selection: country) {
                            ForEach(sortedCountries, id: \.0) { Text($0.1).tag($0.0) }
                        }
                    case .mapUnit:
                        Picker("Map Unit", selection: mapUnit) {
                            ForEach(SekaiAtlas.bundled.features) { Text($0.name).tag($0.id) }
                        }
                    case .allLand: EmptyView()
                    }
                    Picker("Presentation", selection: $options.presentation) {
                        ForEach(SekaiInspectorPresentation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Quality", selection: performanceMode) {
                        Text("Adaptive").tag(0)
                        Text("Exact").tag(1)
                        Text("Battery Saver").tag(2)
                    }
                    slider("Density", value: density, range: 0...1, icon: "circle.grid.3x3.fill")
                    slider("Particle Size", value: $style.particles.size, range: 0.2...4, icon: "circle.dotted")
                    slider("Opacity", value: $style.particles.opacity, range: 0...1, icon: "circle.lefthalf.filled")
                    slider("Brightness", value: $style.particles.brightness, range: 0...2, icon: "sun.max")
                    slider("Highlight", value: $style.particles.highlight, range: 0...1, icon: "sparkles")
                    slider("Refraction", value: $style.particles.refraction, range: 0...1, icon: "circle.hexagongrid")
                }
                Section("GLOBE") {
                    Picker("Material", selection: $style.globe.material) {
                        ForEach(SekaiGlassMaterial.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    slider("Surface", value: $style.globe.opacity, range: 0...1, icon: "circle.fill")
                    slider("Lighting", value: $style.globe.lighting, range: 0...1, icon: "circle.lefthalf.filled")
                    slider("Rim", value: $style.globe.rimOpacity, range: 0...1, icon: "circle")
                    slider("Glow", value: $style.globe.glowIntensity, range: 0...1, icon: "sparkles")
                }
                Section("OVERLAYS") {
                    Toggle("Markers", isOn: $options.showsAnnotations)
                    Toggle("Routes", isOn: $options.showsRoutes)
                    slider("Marker Size", value: $style.annotations.size, range: 0.25...3, icon: "mappin")
                    slider("Route Width", value: $style.routes.width, range: 0.25...4, icon: "point.topleft.down.curvedto.point.bottomright.up")
                    slider("Route Elevation", value: $style.routes.elevation, range: 0...0.5, icon: "arrow.up.circle")
                }
                Section("ENVIRONMENT") {
                    Toggle("Stars", isOn: $style.environment.showsStars)
                    Toggle("Day and Night", isOn: $style.environment.showsDayNightTerminator)
                    slider("Atmosphere", value: $style.environment.atmosphereIntensity, range: 0...1, icon: "circle.dotted")
                    slider("Ambient Light", value: $style.environment.ambientLight, range: 0...1, icon: "sun.max")
                }
                Section("MOTION") {
                    Toggle("Auto Rotate", isOn: autoRotate)
                    slider("Speed", value: $interaction.autoRotationSpeed, range: -1...1, icon: "rotate.3d")
                    Toggle("Stop After Interaction", isOn: $interaction.stopsAutoRotationOnInteraction)
                }
                Section("CAMERA") {
                    Picker("Projection", selection: projectionMode) {
                        Text("Orthographic").tag(0)
                        Text("Perspective").tag(1)
                    }
                    slider("Zoom", value: $camera.zoom, range: interaction.cameraBounds.minimumZoom...interaction.cameraBounds.maximumZoom, icon: "plus.magnifyingglass")
                    slider("Horizontal Offset", value: $camera.offsetX, range: -1...1, icon: "arrow.left.and.right")
                    slider("Vertical Offset", value: $camera.offsetY, range: -1...1, icon: "arrow.up.and.down")
                }
            }
            .navigationTitle("Sekai")
            #if os(iOS) || os(macOS)
            .navigationSubtitle("by Kaizōsha")
            #endif
            .toolbar { Button("Reset", systemImage: "arrow.counterclockwise", action: reset) }
        }
    }

    private var density: Binding<Double> {
        Binding {
            if case let .fraction(value) = style.particles.density { value } else { 1 }
        } set: { style.particles.density = $0 >= 0.999 ? .maximum : .fraction($0) }
    }

    private var source: Binding<SekaiInspectorSource> {
        Binding {
            switch options.filter {
            case .allLand: .allLand
            case .continent: .continent
            case .country, .sovereign: .country
            case .mapUnit, .features: .mapUnit
            }
        } set: { value in
            switch value {
            case .allLand: options.filter = .allLand
            case .continent: options.filter = .continent(SekaiAtlas.bundled.continents.first ?? "Asia")
            case .country: options.filter = .country(sortedCountries.first?.0 ?? "USA")
            case .mapUnit: options.filter = .mapUnit(SekaiAtlas.bundled.features.first?.id ?? "USA")
            }
        }
    }

    private var continent: Binding<String> {
        Binding { if case let .continent(value) = options.filter { value } else { "Asia" } }
            set: { options.filter = .continent($0) }
    }

    private var country: Binding<SekaiFeatureID> {
        Binding { if case let .country(value) = options.filter { value } else { "USA" } }
            set: { options.filter = .country($0) }
    }

    private var mapUnit: Binding<SekaiFeatureID> {
        Binding { if case let .mapUnit(value) = options.filter { value } else { "USA" } }
            set: { options.filter = .mapUnit($0) }
    }

    private var sortedCountries: [(SekaiFeatureID, String)] {
        SekaiAtlas.bundled.countries.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
    }

    private var performanceMode: Binding<Int> {
        Binding {
            switch options.performance { case .adaptive: 0; case .exact: 1; case .batterySaver: 2 }
        } set: {
            options.performance = switch $0 { case 1: .exact; case 2: .batterySaver; default: .adaptive() }
        }
    }

    private var projectionMode: Binding<Int> {
        Binding { if case .orthographic = camera.projection { 0 } else { 1 } }
            set: { camera.projection = $0 == 0 ? .orthographic : .perspective(fieldOfViewDegrees: 42) }
    }

    private var autoRotate: Binding<Bool> {
        Binding { interaction.autoRotationSpeed != 0 } set: { interaction.autoRotationSpeed = $0 ? 0.08 : 0 }
    }

    @ViewBuilder private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, icon: String) -> some View {
        #if os(tvOS)
        LabeledContent(title) {
            HStack {
                Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - (range.upperBound - range.lowerBound) / 20) } label: {
                    Image(systemName: "minus")
                }
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                    .monospacedDigit()
                Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + (range.upperBound - range.lowerBound) / 20) } label: {
                    Image(systemName: "plus")
                }
            }
        }
        #else
        LabeledContent {
            Slider(value: value, in: range)
                .frame(minWidth: 150)
        } label: {
            Label(title, systemImage: icon)
        }
        #endif
    }
}
