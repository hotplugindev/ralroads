<div align="center">
  <img src="images/logo.png" width="148" alt="RalRoads logo">

  # RalRoads

  **A road-aware co-driver for planning routes, recording drives, and sharing clean rally-style challenges.**

  RalRoads is an Android-first Flutter app that turns ordinary routes into readable pacenotes, live driving callouts, local trip history, and optional Matrix-powered community challenges.
</div>

## Product Tour

| Onboarding | Navigate | Route Planner |
| --- | --- | --- |
| <img src="images/screens/onboarding.svg" width="230" alt="Onboarding screen placeholder"> | <img src="images/screens/navigate.svg" width="230" alt="Navigate screen placeholder"> | <img src="images/screens/map-planner.svg" width="230" alt="Map planner screen placeholder"> |

| Route Preview | Drive HUD | Saved Routes |
| --- | --- | --- |
| <img src="images/screens/route-preview.svg" width="230" alt="Route preview screen placeholder"> | <img src="images/screens/drive-hud.svg" width="230" alt="Drive HUD screen placeholder"> | <img src="images/screens/saved-routes.svg" width="230" alt="Saved routes screen placeholder"> |

| Trips | Challenges | Community |
| --- | --- | --- |
| <img src="images/screens/trips.svg" width="230" alt="Trips screen placeholder"> | <img src="images/screens/challenges.svg" width="230" alt="Challenges screen placeholder"> | <img src="images/screens/community.svg" width="230" alt="Community screen placeholder"> |

The images above are placeholders. Replace the files in `images/screens/` with current app screenshots when they are ready.

## What It Does

RalRoads sits between a normal navigation app and a rally roadbook. It plans a route, analyzes the road geometry, enriches it with available OpenStreetMap context, and presents the drive as a clear sequence of upcoming corners, junctions, roundabouts, warnings, and distance cues.

The app is local-first where it matters: saved routes, trips, segments, attempts, settings, and social cache data live on device. Online services are used for routing, maps, search, OSM metadata, and optional Matrix sync.

## Highlights

- **Route planning**: search places, choose start and destination, add waypoints, preview geometry, and save only the routes you decide to keep.
- **Pacenote generation**: convert route geometry into straights, corners, opens/tightens, junctions, roundabouts, exits, warnings, and advisory context.
- **Drive HUD**: follow the route with a dark map, live speed, speed-limit display, upcoming callout banner, voice toggle, warning controls, progress, ETA, and reroute support.
- **Timed callouts**: spoken callouts are scheduled by distance and speed so the driver hears the next instruction before it matters.
- **Saved route management**: searchable and filterable saved routes with useful names based on start, destination, and creation date.
- **Trip recording**: record local drives, review summaries, inspect GPS quality, and share exported run data.
- **Segments and attempts**: crop a finished trip into a private segment, validate future attempts, and keep clean runs separate from poor-GPS runs.
- **Challenges**: create local rally challenges from saved segments, track active and past challenges, and compare attempts.
- **Matrix community layer**: optionally connect a Matrix account for profiles, friends, groups, notifications, directory events, shared segments, and challenge sync.
- **Offline readiness**: saved route data remains available locally, with a dedicated offline maps area for supported platforms.

## App Areas

| Area | Purpose |
| --- | --- |
| Onboarding | Set up OpenRouteService, local profile, Matrix connection, and readiness state. |
| Navigate | Plan new routes, reopen recent saved routes, manage offline maps, and tune navigation settings. |
| Route Preview | Review route shape, warnings, speed limits, pacenotes, and start driving. |
| Drive | Run the live navigation HUD with callouts, progress, rerouting, and optional trip recording. |
| Trips | Record local drives, review summaries, and export/share completed trip data. |
| Segments | Turn clean parts of trips into reusable challenge segments. |
| Challenges | Create, join, inspect, and validate rally-style challenge attempts. |
| Community | Manage Matrix identity, friends, groups, notifications, blocks, and synced directory data. |
| Settings | Manage ORS, Matrix, voice, warnings, route profile, map behavior, and recording preferences. |

## How It Works

1. Choose a start, destination, and optional waypoints.
2. RalRoads requests route geometry from OpenRouteService.
3. Local analysis turns the geometry into pacenotes and callout points.
4. OpenStreetMap and Overpass metadata add road warnings, traffic lights, surfaces, speed-limit context, and roundabout detail when available.
5. You preview the route, save it if useful, and start driving.
6. GPS route matching tracks progress, schedules callouts, and updates the HUD.
7. Finished drives can become trip summaries, shareable exports, segments, attempts, or challenges.

## Setup

RalRoads is a Flutter project.

```sh
flutter pub get
flutter run
```

Online route planning requires an OpenRouteService API key. Add one in the app from **Settings** or pass one during development:

```sh
flutter run --dart-define=ORS_API_KEY=your_key_here
```

Keys saved in Settings take priority over the development key.

## Development

Useful commands:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Regenerate generated database code after Drift schema changes:

```sh
dart run build_runner build
```

Regenerate launcher icons after changing the app logo:

```sh
dart run flutter_launcher_icons
```

## Data Sources And Packages

| Purpose | Source |
| --- | --- |
| App framework | Flutter / Dart |
| Maps | MapLibre GL |
| Map style/data | OpenFreeMap / OpenStreetMap |
| Routing | OpenRouteService |
| Place search | OpenRouteService geocoding, with fallback providers where configured |
| Road metadata | Overpass / OpenStreetMap |
| Local database | Drift / SQLite |
| Legacy route storage | Hive |
| Secure credentials | Flutter Secure Storage |
| GPS and sensors | Geolocator, sensors, compass |
| Voice | Flutter TTS |
| Sharing | Share Plus |
| Federation/social sync | Matrix |

## Screenshot Placeholders

Stable placeholder files live in `images/screens/`:

| File | Screen |
| --- | --- |
| `onboarding.svg` | First-run setup |
| `navigate.svg` | Main navigation tab |
| `map-planner.svg` | Route planner |
| `route-preview.svg` | Route preview and roadbook |
| `drive-hud.svg` | Live driving HUD |
| `saved-routes.svg` | Saved routes management |
| `offline-maps.svg` | Offline map management |
| `settings.svg` | Settings |
| `matrix-connection.svg` | Matrix connection |
| `trips.svg` | Trips dashboard |
| `trip-recording.svg` | Trip recording |
| `trip-summary.svg` | Trip summary |
| `segment-creation.svg` | Segment creation |
| `segment-detail.svg` | Segment detail |
| `attempt-recording.svg` | Attempt recording |
| `challenges.svg` | Challenges dashboard |
| `challenge-detail.svg` | Challenge detail |
| `community.svg` | Community dashboard |

## Current Limits

- Route planning, online search, OSM metadata, and Matrix sync require network access.
- OSM and Overpass metadata can be incomplete, duplicated, outdated, or locally inconsistent.
- Pacenotes are generated from geometry and best-effort context; they are useful driving aids, not official instructions.
- Offline map support depends on platform capabilities and downloaded regions.
- Matrix features are optional and depend on the selected homeserver and account state.

## Safety

RalRoads is an assistance tool. Always follow road signs, traffic laws, local restrictions, current conditions, and your own judgment.

Speed camera and enforcement warnings may be restricted or illegal in some places. Enable them only where permitted.
