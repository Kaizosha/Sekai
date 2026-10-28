import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import MetalKit
import Testing

@testable import SekaiKit

#if os(macOS)
  import AppKit
#endif

@Suite(.serialized)
@MainActor
struct SekaiMetalTests {
  func texture(
    _ renderer: SekaiRenderer, size: Int = 256, format: MTLPixelFormat = .bgra8Unorm_srgb
  ) throws -> MTLTexture {
    let device = try #require(renderer.device, "Native Metal is required for the renderer checks")
    #expect(renderer.status == .ready)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: format, width: size, height: size, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    return try #require(device.makeTexture(descriptor: descriptor))
  }

  func pixels(
    _ renderer: SekaiRenderer, input: SekaiRenderInput = .init(), at time: Double? = nil
  ) throws
    -> [UInt8]
  {
    renderer.update(input, status: nil, camera: { _ in })
    let image = try texture(renderer)
    let pendingCommand = try renderer.render(to: image, at: time ?? CACurrentMediaTime())
    let command = try #require(pendingCommand)
    command.waitUntilCompleted()
    #expect(command.status == .completed)
    #expect(command.error == nil)
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    bytes.withUnsafeMutableBytes {
      image.getBytes(
        $0.baseAddress!, bytesPerRow: image.width * 4,
        from: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0)
    }
    return bytes
  }

