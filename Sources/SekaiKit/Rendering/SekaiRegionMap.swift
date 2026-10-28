import Foundation
import ImageIO

struct SekaiRegionMap: Sendable {
  static let maximumIdentifier = 26 * 26
  static let bundled: SekaiRegionMap? = {
    guard landMask != nil, let url = Bundle.module.url(forResource: "RegionMask", withExtension: "rle"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return Self(data: data)
  }()

  private static let landMask: [UInt8]? = {
    guard let url = Bundle.module.url(forResource: "LandMask", withExtension: "png"),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == 256, image.height == 128, image.bitsPerPixel == 8,
      image.bytesPerRow == 256, let bytes = image.dataProvider?.data,
      CFDataGetLength(bytes) == 256 * 128
    else { return nil }
    return [UInt8](bytes as Data)
  }()

  let width: Int
  let height: Int
  let identifiers: [UInt16]
  private let knownIdentifiers: Set<UInt16>

  init?(data: Data) {
    let bytes = [UInt8](data)
    guard bytes.count >= 12, Array(bytes.prefix(6)) == [83, 75, 82, 71, 2, 0]
    else { return nil }
    func word(_ offset: Int) -> Int { Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) }
    let width = word(6), height = word(8), registryCount = word(10)
    let runsStart = 12 + registryCount * 2
    guard width == 1024, height == 512, (1...Self.maximumIdentifier).contains(registryCount),
      bytes.count >= runsStart, (bytes.count - runsStart).isMultiple(of: 4)
    else { return nil }
    var registry = Set<UInt16>()
    for offset in stride(from: 12, to: runsStart, by: 2) {
      let identifier = word(offset)
      guard (1...Self.maximumIdentifier).contains(identifier),
        registry.insert(UInt16(identifier)).inserted else { return nil }
    }
    var values: [UInt16] = []
    values.reserveCapacity(width * height)
    for offset in stride(from: runsStart, to: bytes.count, by: 4) {
      let identifier = word(offset), count = word(offset + 2)
      guard identifier == 0 || registry.contains(UInt16(identifier)), count > 0,
        count <= width * height - values.count
      else { return nil }
      values.append(contentsOf: repeatElement(UInt16(identifier), count: count))
    }
    guard values.count == width * height else { return nil }
    self.width = width
    self.height = height
    identifiers = values
    knownIdentifiers = registry
  }

  static func identifier(for regionCode: String) -> UInt16? {
    let code = Array(regionCode.utf8)
    guard code.count == 2, code.allSatisfy({ (65...90).contains($0) }) else { return nil }
    let identifier = UInt16(code[0] - 65) * 26 + UInt16(code[1] - 65) + 1
    return bundled?.knownIdentifiers.contains(identifier) == true ? identifier : nil
  }

  func identifier(at coordinate: SekaiCoordinate) -> UInt16 {
    identifier(u: coordinate.longitude / 360 + 0.5, v: 0.5 - coordinate.latitude / 180)
  }

  private func identifier(u: Double, v: Double) -> UInt16 {
    let x = Int(floor((u - floor(u)) * Double(width)))
    let y = min(height - 1, max(0, Int(floor(v * Double(height)))))
    return identifiers[y * width + x]
  }

  func sampledIdentifiers(count: Int) -> Set<UInt16> {
    guard let landMask = Self.landMask else { return [] }
    let count = min(max(count, 512), 32_768)
    var result = Set<UInt16>()
    for index in 0..<count {
      let turn = Float(UInt32(index) &* 0x9e3779b9) / 4_294_967_296
      let angle = turn * 6.28318530718
      let latitude = asin(min(1, max(-1, 1 - 2 * Float(index) / Float(count))))
      let longitude = atan2(cos(angle), sin(angle))
      let u = longitude / (2 * .pi) + 0.5
      let v = 0.5 - latitude / .pi
      let x = Int(floor((u - floor(u)) * 256))
      let y = Int(floor((v - floor(v)) * 128))
      let value = identifier(u: Double(u), v: Double(v))
      if value != 0 && landMask[y * 256 + x] > 0 { result.insert(value) }
    }
    return result
  }
}
