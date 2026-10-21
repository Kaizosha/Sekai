import SekaiKit
import SwiftUI

@main
struct SekaiDemoApp: App {
  var body: some Scene {
    WindowGroup {
      GlobeExample()
    }
  }
}

private struct GlobeExample: View {
  @State private var camera = SekaiCamera.standard
  @State private var rotates = true
  @State private var showsOverlays = true
  @State private var appearance = GlobeAppearance.system
  @State private var status = SekaiRenderStatus.preparing

  private let chicago = SekaiCoordinate(latitude: 41.8781, longitude: -87.6298)
  private let tokyo = SekaiCoordinate(latitude: 35.6762, longitude: 139.6503)

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          Sekai(
            camera: $camera,
            style: appearance.style,
            activity: .active(rotationSpeed: rotates ? 0.08 : 0),
            interaction: .rotationAndZoom,
            markers: markers,
            arcs: arcs,
            onStatusChange: { status = $0 }
          )
          .aspectRatio(1, contentMode: .fit)
          .accessibilityIdentifier("sekai.demo.globe")

          if case .failed = status {
            Text("Metal rendering is unavailable.")
              .foregroundStyle(.secondary)
              .accessibilityIdentifier("sekai.demo.failure")
          }

          VStack(spacing: 20) {
            Picker("Appearance", selection: $appearance) {
              ForEach(GlobeAppearance.allCases) { option in
                Text(option.rawValue).tag(option)
              }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sekai.demo.appearance")

            Toggle("Rotate globe", isOn: $rotates)
              .accessibilityIdentifier("sekai.demo.rotate")
            Toggle("Show markers and arc", isOn: $showsOverlays)
              .accessibilityIdentifier("sekai.demo.overlays")

            HStack {
              Button("Show Tokyo") { camera.focus(on: tokyo) }
                .accessibilityIdentifier("sekai.demo.tokyo")
              Spacer()
              Button("Reset camera") { camera = .standard }
                .accessibilityIdentifier("sekai.demo.reset")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
          }
          .padding(.horizontal)
        }
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
        .padding()
      }
      .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
      .navigationTitle("Sekai")
    }
  }

  private var markers: [SekaiMarker] {
    showsOverlays
      ? [
        .init(id: "chicago", coordinate: chicago),
        .init(id: "tokyo", coordinate: tokyo),
      ] : []
  }

  private var arcs: [SekaiArc] {
    showsOverlays ? [.init(id: "chicago-tokyo", from: chicago, to: tokyo)] : []
  }
}

private enum GlobeAppearance: String, Identifiable, CaseIterable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var id: String { rawValue }

  var style: SekaiStyle {
    switch self {
    case .system: .automatic
    case .light: .light
    case .dark: .dark
    }
  }
}
