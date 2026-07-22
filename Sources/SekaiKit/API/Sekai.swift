import SwiftUI

/// A native SwiftUI globe backed by Sekai's unified offline atlas.
public struct Sekai: View {
    @Binding private var camera: SekaiCamera
    private let selection: Binding<SekaiSelection?>?
    private let hoverSelection: Binding<SekaiSelection?>?
    private let style: SekaiStyle
    private let interaction: SekaiInteractionOptions
    private let performance: SekaiPerformancePolicy
    private let onMetrics: @MainActor (SekaiRenderMetrics) -> Void
    private let layers: [SekaiLayer]

    @State private var scene: SekaiPreparedScene?
    @State private var dragStart: SekaiQuaternion?
    @State private var zoomStart: Double?
    @State private var interactionPausedAutoRotation = false
    @State private var selectedCoordinate: SekaiCoordinate?
    @State private var inertiaTask: Task<Void, Never>?
    @State private var rotationClock = SekaiRotationClock()
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
        self.init(
            camera: camera,
            selection: nil,
            hoverSelection: nil,
            style: style,
            interaction: interaction,
            performance: performance,
            metrics: metrics,
            layers: content()
        )
    }

    public init(
        camera: Binding<SekaiCamera>,
        selection: Binding<SekaiSelection?>,
        hoverSelection: Binding<SekaiSelection?>? = nil,
        style: SekaiStyle = .standard,
        interaction: SekaiInteractionOptions = .standard,
        performance: SekaiPerformancePolicy = .adaptive(),
        metrics: Binding<SekaiRenderMetrics>? = nil,
        @SekaiContentBuilder content: () -> [SekaiLayer] = { [SekaiLayer.landParticles()] }
    ) {
        self.init(
            camera: camera,
            selection: selection,
            hoverSelection: hoverSelection,
            style: style,
            interaction: interaction,
            performance: performance,
            metrics: metrics,
            layers: content()
        )
    }

    public init(
        camera: Binding<SekaiCamera>,
        hoverSelection: Binding<SekaiSelection?>,
        style: SekaiStyle = .standard,
        interaction: SekaiInteractionOptions = .standard,
        performance: SekaiPerformancePolicy = .adaptive(),
        metrics: Binding<SekaiRenderMetrics>? = nil,
        @SekaiContentBuilder content: () -> [SekaiLayer] = { [SekaiLayer.landParticles()] }
    ) {
        self.init(
            camera: camera,
            selection: nil,
            hoverSelection: hoverSelection,
            style: style,
            interaction: interaction,
            performance: performance,
            metrics: metrics,
            layers: content()
        )
    }

    private init(
        camera: Binding<SekaiCamera>,
        selection: Binding<SekaiSelection?>?,
        hoverSelection: Binding<SekaiSelection?>?,
        style: SekaiStyle,
        interaction: SekaiInteractionOptions,
        performance: SekaiPerformancePolicy,
        metrics: Binding<SekaiRenderMetrics>?,
        layers: [SekaiLayer]
    ) {
        _camera = camera
        self.selection = selection
        self.hoverSelection = hoverSelection
        self.style = style
        self.interaction = interaction
        self.performance = performance
        onMetrics = { value in metrics?.wrappedValue = value }
        self.layers = layers
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
                    .shadow(
                        color: style.globe.glowColor.swiftUIColor.opacity(style.globe.glowIntensity * 0.45),
                        radius: diameter * style.globe.glowIntensity * 0.08
                    )
                    .shadow(
                        color: style.environment.atmosphereColor.swiftUIColor.opacity(style.environment.atmosphereIntensity),
                        radius: diameter * style.environment.atmosphereThickness
                    )
                SekaiMetalView(
                    scene: scene,
                    camera: camera,
                    style: style,
                    layers: layers,
                    colorScheme: colorScheme,
                    autoRotationSpeed: effectiveAutoRotationSpeed,
                    rotationClock: rotationClock,
                    performance: performance,
                    onMetrics: onMetrics
                )
                .clipShape(Circle())
                SekaiLabelOverlay(
                    scene: scene,
                    camera: camera,
                    defaultStyle: style,
                    layers: layers,
                    colorScheme: colorScheme,
                    autoRotationSpeed: effectiveAutoRotationSpeed,
                    rotationClock: rotationClock
                )
                .clipShape(Circle())
                SekaiSelectionIndicator(
                    coordinate: selectedCoordinate,
                    camera: camera,
                    autoRotationSpeed: effectiveAutoRotationSpeed,
                    rotationClock: rotationClock
                )
            }
            .frame(width: diameter, height: diameter)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .contentShape(Circle())
            .gesture(rotationGesture)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(doubleTapGesture)
            .simultaneousGesture(selectionGesture(size: CGSize(width: diameter, height: diameter)))
            #if !os(watchOS) && !os(tvOS)
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    hoverSelection?.wrappedValue = pick(
                        at: location,
                        size: CGSize(width: diameter, height: diameter)
                    )?.selection
                case .ended:
                    hoverSelection?.wrappedValue = nil
                }
            }
            #endif
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sekai globe")
            .accessibilityValue(accessibilityValue)
            #if os(tvOS)
            .focusable()
            .onMoveCommand(perform: moveCamera)
            .onPlayPauseCommand { interactionPausedAutoRotation.toggle() }
            #endif
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: sceneKey) {
            let key = sceneKey
            let prepared = await SekaiSceneCache.shared.scene(for: key, style: style)
            guard !Task.isCancelled else { return }
            scene = prepared
        }
        .onAppear { synchronizeSelectionCoordinate() }
        .onDisappear { inertiaTask?.cancel() }
        .onChange(of: selection?.wrappedValue) { _, value in
            if value == nil { selectedCoordinate = nil }
            else if let value { selectedCoordinate = coordinate(for: value) }
        }
        .onChange(of: layers) { _, _ in synchronizeSelectionCoordinate() }
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

    private var effectiveAutoRotationSpeed: Double {
        reduceMotion || interactionPausedAutoRotation ? 0 : interaction.autoRotationSpeed
    }

    private var accessibilityValue: String {
        let selected: String
        switch selection?.wrappedValue {
        case let .atlas(id): selected = ", selected \(SekaiAtlas.bundled.feature(id: id)?.name ?? id.rawValue)"
        case let .annotation(id): selected = ", selected marker \(id)"
        case let .route(id): selected = ", selected route \(id)"
        case let .custom(_, featureID): selected = ", selected \(featureID)"
        case nil: selected = ""
        }
        return "Zoom \(Int(camera.zoom * 100)) percent\(selected)"
    }

    private var sceneKey: SekaiSceneKey {
        SekaiSceneKey(
            sourceLayers: layers,
            particleLayers: layers.compactMap { layer in
                if case let .particles(id, filter, overrideStyle) = layer {
                    return .init(
                        id: id,
                        filter: filter,
                        density: overrideStyle?.density ?? style.particles.density
                    )
                }
                return nil
            },
            defaultAnnotationElevation: style.annotations.elevation,
            defaultRouteElevation: style.routes.elevation,
            defaultRouteProgress: style.routes.progress,
            defaultRoutePattern: style.routes.pattern,
            defaultRouteEndpointSize: style.routes.endpointSize,
            automaticParticleLimit: automaticParticleLimit
        )
    }

    private var automaticParticleLimit: Int {
        switch performance {
        case .exact: SekaiAtlas.maximumParticleCount
        case .batterySaver: 32_768
        case .adaptive: 262_144
        }
    }

    private var rotationGesture: some Gesture {
        #if os(tvOS)
        TapGesture().onEnded {}
        #else
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard interaction.allowsRotation else { return }
                let start = dragStart ?? camera.orientation
                if dragStart == nil {
                    stopInertia()
                    dragStart = start
                    if interaction.stopsAutoRotationOnInteraction { interactionPausedAutoRotation = true }
                }
                camera.orientation = dragRotation(value.translation) * start
            }
            .onEnded { value in
                dragStart = nil
                startInertia(
                    horizontal: value.predictedEndTranslation.width - value.translation.width,
                    vertical: value.predictedEndTranslation.height - value.translation.height
                )
            }
        #endif
    }

    private func dragRotation(_ translation: CGSize) -> SekaiQuaternion {
        let yaw = SekaiQuaternion.axisAngle(
            x: 0, y: 1, z: 0,
            radians: Double(translation.width) * .pi / 360
        )
        let pitch = SekaiQuaternion.axisAngle(
            x: 1, y: 0, z: 0,
            radians: Double(translation.height) * .pi / 360
        )
        return pitch * yaw
    }

    private func startInertia(horizontal: CGFloat, vertical: CGFloat) {
        let retention = min(max(interaction.inertia, 0), 0.98)
        guard retention > 0, !reduceMotion else { return }
        var horizontalVelocity = Double(horizontal) * .pi / 3_600
        var verticalVelocity = Double(vertical) * .pi / 3_600
        let magnitude = hypot(horizontalVelocity, verticalVelocity)
        guard magnitude > 0.000_2 else { return }
        if magnitude > 0.08 {
            let scale = 0.08 / magnitude
            horizontalVelocity *= scale
            verticalVelocity *= scale
        }
        inertiaTask = Task { @MainActor in
            while !Task.isCancelled, hypot(horizontalVelocity, verticalVelocity) > 0.000_12 {
                let yaw = SekaiQuaternion.axisAngle(x: 0, y: 1, z: 0, radians: horizontalVelocity)
                let pitch = SekaiQuaternion.axisAngle(x: 1, y: 0, z: 0, radians: verticalVelocity)
                camera.orientation = pitch * yaw * camera.orientation
                horizontalVelocity *= retention
                verticalVelocity *= retention
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopInertia() {
        inertiaTask?.cancel()
        inertiaTask = nil
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
                    stopInertia()
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
            stopInertia()
            camera.zoom *= interaction.doubleTapZoom
            camera.clamp(to: interaction.cameraBounds)
            if interaction.stopsAutoRotationOnInteraction { interactionPausedAutoRotation = true }
        }
    }

    private func selectionGesture(size: CGSize) -> some Gesture {
        #if os(watchOS) || os(tvOS)
        return TapGesture().onEnded {}
        #else
        return SpatialTapGesture(count: 1).onEnded { value in
            guard interaction.allowsSelection else { return }
            let result = pick(at: value.location, size: size)
            selection?.wrappedValue = result?.selection
            selectedCoordinate = result?.coordinate
        }
        #endif
    }

    private func pick(at point: CGPoint, size: CGSize) -> SekaiPickResult? {
        guard interaction.allowsSelection, let scene else { return nil }
        let spin = rotationClock.angle(speed: effectiveAutoRotationSpeed)
        return scene.pick(
            at: point,
            context: SekaiProjectionContext(size: size, camera: camera, spinAngle: spin)
        )
    }

    private func coordinate(for selection: SekaiSelection) -> SekaiCoordinate? {
        switch selection {
        case let .atlas(id):
            return SekaiAtlas.bundled.feature(id: id)?.labelCoordinate
        case let .annotation(id):
            for layer in layers {
                switch layer {
                case let .annotations(_, values):
                    if let annotation = values.first(where: { $0.id == id }) { return annotation.coordinate }
                case let .userLocation(_, annotation) where annotation.id == id:
                    return annotation.coordinate
                default: break
                }
            }
        case let .route(id):
            for layer in layers {
                if case let .routes(_, values) = layer,
                   let route = values.first(where: { $0.id == id }) {
                    return SekaiVector3.slerp(
                        SekaiVector3(route.from),
                        SekaiVector3(route.to),
                        progress: 0.5
                    ).coordinate
                }
            }
        case let .custom(layerID, featureID):
            for layer in layers where layer.id == layerID {
                switch layer {
                case let .polylines(_, values): return values.first { $0.id == featureID }?.coordinates.first
                case let .polygons(_, values): return values.first { $0.id == featureID }?.rings.first?.first
                case let .circles(_, values): return values.first { $0.id == featureID }?.center
                case let .heatmap(_, values): return values.first { $0.id == featureID }?.coordinate
                default: break
                }
            }
        }
        return nil
    }

    private func synchronizeSelectionCoordinate() {
        selectedCoordinate = selection?.wrappedValue.flatMap(coordinate(for:))
    }
}

private struct SekaiSelectionIndicator: View {
    let coordinate: SekaiCoordinate?
    let camera: SekaiCamera
    let autoRotationSpeed: Double
    let rotationClock: SekaiRotationClock

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: autoRotationSpeed == 0)) { timeline in
            GeometryReader { geometry in
                if let coordinate,
                   let projected = SekaiProjectionContext(
                       size: geometry.size,
                       camera: camera,
                       spinAngle: rotationClock.angle(
                           at: timeline.date.timeIntervalSinceReferenceDate,
                           speed: autoRotationSpeed
                       )
                   ).project(coordinate, elevation: 0.035) {
                    Circle()
                        .fill(.clear)
                        #if os(visionOS)
                        .glassBackgroundEffect(in: Circle())
                        #else
                        .glassEffect(.clear.tint(.accentColor), in: .circle)
                        #endif
                        .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
                        .frame(width: 18, height: 18)
                        .position(projected.point)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                    with: .color(.white.opacity(0.35 + pseudoRandom(index + 11) * 0.5))
                )
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
