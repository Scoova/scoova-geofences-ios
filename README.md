# ScoovaGeofences

Swift client for the Scoova geofences API at
`https://api.scoo-va.info/v1/geofences`.

Stored named polygons plus point-in-polygon containment checks. Useful for
service-area gating, no-parking zones, depot perimeters, school zones,
congestion zones — anything where a location needs to be tested against a
set of regions.

## Install — Swift Package Manager

In Xcode: **File → Add Packages…** and paste

```
https://github.com/Scoova/scoova-geofences-ios.git
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/Scoova/scoova-geofences-ios.git", from: "1.0.1")
```

Then add `ScoovaGeofences` to your target dependencies.

## Quick start

```swift
import ScoovaGeofences

let client = GeofencesClient(apiKey: ProcessInfo.processInfo.environment["SCOOVA_API_KEY"])

Task {
    // Save a polygon
    let geometry = AnyJSON(rawValue: [
        "type": "Polygon",
        "coordinates": [[
            [-74.020, 40.700], [-73.910, 40.700],
            [-73.910, 40.880], [-74.020, 40.880],
            [-74.020, 40.700],
        ]],
    ])
    let created = try await client.create(name: "Manhattan service area", geometry: geometry)

    // List
    let all = try await client.list()

    // Point-in-polygon
    let result = try await client.check(lat: 40.748, lon: -73.985)
    print(result.inside.map(\.name)) // ["Manhattan service area"]

    // Delete
    try await client.delete(created.id)
}
```

## Methods

| Method | Description |
| --- | --- |
| `list()` | Every geofence on the account. |
| `get(_ id:)` | One geofence by id, with full geometry. |
| `create(name:geometry:)` | Save a new geofence. Returns the full record. |
| `delete(_ id:)` (alias: `remove(_:)`) | Remove one. |
| `check(lat:lon:)` | Returns every geofence whose polygon contains the point. |

Every method accepts an optional trailing `locale:` parameter to override the
client-default locale for that call.

## Locale

```swift
let client = GeofencesClient(apiKey: "…", locale: "fr")
```

Sent as `?locale=fr` and `Accept-Language: fr`. Per-call `locale:` overrides
the client default.

Accepted codes: `en`, `en-US`, `en-GB`, `en-CA`, `fr`, `es`, `de`, `it`,
`pt-BR`, `nl`, plus their regional variants.

## Errors

```swift
do {
    _ = try await client.get("does-not-exist")
} catch let e as GeofencesError {
    print(e.status)  // 404
    print(e.code)    // Optional("NOT_FOUND")
}
```

## License

Apache-2.0. Copyright 2026 Scoova.
