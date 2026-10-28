@preconcurrency import MetalKit
import QuartzCore

struct SekaiRenderInput: Equatable {
  var camera = SekaiCamera.standard
  var style = SekaiStyle.automatic
  var activity = SekaiActivity.active()
  var interaction = SekaiInteraction.rotationAndZoom
  var markers: [SekaiMarker] = []
  var arcs: [SekaiArc] = []
  var regions: [SekaiRegionHighlight] = []
  var dark = false
  var allowsMotion = true
  var isSceneActive = true
}

struct SekaiUniforms {
  var orientation: SIMD4<Float>
  var viewport: SIMD4<Float>
  var camera: SIMD4<Float>
  var ocean: SIMD4<Float>
  var land: SIMD4<Float>
  var glow: SIMD4<Float>
  var options: SIMD4<Float>
  var markerColor: SIMD4<Float>
  var arcColor: SIMD4<Float>
}
private struct SekaiMarkerGPU {
  var positionSize: SIMD4<Float>
  var color: SIMD4<Float>
}
private struct SekaiArcGPU {
  var fromHeight: SIMD4<Float>
  var toWidth: SIMD4<Float>
  var color: SIMD4<Float>
}

@MainActor
final class SekaiRenderer: NSObject, MTKViewDelegate {
  let device: MTLDevice?
  private var queue: MTLCommandQueue?
  private var globe: MTLRenderPipelineState?
  private var marker: MTLRenderPipelineState?
  private var arc: MTLRenderPipelineState?
  private var mask: MTLTexture?
  private var regionMask: MTLTexture?
  private var regionColors: MTLBuffer?
  private var fallbackMarkers: [SekaiMarker] = []
  private var sampledRegions: Set<UInt16> = []
  private var sampledRegionCount = 0
  private var markerBuffer: MTLBuffer?
  private var arcBuffer: MTLBuffer?
  private var markerCount = 0
  private var arcCount = 0
  private let inFlight = DispatchSemaphore(value: 3)
  private var motion = SekaiMotion()
  private var dragStart: SekaiQuaternion?
  private var zoomStart: Double?
  private var statusDelivery: Task<Void, Never>?
  private var pendingStatus: SekaiRenderStatus?
  private var deliveredStatus: SekaiRenderStatus?
  private var hasDrawableSize = true
  private weak var nativeView: MTKView?
  private(set) var input = SekaiRenderInput()
  private(set) var status = SekaiRenderStatus.preparing
  private(set) var isAttached = false
  private(set) var isStopped = false
  private(set) var submittedFrames = 0
  #if DEBUG
    private let completions = SekaiCompletionCount()
    var completedFrames: Int { completions.value }
  #endif
  private(set) var markerUploads = 0
  private(set) var arcUploads = 0
  private(set) var regionUploads = 0
  var onCameraChange: (@MainActor (SekaiCamera) -> Void)?
  private var onStatusChange: (@MainActor (SekaiRenderStatus) -> Void)?

