#if canImport(MetalKit) && !os(watchOS)
@preconcurrency import MetalKit
import SwiftUI

#if os(macOS)
private typealias SekaiRepresentable = NSViewRepresentable
#else
private typealias SekaiRepresentable = UIViewRepresentable
#endif

struct SekaiMetalView: SekaiRepresentable {
    let scene: SekaiPreparedScene?
    let camera: SekaiCamera
    let style: SekaiStyle
    let layers: [SekaiLayer]
    let colorScheme: ColorScheme
    let autoRotationSpeed: Double
    let performance: SekaiPerformancePolicy
    let onMetrics: @MainActor (SekaiRenderMetrics) -> Void

    func makeCoordinator() -> Renderer { Renderer() }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView { makeView(context: context) }
    func updateNSView(_ view: MTKView, context: Context) { update(view, renderer: context.coordinator) }
    #else
    func makeUIView(context: Context) -> MTKView { makeView(context: context) }
    func updateUIView(_ view: MTKView, context: Context) { update(view, renderer: context.coordinator) }
    #endif

    private func makeView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        #if !os(macOS)
        view.isOpaque = false
        view.backgroundColor = .clear
        #endif
        context.coordinator.configure(view)
        return view
    }

    private func update(_ view: MTKView, renderer: Renderer) {
        renderer.update(scene: scene, camera: camera, style: style, colorScheme: colorScheme,
                        autoRotationSpeed: autoRotationSpeed, performance: performance, onMetrics: onMetrics)
        let animates = autoRotationSpeed != 0
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.enableSetNeedsDisplay = !animates
        view.isPaused = !animates
        if !animates { view.draw() }
    }

    private var preferredFramesPerSecond: Int {
        switch performance {
        case let .adaptive(minimum): max(30, minimum)
        case .exact: 120
        case .batterySaver: 30
        }
    }

    @MainActor final class Renderer: NSObject, MTKViewDelegate {
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var linePipeline: MTLRenderPipelineState?
        private var device: MTLDevice?
        private var buffer: MTLBuffer?
        private var boundaryBuffer: MTLBuffer?
        private var boundaryFillBuffer: MTLBuffer?
        private var annotationBuffer: MTLBuffer?
        private var routeBuffer: MTLBuffer?
        private var count = 0
        private var boundaryCount = 0
        private var boundaryFillCount = 0
        private var annotationCount = 0
        private var routeCount = 0
        private var loadedScene: ObjectIdentifier?
        private var state = State.zero
        private let epoch = CACurrentMediaTime()
        private var metricEpoch = CACurrentMediaTime()
        private var metricFrames = 0
        private var metricsCallback: @MainActor (SekaiRenderMetrics) -> Void = { _ in }
        private var policy: SekaiPerformancePolicy = .adaptive()

        func configure(_ view: MTKView) {
            guard let device = view.device,
                  let library = try? device.makeDefaultLibrary(bundle: .module),
                  let vertex = library.makeFunction(name: "sekaiUnifiedParticleVertex"),
                  let fragment = library.makeFunction(name: "sekaiUnifiedParticleFragment") else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.fragmentFunction = library.makeFunction(name: "sekaiUnifiedLineFragment")
            linePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
            self.device = device
            queue = device.makeCommandQueue()
            view.delegate = self
        }

        func update(scene: SekaiPreparedScene?, camera: SekaiCamera, style: SekaiStyle,
                    colorScheme: ColorScheme, autoRotationSpeed: Double,
                    performance: SekaiPerformancePolicy,
                    onMetrics: @escaping @MainActor (SekaiRenderMetrics) -> Void) {
            policy = performance
            metricsCallback = onMetrics
            if let scene, loadedScene != ObjectIdentifier(scene) {
                loadedScene = ObjectIdentifier(scene)
                buffer = makeBuffer(scene.particles)
                boundaryBuffer = makeBuffer(scene.boundaries)
                boundaryFillBuffer = makeBuffer(scene.boundaryFills)
                annotationBuffer = makeBuffer(scene.annotations)
                routeBuffer = makeBuffer(scene.routes)
                count = buffer == nil ? 0 : scene.particles.count
                boundaryCount = boundaryBuffer == nil ? 0 : scene.boundaries.count
                boundaryFillCount = boundaryFillBuffer == nil ? 0 : scene.boundaryFills.count
                annotationCount = annotationBuffer == nil ? 0 : scene.annotations.count
                routeCount = routeBuffer == nil ? 0 : scene.routes.count
            }
            let resolved = style.particles.color.resolved(dark: colorScheme == .dark)
            let sun = SekaiVector3(SekaiCoordinate(
                latitude: style.environment.sunLatitude,
                longitude: style.environment.sunLongitude
            )).normalized()
            state = State(
                quaternion: SIMD4(Float(camera.orientation.x), Float(camera.orientation.y),
                                  Float(camera.orientation.z), Float(camera.orientation.w)),
                color: SIMD4(Float(resolved.red), Float(resolved.green), Float(resolved.blue),
                             Float(resolved.alpha * style.particles.opacity)),
                zoom: Float(camera.zoom), pointSize: Float(max(style.particles.minimumPixelDiameter, style.particles.size)),
                autoRotationSpeed: Float(autoRotationSpeed), projection: camera.projection.fieldOfViewDegrees == 0 ? 0 : 1,
                projectionScale: camera.projection.fieldOfViewDegrees == 0
                    ? 1 : Float(1 / tan(camera.projection.fieldOfViewDegrees * .pi / 360)),
                offset: SIMD2(Float(camera.offsetX), Float(camera.offsetY)),
                optical: SIMD4(Float(style.particles.brightness), Float(style.particles.highlight),
                               Float(style.particles.refraction), Float(style.particles.depthFade)),
                environment: SIMD4(
                    Float(sun.x), Float(sun.y), Float(sun.z),
                    style.environment.showsDayNightTerminator ? Float(style.environment.ambientLight) : -1
                ),
                boundaryColor: style.boundaries.strokeColor.metalColor(dark: colorScheme == .dark, opacity: style.boundaries.strokeOpacity),
                boundaryFillColor: style.boundaries.fillColor.metalColor(dark: colorScheme == .dark, opacity: style.boundaries.fillOpacity),
                boundarySize: Float(max(0.5, style.boundaries.strokeWidth)),
                boundaryOptical: SIMD4(1, Float(style.boundaries.highlight), Float(style.boundaries.refraction), 0.15),
                routeColor: style.routes.color.metalColor(opacity: style.routes.opacity),
                routeSize: Float(max(0.5, style.routes.width)),
                routeOptical: SIMD4(1, Float(style.routes.highlight), 0.45, 0.12),
                annotationColor: style.annotations.color.metalColor(opacity: style.annotations.opacity),
                annotationSize: Float(max(2, style.annotations.size * 9)),
                annotationOptical: SIMD4(1, Float(style.annotations.highlight), Float(style.annotations.halo), 0.08)
            )
        }

        private func makeBuffer(_ values: [PackedParticle]) -> MTLBuffer? {
            values.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress, !bytes.isEmpty else { return nil }
                return device?.makeBuffer(bytes: base, length: bytes.count, options: .storageModeShared)
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let queue,
                  let command = queue.makeCommandBuffer(), let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable, let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            var uniforms = Uniforms(
                quaternion: state.quaternion,
                color: state.color,
                viewport: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                offset: state.offset,
                zoom: state.zoom,
                pointSize: state.pointSize,
                elapsed: Float(CACurrentMediaTime() - epoch),
                autoRotationSpeed: state.autoRotationSpeed,
                projection: state.projection,
                projectionScale: state.projectionScale,
                optical: state.optical,
                environment: state.environment
            )
            encoder.setRenderPipelineState(pipeline)
            if let buffer, count > 0 {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
            }
            if let linePipeline {
                encoder.setRenderPipelineState(linePipeline)
                if let boundaryFillBuffer, boundaryFillCount > 0 {
                    uniforms.color = state.boundaryFillColor
                    encoder.setVertexBuffer(boundaryFillBuffer, offset: 0, index: 0)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: boundaryFillCount)
                }
                if let boundaryBuffer, boundaryCount > 0 {
                    uniforms.color = state.boundaryColor
                    uniforms.optical = state.boundaryOptical
                    encoder.setVertexBuffer(boundaryBuffer, offset: 0, index: 0)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: boundaryCount)
                    if state.boundarySize > 1 {
                        uniforms.pointSize = state.boundarySize
                        encoder.setRenderPipelineState(pipeline)
                        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: boundaryCount)
                        encoder.setRenderPipelineState(linePipeline)
                    }
                }
                if let routeBuffer, routeCount > 0 {
                    uniforms.color = state.routeColor
                    uniforms.optical = state.routeOptical
                    encoder.setVertexBuffer(routeBuffer, offset: 0, index: 0)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: routeCount)
                    uniforms.pointSize = state.routeSize
                    encoder.setRenderPipelineState(pipeline)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: routeCount)
                }
            }
            if let annotationBuffer, annotationCount > 0 {
                uniforms.color = state.annotationColor
                uniforms.pointSize = state.annotationSize
                uniforms.optical = state.annotationOptical
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBuffer(annotationBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: annotationCount)
            }
            encoder.endEncoding()
            command.present(drawable)
            command.commit()
            metricFrames += 1
            let now = CACurrentMediaTime()
            let duration = now - metricEpoch
            if duration >= 1 {
                let framesPerSecond = Double(metricFrames) / duration
                metricsCallback(SekaiRenderMetrics(
                    logicalParticleCount: count,
                    requestedParticleCount: count,
                    renderedParticleCount: count,
                    culledParticleCount: 0,
                    framesPerSecond: framesPerSecond,
                    frameTimeMilliseconds: framesPerSecond > 0 ? 1_000 / framesPerSecond : 0,
                    renderScale: 1,
                    levelOfDetail: 1,
                    policy: policy
                ))
                metricFrames = 0
                metricEpoch = now
            }
        }
    }
}

