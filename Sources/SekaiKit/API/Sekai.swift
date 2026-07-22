import SwiftUI

/// A native SwiftUI globe backed by Sekai's unified offline atlas.
public struct Sekai: View {
    @Binding private var camera: SekaiCamera
    private let style: SekaiStyle
    private let interaction: SekaiInteractionOptions
    private let performance: SekaiPerformancePolicy
    private let onMetrics: @MainActor (SekaiRenderMetrics) -> Void
    private let layers: [SekaiLayer]

    @State private var scene: SekaiPreparedScene?
    @State private var dragStart: SekaiQuaternion?
    @State private var zoomStart: Double?
    @State private var interactionPausedAutoRotation = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        camera: Binding<SekaiCamera>,
        style: SekaiStyle = .standard,
        interaction: SekaiInteractionOptions = .standard,
        performance: SekaiPerformancePolicy = .adaptive(),
        metrics: Binding<SekaiRenderMetrics>? = nil,
        @SekaiContentBuilder content: () -> [SekaiLayer] = { [SekaiLayer.landParticles()] }
    ) {
        _camera = camera
        self.style = style
        self.interaction = interaction
        self.performance = performance
        onMetrics = { value in metrics?.wrappedValue = value }
        layers = content()
    }

    public var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            ZStack {
                style.environment.backgroundColor.swiftUIColor
                if style.environment.showsStars {
                    SekaiStarField(density: style.environment.starDensity)
                }
                globeSurface
                    .overlay {
                        Circle().stroke(globeRim, lineWidth: max(0, style.globe.rimWidth))
                    }
                    .brightness((style.globe.lighting - 1) * 0.16 - style.globe.darkness * 0.45)
                    .shadow(color: style.globe.glowColor.swiftUIColor.opacity(style.globe.glowIntensity * 0.45),
                            radius: diameter * style.globe.glowIntensity * 0.08)
                    .shadow(color: style.environment.atmosphereColor.swiftUIColor.opacity(style.environment.atmosphereIntensity),
                            radius: diameter * style.environment.atmosphereThickness)
                SekaiMetalView(
                    scene: scene,
                    camera: camera,
                    style: style,
                    layers: layers,
                    colorScheme: colorScheme,
                    autoRotationSpeed: reduceMotion || interactionPausedAutoRotation ? 0 : interaction.autoRotationSpeed,
                    performance: performance,
                    onMetrics: onMetrics
                )
                .clipShape(Circle())
            }
            .frame(width: diameter, height: diameter)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .contentShape(Circle())
            .gesture(rotationGesture)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(doubleTapGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sekai globe")
            .accessibilityValue("Zoom \(Int(camera.zoom * 100)) percent")
            #if os(tvOS)
            .focusable()
            .onMoveCommand(perform: moveCamera)
            .onPlayPauseCommand { interactionPausedAutoRotation.toggle() }
            #endif
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: sceneKey) {
            let key = sceneKey
            let limit = automaticParticleLimit
            let prepared = await Task.detached(priority: .userInitiated) {
                SekaiPreparedScene.prepare(layers: key, defaultStyle: style, automaticLimit: limit)
            }.value
            guard !Task.isCancelled else { return }
            scene = prepared
        }
    }

    @ViewBuilder private var globeSurface: some View {
        #if os(visionOS)
        Circle()
            .fill(style.globe.surfaceColor.swiftUIColor.opacity(style.globe.opacity * 0.12))
            .glassBackgroundEffect(in: Circle())
        #else
        Circle()
            .fill(.clear)
            .glassEffect(glass, in: .circle)
        #endif
    }

    #if !os(visionOS)
    private var glass: Glass {
        let color = style.globe.surfaceColor.swiftUIColor.opacity(style.globe.opacity)
        return switch style.globe.material {
        case .clear: .clear.tint(color)
        case .regular: .regular.tint(color)
        }
    }
    #endif

    private var globeRim: Color {
        style.globe.glowColor.swiftUIColor.opacity(style.globe.rimOpacity)
    }

    private var sceneKey: SekaiSceneKey {
        SekaiSceneKey(sourceLayers: layers, particleLayers: layers.compactMap { layer in
            if case let .particles(_, filter, overrideStyle) = layer {
                return .init(filter: filter, density: overrideStyle?.density ?? style.particles.density)
            }
            return nil
        }, defaultAnnotationElevation: style.annotations.elevation, defaultRouteElevation: style.routes.elevation)
    }

    private var automaticParticleLimit: Int {
        switch performance {
        case .exact: SekaiAtlas.maximumParticleCount
        case .batterySaver: 16_384
        case .adaptive: 65_536
        }
    }

    private var rotationGesture: some Gesture {
        #if os(tvOS)
        TapGesture().onEnded {}
        #else
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard interaction.allowsRotation else { return }
                let start = dragStart ?? camera.orientation
                if dragStart == nil {
                    dragStart = start
                    if interaction.stopsAutoRotationOnInteraction { interactionPausedAutoRotation = true }
                }
                let yaw = SekaiQuaternion.axisAngle(x: 0, y: 1, z: 0, radians: value.translation.width * .pi / 360)
                let pitch = SekaiQuaternion.axisAngle(x: 1, y: 0, z: 0, radians: value.translation.height * .pi / 360)
                camera.orientation = pitch * yaw * start
            }
            .onEnded { _ in dragStart = nil }
        #endif
    }

    private var zoomGesture: some Gesture {
        #if os(watchOS) || os(tvOS)
        TapGesture().onEnded {}
        #else
        MagnifyGesture()
            .onChanged { value in
                guard interaction.allowsZoom else { return }
                let start = zoomStart ?? camera.zoom
                if zoomStart == nil {
                    zoomStart = start
                    if interaction.stopsAutoRotationOnInteraction { interactionPausedAutoRotation = true }
                }
                camera.zoom = start * value.magnification
                camera.clamp(to: interaction.cameraBounds)
            }
            .onEnded { _ in zoomStart = nil }
        #endif
    }

    #if os(tvOS)
    private func moveCamera(_ direction: MoveCommandDirection) {
        guard interaction.allowsRotation else { return }
        let radians = 8.0 * Double.pi / 180
        let delta: SekaiQuaternion = switch direction {
        case .left: .axisAngle(x: 0, y: 1, z: 0, radians: -radians)
        case .right: .axisAngle(x: 0, y: 1, z: 0, radians: radians)
        case .up: .axisAngle(x: 1, y: 0, z: 0, radians: -radians)
        case .down: .axisAngle(x: 1, y: 0, z: 0, radians: radians)
        @unknown default: .identity
        }
        camera.orientation = delta * camera.orientation
        if interaction.stopsAutoRotationOnInteraction { interactionPausedAutoRotation = true }
    }
    #endif

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2).onEnded {
            guard interaction.allowsZoom else { return }
            camera.zoom *= interaction.doubleTapZoom
            camera.clamp(to: interaction.cameraBounds)
            if interaction.stopsAutoRotationOnInteraction { interactionPausedAutoRotation = true }
        }
    }
}

