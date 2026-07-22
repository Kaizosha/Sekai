import Foundation

public enum SekaiAtlasError: Error, LocalizedError, Sendable {
    case missingBundledAtlas
    case invalidHeader
    case unsupportedVersion(Int)
    case truncatedData
    case invalidMetadata

    public var errorDescription: String? {
        switch self {
        case .missingBundledAtlas: "The bundled Sekai atlas is missing."
        case .invalidHeader: "The Sekai atlas header is invalid."
        case let .unsupportedVersion(version): "Sekai atlas version \(version) is unsupported."
        case .truncatedData: "The Sekai atlas is incomplete."
        case .invalidMetadata: "The Sekai atlas metadata is invalid."
        }
    }
}

public struct SekaiAtlasInformation: Equatable, Sendable {
    public let source: String
    public let sourceVersion: String
    public let sourceSHA256: String
    public let particleCount: Int
    public let mapUnitCount: Int
    public let levelOfDetailTolerances: [Double]
}

public struct SekaiAtlasParticle: Equatable, Sendable {
    public let coordinate: SekaiCoordinate
    public let featureID: SekaiFeatureID
    public let rank: Int
    public let regionalRank: Int
}

/// The immutable, memory-mapped source of geography used by every Sekai layer.
public final class SekaiAtlas: @unchecked Sendable {
    public static let maximumParticleCount = 1_048_576

    public static let bundled: SekaiAtlas = {
        do { return try SekaiAtlas() }
        catch { fatalError("Unable to load SekaiWorld.sekaiatlas: \(error)") }
    }()

    public let information: SekaiAtlasInformation
    public let features: [SekaiFeature]
    public let continents: [String]
    public let sovereigns: [SekaiFeatureID: String]
    public let countries: [SekaiFeatureID: String]
    public let worldviews: [SekaiWorldview]

    private let data: Data
    private let header: Header
    private let metadata: Metadata
    private let featureIndexes: [SekaiFeatureID: Int]
    private let sovereignIndexes: [SekaiFeatureID: Int]
    private let countryIndexes: [SekaiFeatureID: Int]

    public convenience init() throws {
        guard let url = Bundle.module.url(forResource: "SekaiWorld", withExtension: "sekaiatlas") else {
            throw SekaiAtlasError.missingBundledAtlas
        }
        try self.init(contentsOf: url)
    }

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let header = try Header(data: data)
        guard header.fileLength <= data.count else { throw SekaiAtlasError.truncatedData }
        let metadataRange = header.headerSize..<(header.headerSize + header.metadataLength)
        guard metadataRange.upperBound <= data.count else { throw SekaiAtlasError.truncatedData }
        guard let metadata = try? JSONDecoder().decode(Metadata.self, from: data[metadataRange]) else {
            throw SekaiAtlasError.invalidMetadata
        }
        guard metadata.mapUnits.count == header.featureCount else { throw SekaiAtlasError.invalidMetadata }

