import Foundation

/// A point on the WGS84 ellipsoid.
public struct LatLon: Codable, Sendable, Hashable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

/// A stored geofence on the account. `geometry` is opaque GeoJSON
/// (`Polygon` or `MultiPolygon`).
public struct Geofence: Codable, Sendable {
    public let id: String
    public let name: String
    public let geometry: AnyJSON
    public let createdAt: Int64?

    public init(id: String, name: String, geometry: AnyJSON, createdAt: Int64? = nil) {
        self.id = id; self.name = name; self.geometry = geometry; self.createdAt = createdAt
    }
}

/// Reference to a geofence (id + name) without the heavy geometry payload.
public struct GeofenceRef: Codable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// Result of a containment check. `inside` is empty if no fences match.
public struct GeofenceCheckResult: Codable, Sendable {
    public let point: LatLon
    public let inside: [GeofenceRef]
    public init(point: LatLon, inside: [GeofenceRef]) {
        self.point = point; self.inside = inside
    }
}

/// Server response shape on a successful create.
internal struct GeofenceCreated: Codable, Sendable {
    let id: String
    let name: String
    let createdAt: Int64
}

/// Thrown on any non-2xx response from the gateway.
public struct GeofencesError: Error, CustomStringConvertible, Sendable {
    public let status: Int
    public let code: String?
    public let message: String

    public init(status: Int, code: String? = nil, message: String) {
        self.status = status; self.code = code; self.message = message
    }

    public var description: String {
        "GeofencesError(status=\(status), code=\(code ?? "—"), message=\(message))"
    }
}

/// Generic envelope for the gateway's `{success, data, error?, code?}` shape.
internal struct Envelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
    let code: String?
}

/// Opaque JSON carrier used for `geometry` so the SDK doesn't force callers
/// through a constrained shape for legitimate exotic GeoJSON.
public struct AnyJSON: Codable, @unchecked Sendable {
    public let rawValue: Any
    public init(rawValue: Any) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.rawValue = NSNull(); return }
        if let v = try? c.decode(Bool.self)   { self.rawValue = v; return }
        if let v = try? c.decode(Int64.self)  { self.rawValue = v; return }
        if let v = try? c.decode(Double.self) { self.rawValue = v; return }
        if let v = try? c.decode(String.self) { self.rawValue = v; return }
        if let v = try? c.decode([AnyJSON].self) { self.rawValue = v.map { $0.rawValue }; return }
        if let v = try? c.decode([String: AnyJSON].self) {
            self.rawValue = v.mapValues { $0.rawValue }; return
        }
        self.rawValue = NSNull()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch rawValue {
        case is NSNull: try c.encodeNil()
        case let b as Bool: try c.encode(b)
        case let i as Int64: try c.encode(i)
        case let i as Int: try c.encode(Int64(i))
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let arr as [Any]: try c.encode(arr.map { AnyJSON(rawValue: $0) })
        case let obj as [String: Any]: try c.encode(obj.mapValues { AnyJSON(rawValue: $0) })
        default: try c.encodeNil()
        }
    }
}
