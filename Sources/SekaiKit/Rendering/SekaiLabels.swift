import SwiftUI

struct SekaiLabelOverlay: View {
    let scene: SekaiPreparedScene?
    let camera: SekaiCamera
    let defaultStyle: SekaiStyle
    let layers: [SekaiLayer]
    let colorScheme: ColorScheme
    let autoRotationSpeed: Double
    let rotationClock: SekaiRotationClock

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: autoRotationSpeed == 0)) { timeline in
            GeometryReader { geometry in
                let labels = placedLabels(
                    size: geometry.size,
                    timestamp: timeline.date.timeIntervalSinceReferenceDate
                )
                ForEach(labels) { label in
                    labelView(label)
                        .position(label.point)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func labelView(_ label: PlacedLabel) -> some View {
        let foreground = label.style.color.sekaiResolved(dark: colorScheme == .dark).swiftUIColor
        Text(label.text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 160)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            #if os(visionOS)
            .glassBackgroundEffect(in: Capsule())
            #else
            .glassEffect(.clear, in: .capsule)
            #endif
    }

    @MainActor
    private func placedLabels(size: CGSize, timestamp: TimeInterval) -> [PlacedLabel] {
        guard let scene else { return [] }
        let lookup = SekaiLayerVisualStyles(layers: layers)
        let angle = rotationClock.angle(at: timestamp, speed: autoRotationSpeed)
        let projection = SekaiProjectionContext(size: size, camera: camera, spinAngle: angle)
        var occupied: [CGRect] = []
        var layerCounts: [String: Int] = [:]
        var output: [PlacedLabel] = []

        for label in scene.labels.sorted(by: { $0.priority > $1.priority }) {
            let style = lookup.labels[label.layerID] ?? label.styleOverride ?? defaultStyle.labels
            guard camera.zoom >= style.minimumZoom,
                  layerCounts[label.layerID, default: 0] < max(style.maximumCount, 0),
                  let projected = projection.project(label.coordinate) else { continue }
            let width = CGFloat(min(max(Double(label.text.count) * 6.6 + 16, 42), 180))
            let height = CGFloat(24)
            let padding = CGFloat(max(style.collisionPadding, 0))
            let frame = CGRect(
                x: projected.point.x - width * 0.5 - padding,
                y: projected.point.y - height * 0.5 - padding,
                width: width + padding * 2,
                height: height + padding * 2
            )
            guard frame.minX >= 0, frame.maxX <= size.width,
                  frame.minY >= 0, frame.maxY <= size.height,
                  !occupied.contains(where: { $0.intersects(frame) }) else { continue }
            occupied.append(frame)
            layerCounts[label.layerID, default: 0] += 1
            output.append(PlacedLabel(
                id: label.id,
                text: label.text,
                point: projected.point,
                style: style
            ))
        }
        return output
    }
}

private struct PlacedLabel: Identifiable {
    let id: String
    let text: String
    let point: CGPoint
    let style: SekaiLabelStyle
}

extension SekaiAdaptiveColor {
    func sekaiResolved(dark: Bool) -> SekaiColor {
        switch self {
        case let .fixed(value): value.normalized()
        case let .appearance(light, dark: darkValue): (dark ? darkValue : light).normalized()
        }
    }
}