        self.data = data
        self.header = header
        self.metadata = metadata
        continents = metadata.continents
        sovereigns = Dictionary(uniqueKeysWithValues: metadata.sovereigns.map {
            (SekaiFeatureID(rawValue: $0.id), $0.name)
        })
        countries = Dictionary(uniqueKeysWithValues: metadata.countries.map {
            (SekaiFeatureID(rawValue: $0.id), $0.name)
        })
        worldviews = metadata.worldviews.map(SekaiWorldview.init(rawValue:))
        features = metadata.mapUnits.map(Self.makeFeature)
        featureIndexes = Dictionary(uniqueKeysWithValues: features.enumerated().map { ($1.id, $0) })
        sovereignIndexes = Dictionary(uniqueKeysWithValues: metadata.sovereigns.enumerated().map {
            (SekaiFeatureID(rawValue: $1.id), $0)
        })
        countryIndexes = Dictionary(uniqueKeysWithValues: metadata.countries.enumerated().map {
            (SekaiFeatureID(rawValue: $1.id), $0)
        })
        information = SekaiAtlasInformation(
            source: metadata.source,
            sourceVersion: metadata.sourceVersion,
            sourceSHA256: metadata.sourceSHA256,
            particleCount: header.pointCount,
            mapUnitCount: header.featureCount,
            levelOfDetailTolerances: metadata.lodTolerancesDegrees
        )
    }

    public func feature(id: SekaiFeatureID) -> SekaiFeature? {
        featureIndexes[id].map { features[$0] }
    }

    public func search(_ query: String, locale: Locale = .current) -> [SekaiFeature] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return features }
        return features.filter { feature in
            feature.id.rawValue.localizedCaseInsensitiveContains(needle)
                || feature.name.localizedCaseInsensitiveContains(needle)
                || feature.longName.localizedCaseInsensitiveContains(needle)
                || feature.localizedName(locale: locale).localizedCaseInsensitiveContains(needle)
                || feature.isoA2?.localizedCaseInsensitiveContains(needle) == true
                || feature.isoA3?.localizedCaseInsensitiveContains(needle) == true
        }
    }

    public func availableParticleCount(for filter: SekaiRegionFilter = .allLand) -> Int {
        if case .allLand = filter { return header.pointCount }
        return selectedFeatureIndexes(for: filter).reduce(into: 0) { total, index in
            total += features[index].particleCount
        }
    }

    public func particles(
        matching filter: SekaiRegionFilter = .allLand,
        density: SekaiParticleDensity = .automatic,
        automaticLimit: Int = 32_768
    ) -> [SekaiAtlasParticle] {
        let requested: Int
        switch density {
        case .maximum: requested = .max
        case let .count(value): requested = max(0, value)
        case .automatic: requested = max(0, automaticLimit)
        case .fraction: requested = .max
        }
        guard requested != 0 else { return [] }

        var records: [PointRecord] = []
        records.reserveCapacity(min(header.pointCount, requested == .max ? header.pointCount : requested))
        for rank in 0..<header.pointCount {
            let record = point(at: rank)
            guard matches(record, filter: filter) else { continue }
            records.append(record.with(rank: rank))
            if requested != .max, records.count == requested { break }
        }
        if case let .fraction(value) = density {
            let fraction = min(max(value, 0), 1)
            records = Array(records.prefix(Int((Double(records.count) * fraction).rounded(.down))))
        }
        return records.map { record in
            SekaiAtlasParticle(
                coordinate: record.coordinate,
                featureID: features[record.featureIndex].id,
                rank: record.rank,
                regionalRank: record.regionalRank
            )
        }
    }

    func packedParticles(
        matching filter: SekaiRegionFilter,
        density: SekaiParticleDensity,
        automaticLimit: Int
    ) -> [PackedParticle] {
        let limit: Int
        switch density {
        case .maximum: limit = .max
        case let .count(value): limit = max(0, value)
        case .automatic: limit = max(0, automaticLimit)
        case let .fraction(value):
            let available = availableParticleCount(for: filter)
            limit = Int((Double(available) * min(max(value, 0), 1)).rounded(.down))
        }
        guard limit != 0 else { return [] }
        var output: [PackedParticle] = []
        output.reserveCapacity(min(header.pointCount, limit == .max ? header.pointCount : limit))
        for rank in 0..<header.pointCount {
            let record = point(at: rank)
            guard matches(record, filter: filter) else { continue }
            let vector = SekaiVector3(record.coordinate)
            output.append(PackedParticle(
                position: SIMD3(Float(vector.x), Float(vector.y), Float(vector.z)),
                rank: UInt32(rank)
            ))
            if limit != .max, output.count == limit { break }
        }
        return output
    }

    func packedBoundaryVertices(matching filter: SekaiRegionFilter, levelOfDetail: Int) -> [PackedParticle] {
        let selected = selectedFeatureIndexes(for: filter)
        let lod = UInt8(min(max(levelOfDetail, 0), 2))
        var output: [PackedParticle] = []
        output.reserveCapacity(min(header.lineSegmentCount * 2, 2_000_000))
        for index in 0..<header.lineSegmentCount {
            let offset = header.lineSegmentsOffset + index * 12
            guard data[offset + 2] == lod, selected.contains(Int(data.uint16(at: offset))) else { continue }
            output.append(PackedParticle(quantizedLatitude: data.uint16(at: offset + 4), quantizedLongitude: data.uint16(at: offset + 6)))
            output.append(PackedParticle(quantizedLatitude: data.uint16(at: offset + 8), quantizedLongitude: data.uint16(at: offset + 10)))
        }
        return output
    }

    func packedBoundaryFillVertices(matching filter: SekaiRegionFilter, levelOfDetail: Int) -> [PackedParticle] {
        let selected = selectedFeatureIndexes(for: filter)
        let lod = UInt8(min(max(levelOfDetail, 0), 2))
        var output: [PackedParticle] = []
        for recordIndex in 0..<header.meshRecordCount {
            let recordOffset = header.meshRecordsOffset + recordIndex * 20
            guard data[recordOffset + 2] == lod,
                  selected.contains(Int(data.uint16(at: recordOffset))) else { continue }
            let indexStart = Int(data.uint32(at: recordOffset + 12))
            let indexCount = Int(data.uint32(at: recordOffset + 16))
            output.reserveCapacity(output.count + indexCount)
            for localIndex in 0..<indexCount {
                let vertexIndex = Int(data.uint32(at: header.meshIndicesOffset + (indexStart + localIndex) * 4))
                let vertexOffset = header.meshVerticesOffset + vertexIndex * 4
                output.append(PackedParticle(
                    quantizedLatitude: data.uint16(at: vertexOffset),
                    quantizedLongitude: data.uint16(at: vertexOffset + 2)
                ))
            }
        }
        return output
    }

    private func selectedFeatureIndexes(for filter: SekaiRegionFilter) -> Set<Int> {
        switch filter {
        case .allLand: Set(features.indices)
        case let .continent(name):
            Set(features.indices.filter { features[$0].continent.localizedCaseInsensitiveCompare(name) == .orderedSame })
        case let .sovereign(id):
            Set(metadata.mapUnits.indices.filter { metadata.mapUnits[$0].sovereignID == id.rawValue })
        case let .country(id):
            Set(metadata.mapUnits.indices.filter { metadata.mapUnits[$0].countryID == id.rawValue })
        case let .mapUnit(id): featureIndexes[id].map { Set([$0]) } ?? []
        case let .features(ids): Set(ids.compactMap { featureIndexes[$0] })
        }
    }

    private func point(at rank: Int) -> PointRecord {
        let offset = header.pointsOffset + rank * PointRecord.byteCount
        return PointRecord(
            latitude: data.uint16(at: offset),
            longitude: data.uint16(at: offset + 2),
            continentIndex: Int(data[offset + 4]),
            flags: data[offset + 5],
            featureIndex: Int(data.uint16(at: offset + 6)),
            sovereignIndex: Int(data.uint16(at: offset + 8)),
            countryIndex: Int(data.uint16(at: offset + 10)),
            regionalRank: Int(data.uint32(at: offset + 12)),
            rank: rank
        )
    }

    private func matches(_ point: PointRecord, filter: SekaiRegionFilter) -> Bool {
        switch filter {
        case .allLand: true
        case let .continent(name):
            continents.indices.contains(point.continentIndex)
                && continents[point.continentIndex].localizedCaseInsensitiveCompare(name) == .orderedSame
        case let .sovereign(id): sovereignIndexes[id] == point.sovereignIndex
        case let .country(id): countryIndexes[id] == point.countryIndex
        case let .mapUnit(id): featureIndexes[id] == point.featureIndex
        case let .features(ids): ids.contains(features[point.featureIndex].id)
        }
    }

    private static func makeFeature(_ unit: MapUnit) -> SekaiFeature {
        let kind: SekaiFeatureKind = switch unit.type.lowercased() {
        case let value where value.contains("disputed") || value.contains("indeterminate"): .disputed
        case let value where value.contains("dependency") || value.contains("territory"): .dependency
        case let value where value.contains("country") || value.contains("sovereign"): .country
        default: .territory
        }
        let bounds = unit.bounds.count == 4
            ? SekaiCoordinateBounds(
                south: unit.bounds[0], west: unit.bounds[1],
                north: unit.bounds[2], east: unit.bounds[3]
            )
            : .world
        let label = unit.label.count == 2
            ? SekaiCoordinate(latitude: unit.label[0], longitude: unit.label[1])
            : SekaiCoordinate(latitude: 0, longitude: 0)
        return SekaiFeature(
            id: SekaiFeatureID(rawValue: unit.id), name: unit.name, longName: unit.longName,
            kind: kind, continent: unit.continent, region: unit.region, subregion: unit.subregion,
            sovereignID: SekaiFeatureID(rawValue: unit.sovereignID),
            countryID: SekaiFeatureID(rawValue: unit.countryID), isoA2: unit.isoA2.nilIfPlaceholder,
            isoA3: unit.isoA3.nilIfPlaceholder, labelCoordinate: label, bounds: bounds,
            minimumZoom: unit.minimumZoom, particleCount: unit.particleCount,
            localizedNames: unit.names, worldviewClassifications: unit.worldview
        )
    }
}

