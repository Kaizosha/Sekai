@preconcurrency import MetalKit
import SwiftUI

#if os(macOS)
  private typealias SekaiViewRepresentable = NSViewRepresentable
#else
  private typealias SekaiViewRepresentable = UIViewRepresentable
#endif

struct SekaiMetalView: SekaiViewRepresentable {
  let input: SekaiRenderInput
  let onCameraChange: @MainActor (SekaiCamera) -> Void
  let onStatusChange: @MainActor (SekaiRenderStatus) -> Void

  func makeCoordinator() -> SekaiRenderer { SekaiRenderer() }

  #if os(macOS)
    func makeNSView(context: Context) -> SekaiNativeView { makeView(context.coordinator) }
    func updateNSView(_ view: SekaiNativeView, context: Context) {
      update(view, renderer: context.coordinator)
    }
    static func dismantleNSView(_ view: SekaiNativeView, coordinator: SekaiRenderer) {
      coordinator.stop(view)
      view.renderer = nil
    }
  #else
    func makeUIView(context: Context) -> SekaiNativeView { makeView(context.coordinator) }
    func updateUIView(_ view: SekaiNativeView, context: Context) {
      update(view, renderer: context.coordinator)
    }
    static func dismantleUIView(_ view: SekaiNativeView, coordinator: SekaiRenderer) {
      coordinator.stop(view)
      view.renderer = nil
    }
  #endif

  private func makeView(_ renderer: SekaiRenderer) -> SekaiNativeView {
    let view = SekaiNativeView(frame: .zero, device: renderer.device)
    view.renderer = renderer
    view.delegate = renderer
    view.isPaused = true
    view.enableSetNeedsDisplay = true
    view.framebufferOnly = true
    view.colorPixelFormat = .bgra8Unorm_srgb
    view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    #if !os(macOS)
      view.isOpaque = false
      view.backgroundColor = .clear
    #endif
    view.installGestures()
    return view
  }

  private func update(_ view: SekaiNativeView, renderer: SekaiRenderer) {
    renderer.update(input, status: onStatusChange, camera: onCameraChange)
    renderer.setAttached(view.window != nil && !view.isHidden)
    #if os(macOS)
      view.gestureRecognizers.forEach {
        $0.isEnabled = input.interaction != .disabled && input.isSceneActive
      }
    #else
      view.gestureRecognizers?.forEach {
        $0.isEnabled = input.interaction != .disabled && input.isSceneActive
      }
    #endif
    renderer.refreshCadence(view)
  }
}

#if os(macOS)
  final class SekaiNativeView: MTKView {
    weak var renderer: SekaiRenderer?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      renderer?.setAttached(window != nil && !isHiddenOrHasHiddenAncestor)
      renderer?.refreshCadence(self)
    }

    override func viewDidHide() {
      super.viewDidHide()
      renderer?.setAttached(false)
      renderer?.refreshCadence(self)
    }

    override func viewDidUnhide() {
      super.viewDidUnhide()
      renderer?.setAttached(window != nil)
      renderer?.refreshCadence(self)
    }

    func installGestures() {
      addGestureRecognizer(NSPanGestureRecognizer(target: self, action: #selector(pan)))
      addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(pinch)))
    }

    @objc private func pan(_ gesture: NSPanGestureRecognizer) {
      guard let renderer else { return }
      switch gesture.state {
      case .began: renderer.beginRotation()
      case .changed:
        let point = gesture.translation(in: self)
        renderer.rotate(translation: CGSize(width: point.x, height: -point.y))
      case .ended, .cancelled, .failed: renderer.endRotation()
      default: break
      }
      renderer.refreshCadence(self)
    }

    @objc private func pinch(_ gesture: NSMagnificationGestureRecognizer) {
      guard let renderer else { return }
      switch gesture.state {
      case .began: renderer.beginZoom()
      case .changed: renderer.zoom(scale: gesture.magnification + 1)
      case .ended, .cancelled, .failed: renderer.endZoom()
      default: break
      }
      renderer.refreshCadence(self)
    }
  }
#else
  final class SekaiNativeView: MTKView {
    weak var renderer: SekaiRenderer?

    override func didMoveToWindow() {
      super.didMoveToWindow()
      renderer?.setAttached(window != nil && !isHidden)
      renderer?.refreshCadence(self)
    }

    override var isHidden: Bool {
      didSet {
        renderer?.setAttached(window != nil && !isHidden)
        renderer?.refreshCadence(self)
      }
    }

    func installGestures() {
      #if !os(tvOS)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan)))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch)))
      #endif
    }

    #if !os(tvOS)
      @objc private func pan(_ gesture: UIPanGestureRecognizer) {
        guard let renderer else { return }
        switch gesture.state {
        case .began: renderer.beginRotation()
        case .changed:
          let point = gesture.translation(in: self)
          renderer.rotate(translation: CGSize(width: point.x, height: point.y))
        case .ended, .cancelled, .failed: renderer.endRotation()
        default: break
        }
        renderer.refreshCadence(self)
      }

      @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard let renderer else { return }
        switch gesture.state {
        case .began: renderer.beginZoom()
        case .changed: renderer.zoom(scale: gesture.scale)
        case .ended, .cancelled, .failed: renderer.endZoom()
        default: break
        }
        renderer.refreshCadence(self)
      }
    #endif
  }
#endif
