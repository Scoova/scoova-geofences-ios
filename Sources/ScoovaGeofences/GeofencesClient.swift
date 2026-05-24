import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Options for ``GeofencesClient``.
public struct GeofencesClientOptions: Sendable {
    public let apiKey: String
    public let baseURL: URL
    public let iosBundleId: String?
    public let locale: String?
    public let urlSession: URLSession

    /// - Parameters:
    ///   - apiKey: Defaults to `SCOOVA_API_KEY` env, then `"demo"`.
    ///   - baseURL: Defaults to `https://api.scoo-va.info/api/v1`.
    ///   - iosBundleId: Sent as `X-Ios-Bundle-Identifier`. Defaults to
    ///     `Bundle.main.bundleIdentifier`.
    ///   - locale: Default locale (BCP-47, e.g. `en`, `fr`, `pt-BR`). Sent as
    ///     `?locale=` and `Accept-Language` header. Per-call overrides supported.
    ///   - urlSession: Inject a custom session for proxies, mocks, logging.
    public init(
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.scoo-va.info/api/v1")!,
        iosBundleId: String? = Bundle.main.bundleIdentifier,
        locale: String? = nil,
        urlSession: URLSession = .shared
    ) {
        if let k = apiKey, !k.isEmpty {
            self.apiKey = k
        } else if let env = ProcessInfo.processInfo.environment["SCOOVA_API_KEY"], !env.isEmpty {
            self.apiKey = env
        } else {
            self.apiKey = "demo"
        }
        self.baseURL = baseURL
        self.iosBundleId = iosBundleId
        self.locale = locale
        self.urlSession = urlSession
    }
}