struct PackedParticle: Sendable {
    let position: SIMD3<Float>
    let rank: UInt32

    init(_ coordinate: SekaiCoordinate, elevation: Double = 0) {
        let vector = SekaiVector3(coordinate, radius: 1 + elevation)
        position = SIMD3(Float(vector.x), Float(vector.y), Float(vector.z))
        rank = 0
    }

    init(quantizedLatitude: UInt16, quantizedLongitude: UInt16) {
        self.init(SekaiCoordinate(
            latitude: Double(quantizedLatitude) / 65_535 * 180 - 90,
            longitude: Double(quantizedLongitude) / 65_535 * 360 - 180
        ), elevation: 0.002)
    }

    init(position: SIMD3<Float>, rank: UInt32) {
        self.position = position
        self.rank = rank
    }
}

private struct Header {
    static let magic = Array("SEKAIAT\0".utf8)
    let headerSize: Int
    let pointCount: Int
    let featureCount: Int
    let metadataLength: Int
    let pointsOffset: Int
    let lineSegmentsOffset: Int
    let lineSegmentCount: Int
    let meshRecordsOffset: Int
    let meshVerticesOffset: Int
    let meshIndicesOffset: Int
    let meshRecordCount: Int
    let fileLength: Int

    init(data: Data) throws {
        guard data.count >= 128, Array(data.prefix(8)) == Self.magic else { throw SekaiAtlasError.invalidHeader }
        let version = Int(data.uint32(at: 8))
        guard version == 1 else { throw SekaiAtlasError.unsupportedVersion(version) }
        headerSize = Int(data.uint32(at: 12))
        pointCount = Int(data.uint32(at: 16))
        featureCount = Int(data.uint32(at: 20))
        meshRecordCount = Int(data.uint32(at: 24))
        lineSegmentCount = Int(data.uint32(at: 36))
        metadataLength = Int(data.uint64(at: 40))
        pointsOffset = Int(data.uint64(at: 48))
        meshRecordsOffset = Int(data.uint64(at: 56))
        meshVerticesOffset = Int(data.uint64(at: 64))
        meshIndicesOffset = Int(data.uint64(at: 72))
        lineSegmentsOffset = Int(data.uint64(at: 80))
        fileLength = Int(data.uint64(at: 88))
        guard headerSize == 128, pointCount > 0, featureCount > 0,
              metadataLength > 0, pointsOffset >= headerSize,
              meshRecordsOffset >= pointsOffset, meshVerticesOffset >= meshRecordsOffset,
              meshIndicesOffset >= meshVerticesOffset, lineSegmentsOffset >= meshIndicesOffset,
              fileLength >= lineSegmentsOffset + lineSegmentCount * 12 else {
            throw SekaiAtlasError.invalidHeader
        }
    }
}