private struct SekaiStarField: View {
    let density: Double

    var body: some View {
        Canvas { context, size in
            let count = Int(220 * min(max(density, 0), 1))
            for index in 0..<count {
                let x = pseudoRandom(index * 2) * size.width
                let y = pseudoRandom(index * 2 + 1) * size.height
                let diameter = 0.6 + pseudoRandom(index * 3 + 7) * 1.2
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                             with: .color(.white.opacity(0.35 + pseudoRandom(index + 11) * 0.5)))
            }
        }
        .allowsHitTesting(false)
    }

    private func pseudoRandom(_ value: Int) -> Double {
        let mixed = UInt64(truncatingIfNeeded: value &* 1_103_515_245 &+ 12_345)
        return Double(mixed % 10_000) / 10_000
    }
}

extension SekaiColor {
    var swiftUIColor: Color {
        let value = normalized()
        return Color(red: value.red, green: value.green, blue: value.blue, opacity: value.alpha)
    }
}

struct SekaiSceneKey: Equatable {
    struct Layer: Equatable, Sendable {
        let filter: SekaiRegionFilter
        let density: SekaiParticleDensity
    }
    let sourceLayers: [SekaiLayer]
    let particleLayers: [Layer]
    let defaultAnnotationElevation: Double
    let defaultRouteElevation: Double

    static func == (left: Self, right: Self) -> Bool {
        guard left.particleLayers == right.particleLayers,
              left.defaultAnnotationElevation == right.defaultAnnotationElevation,
              left.defaultRouteElevation == right.defaultRouteElevation,
              left.sourceLayers.count == right.sourceLayers.count else { return false }
        return zip(left.sourceLayers, right.sourceLayers).allSatisfy(layerGeometryEquals)
    }