private struct Uniforms {
    var quaternion: SIMD4<Float>
    var color: SIMD4<Float>
    var viewport: SIMD2<Float>
    var offset: SIMD2<Float>
    var zoom: Float
    var pointSize: Float
    var elapsed: Float
    var autoRotationSpeed: Float
    var projection: UInt32
    var projectionScale: Float
    var optical: SIMD4<Float>
    var environment: SIMD4<Float>
}

private struct State {
    var quaternion: SIMD4<Float>
    var color: SIMD4<Float>
    var zoom: Float
    var pointSize: Float
    var autoRotationSpeed: Float
    var projection: UInt32
    var projectionScale: Float = 1
    var offset: SIMD2<Float> = .zero
    var optical: SIMD4<Float> = SIMD4(1, 0.7, 0.55, 0.28)
    var environment: SIMD4<Float> = SIMD4(0, 0, 1, -1)
    var boundaryColor: SIMD4<Float> = SIMD4(1, 1, 1, 0.8)
    var boundaryFillColor: SIMD4<Float> = SIMD4(1, 1, 1, 0.26)
    var boundarySize: Float = 1
    var boundaryOptical: SIMD4<Float> = SIMD4(1, 0.65, 0.5, 0.15)
    var routeColor: SIMD4<Float> = SIMD4(1, 0.35, 0.9, 0.9)
    var routeSize: Float = 1
    var routeOptical: SIMD4<Float> = SIMD4(1, 0.75, 0.45, 0.12)
    var annotationColor: SIMD4<Float> = SIMD4(1, 0.18, 0.16, 1)
    var annotationSize: Float = 8
    var annotationOptical: SIMD4<Float> = SIMD4(1, 0.8, 0.24, 0.08)
    static let zero = State(quaternion: SIMD4(0, 0, 0, 1), color: SIMD4(0, 0, 0, 1),
                            zoom: 1, pointSize: 1, autoRotationSpeed: 0, projection: 0)
}

