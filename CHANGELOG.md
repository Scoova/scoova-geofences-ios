# Changelog

All notable changes to `ScoovaGeofences` are documented here.

## 1.0.0 — 2026-05-25

Initial release.

- `GeofencesClient` — `list`, `get`, `create`, `delete` (aliased as `remove`), `check`
- `GeofencesError` with `status` + structured gateway `code`
- Locale support via `?locale=` and `Accept-Language`, both client-default and per-call
- API key from constructor, falling back to `SCOOVA_API_KEY` env, falling back to `"demo"`
- `URLSession`-based transport with `async`/`await`
- iOS 15+, macOS 12+, tvOS 15+, watchOS 8+
