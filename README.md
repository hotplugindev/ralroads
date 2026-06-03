# RalRoads

RalRoads is a personal pocket co-driver Flutter app for exploring a map,
planning road routes, generating local rally-style pacenotes from route
geometry, and speaking those notes while driving.

The app logo is registered as a Flutter asset at:

```text
assets/branding/ralroads_logo.png
```

Android launcher icons are generated from that logo with
`flutter_launcher_icons`.

## API Keys

The app does not require an OpenRouteService API key at compile or run time.
Users can open Settings and add their own key inside the app.

Create a free OpenRouteService key here:

https://openrouteservice.org/sign-up/

OpenFreeMap map display works without an OpenRouteService key. Online route
planning requires a valid OpenRouteService API key. If the key is missing,
route planning is disabled and the app offers to open Settings. If the key is
invalid or rejected, route planning shows a helpful error instead of crashing.

There is no automatic GPX-provider fallback in this version.

## Map And Drive Mode

The map planner supports visible start, destination, and waypoint pins for
long-pressed route points. The Locate Me button asks for foreground location
permission, moves the map to the current GPS location, and shows a blue
current-location marker when available.

Drive mode is map-based: it displays the route, updates the current position
marker, highlights color-coded pacenote danger zones, shows road warning
markers, displays a readable current speed/speed-limit card, and keeps spoken
callouts with compact navigation controls on top of the map. The driving UI is
map-focused with a clear follow-mode button plus icon-based callouts and
upcoming warnings.

## Road Warnings

RalRoads uses OpenStreetMap/Overpass best-effort data to enrich planned routes.
It can show speed limits, speed bumps, traffic lights, stop/give-way signs,
surface changes, tunnels, bridges, roundabouts, and optionally speed cameras.

OpenStreetMap data may be incomplete or outdated. Speed camera warnings may be
restricted in some countries and are disabled by default. Enable them only where
legal in Settings.

Warnings are loaded once per planned route and saved locally with saved routes.

Saved routes can be renamed from the Saved Routes screen without losing route
geometry, pacenotes, warnings, or speed-limit data.

## Developer Mode

For development, a build-time fallback key is still supported:

```sh
flutter run --dart-define=ORS_API_KEY=your_key_here
```

Saved keys entered in Settings take priority over the build-time key.

## Running

```sh
flutter pub get
dart run flutter_launcher_icons
flutter run
```