    private static func layerGeometryEquals(_ pair: (SekaiLayer, SekaiLayer)) -> Bool {
        switch pair {
        case let (.particles(_, left, _), .particles(_, right, _)),
             let (.boundaries(_, left, _), .boundaries(_, right, _)),
             let (.labels(_, left, _), .labels(_, right, _)):
            left == right
        case let (.annotations(_, left), .annotations(_, right)):
            left.map { ($0.coordinate, $0.style?.elevation) }.elementsEqual(
                right.map { ($0.coordinate, $0.style?.elevation) }, by: ==
            )
        case let (.routes(_, left), .routes(_, right)):
            left.map { ($0.from, $0.to, $0.curve, $0.style?.elevation) }.elementsEqual(
                right.map { ($0.from, $0.to, $0.curve, $0.style?.elevation) }, by: ==
            )
        case let (.polylines(_, left), .polylines(_, right)):
            left.map { ($0.coordinates, $0.style.elevation) }.elementsEqual(
                right.map { ($0.coordinates, $0.style.elevation) }, by: ==
            )
        case let (.userLocation(_, left), .userLocation(_, right)):
            left.coordinate == right.coordinate && left.style?.elevation == right.style?.elevation
        case let (.physical(_, left), .physical(_, right)): left == right
        case let (.polygons(_, left), .polygons(_, right)): left == right
        case let (.circles(_, left), .circles(_, right)): left == right
        case let (.heatmap(_, left), .heatmap(_, right)): left == right
        case let (.texture(_, leftName, _), .texture(_, rightName, _)): leftName == rightName
        default: false
        }
    }
}

final class SekaiPreparedScene: @unchecked Sendable {
    let particles: [PackedParticle]
    let boundaryFills: [PackedParticle]
    let boundaries: [PackedParticle]
    let annotations: [PackedParticle]
    let routes: [PackedParticle]

    init(particles: [PackedParticle], boundaryFills: [PackedParticle], boundaries: [PackedParticle], annotations: [PackedParticle], routes: [PackedParticle]) {
        self.particles = particles
        self.boundaryFills = boundaryFills
        self.boundaries = boundaries
        self.annotations = annotations
        self.routes = routes
    }

    static func prepare(layers: SekaiSceneKey, defaultStyle: SekaiStyle, automaticLimit: Int) -> SekaiPreparedScene {
        let atlas = SekaiAtlas.bundled
        let particles = layers.particleLayers.flatMap {
            atlas.packedParticles(matching: $0.filter, density: $0.density, automaticLimit: automaticLimit)
        }
        var boundaries: [PackedParticle] = []
        var boundaryFills: [PackedParticle] = []
        var annotations: [PackedParticle] = []
        var routes: [PackedParticle] = []
        for layer in layers.sourceLayers {
            switch layer {
            case let .boundaries(_, filter, _):
                boundaryFills += atlas.packedBoundaryFillVertices(matching: filter, levelOfDetail: 1)
                boundaries += atlas.packedBoundaryVertices(matching: filter, levelOfDetail: 1)
            case let .annotations(_, values):
                annotations += values.map { PackedParticle($0.coordinate, elevation: $0.style?.elevation ?? defaultStyle.annotations.elevation) }
            case let .userLocation(_, annotation):
                annotations.append(PackedParticle(annotation.coordinate, elevation: annotation.style?.elevation ?? defaultStyle.annotations.elevation))
            case let .routes(_, values):
                routes += values.flatMap { routeVertices($0, defaultStyle: defaultStyle.routes) }
            case let .polylines(_, values):
                routes += values.flatMap { linePairs($0.coordinates, elevation: $0.style.elevation) }
            default: break
            }
        }
        return SekaiPreparedScene(particles: particles, boundaryFills: boundaryFills, boundaries: boundaries, annotations: annotations, routes: routes)
    }

    private static func routeVertices(_ route: SekaiRoute, defaultStyle: SekaiRouteStyle) -> [PackedParticle] {
        let style = route.style ?? defaultStyle
        let coordinates: [SekaiCoordinate]
        switch route.curve {
        case let .custom(values): coordinates = values
        case .rhumb: coordinates = stride(from: 0.0, through: 1.0, by: 1.0 / 64).map {
            SekaiCoordinate(latitude: route.from.latitude + (route.to.latitude - route.from.latitude) * $0,
                            longitude: route.from.longitude + (route.to.longitude - route.from.longitude) * $0)
        }
        case .greatCircle:
            let start = SekaiVector3(route.from)
            let end = SekaiVector3(route.to)
            coordinates = stride(from: 0.0, through: 1.0, by: 1.0 / 64).map { progress in
                let point = SekaiVector3.slerp(start, end, progress: progress)
                return SekaiCoordinate(latitude: asin(point.y) * 180 / .pi, longitude: atan2(point.x, point.z) * 180 / .pi)
            }
        }
        return linePairs(coordinates, elevation: style.elevation)
    }

    private static func linePairs(_ coordinates: [SekaiCoordinate], elevation: Double) -> [PackedParticle] {
        guard coordinates.count > 1 else { return [] }
        return zip(coordinates, coordinates.dropFirst()).flatMap {
            [PackedParticle($0.0, elevation: elevation), PackedParticle($0.1, elevation: elevation)]
        }
    }
}