  init(
    device: MTLDevice? = MTLCreateSystemDefaultDevice(), bundle: Bundle? = nil,
    pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
  ) {
    self.device = device
    super.init()
    guard let device else {
      status = .failed(.metalUnavailable)
      return
    }
    do {
      let bundle = bundle ?? .module
      guard let url = bundle.url(forResource: "LandMask", withExtension: "png") else {
        throw SekaiRenderError.resourceUnavailable
      }
      let library: MTLLibrary
      do { library = try device.makeDefaultLibrary(bundle: bundle) } catch {
        throw SekaiRenderError.resourceUnavailable
      }
      globe = try Self.pipeline(
        device: device, library: library, vertex: "sekaiGlobeVertex",
        fragment: "sekaiGlobeFragment", format: pixelFormat)
      marker = try Self.pipeline(
        device: device, library: library, vertex: "sekaiMarkerVertex",
        fragment: "sekaiMarkerFragment", format: pixelFormat)
      arc = try Self.pipeline(
        device: device, library: library, vertex: "sekaiArcVertex", fragment: "sekaiArcFragment",
        format: pixelFormat)
      mask = try MTKTextureLoader(device: device).newTexture(URL: url, options: [.SRGB: false])
      guard let regions = SekaiRegionMap.bundled else { throw SekaiRenderError.resourceUnavailable }
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .r16Uint, width: regions.width, height: regions.height, mipmapped: false)
      descriptor.storageMode = .shared
      descriptor.usage = .shaderRead
      regionMask = device.makeTexture(descriptor: descriptor)
      guard let regionMask else { throw SekaiRenderError.allocationFailed }
      regions.identifiers.withUnsafeBytes { bytes in
        regionMask.replace(region: MTLRegionMake2D(0, 0, regions.width, regions.height),
          mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: regions.width * 2)
      }
      regionColors = buffer([SIMD4<Float>](repeating: SIMD4(0, 0, 0, -1),
        count: SekaiRegionMap.maximumIdentifier + 1))
      guard regionColors != nil else { throw SekaiRenderError.allocationFailed }
      queue = device.makeCommandQueue()
      guard queue != nil else { throw SekaiRenderError.allocationFailed }
      status = .ready
    } catch let error as SekaiRenderError { status = .failed(error) } catch {
      status = .failed(.resourceUnavailable)
    }
  }

  private static func pipeline(
    device: MTLDevice, library: MTLLibrary, vertex: String, fragment: String, format: MTLPixelFormat
  ) throws -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    guard let vertex = library.makeFunction(name: vertex),
      let fragment = library.makeFunction(name: fragment)
    else {
      throw SekaiRenderError.pipelineUnavailable
    }
    descriptor.vertexFunction = vertex
    descriptor.fragmentFunction = fragment
    let color = descriptor.colorAttachments[0]!
    color.pixelFormat = format
    color.isBlendingEnabled = true
    color.sourceRGBBlendFactor = .one
    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
    color.sourceAlphaBlendFactor = .one
    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    do { return try device.makeRenderPipelineState(descriptor: descriptor) } catch {
      throw SekaiRenderError.pipelineUnavailable
    }
  }

  func update(
    _ value: SekaiRenderInput, status: (@MainActor (SekaiRenderStatus) -> Void)?,
    camera: @escaping @MainActor (SekaiCamera) -> Void
  ) {
    guard !isStopped else { return }
    let old = input
    let normalizedCamera = value.camera.normalized
    if old.camera.orientation != normalizedCamera.orientation {
      _ = motion.consume(at: CACurrentMediaTime())
    }
    input = value
    input.camera = normalizedCamera
    onCameraChange = camera
    onStatusChange = status
    motion.update(at: CACurrentMediaTime(), speed: rotationSpeed)
    if old.regions != input.regions || old.style.sampleCount != input.style.sampleCount {
      uploadRegions()
    }
    if old.markers != input.markers { uploadMarkers() }
    if old.arcs != input.arcs { uploadArcs() }
    if !allowsInteraction {
      dragStart = nil
      zoomStart = nil
    }
    deliverStatus()
  }

  private var rotationSpeed: Double {
    guard isAttached, hasDrawableSize, input.isSceneActive, input.allowsMotion, dragStart == nil,
      zoomStart == nil
    else { return 0 }
    return input.activity.speed
  }

  private var allowsInteraction: Bool {
    guard isAttached, input.isSceneActive, input.interaction != .disabled else { return false }
    if case .suspended = input.activity { return false }
    return true
  }

  var drawsContinuously: Bool { !isStopped && status == .ready && rotationSpeed != 0 }

  func setAttached(_ attached: Bool) {
    motion.update(at: CACurrentMediaTime(), speed: rotationSpeed)
    isAttached = attached
    if !attached {
      dragStart = nil
      zoomStart = nil
    }
    motion.update(at: CACurrentMediaTime(), speed: rotationSpeed)
  }

  func refreshCadence(_ view: MTKView) {
    nativeView = view
    let now = CACurrentMediaTime()
    motion.update(at: now, speed: rotationSpeed)
    hasDrawableSize =
      !view.bounds.isEmpty && view.drawableSize.width > 0 && view.drawableSize.height > 0
    motion.update(at: now, speed: rotationSpeed)
    view.isPaused = !drawsContinuously || view.bounds.isEmpty
    view.enableSetNeedsDisplay = view.isPaused
    #if os(macOS)
      view.preferredFramesPerSecond = min(120, view.window?.screen?.maximumFramesPerSecond ?? 60)
    #elseif !os(visionOS)
      view.preferredFramesPerSecond = min(
        120, view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
    #endif
    if view.isPaused, isAttached, input.isSceneActive, !view.bounds.isEmpty, status == .ready {
      view.draw()
    }
  }

  private func deliverStatus() {
    let next = status
    guard onStatusChange != nil, deliveredStatus != next, pendingStatus != next else { return }
    pendingStatus = next
    statusDelivery?.cancel()
    statusDelivery = Task { @MainActor [weak self] in
      guard !Task.isCancelled, let self, !self.isStopped else { return }
      self.pendingStatus = nil
      self.deliveredStatus = next
      self.onStatusChange?(next)
    }
  }

  func stop(_ view: MTKView) {
    guard !isStopped else { return }
    isStopped = true
    isAttached = false
    view.isPaused = true
    view.delegate = nil
    nativeView = nil
    statusDelivery?.cancel()
    statusDelivery = nil
    onStatusChange = nil
    onCameraChange = nil
    markerBuffer = nil
    arcBuffer = nil
    mask = nil
    regionMask = nil
    regionColors = nil
    fallbackMarkers = []
    sampledRegions = []
    globe = nil
    marker = nil
    arc = nil
    queue = nil
  }

  private func uploadMarkers() {
    let values = (input.markers + fallbackMarkers).map { value -> SekaiMarkerGPU in
      let p = SekaiVector3(
        .init(latitude: value.coordinate.latitude, longitude: value.coordinate.longitude))
      return SekaiMarkerGPU(
        positionSize: SIMD4(
          Float(p.x), Float(p.y), Float(p.z), Float(sekaiBound(value.size, 0...100, fallback: 6))),
        color: value.color?.linear ?? SIMD4(0, 0, 0, -1)
      )
    }
    markerBuffer = buffer(values)
    markerCount = values.count
    markerUploads += 1
  }

  private func uploadRegions() {
    guard let map = SekaiRegionMap.bundled else { return }
    let count = min(max(input.style.sampleCount, 512), 32_768)
    if sampledRegionCount != count {
      sampledRegions = map.sampledIdentifiers(count: count)
      sampledRegionCount = count
    }
    var colors = [SIMD4<Float>](repeating: SIMD4(0, 0, 0, -1),
      count: SekaiRegionMap.maximumIdentifier + 1)
    var anchors: [SekaiMarker] = []
    var highlights: [UInt16: SekaiRegionHighlight] = [:]
    for highlight in input.regions {
      if let identifier = SekaiRegionMap.identifier(for: highlight.regionCode) {
        highlights[identifier] = highlight
      }
    }
    for (identifier, highlight) in highlights.sorted(by: { $0.key < $1.key }) {
      colors[Int(identifier)] = highlight.color.linear
      if !sampledRegions.contains(identifier), let coordinate = highlight.fallbackCoordinate {
        anchors.append(.init(id: "region-\(highlight.regionCode)", coordinate: coordinate,
          size: 5, color: highlight.color))
      }
    }
    regionColors = buffer(colors)
    regionUploads += 1
    if anchors != fallbackMarkers {
      fallbackMarkers = anchors
      uploadMarkers()
    }
  }

  private func uploadArcs() {
    let values = input.arcs.map { value -> SekaiArcGPU in
      let a = SekaiVector3(.init(latitude: value.from.latitude, longitude: value.from.longitude))
      let b = SekaiVector3(.init(latitude: value.to.latitude, longitude: value.to.longitude))
      return SekaiArcGPU(
        fromHeight: SIMD4(
          Float(a.x), Float(a.y), Float(a.z), Float(sekaiBound(value.height, 0...2, fallback: 0.15))
        ),
        toWidth: SIMD4(
          Float(b.x), Float(b.y), Float(b.z), Float(sekaiBound(value.width, 0...30, fallback: 1.5))),
        color: value.color?.linear ?? SIMD4(0, 0, 0, -1)
      )
    }
    arcBuffer = buffer(values)
    arcCount = values.count
    arcUploads += 1
  }

  private func buffer<T>(_ values: [T]) -> MTLBuffer? {
    guard !values.isEmpty else { return nil }
    let result = values.withUnsafeBytes { bytes in
      device?.makeBuffer(
        bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
    }
    if result == nil {
      status = .failed(.allocationFailed)
      deliverStatus()
    }
    return result
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { refreshCadence(view) }

  func draw(in view: MTKView) {
    guard !isStopped, isAttached, input.isSceneActive, !view.bounds.isEmpty,
      let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable
    else { return }
    let scale = Double(view.drawableSize.width / max(view.bounds.width, 1))
    do {
      _ = try submit(
        pass: pass, size: view.drawableSize, scale: scale, at: CACurrentMediaTime(),
        drawable: drawable)
    } catch let error as SekaiRenderError {
      status = .failed(error)
      view.isPaused = true
      deliverStatus()
    } catch {
      status = .failed(.pipelineUnavailable)
      view.isPaused = true
      deliverStatus()
    }
  }

  func render(to texture: MTLTexture, at time: Double = CACurrentMediaTime()) throws
    -> MTLCommandBuffer?
  {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    return try submit(
      pass: pass, size: CGSize(width: texture.width, height: texture.height), scale: 1, at: time,
      drawable: nil)
  }

  private func submit(
    pass: MTLRenderPassDescriptor, size: CGSize, scale: Double, at time: Double,
    drawable: CAMetalDrawable?
  ) throws -> MTLCommandBuffer? {
    guard !isStopped, status == .ready, let queue, let globe, let marker, let arc, let mask,
      let regionMask, let regionColors else {
      if case .failed(let error) = status { throw error }
      throw SekaiRenderError.pipelineUnavailable
    }
    guard inFlight.wait(timeout: .now()) == .success else { return nil }
    guard let command = queue.makeCommandBuffer(),
      let encoder = command.makeRenderCommandEncoder(descriptor: pass)
    else {
      inFlight.signal()
      throw SekaiRenderError.allocationFailed
    }
    var uniforms = uniforms(size: size, scale: scale, at: time)
    encoder.setRenderPipelineState(globe)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SekaiUniforms>.stride, index: 0)
    encoder.setFragmentTexture(mask, index: 0)
    encoder.setFragmentTexture(regionMask, index: 1)
    encoder.setFragmentBuffer(regionColors, offset: 0, index: 2)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<SekaiUniforms>.stride, index: 1)
    if let arcBuffer, arcCount > 0 {
      encoder.setRenderPipelineState(arc)
      encoder.setVertexBuffer(arcBuffer, offset: 0, index: 0)
      encoder.drawPrimitives(
        type: .triangleStrip, vertexStart: 0, vertexCount: 130, instanceCount: arcCount)
    }
    if let markerBuffer, markerCount > 0 {
      encoder.setRenderPipelineState(marker)
      encoder.setVertexBuffer(markerBuffer, offset: 0, index: 0)
      encoder.drawPrimitives(
        type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: markerCount)
    }
    encoder.endEncoding()
    if let drawable { command.present(drawable) }
    let semaphore = inFlight
    #if DEBUG
      let completions = completions
    #endif
    command.addCompletedHandler { [weak self] command in
      semaphore.signal()
      #if DEBUG
        completions.record()
      #endif
      if command.status == .error {
        Task { @MainActor [weak self] in
          guard let self, !self.isStopped else { return }
          self.status = .failed(.renderingFailed)
          self.nativeView?.isPaused = true
          self.deliverStatus()
        }
      }
    }
    submittedFrames += 1
    command.commit()
    return command
  }

  private func uniforms(size: CGSize, scale: Double, at now: Double) -> SekaiUniforms {
    motion.update(at: now, speed: rotationSpeed)
    let camera = input.camera.normalized
    let spin = SekaiQuaternion.axisAngle(x: 0, y: 1, z: 0, radians: motion.angle)
    let orientation = camera.orientation * spin
    let palette = input.style.palette(dark: input.dark)
    return SekaiUniforms(
      orientation: SIMD4(
        Float(orientation.x), Float(orientation.y), Float(orientation.z), Float(orientation.w)),
      viewport: SIMD4(
        Float(max(size.width, 1)), Float(max(size.height, 1)), Float(scale), Float(camera.zoom)),
      camera: SIMD4(
        Float(camera.offsetX), Float(camera.offsetY),
        Float(min(max(input.style.sampleCount, 512), 32_768)),
        Float(sekaiBound(input.style.dotSize, 0.001...0.06, fallback: 0.008))),
      ocean: palette.ocean.linear, land: palette.land.linear, glow: palette.glow.linear,
      options: SIMD4(
        Float(sekaiBound(input.style.brightness, 0...4, fallback: 1)),
        Float(sekaiBound(input.style.diffuse, 0...8, fallback: 1)),
        Float(sekaiBound(input.style.opacity, 0...1, fallback: 1)),
        Float(sekaiBound(input.style.glow, 0...0.5, fallback: 0.12))),
      markerColor: input.style.markerColor.linear, arcColor: input.style.arcColor.linear
    )
  }

  func beginRotation() {
    guard allowsInteraction else { return }
    let angle = motion.consume(at: CACurrentMediaTime())
    input.camera.orientation =
      input.camera.orientation * .axisAngle(x: 0, y: 1, z: 0, radians: angle)
    dragStart = input.camera.orientation
    motion.update(at: CACurrentMediaTime(), speed: 0)
    onCameraChange?(input.camera)
  }

  func rotate(translation: CGSize) {
    guard allowsInteraction, let start = dragStart else { return }
    let yaw = SekaiQuaternion.axisAngle(
      x: 0, y: 1, z: 0, radians: Double(translation.width) * .pi / 360)
    let pitch = SekaiQuaternion.axisAngle(
      x: 1, y: 0, z: 0, radians: Double(translation.height) * .pi / 360)
    input.camera.orientation = pitch * yaw * start
    onCameraChange?(input.camera)
  }

  func endRotation() {
    dragStart = nil
    motion.update(at: CACurrentMediaTime(), speed: rotationSpeed)
  }

  func beginZoom() {
    guard allowsInteraction, input.interaction == .rotationAndZoom else { return }
    let now = CACurrentMediaTime()
    motion.update(at: now, speed: rotationSpeed)
    zoomStart = input.camera.zoom
    motion.update(at: now, speed: 0)
  }
  func zoom(scale: Double) {
    guard allowsInteraction, input.interaction == .rotationAndZoom, let start = zoomStart else {
      return
    }
    input.camera.zoom = sekaiBound(start * scale, 0.5...4, fallback: 1)
    onCameraChange?(input.camera)
  }
  func endZoom() {
    zoomStart = nil
    motion.update(at: CACurrentMediaTime(), speed: rotationSpeed)
  }
}

#if DEBUG
  private final class SekaiCompletionCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func record() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
  }
#endif