private extension SekaiAdaptiveColor {
    func resolved(dark: Bool) -> SekaiColor {
        switch self {
        case let .fixed(value): value.normalized()
        case let .appearance(light, dark: darkValue): (dark ? darkValue : light).normalized()
        }
    }

    func metalColor(dark: Bool, opacity: Double) -> SIMD4<Float> {
        resolved(dark: dark).metalColor(opacity: opacity)
    }
}

private extension SekaiColor {
    func metalColor(opacity: Double) -> SIMD4<Float> {
        let value = normalized()
        return SIMD4(Float(value.red), Float(value.green), Float(value.blue), Float(value.alpha * opacity))
    }
}
#else
import SwiftUI

struct SekaiMetalView: View {
    let scene: SekaiPreparedScene?
    let camera: SekaiCamera
    let style: SekaiStyle
    let layers: [SekaiLayer]
    let colorScheme: ColorScheme
    let autoRotationSpeed: Double
    let performance: SekaiPerformancePolicy
    let onMetrics: @MainActor (SekaiRenderMetrics) -> Void

    var body: some View {
        Canvas { context, size in
            guard let scene else { return }
            let radius = min(size.width, size.height) * 0.5
            for particle in scene.particles.prefix(4_096) {
                let vector = SekaiVector3(x: Double(particle.position.x), y: Double(particle.position.y), z: Double(particle.position.z))
                    .rotated(by: camera.orientation)
                guard vector.z > 0 else { continue }
                let point = CGPoint(x: size.width / 2 + vector.x * radius * camera.zoom,
                                    y: size.height / 2 - vector.y * radius * camera.zoom)
                context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 1, height: 1)), with: .color(.primary))
            }
        }
    }
}
#endif
