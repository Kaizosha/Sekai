import SwiftUI

/// An offline native Metal globe. The host owns the requested camera and decides when coverage requires suspension.
public struct Sekai: View {
  @Binding private var camera: SekaiCamera
  private let style: SekaiStyle
  private let activity: SekaiActivity
  private let interaction: SekaiInteraction
  private let markers: [SekaiMarker]
  private let arcs: [SekaiArc]
  private let regions: [SekaiRegionHighlight]
  private let onStatusChange: (@MainActor (SekaiRenderStatus) -> Void)?
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var status = SekaiRenderStatus.preparing
  @State private var isVisible = false

  public init(
    camera: Binding<SekaiCamera>,
    style: SekaiStyle = .automatic,
    activity: SekaiActivity = .active(),
    interaction: SekaiInteraction = .rotationAndZoom,
    markers: [SekaiMarker] = [],
    arcs: [SekaiArc] = [],
    regions: [SekaiRegionHighlight] = [],
    onStatusChange: (@MainActor (SekaiRenderStatus) -> Void)? = nil
  ) {
    _camera = camera
    self.style = style
    self.activity = activity
    self.interaction = interaction
    self.markers = markers
    self.arcs = arcs
    self.regions = regions
    self.onStatusChange = onStatusChange
  }

  public var body: some View {
    SekaiMetalView(
      input: SekaiRenderInput(
        camera: camera, style: style, activity: activity, interaction: interaction,
        markers: markers, arcs: arcs, regions: regions, dark: colorScheme == .dark,
        allowsMotion: !reduceMotion, isSceneActive: isVisible && scenePhase == .active
      ),
      onCameraChange: { camera = $0 },
      onStatusChange: { next in
        guard status != next else { return }
        status = next
        onStatusChange?(next)
      }
    )
    .overlay {
      if case .failed = status {
        Circle().fill(.quaternary).padding()
          .overlay { Image(systemName: "globe").font(.largeTitle).foregroundStyle(.secondary) }
          .allowsHitTesting(false)
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Globe")
    .onAppear { isVisible = true }
    .onDisappear { isVisible = false }
  }
}