/// Standalone client for the Scoova geofences API at
/// `https://api.scoo-va.info/api/v1/geofences`.
///
/// Stored named polygons plus point-in-polygon containment checks. Useful for
/// service-area gating, no-parking zones, depot perimeters, school zones,
/// congestion zones — anything where a location needs to be tested against a
/// set of regions.
///
///     let client = GeofencesClient(options: .init(apiKey: "sk_live_…"))
///     let all = try await client.list()
///     let result = try await client.check(lat: 40.748, lon: -73.985)
///
/// Every method is `async` and throws ``GeofencesError`` on non-2xx with the
/// gateway's structured `code` (e.g. `NOT_FOUND`, `KEY_RESTRICTED`).
public final class GeofencesClient: @unchecked Sendable {
    public let options: GeofencesClientOptions
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(options: GeofencesClientOptions = GeofencesClientOptions()) {
        self.options = options
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public convenience init(apiKey: String? = nil, locale: String? = nil) {
        self.init(options: GeofencesClientOptions(apiKey: apiKey, locale: locale))
    }

    // ─── Public API ──────────────────────────────────────────────────────

    /// Every geofence stored on the account.
    public func list(locale: String? = nil) async throws -> [Geofence] {
        let env: Envelope<[Geofence]> = try await get("/geofences", locale: locale)
        return env.data ?? []
    }

    /// Look up one by id. Throws ``GeofencesError`` with `status=404`,
    /// `code="NOT_FOUND"` if the id doesn't exist.
    public func get(_ id: String, locale: String? = nil) async throws -> Geofence {
        guard !id.isEmpty else {
            throw GeofencesError(status: 400, code: "INVALID_ARGUMENT", message: "id is required")
        }
        let env: Envelope<Geofence> = try await get("/geofences/\(percentEncode(id))", locale: locale)
        guard let g = env.data else {
            throw GeofencesError(status: 404, code: "NOT_FOUND", message: "Geofence \(id) not found")
        }
        return g
    }

    /// Store a new geofence. `geometry` must be a GeoJSON `Polygon` or
    /// `MultiPolygon`. The server returns `{id, name, createdAt}` only —
    /// this method re-fetches the full record so callers always get a
    /// complete ``Geofence`` back.
    public func create(name: String, geometry: AnyJSON, locale: String? = nil) async throws -> Geofence {
        guard !name.isEmpty else {
            throw GeofencesError(status: 400, code: "INVALID_ARGUMENT", message: "name is required")
        }
        struct Body: Encodable { let name: String; let geometry: AnyJSON }
        let env: Envelope<GeofenceCreated> = try await post(
            "/geofences",
            body: Body(name: name, geometry: geometry),
            locale: locale,
        )
        guard let created = env.data else {
            throw GeofencesError(status: 500, code: nil, message: "create response missing data")
        }
        return try await get(created.id, locale: locale)
    }

    /// Remove a geofence. No-op success if it already didn't exist.
    public func delete(_ id: String, locale: String? = nil) async throws {
        guard !id.isEmpty else {
            throw GeofencesError(status: 400, code: "INVALID_ARGUMENT", message: "id is required")
        }
        _ = try await execute(request: request(
            url: url("/geofences/\(percentEncode(id))", locale: locale),
            method: "DELETE",
            body: nil,
            locale: locale,
        ))
    }

    /// Alias of ``delete(_:locale:)`` — matches the Flutter SDK's `remove()` naming.
    public func remove(_ id: String, locale: String? = nil) async throws {
        try await delete(id, locale: locale)
    }

    /// Returns every geofence on this account whose polygon contains the
    /// supplied point. `inside` is empty if none match.
    public func check(lat: Double, lon: Double, locale: String? = nil) async throws -> GeofenceCheckResult {
        struct Body: Encodable { let lat: Double; let lon: Double }
        let env: Envelope<GeofenceCheckResult> = try await post(
            "/geofences/check",
            body: Body(lat: lat, lon: lon),
            locale: locale,
        )
        return env.data ?? GeofenceCheckResult(point: LatLon(lat: lat, lon: lon), inside: [])
    }

    // ─── HTTP plumbing ───────────────────────────────────────────────────

    private func url(_ path: String, locale: String?) -> URL {
        var comps = URLComponents()
        comps.scheme = options.baseURL.scheme
        comps.host = options.baseURL.host
        comps.port = options.baseURL.port
        comps.path = options.baseURL.path + (path.hasPrefix("/") ? path : "/" + path)
        if let loc = locale ?? options.locale {
            comps.queryItems = [URLQueryItem(name: "locale", value: loc)]
        }
        return comps.url!
    }

    private func request(url: URL, method: String, body: Data?, locale: String?) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(options.apiKey, forHTTPHeaderField: "X-API-Key")
        if let bid = options.iosBundleId, !bid.isEmpty {
            r.setValue(bid, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        if let loc = locale ?? options.locale {
            r.setValue(loc, forHTTPHeaderField: "Accept-Language")
        }
        if let body {
            r.httpBody = body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        return r
    }

    private func execute(request: URLRequest) async throws -> Data {
        let (data, resp): (Data, URLResponse)
        #if canImport(FoundationNetworking)
        (data, resp) = try await withCheckedThrowingContinuation { cont in
            options.urlSession.dataTask(with: request) { d, r, e in
                if let e { cont.resume(throwing: e) }
                else if let d, let r { cont.resume(returning: (d, r)) }
                else { cont.resume(throwing: GeofencesError(status: 0, message: "no response")) }
            }.resume()
        }
        #else
        (data, resp) = try await options.urlSession.data(for: request)
        #endif

        guard let http = resp as? HTTPURLResponse else {
            throw GeofencesError(status: 0, code: nil, message: "no HTTP response")
        }
        if !(200..<300).contains(http.statusCode) {
            let (code, msg) = parseError(data)
            throw GeofencesError(
                status: http.statusCode,
                code: code,
                message: msg ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
            )
        }
        return data
    }

    private func parseError(_ data: Data) -> (String?, String?) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }
        return (obj["code"] as? String, obj["error"] as? String)
    }

    private func get<T: Decodable>(_ path: String, locale: String?) async throws -> T {
        let req = request(url: url(path, locale: locale), method: "GET", body: nil, locale: locale)
        let data = try await execute(request: req)
        return try decoder.decode(T.self, from: data)
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B, locale: String?) async throws -> T {
        let payload = try encoder.encode(body)
        let req = request(url: url(path, locale: locale), method: "POST", body: payload, locale: locale)
        let data = try await execute(request: req)
        return try decoder.decode(T.self, from: data)
    }

    private func percentEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}
