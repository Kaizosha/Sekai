import Foundation

struct SekaiMotion {
  private(set) var angle = 0.0
  private var timestamp: Double?
  private var speed = 0.0

  mutating func update(at now: Double, speed nextSpeed: Double) {
    if let timestamp {
      angle = (angle + max(0, now - timestamp) * speed).truncatingRemainder(dividingBy: .pi * 2)
    }
    timestamp = now
    speed = nextSpeed.isFinite ? nextSpeed : 0
  }

  mutating func consume(at now: Double) -> Double {
    update(at: now, speed: speed)
    let result = angle
    angle = 0
    return result
  }
}
