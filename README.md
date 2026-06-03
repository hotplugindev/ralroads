# RoadNotes

RoadNotes is a personal pocket co-driver Flutter app for exploring a map,
planning road routes, generating local rally-style pacenotes from route
geometry, and speaking those notes while driving.

## API Keys

The app no longer requires an OpenRouteService API key at compile or run time.
Users can open Settings and add their own key inside the app.

Create a free OpenRouteService key here:

https://openrouteservice.org/sign-up/

OpenFreeMap map display works without an OpenRouteService key. Online route
planning requires a valid OpenRouteService API key. If the key is missing,
route planning is disabled and the app offers to open Settings. If the key is
invalid or rejected, route planning shows a helpful error instead of crashing.

There is no automatic GPX-provider fallback in this version.

## Developer Mode

For development, a build-time fallback key is still supported:

```sh
flutter run --dart-define=ORS_API_KEY=your_key_here
```

Saved keys entered in Settings take priority over the build-time key.

## Running

```sh
flutter pub get
flutter run
```