  @Test func packagedShadersDrawLightAndDarkGlobesWithTransparentCorners() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.style.glow = 0
    let light = try pixels(renderer, input: input)
    input.dark = true
    let dark = try pixels(renderer, input: input)
    #expect(light[3] == 0 && dark[3] == 0)
    #expect(light[(128 * 256 + 128) * 4 + 3] > 250)
    #expect(dark[(128 * 256 + 128) * 4 + 3] > 250)
    #expect(light != dark)
    #expect(Set(stride(from: 0, to: light.count, by: 4).map { light[$0] }).count > 20)
    try save(light, name: "Sekai-Light.png")
    try save(dark, name: "Sekai-Dark.png")
  }

  @Test func transparentOceanRGBDoesNotTintPartialLandCoverage() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.style = SekaiStyle(
      glow: 0,
      landColor: .init(red: 1, green: 0, blue: 0),
      oceanColor: .init(red: 0, green: 0, blue: 1, alpha: 0))
    let blue = try pixels(renderer, input: input)
    input.style.oceanColor = .init(red: 0, green: 1, blue: 0, alpha: 0)
    let green = try pixels(renderer, input: input)
    let partialPixels = stride(from: 3, to: blue.count, by: 4).filter {
      blue[$0] > 0 && blue[$0] < 250
    }.count
    #expect(partialPixels > 100, "The fixture must exercise partially covered land dots")
    let changedChannels = zip(blue, green).filter { $0 != $1 }.count
    #expect(changedChannels == 0, "A fully transparent ocean must contribute no RGB at land edges")
  }

  @Test func frontMarkersAndArcsDrawWhileRearGeometryIsOccluded() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.camera = .init()
    input.style.glow = 0
    let base = try pixels(renderer, input: input)
    input.markers = [
      .init(
        id: "rear", coordinate: .init(latitude: 0, longitude: 180), size: 30,
        color: .init(red: 1, green: 0, blue: 0))
    ]
    #expect(try pixels(renderer, input: input) == base)
    input.markers = [
      .init(
        id: "front", coordinate: .init(latitude: 0, longitude: 0), size: 30,
        color: .init(red: 1, green: 0, blue: 0))
    ]
    let front = try pixels(renderer, input: input)
    let center = (128 * 256 + 128) * 4
    #expect(front[center + 2] > 240 && front[center + 1] < 20)
    input.markers = []
    input.arcs = [
      .init(
        id: "rear", from: .init(latitude: -20, longitude: 175),
        to: .init(latitude: 20, longitude: 175), color: .init(red: 0, green: 1, blue: 0))
    ]
    #expect(try pixels(renderer, input: input) == base)
    input.arcs = [
      .init(
        id: "front", from: .init(latitude: -20, longitude: -30),
        to: .init(latitude: 20, longitude: 30), width: 4, color: .init(red: 0, green: 1, blue: 0))
    ]
    #expect(try pixels(renderer, input: input) != base)
  }

  @Test func floatOutputIsFiniteAtPolesRimDensityLimitsAndZeroOpacity() throws {
    let renderer = SekaiRenderer(pixelFormat: .rgba32Float)
    var input = SekaiRenderInput()
    for count in [Int.min, 512, 32_768, Int.max] {
      for latitude in [-90.0, 0, 90] {
        input.camera.focus(on: .init(latitude: latitude, longitude: 180))
        input.style.sampleCount = count
        input.style.dotSize = count == Int.min ? .nan : 0.008
        renderer.update(input, status: nil, camera: { _ in })
        let image = try texture(renderer, size: 128, format: .rgba32Float)
        let pendingCommand = try renderer.render(to: image)
        let command = try #require(pendingCommand)
        command.waitUntilCompleted()
        #expect(command.status == .completed)
        var values = [Float](repeating: 0, count: 128 * 128 * 4)
        values.withUnsafeMutableBytes {
          image.getBytes(
            $0.baseAddress!, bytesPerRow: 128 * 16, from: MTLRegionMake2D(0, 0, 128, 128),
            mipmapLevel: 0)
        }
        let areFinite = values.allSatisfy { $0.isFinite }
        #expect(areFinite)
        #expect(values[(64 * 128 + 64) * 4 + 3] > 0.9)
      }
    }
    input.style.opacity = 0
    renderer.update(input, status: nil, camera: { _ in })
    let image = try texture(renderer, size: 128, format: .rgba32Float)
    let pendingCommand = try renderer.render(to: image)
    let command = try #require(pendingCommand)
    command.waitUntilCompleted()
    var values = [Float](repeating: 0, count: 128 * 128 * 4)
    values.withUnsafeMutableBytes {
      image.getBytes(
        $0.baseAddress!, bytesPerRow: 128 * 16, from: MTLRegionMake2D(0, 0, 128, 128),
        mipmapLevel: 0)
    }
    #expect(values.allSatisfy { $0 == 0 })
  }

  @Test func cameraAppearanceAndDensityDoNotReuploadOverlayBuffers() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.markers = [.init(id: "a", coordinate: .init(latitude: 0, longitude: 0))]
    input.arcs = [
      .init(id: "a", from: .init(latitude: 0, longitude: 0), to: .init(latitude: 20, longitude: 20))
    ]
    _ = try pixels(renderer, input: input)
    #expect(renderer.markerUploads == 1 && renderer.arcUploads == 1)
    input.camera.zoom = 1.5
    input.dark = true
    input.style.sampleCount = 8_000
    input.style.markerColor = .init(red: 0, green: 0.8, blue: 0)
    _ = try pixels(renderer, input: input)
    #expect(renderer.markerUploads == 1 && renderer.arcUploads == 1)
    input.markers[0].size = 12
    _ = try pixels(renderer, input: input)
    #expect(renderer.markerUploads == 2 && renderer.arcUploads == 1)
  }

  @Test func failureAndDismantlingStopNativeCadence() async throws {
    #expect(SekaiRenderer(device: nil).status == .failed(.metalUnavailable))
    #expect(
      SekaiRenderer(bundle: Bundle(for: NSObject.self)).status == .failed(.resourceUnavailable))
    let renderer = SekaiRenderer()
    let view = MTKView(frame: .init(x: 0, y: 0, width: 256, height: 256), device: renderer.device)
    view.delegate = renderer
    var input = SekaiRenderInput()
    input.activity = .active(rotationSpeed: 0.1)
    renderer.update(input, status: nil, camera: { _ in })
    renderer.setAttached(true)
    #expect(renderer.drawsContinuously)
    input.activity = .suspended
    renderer.update(input, status: nil, camera: { _ in })
    renderer.refreshCadence(view)
    #expect(view.isPaused && !renderer.drawsContinuously)
    let count = renderer.submittedFrames
    try await Task.sleep(for: .milliseconds(100))
    #expect(renderer.submittedFrames == count)
    input.activity = .active(rotationSpeed: 0.1)
    renderer.update(input, status: nil, camera: { _ in })
    renderer.setAttached(false)
    #expect(!renderer.drawsContinuously)
    renderer.setAttached(true)
    renderer.stop(view)
    #expect(view.delegate == nil && view.isPaused && renderer.isStopped)
    renderer.update(input, status: nil, camera: { _ in })
    #expect(!renderer.drawsContinuously)
    let image = try texture(renderer)
    #expect(throws: SekaiRenderError.pipelineUnavailable) { try renderer.render(to: image) }
  }

  @Test func maskOrientationMatchesKnownLandAndOceanCoordinates() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.style = SekaiStyle(
      dotSize: 0.06, glow: 0,
      landColor: .init(red: 1, green: 0, blue: 0),
      oceanColor: .init(red: 0, green: 0, blue: 1))
    for coordinate in [
      SekaiCoordinate(latitude: 40, longitude: -100), .init(latitude: -25, longitude: 135),
    ] {
      input.camera.focus(on: coordinate)
      let values = try pixels(renderer, input: input)
      let center = (128 * 256 + 128) * 4
      #expect(values[center + 2] > 230 && values[center] < 20)
    }
    input.camera.focus(on: .init(latitude: 0, longitude: -140))
    let ocean = try pixels(renderer, input: input)
    let center = (128 * 256 + 128) * 4
    #expect(ocean[center] > 230 && ocean[center + 2] < 20)
  }

  @Test func draggingPreservesVisibleSpinAndExternalOrientationStartsFromItsRequest() throws {
    let renderer = SekaiRenderer()
    var input = SekaiRenderInput()
    input.camera = .init()
    input.activity = .active(rotationSpeed: 0.1)
    input.markers = [
      .init(
        id: "origin", coordinate: .init(latitude: 0, longitude: 0), size: 20,
        color: .init(red: 1, green: 0, blue: 0))
    ]
    renderer.update(input, status: nil, camera: { _ in })
    renderer.setAttached(true)
    let before = try pixels(renderer, input: input, at: CACurrentMediaTime() + 2)
    renderer.beginRotation()
    renderer.rotate(translation: .zero)
    input.camera = renderer.input.camera
    let after = try pixels(renderer, input: input)
    let start = try redMarkerCenter(before)
    let end = try redMarkerCenter(after)
    #expect(
      hypot(start.x - end.x, start.y - end.y) < 0.1,
      "Starting a drag must retain the visible marker position")
    renderer.endRotation()
    let tokyo = SekaiCoordinate(latitude: 35.68, longitude: 139.69)
    input.camera.focus(on: tokyo)
    input.markers = [
      .init(
        id: "tokyo", coordinate: tokyo, size: 20,
        color: .init(red: 1, green: 0, blue: 0))
    ]
    let focused = try pixels(renderer, input: input)
    let center = (128 * 256 + 128) * 4
    #expect(focused[center + 2] > 240 && focused[center + 1] < 20)
  }

  @Test func statusIsPublishedOnlyForAnActualTransition() async throws {
    let renderer = SekaiRenderer()
    var values: [SekaiRenderStatus] = []
    var input = SekaiRenderInput()
    for index in 0..<20 {
      input.camera.zoom = 1 + Double(index) / 100
      renderer.update(input, status: { values.append($0) }, camera: { _ in })
    }
    await Task.yield()
    #expect(values == [.ready])
    renderer.update(input, status: { values.append($0) }, camera: { _ in })
    await Task.yield()
    #expect(values == [.ready])
  }

  #if os(macOS)
    @Test func attachedNativeViewDrawsThenSuspendsAndReleasesItsRenderer() async throws {
      _ = NSApplication.shared
      let window = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 256, height: 256),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      var renderer: SekaiRenderer? = SekaiRenderer()
      let hasReleasedRenderer = { [weak renderer] in renderer == nil }
      let view = SekaiNativeView(
        frame: .init(x: 0, y: 0, width: 256, height: 256), device: renderer?.device)
      view.colorPixelFormat = .bgra8Unorm_srgb
      view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
      window.contentView = view
      defer {
        renderer?.stop(view)
        view.renderer = nil
        window.contentView = nil
        window.close()
      }
      do {
        let engine = try #require(renderer)
        view.renderer = engine
        view.delegate = engine
        var input = SekaiRenderInput()
        input.activity = .active(rotationSpeed: 0.1)
        engine.update(input, status: nil, camera: { _ in })
        window.makeKeyAndOrderFront(nil)
        engine.setAttached(true)
        engine.refreshCadence(view)
        let deadline = ContinuousClock.now + .seconds(2)
        while engine.completedFrames < 3 && ContinuousClock.now < deadline {
          try await Task.sleep(for: .milliseconds(20))
        }
        #expect(
          engine.completedFrames >= 3,
          "The positive phase must actually present Metal work before pause is tested")
        input.activity = .suspended
        engine.update(input, status: nil, camera: { _ in })
        engine.refreshCadence(view)
        try await Task.sleep(for: .milliseconds(100))
        let paused = engine.submittedFrames
        try await Task.sleep(for: .milliseconds(120))
        #expect(engine.submittedFrames == paused)
        #expect(view.isPaused)
        input.style = .dark
        engine.update(input, status: nil, camera: { _ in })
        engine.refreshCadence(view)
        #expect(engine.submittedFrames == paused + 1)
        engine.stop(view)
        view.renderer = nil
      }
      renderer = nil
      try await Task.sleep(for: .milliseconds(50))
      #expect(hasReleasedRenderer())
      #expect(view.delegate == nil && view.isPaused)
    }
  #endif

  private func redMarkerCenter(_ pixels: [UInt8]) throws -> CGPoint {
    var x = 0.0
    var y = 0.0
    var count = 0.0
    for row in 0..<256 {
      for column in 0..<256 {
        let index = (row * 256 + column) * 4
        if pixels[index + 2] > 240 && pixels[index + 1] < 20 && pixels[index] < 20 {
          x += Double(column)
          y += Double(row)
          count += 1
        }
      }
    }
    #expect(count > 20, "The marker must actually be visible")
    return CGPoint(x: x / max(count, 1), y: y / max(count, 1))
  }

  func save(_ pixels: [UInt8], name: String) throws {
    guard let directory = ProcessInfo.processInfo.environment["SEKAI_TEST_EVIDENCE_DIR"] else {
      return
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(
      CGImage(
        width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(
          rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue), provider: provider, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent))
    let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
    let destination = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
  }
}
