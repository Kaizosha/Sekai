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
    let rotationClock: SekaiRotationClock
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
        view.colorPixelFormat = .bgra8Unorm_srgb
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
        renderer.update(
            scene: scene,
            camera: camera,
            style: style,
            layers: layers,
            colorScheme: colorScheme,
            autoRotationSpeed: autoRotationSpeed,
            rotationClock: rotationClock,
            performance: performance,
            onMetrics: onMetrics
        )
        let animates = autoRotationSpeed != 0
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.enableSetNeedsDisplay = !animates
        view.isPaused = !animates
        if !animates { view.draw() }
    }

    private var preferredFramesPerSecond: Int {
        switch performance {
        case let .adaptive(minimum): min(max(30, minimum), 120)
        case .exact: 120
        case .batterySaver: 30
        }
    }

    @MainActor final class Renderer: NSObject, MTKViewDelegate {
        private struct ParticleGPU {
            let batch: SekaiPreparedParticleBatch
            let buffer: MTLBuffer?
        }

        private struct SurfaceGPU {
            let batch: SekaiPreparedSurfaceBatch
            let fillBuffers: [MTLBuffer?]
            let lineBuffers: [MTLBuffer?]
        }

        private struct LineGPU {
            let batch: SekaiPreparedLineBatch
            let buffer: MTLBuffer?
        }

        private struct PointGPU {
            let batch: SekaiPreparedPointBatch
            let buffer: MTLBuffer?
        }

        private var queue: MTLCommandQueue?
        private var particlePipeline: MTLRenderPipelineState?
        private var linePipeline: MTLRenderPipelineState?
        private var device: MTLDevice?
        private var particleBatches: [ParticleGPU] = []
        private var surfaceBatches: [SurfaceGPU] = []
        private var lineBatches: [LineGPU] = []
        private var pointBatches: [PointGPU] = []
        private var drawOrder: [SekaiPreparedDrawReference] = []
        private var loadedScene: ObjectIdentifier?
        private var camera = SekaiCamera.standard
        private var style = SekaiStyle.standard
        private var visualStyles = SekaiLayerVisualStyles(layers: [])
        private var isDark = false
        private var autoRotationSpeed = 0.0
        private var rotationClock: SekaiRotationClock?
        private var metricsCallback: @MainActor (SekaiRenderMetrics) -> Void = { _ in }
        private var policy: SekaiPerformancePolicy = .adaptive()
        private var adaptiveQuality = 1.0
        private var adaptiveLOD = 0
        private var lowFrameWindows = 0
        private var highFrameWindows = 0
        private var metricEpoch = Date.timeIntervalSinceReferenceDate
        private var metricFrames = 0

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
            particlePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.fragmentFunction = library.makeFunction(name: "sekaiUnifiedLineFragment")
            linePipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
            self.device = device
            queue = device.makeCommandQueue()
            view.delegate = self
        }

        func update(
            scene: SekaiPreparedScene?,
            camera: SekaiCamera,
            style: SekaiStyle,
            layers: [SekaiLayer],
            colorScheme: ColorScheme,
            autoRotationSpeed: Double,
            rotationClock: SekaiRotationClock,
            performance: SekaiPerformancePolicy,
            onMetrics: @escaping @MainActor (SekaiRenderMetrics) -> Void
        ) {
            if policy != performance {
                policy = performance
                resetAdaptiveState()
            }
            metricsCallback = onMetrics
            self.camera = camera
            self.style = style
            visualStyles = SekaiLayerVisualStyles(layers: layers)
            isDark = colorScheme == .dark
            self.autoRotationSpeed = autoRotationSpeed
            self.rotationClock = rotationClock

            if let scene, loadedScene != ObjectIdentifier(scene) {
                loadedScene = ObjectIdentifier(scene)
                particleBatches = scene.particleBatches.map { ParticleGPU(batch: $0, buffer: makeBuffer($0.vertices)) }
                surfaceBatches = scene.surfaceBatches.map { batch in
                    SurfaceGPU(
                        batch: batch,
                        fillBuffers: batch.fillVerticesByLevelOfDetail.map(makeBuffer),
                        lineBuffers: batch.lineVerticesByLevelOfDetail.map(makeBuffer)
                    )
                }
                lineBatches = scene.lineBatches.map { LineGPU(batch: $0, buffer: makeBuffer($0.vertices)) }
                pointBatches = scene.pointBatches.map { PointGPU(batch: $0, buffer: makeBuffer($0.vertices)) }
                drawOrder = scene.drawOrder
            } else if scene == nil {
                loadedScene = nil
                particleBatches = []
                surfaceBatches = []
                lineBatches = []
                pointBatches = []
                drawOrder = []
            }
        }

        private func resetAdaptiveState() {
            lowFrameWindows = 0
            highFrameWindows = 0
            switch policy {
            case .exact:
                adaptiveQuality = 1
                adaptiveLOD = 0
            case .batterySaver:
                adaptiveQuality = 0.25
                adaptiveLOD = 2
            case .adaptive:
                adaptiveQuality = 1
                adaptiveLOD = 0
            }
        }

        private func makeBuffer(_ values: [PackedParticle]) -> MTLBuffer? {
            values.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress, !bytes.isEmpty else { return nil }
                return device?.makeBuffer(bytes: base, length: bytes.count, options: .storageModeShared)
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let particlePipeline, let linePipeline, let queue,
                  let command = queue.makeCommandBuffer(),
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }

            var uniforms = baseUniforms(view: view)
            var submittedParticles = 0
            let logicalParticles = particleBatches.reduce(0) { $0 + $1.batch.vertices.count }

            for reference in drawOrder {
                switch reference {
                case let .particles(index):
                    guard particleBatches.indices.contains(index) else { continue }
                    let gpu = particleBatches[index]
                    guard let buffer = gpu.buffer else { continue }
                    let particleStyle = visualStyles.particles[gpu.batch.layerID]
                        ?? gpu.batch.styleOverride
                        ?? style.particles
                    let count = min(
                        gpu.batch.vertices.count,
                        max(gpu.batch.vertices.isEmpty ? 0 : 1, Int(Double(gpu.batch.vertices.count) * adaptiveQuality))
                    )
                    guard count > 0 else { continue }
                    submittedParticles += count
                    apply(particleStyle, to: &uniforms)
                    encoder.setRenderPipelineState(particlePipeline)
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)

                case let .surface(index):
                    guard surfaceBatches.indices.contains(index) else { continue }
                    let gpu = surfaceBatches[index]
                    let boundaryStyle = visualStyles.boundaries[gpu.batch.layerID]
                        ?? gpu.batch.styleOverride
                        ?? style.boundaries
                    let level = min(adaptiveLOD, max(gpu.lineBuffers.count - 1, 0))
                    if gpu.batch.fillVerticesByLevelOfDetail.indices.contains(level),
                       let buffer = gpu.fillBuffers[level] {
                        applyBoundaryFill(boundaryStyle, to: &uniforms)
                        encoder.setRenderPipelineState(linePipeline)
                        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        encoder.drawPrimitives(
                            type: .triangle,
                            vertexStart: 0,
                            vertexCount: gpu.batch.fillVerticesByLevelOfDetail[level].count
                        )
                    }
                    if gpu.batch.lineVerticesByLevelOfDetail.indices.contains(level),
                       let buffer = gpu.lineBuffers[level] {
                        applyBoundaryLine(boundaryStyle, to: &uniforms)
                        encoder.setRenderPipelineState(linePipeline)
                        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        let count = gpu.batch.lineVerticesByLevelOfDetail[level].count
                        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: count)
                        if boundaryStyle.strokeWidth > 1 {
                            encoder.setRenderPipelineState(particlePipeline)
                            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
                        }
                    }

                case let .line(index):
                    guard lineBatches.indices.contains(index) else { continue }
                    let gpu = lineBatches[index]
                    guard let buffer = gpu.buffer, !gpu.batch.vertices.isEmpty else { continue }
                    let routeStyle = gpu.batch.styleOverride ?? style.routes
                    apply(routeStyle, to: &uniforms)
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.setRenderPipelineState(linePipeline)
                    encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: gpu.batch.vertices.count)
                    encoder.setRenderPipelineState(particlePipeline)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gpu.batch.vertices.count)

                case let .points(index):
                    guard pointBatches.indices.contains(index) else { continue }
                    let gpu = pointBatches[index]
                    guard let buffer = gpu.buffer, !gpu.batch.vertices.isEmpty else { continue }
                    apply(gpu.batch.material, to: &uniforms)
                    encoder.setRenderPipelineState(particlePipeline)
                    encoder.setVertexBuffer(buffer, offset: 0, index: 0)
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gpu.batch.vertices.count)
                }
            }

            encoder.endEncoding()
            command.present(drawable)
            command.commit()
            recordMetrics(logical: logicalParticles, submitted: submittedParticles)
        }

        private func baseUniforms(view: MTKView) -> Uniforms {
            let sun = SekaiVector3(SekaiCoordinate(
                latitude: style.environment.sunLatitude,
                longitude: style.environment.sunLongitude
            )).normalized()
            return Uniforms(
                quaternion: SIMD4(
                    Float(camera.orientation.x), Float(camera.orientation.y),
                    Float(camera.orientation.z), Float(camera.orientation.w)
                ),
                color: SIMD4(0, 0, 0, 1),
                viewport: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                offset: SIMD2(Float(camera.offsetX), Float(camera.offsetY)),
                zoom: Float(camera.zoom),
                pointSize: 1,
                spinAngle: Float(rotationClock?.angle(speed: autoRotationSpeed) ?? 0),
                reserved: 0,
                projection: camera.projection.fieldOfViewDegrees == 0 ? 0 : 1,
                projectionScale: camera.projection.fieldOfViewDegrees == 0
                    ? 1 : Float(1 / tan(camera.projection.fieldOfViewDegrees * .pi / 360)),
                optical: SIMD4(1, 0.7, 0.55, 0.28),
                material: SIMD4(0.55, 0, 0, 0),
                environment: SIMD4(
                    Float(sun.x), Float(sun.y), Float(sun.z),
                    style.environment.showsDayNightTerminator ? Float(style.environment.ambientLight) : -1
                )
            )
        }

        private func apply(_ particleStyle: SekaiParticleStyle, to uniforms: inout Uniforms) {
            uniforms.color = particleStyle.color.sekaiMetalColor(
                dark: isDark,
                opacity: particleStyle.opacity
            )
            uniforms.pointSize = Float(max(particleStyle.minimumPixelDiameter, particleStyle.size))
            uniforms.optical = SIMD4(
                Float(particleStyle.brightness), Float(particleStyle.highlight),
                Float(particleStyle.refraction), Float(particleStyle.depthFade)
            )
            uniforms.material = SIMD4(0.58, 0, 0, 0)
        }

        private func applyBoundaryFill(_ boundaryStyle: SekaiBoundaryStyle, to uniforms: inout Uniforms) {
            uniforms.color = boundaryStyle.fillColor.sekaiMetalColor(
                dark: isDark,
                opacity: boundaryStyle.fillOpacity
            )
            uniforms.optical = SIMD4(1, Float(boundaryStyle.highlight), Float(boundaryStyle.refraction), 0.15)
            uniforms.material = SIMD4(0.58, 0, 0, 0)
        }

        private func applyBoundaryLine(_ boundaryStyle: SekaiBoundaryStyle, to uniforms: inout Uniforms) {
            uniforms.color = boundaryStyle.strokeColor.sekaiMetalColor(
                dark: isDark,
                opacity: boundaryStyle.strokeOpacity
            )
            uniforms.pointSize = Float(max(0.5, boundaryStyle.strokeWidth))
            uniforms.optical = SIMD4(1, Float(boundaryStyle.highlight), Float(boundaryStyle.refraction), 0.15)
            uniforms.material = SIMD4(0.52, 0.08, 0, 0)
        }

        private func apply(_ routeStyle: SekaiRouteStyle, to uniforms: inout Uniforms) {
            uniforms.color = routeStyle.color.sekaiMetalColor(opacity: routeStyle.opacity)
            uniforms.pointSize = Float(max(0.5, routeStyle.width))
            uniforms.optical = SIMD4(1, Float(routeStyle.highlight), 0.45, 0.12)
            uniforms.material = SIMD4(0.52, 0.12, 0, 0)
        }

        private func apply(_ material: SekaiPreparedPointMaterial, to uniforms: inout Uniforms) {
            switch material {
            case let .annotation(override):
                let annotationStyle = override ?? style.annotations
                uniforms.color = annotationStyle.color.sekaiMetalColor(opacity: annotationStyle.opacity)
                uniforms.pointSize = Float(max(2, annotationStyle.size * 9))
                uniforms.optical = SIMD4(1, Float(annotationStyle.highlight), 0.42, 0.08)
                uniforms.material = SIMD4(Float(annotationStyle.core), Float(annotationStyle.halo), 0, 0)
            case let .routeEndpoint(override):
                let routeStyle = override ?? style.routes
                uniforms.color = routeStyle.color.sekaiMetalColor(opacity: routeStyle.opacity)
                uniforms.pointSize = Float(max(2, routeStyle.endpointSize * 100))
                uniforms.optical = SIMD4(1, Float(routeStyle.highlight), 0.45, 0.08)
                uniforms.material = SIMD4(0.48, 0.32, 0, 0)
            case let .heat(weight):
                let value = min(max(weight, 0), 1)
                let color = SekaiColor(red: value, green: 0.28 + (1 - value) * 0.35, blue: 1 - value * 0.72)
                uniforms.color = color.sekaiMetalColor(opacity: 0.3 + value * 0.45)
                uniforms.pointSize = Float(14 + value * 30)
                uniforms.optical = SIMD4(1.15, 0.8, 0.35, 0.1)
                uniforms.material = SIMD4(0.2, 0.9, 0, 0)
            }
        }

        private func recordMetrics(logical: Int, submitted: Int) {
            metricFrames += 1
            let now = Date.timeIntervalSinceReferenceDate
            let duration = now - metricEpoch
            guard duration >= 1 else { return }
            let framesPerSecond = Double(metricFrames) / duration
            adjustQuality(framesPerSecond: framesPerSecond)
            metricsCallback(SekaiRenderMetrics(
                logicalParticleCount: logical,
                requestedParticleCount: logical,
                renderedParticleCount: submitted,
                culledParticleCount: max(0, logical - submitted),
                framesPerSecond: framesPerSecond,
                frameTimeMilliseconds: framesPerSecond > 0 ? 1_000 / framesPerSecond : 0,
                renderScale: 1,
                levelOfDetail: adaptiveLOD,
                policy: policy
            ))
            metricFrames = 0
            metricEpoch = now
        }

        private func adjustQuality(framesPerSecond: Double) {
            guard case let .adaptive(minimumFramesPerSecond) = policy else { return }
            let target = Double(max(minimumFramesPerSecond, 1))
            if framesPerSecond < target * 0.9 {
                lowFrameWindows += 1
                highFrameWindows = 0
                if lowFrameWindows >= 2 {
                    adaptiveQuality = max(0.125, adaptiveQuality * 0.72)
                    adaptiveLOD = adaptiveQuality >= 0.72 ? 0 : adaptiveQuality >= 0.3 ? 1 : 2
                    lowFrameWindows = 0
                }
            } else if (adaptiveQuality < 1 && framesPerSecond >= target * 0.97)
                        || framesPerSecond > target * 1.02 {
                highFrameWindows += 1
                lowFrameWindows = 0
                if highFrameWindows >= 3 {
                    adaptiveQuality = min(1, adaptiveQuality / 0.82)
                    adaptiveLOD = adaptiveQuality >= 0.72 ? 0 : adaptiveQuality >= 0.3 ? 1 : 2
                    highFrameWindows = 0
                }
            } else {
                lowFrameWindows = 0
                highFrameWindows = 0
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
    var spinAngle: Float
    var reserved: Float
    var projection: UInt32
    var projectionScale: Float
    var optical: SIMD4<Float>
    var material: SIMD4<Float>
    var environment: SIMD4<Float>
}

private extension SekaiAdaptiveColor {
    func sekaiMetalColor(dark: Bool, opacity: Double) -> SIMD4<Float> {
        sekaiResolved(dark: dark).sekaiMetalColor(opacity: opacity)
    }
}

private extension SekaiColor {
    func sekaiMetalColor(opacity: Double) -> SIMD4<Float> {
        let value = normalized()
        return SIMD4(
            Float(value.red), Float(value.green), Float(value.blue),
            Float(value.alpha * min(max(opacity, 0), 1))
        )
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
    let rotationClock: SekaiRotationClock
    let performance: SekaiPerformancePolicy
    let onMetrics: @MainActor (SekaiRenderMetrics) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: autoRotationSpeed == 0)) { timeline in
            Canvas { context, size in
                guard let scene else { return }
                let spin = rotationClock.angle(
                    at: timeline.date.timeIntervalSinceReferenceDate,
                    speed: autoRotationSpeed
                )
                let projection = SekaiProjectionContext(size: size, camera: camera, spinAngle: spin)
                let points = scene.particleBatches.lazy.flatMap(\.vertices).prefix(4_096)
                for particle in points {
                    let vector = SekaiVector3(
                        x: Double(particle.position.x),
                        y: Double(particle.position.y),
                        z: Double(particle.position.z)
                    )
                    guard let projected = projection.project(vector) else { continue }
                    context.fill(
                        Path(ellipseIn: CGRect(x: projected.point.x, y: projected.point.y, width: 1, height: 1)),
                        with: .color(.primary)
                    )
                }
            }
        }
    }
}
#endif