private struct PointRecord {
    static let byteCount = 16
    let latitude: UInt16
    let longitude: UInt16
    let continentIndex: Int
    let flags: UInt8
    let featureIndex: Int
    let sovereignIndex: Int
    let countryIndex: Int
    let regionalRank: Int
    var rank: Int

    var coordinate: SekaiCoordinate {
        SekaiCoordinate(
            latitude: Double(latitude) / 65_535 * 180 - 90,
            longitude: Double(longitude) / 65_535 * 360 - 180
        )
    }

    func with(rank: Int) -> Self {
        Self(latitude: latitude, longitude: longitude, continentIndex: continentIndex, flags: flags,
             featureIndex: featureIndex, sovereignIndex: sovereignIndex, countryIndex: countryIndex,
             regionalRank: regionalRank, rank: rank)
    }
}

private struct Metadata: Decodable {
    let source: String
    let sourceVersion: String
    let sourceSHA256: String
    let lodTolerancesDegrees: [Double]
    let continents: [String]
    let sovereigns: [Entity]
    let countries: [Entity]
    let worldviews: [String]
    let mapUnits: [MapUnit]
}

private struct Entity: Decodable { let id: String; let name: String }

private struct MapUnit: Decodable {
    let id: String
    let name: String
    let longName: String
    let type: String
    let continent: String
    let region: String
    let subregion: String
    let sovereignID: String
    let countryID: String
    let isoA2: String
    let isoA3: String
    let label: [Double]
    let bounds: [Double]
    let minimumZoom: Double
    let names: [String: String]
    let worldview: [String: String]
    let particleCount: Int
}

private extension String {
    var nilIfPlaceholder: String? {
        isEmpty || self == "-99" ? nil : self
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
    }

    func uint64(at offset: Int) -> UInt64 {
        UInt64(uint32(at: offset)) | UInt64(uint32(at: offset + 4)) << 32
    }
}
