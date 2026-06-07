# RalRoads Local-First Navigation And Matrix Challenge Platform Plan

## Baseline Stabilization

- `flutter pub get`: passed.
- `flutter analyze`: initially reported 31 warnings/infos; fixed. Current result: no issues.
- `flutter test`: passed, 47 tests after shell/session/repository and validation coverage.
- `flutter build apk --debug`: blocked by environment, not source code. Flutter reports no Android SDK and suggests setting `ANDROID_HOME`.
- Follow-up baseline on 2026-06-07: `flutter analyze` clean, `flutter test` 40 tests passing, `adb` not found on PATH.
- Current run baseline on 2026-06-07: `flutter pub get` passed, `flutter analyze` clean, `flutter test` 47 tests passing, `adb` not found on PATH.
- Scope-correction baseline on 2026-06-07: `flutter pub get` passed and `flutter analyze` passed before validator-removal edits. Initial sandboxed `flutter test` was blocked by loopback binding permissions; elevated test run exposed a Trip Summary stream-cleanup test failure.
- Final verification on 2026-06-07: `dart format .` completed, `flutter analyze` is clean, and `flutter test --concurrency=1` passes 67 tests. Android builds are blocked because Flutter Doctor cannot locate an Android SDK.
- Onboarding/Matrix product pass on 2026-06-07: baseline verified at 67 tests, onboarding rebuilt with keyboard-aware scrolling and inline Matrix login, Matrix login now advances onboarding automatically after session state changes, Matrix custom profile/friend/group/directory event ingestion writes through Drift repositories, Community shows cached requests/friends/groups/directory events, and tests now cover 72 passing cases. Android builds remain blocked by missing Android SDK.
- Online challenge ecosystem pass on 2026-06-07: baseline `flutter pub get` passed; initial `flutter analyze` exposed source issues in Matrix media/client/test imports and is now clean after fixes; sandboxed `flutter test --concurrency=1` was blocked by sqlite3 native-asset DNS, elevated run passed 92 tests before challenge edits. This pass added Matrix challenge create/cancel/delete ingestion, room-backed challenge event queueing, repository-based Matrix event cache/dedupe helpers, and targeted Matrix challenge tests. The full real two-account challenge lifecycle is still not complete.

## Current Online Challenge Audit - 2026-06-07

Implemented state:

- Canonical local challenge storage currently uses Drift `challenges` plus `challenge_participants`, tied to canonical `challenge_segments` and immutable `segment_versions`.
- Challenge lists in the Challenges tab are reactive Drift watchers for active/past challenges and local segments.
- Challenge details can load the route geometry, start attempts, show leaderboard-style attempt rows, and use only honest trust labels: `Local`, `Locally validated`, `Shared / Unverified`, and `Group trusted`.
- Matrix sync now ingests RalRoads profile, friend, group, directory segment, shared package, segment, attempt result, and challenge lifecycle events.
- Room-backed local challenge creation now immediately saves locally and queues `org.ralroads.challenge.created.v1` in the durable Matrix outbox.
- Remote `org.ralroads.challenge.created.v1`, `updated.v1`, `cancelled.v1`, and `deleted.v1` events are parsed safely, can import an embedded segment package first, ensure a Matrix room shell exists, and upsert the challenge through `ChallengeRepository`.
- Matrix event deduplication and debug/event caching now go through `SyncRepository` helpers instead of direct ingestor writes for the common event path.

Exact missing challenge features:

- Drift schema still lacks first-class challenge revisions, previous revision hashes, owner Matrix IDs, challenge descriptions, visibility, participant policy, group trust policy, content hash/signature, source event IDs, source room type, package media references, downloaded package state, leaderboard cache, moderation state, tombstones, and conflict records.
- Current challenge creation UI is still a compact dialog, not the complete choose-segment/details/visibility/policy/rules/target/review flow.
- Challenge detail is still a one-shot `FutureBuilder`; it must become a reactive controller/watch composition so edits, attempts, downloads, tombstones, and leaderboard changes update without reopening.
- Attempt rows are segment-window based, not exact challenge revision/segment-version leaderboard entries.
- Matrix segment and attempt sharing still uses encrypted JSON temp packages, not complete `.rrsegment` / `.rrattempt` archive formats with decompression limits, manifest verification, and Ed25519 signatures.
- Discovery map/list, viewport spatial queries, clustering, directory subscriptions, package download UX, participant join/leave/invite flows, moderation UI, privacy preview/redaction, and conflict UI remain incomplete.
- Matrix sync still needs persisted sync tokens, redactions, pagination, leave/ban handling, retry/backoff detail states, encrypted-room safety checks, and no auto-join invite behavior.
- No end-to-end two-real-account Matrix acceptance run has been completed in this environment.

Current Matrix event schemas:

- `org.ralroads.challenge.created.v1`, `org.ralroads.challenge.updated.v1`, `org.ralroads.challenge.cancelled.v1`, and `org.ralroads.challenge.deleted.v1` are supported in this slice.
- Supported fields: `schemaVersion: 1`, `entityId`, `revision`, `authorMatrixId`, `timestamp`, `payload`, optional `payloadHash`, and optional embedded `segment`.
- Supported challenge payload fields: `challengeId`, `revision`, `segmentId`, `name`, `status`, `visibility`, `sourceRoomId`, `authorMatrixId`, `startsAt`, `deadline` / `endsAt`, and `updatedAt`.
- Supported statuses: `draft`, `active`, `ended`, `cancelled`, `deleted`.
- Supported visibility labels: `local`, `friend`, `group`, `directory`.
- Parser behavior: unsupported schema versions, invalid Matrix IDs, missing required IDs, invalid statuses, wrong payload hashes, and oversize payloads are ignored without crashing sync. Unknown fields are tolerated.
- Hash/signature status: payload hash checking exists only for plain SHA-256 JSON payloads. Full canonical JSON and Ed25519 signature verification are still missing.

Data migrations needed next:

- Add non-destructive schema version 2 tables for `challenge_revisions`, `challenge_sources`, `challenge_sync_state`, `challenge_tombstones`, `downloaded_challenge_packages`, `directory_challenge_index`, `challenge_leaderboard_cache`, `challenge_moderation_state`, `matrix_event_mapping`, `package_media_references`, and outbox dependencies.
- Backfill existing `challenges` rows into revision 1 rows and keep current rows as the latest materialized view until the UI is cut over.
- Add indexes for challenge ID, owner, room ID, status, deadline, segment ID/version, visibility, sync state, region/bounds/geohash, and updated time.
- Keep all migrations idempotent and non-destructive; no existing local challenges or segments may be deleted.

UI information architecture:

- Challenges root should become four internal sections: Discover, My Challenges, Attempts, and Leaderboards.
- Community remains for Matrix profile, friends, groups, invitations, and directory subscriptions, with shortcuts into challenge views only.
- Challenge cards should show name, route thumbnail/overview, source, status, distance, duration, deadline, trust, sync state, downloaded state, and one primary Open action.
- Challenge detail should have Overview, Leaderboard, Participants, My Attempts, and Rules tabs.
- Discover should be local Drift-backed map/list with viewport queries, simplified route previews, start/finish markers, filters, and lazy full-package download.

Synchronization model:

- Local challenge creation always writes Drift first.
- Room-backed challenge creation queues Matrix events through durable outbox rows.
- Media/package uploads must precede dependent publish events once package formats are complete.
- Incoming Matrix challenge events are deduplicated by event ID, parsed, optionally import an embedded segment, and upsert via repositories.
- Offline actions remain queued and should retry exactly once per event ID transaction; advanced dependency states and exponential backoff remain to be implemented.

Conflict rules:

- Challenge IDs are stable.
- Revisions must become immutable; current schema only stores latest materialized challenge state.
- Highest valid authorized revision should win once revision tables exist.
- Cancelled and deleted states override active when authorized.
- Stale local edits against newer remote revisions must be shown as conflicts instead of silently overwritten.
- Segments remain immutable by version; attempts remain immutable after submission except supersession/deletion events.

Challenge test plan:

- Existing targeted tests now cover Matrix challenge create/cancel ingestion and local room-backed challenge event queueing.
- Add repository tests for create, edit revision, stale revision rejection, cancel, delete/tombstone, and materialized latest state.
- Add Matrix schema tests for unsupported versions, malformed IDs, invalid enum values, wrong hash, duplicate event ID, missing segment package, and safe unknown-field tolerance.
- Add package tests for `.rrsegment` and `.rrattempt` round trip, corrupted hash, oversized payload, invalid coordinates, duplicate traces, and signature verification.
- Add widget tests for reactive challenge details, create flow, sync state chips, detail tabs, discovery empty/loading/error states, and text-scale/landscape layouts.
- Add integration/manual tests using two real Matrix accounts for publish, receive, download, attempt, validate, share result, leaderboard update, edit, cancel, delete, offline queue, and duplicate prevention.

## Current Product Phases

- Phase 1 baseline verification: complete for this run; `flutter pub get`, `flutter analyze`, and `flutter test --concurrency=1` matched the expected clean baseline before product edits.
- Phase 2 onboarding keyboard/layout behavior: implemented a SafeArea/LayoutBuilder/Column/Expanded/SingleChildScrollView structure with keyboard-aware padding, dismiss-on-tap/drag, scroll padding on fields, wrapping bottom controls, and responsive text wrapping.
- Phase 3 onboarding smoothness: removed the non-scrollable PageView and Spacer-heavy pages, kept controllers in state, narrowed rebuilds to current step widgets, and avoided duplicate Matrix route navigation during onboarding.
- Phase 4 Matrix onboarding completion: Matrix login is inline, preserves entered values on failure, shows progress/error/success state, listens to canonical session state, and auto-advances after a persisted usable session appears.
- Phase 5 canonical Matrix implementation: no second Matrix client was added. The app still uses one existing HTTP Matrix account/sync boundary because network-restricted dependency changes prevented adding a maintained SDK in this run.
- Phase 6/7 Matrix lifecycle and sync: existing session restore/sync loop is preserved; ingestion now handles RalRoads profile, friend, group, and directory events in addition to segment/attempt events.
- Phase 8 outgoing queue: existing durable outbox remains and is still covered by tests; advanced dependency/media retry states remain incomplete.
- Phase 9 custom events: profile, friend request/accepted/removed, group profile, and directory segment publication events now have concrete ingestion paths with payload-size and shape checks.
- Phase 10 friends: Matrix-derived friend request/accepted/removed events persist to Drift and appear in Community; interactive send/accept/reject/block UI is still incomplete.
- Phase 11 groups: Matrix group profile events persist Matrix-room-backed groups and appear in Community; create/invite/join/roles/power-level UI remains incomplete.
- Phase 12 communities/directories: subscribed directory event cache now has a watcher and Community display; subscribe/search/import/publish flows remain incomplete.
- Phase 15 shared leaderboards: trust labels remain documented, but Matrix-derived leaderboard aggregation is still incomplete.
- Phase 16/17 Community/reactivity: Community now watches Drift-backed social and directory data and updates without tab switching.
- Phase 18-22 UI/responsive/settings work: onboarding received the responsive overhaul and regression tests; the full app-wide UI cleanup remains a larger unfinished phase.

## Validator Scope Decision

Independent validator infrastructure is intentionally out of scope for RalRoads.

Removed or excluded:

- Standalone validator tools, daemons, independent validator attestations, validator queues, validator trust settings, N-of-M consensus, and external validation services.
- Matrix event types or Drift tables whose only purpose is independent validator attestation.
- UI language that labels shared attempts as simply `Verified`.

Kept:

- Deterministic local validation in `packages/ralroads_validation`.
- Local validation result storage for attempts.
- Device identity and signatures for authorship/package integrity.
- Matrix sharing, group trust policy, and moderation as social trust layers.

Trust labels:

- `Local`: exists only on the current device.
- `Locally validated`: passed deterministic validation on this device, with no independent verification.
- `Shared / Unverified`: received through Matrix; authorship and package integrity may be checked, but trace legitimacy is not independently guaranteed.
- `Group trusted`: accepted by a private Matrix group policy, still not equivalent to independent technical verification.

## Implementation Ledger

Completed:

- Repository audit captured current models, services, UI screens, Hive boxes, ORS/Overpass integration, navigation pipeline, route analysis, DriveScreen, and tests.
- Analyzer cleanup removed stale imports/fields, fixed deprecated widget/sensor APIs, and resolved style lints.
- `flutter_secure_storage` added.
- `SecureCredentialService` introduced with injectable storage and in-memory test implementation.
- ORS API key reads/writes moved from Hive into secure storage.
- Legacy Hive ORS key migration is idempotent and deletes the Hive key only after a successful secure write.
- Secure credential tests added.

Current checkpoint:

- The app still launches through the existing `HomeScreen` and does not require an ORS key.
- Existing route planning, saved routes, preview, DriveScreen, pacenotes, warnings, TTS, and settings are preserved.
- Android build remains blocked by missing Android SDK in this environment.
- Drift/SQLite schema version 1 is present with local account, Matrix metadata, social, trip, route, segment, attempt, challenge, moderation, privacy, outgoing-event, media-upload, sync-cursor, directory-cache, and blocked-user tables.
- Saved-route migration mirrors Hive saved routes into normalized SQLite rows for route summary, points, pacenotes, road warnings, and speed limits.
- Saved-route migration is idempotent and does not delete Hive saved-route data.
- Repository container introduced with `NavigationRepository` and `TripRepository`.
- `NavigationRepository` hides Hive plus saved-route SQLite migration behind saved-route methods.
- `TripRepository` writes real local trip rows and trip points to Drift and can finish/list trips.
- Five-tab shell introduced: Navigate, Challenges, Trips, Community, Settings.
- Onboarding introduced and shown until local completion.
- App/session state introduced for local profile, Matrix connection state, ORS connection state, offline status, and onboarding completion.
- Matrix account foundation introduced with real password-login HTTP boundary, secure token storage, session restoration, and logout.
- Trips tab, trip recording screen, trip summary screen, and private segment creation entry point introduced.
- Local repositories expanded for profiles, friends, groups, segments, attempts, challenges, sync/media queues, offline maps, and social snapshots.
- Trip recording hardened with single-active-trip behavior, active-trip resume, pause/resume persistence, cancel confirmation, progress persistence, and trip deletion support.
- Trip summary now reads persisted trip point stats and exposes rename, privacy, delete, and create-segment actions.
- Pure Dart `packages/ralroads_validation` MVP added with deterministic local attempt validation and SHA-256 result hashes.
- Validator tests cover clean results, sustained speed-limit invalidation, and deterministic hashes.
- Trip Summary widget tests now use reactive Drift streams and explicitly unmount the screen before test teardown.
- Independent validator attestation repository APIs, tests, Drift table, and standalone CLI tool have been removed.

Next checkpoint:

- Expand repository coverage for segments, attempts, challenges, social/profile, offline maps, and sync.
- Start moving screens onto repositories while preserving existing behavior.

This run targets:

- Complete local repository boundaries for profile, friends, groups, segments, attempts, challenges, sync, social, and offline maps.
- Add lightweight app session and account connection state.
- Replace the one-screen landing page with a five-tab RalRoads shell.
- Add real local trips dashboard and trip recording UI backed by `TripRepository`.
- Add disconnected Matrix/ORS states that explain account requirements without fake data.

Visible action audit:

- Onboarding `Use offline`: working; marks onboarding complete and opens the app shell.
- Onboarding `Connect Matrix`: opens real Matrix login flow.
- Onboarding `ORS settings`: opens existing ORS settings/key test flow.
- Navigate `Plan`: opens existing planner when ORS is connected; otherwise opens ORS settings.
- Navigate `Saved routes`: opens existing saved-routes flow.
- Navigate `Offline maps`: opens existing offline-map manager.
- Navigate `Navigation settings`: opens existing settings.
- Trips `Start`: opens real `TripRecordingScreen` backed by `TripRepository`.
- Trips trip cards: open real `TripSummaryScreen`.
- Trip recording `Pause`, `Resume`, `Stop`: implemented; cancel/restart recovery still needs hardening.
- Trip summary `Create segment`: opens local segment creation from persisted trip points.
- Segment creation `Save private segment`: persists private local segment; non-private visibility explains Matrix requirement.
- Challenges `Create`: creates a local challenge when a local segment exists; otherwise explains that a segment must be created first.
- Challenges `Connect Matrix`: opens real Matrix login flow.
- Community `Connect Matrix`: opens real Matrix login flow.
- Community local profile/group actions: create local Drift-backed profile/group data; no fake network data.
- Settings Matrix/ORS/offline actions: open real implemented flows.

Exact remaining product gaps after this checkpoint:

- Trip recording still needs richer lifecycle/background warnings and speed-limit lookup during free recording.
- Trip summary still needs richer route visualization and export controls.
- Segment creation needs map-based start/end selection, stronger suitability checks, content hash/signature, and richer persisted metadata.
- Deterministic validation exists as a pure Dart MVP but is not yet wired into visible segment/challenge attempt recording.
- Matrix sync is not yet a full SDK-backed sync loop; current Matrix support is login/session only.
- Matrix media sharing and signed `.rrsegment` packages are not yet implemented.
- Challenge detail, segment detail, local leaderboard, and attempt UI remain to be built.
- Shared leaderboards still need Matrix-derived aggregation using `Local`, `Locally validated`, `Shared / Unverified`, and `Group trusted` labels, without external validator claims.

## Current Architecture

RalRoads is a local-first Flutter app with a small service layer and mostly screen-local orchestration.

- App entry: `lib/main.dart` initializes `RouteStorageService` and `SettingsService`, then opens `HomeScreen`.
- Navigation UI: `HomeScreen`, `MapPlannerScreen`, `RoutePreviewScreen`, `DriveScreen`, `SavedRoutesScreen`, `OfflineMapsScreen`, `SettingsScreen`.
- Online routing: `OrsService` calls OpenRouteService directions and parses route geometry plus ORS steps into `RouteManeuver`s.
- Online place search: `GeocodingService` uses OpenRouteService geocoding and ranking heuristics.
- Road metadata: `OverpassService` queries Overpass in route chunks and extracts route-relevant warnings and speed limits.
- Route analysis: `RouteAnalysisService`, `RouteSemanticEngine`, `RouteFeatureMatcher`, `PacenoteGenerator`, and `RouteEventScorer` form the existing road-awareness pipeline.
- Driving: `DriveScreen` consumes route points, pacenotes, warnings, speed limits, `NavigationFusionService`, `CalloutScheduler`, and TTS.
- Local persistence: Hive boxes store saved routes and settings.
- Tests: coverage exists for geocoding, route analysis, pacenote context, route simplification, HUD calculations, and the home widget.

## Reusable Systems

- `RoutePoint`, `MatchedRoute`, `RouteManeuver`, `RoadSector`, `PaceNote`, `RoadWarning`, and `SpeedLimitSegment` are good canonical model seeds for SQLite entities.
- `RouteSemanticEngine` already has conservative semantic concepts: roundabouts, junctions, forks, hairpins, connected roads, evidence, contradictions, and diagnostics.
- `RouteFeatureMatcher` already encodes route ownership ideas needed for stop signs, cameras, speed limits, bridges, tunnels, and side-road rejection.
- `CalloutScheduler` already centralizes callout queueing, priority, expiration, merging, interruption, spoken IDs, and speed-based lead distance.
- `NavigationFusionService` already combines GPS, route matching, compass, gyroscope, accelerometer, smoothing, and display interpolation.
- `RouteStorageService` preserves current saved-route behavior and is the required backward-compatibility source for migration.
- `SettingsService` is the current single settings API and should remain the compatibility facade while storage moves underneath it.

## Broken, Missing, Or Duplicated Systems

- ORS API keys are currently stored in Hive, which is not acceptable for production secrets.
- There is no Matrix account, sync, room, media, notification, profile, friends, group, report, or moderation system.
- There is no Drift/SQLite database; durable structured data is stored as Hive maps.
- Saved routes are stored as large JSON-like blobs, which will not scale to trips, route chunks, traces, attempts, or sync state.
- Route planning, preview, DriveScreen, and callout systems are partially coupled through screen constructors rather than a canonical persisted route-analysis manifest.
- Package formats, package signatures, richer segment metadata, and Matrix sharing are incomplete.
- Offline map management exists as a screen/service shell, but no full offline route package readiness model is persisted.
- Privacy zones exist locally; broader privacy defaults, data export/delete flows, and Matrix social trust policy UI are incomplete.
- There is no product-level primary navigation matching Navigate, Challenges, Trips, Community, Settings.

## Product Principles

- Navigation, saved routes, prepared routes, simulation, DriveScreen, and offline-capable data remain usable without Matrix.
- Matrix powers social identity, federation, rooms, friends, groups, challenges, directories, sync, notifications, media, reports, and moderation.
- OpenRouteService powers online routing, place search, alternatives, route metadata, and elevation where available.
- RalRoads does not operate proprietary account infrastructure and does not reuse passwords across services.
- ORS credentials are API keys only; no ORS account password is requested or stored.
- Private trips and invalid attempts remain local unless the user explicitly shares them.
- Official rankings accept only legal clean attempts. Speed-limit violations invalidate official attempts.
- No top-speed ranking, public illegal leaderboard, live ghost racing, live opponent delta, or public over-limit stats.
- Driving UI stays calm and honest about map, speed-limit, GPS, grip, and road-data uncertainty.

## Data Migration Strategy

- Keep Hive readable for existing settings and saved routes until migration is complete.
- Add a schema version table in SQLite/Drift and run idempotent migrations at app startup.
- Migrate saved routes from Hive into normalized SQLite tables without deleting Hive data until the user confirms or a verified backup/export exists.
- Migrate ORS API keys from Hive into secure storage, then remove only the legacy Hive key after a successful secure write.
- Store large traces as compact point rows or chunked binary payloads with indexes, not duplicated JSON blobs.
- Keep compatibility facades (`SettingsService`, `RouteStorageService`) while replacing their backing stores.
- Add migration tests using representative old Hive maps for routes with and without `matchedRoute`, warnings, and speed limits.

## Secure Storage And Device Identity

- Use platform secure storage backed by Android Keystore/iOS Keychain for Matrix tokens, ORS API key, Matrix device IDs, crypto secrets, signing keys, and recovery secrets.
- Implement `SecureCredentialService` as the only API for secrets.
- Implement `DeviceIdentityService` to create and load a RalRoads Ed25519 device identity.
- Implement `EventSigningService` and `SignatureVerificationService` for authorship and package integrity.
- Sign segment packages, attempt packages, and device/profile events where appropriate.
- State clearly in code and UI that signatures do not prove GPS authenticity.

## Local Database Architecture

Use Drift/SQLite for structured durable data. Hive may remain for small non-secret preferences during migration.

Core tables:

- `app_accounts`, `matrix_sessions`, `matrix_devices`, `signing_keys`
- `profiles`, `friends`, `friend_requests`, `rooms`, `groups`, `group_members`
- `trips`, `trip_points`
- `route_plans`, `saved_routes`, `route_chunks`, `route_edges`, `route_maneuvers`
- `semantic_sectors`, `pacenotes`, `road_warnings`, `speed_limit_segments`, `offline_map_regions`
- `segments`, `segment_versions`, `segment_route_points`, `segment_rules`
- `segment_attempts`, `attempt_points`, `attempt_validation_results`
- `challenges`, `challenge_participants`
- `notifications`, `reports`, `moderation_actions`, `private_zones`
- `outgoing_events`, `pending_media_uploads`, `sync_state`, `cached_directory_events`, `blocked_users`

Requirements:

- Stable IDs, foreign keys, schema versions, indexes, and transactions.
- Indexes for route distance, dates, room IDs, segment IDs, attempt IDs, sync state, and upload state.
- Large GPS traces stored efficiently and incrementally.
- No destructive migration without explicit user consent.

## Matrix Architecture

Use a maintained Matrix Dart/Flutter SDK if compatible.

Services:

- `MatrixAccountService`: homeserver discovery, login, registration, logout, session restore.
- `MatrixSyncService`: sync loop, reconnect, token refresh, offline queue coordination.
- `MatrixRoomService`: direct rooms, group rooms, invites, membership, power levels, redactions.
- `MatrixMediaService`: upload/download, hash verification, encrypted package upload.
- `MatrixCryptoService`: encrypted room support, devices, verification, cross-signing where SDK supports it.
- `MatrixProfileService`: display names, avatars, public RalRoads profile events.
- `MatrixPushService`: push rules and notification state.

Registration must support homeserver-specific flows such as email, CAPTCHA, terms, token, disabled registration, and unsupported stages via secure browser or clear UI.

## RalRoads Matrix Event Schema

Define strict versioned custom event types:

- `org.ralroads.profile.v1`
- `org.ralroads.friend.request.v1`
- `org.ralroads.friend.accepted.v1`
- `org.ralroads.friend.removed.v1`
- `org.ralroads.device.key.v1`
- `org.ralroads.group.profile.v1`
- `org.ralroads.group.rules.v1`
- `org.ralroads.segment.created.v1`
- `org.ralroads.segment.updated.v1`
- `org.ralroads.segment.deprecated.v1`
- `org.ralroads.segment.published.v1`
- `org.ralroads.attempt.submitted.v1`
- `org.ralroads.attempt.result.v1`
- `org.ralroads.challenge.created.v1`
- `org.ralroads.challenge.updated.v1`
- `org.ralroads.group.trust_policy.v1`
- `org.ralroads.report.created.v1`
- `org.ralroads.segment.moderation.v1`

Every event includes schema version, stable entity ID, creation timestamp, author Matrix ID, author device key ID, relevant content hash, and RalRoads signature where relevant. Unsupported or malformed events are rejected safely.

## Local-First Sync Architecture

Services:

- `SyncCoordinator`
- `OutgoingEventQueue`
- `PendingMediaQueue`
- `ConflictResolver`
- `MatrixEventIngestor`

Requirements:

- Queue offline changes and retry with exponential backoff.
- Make outgoing operations idempotent.
- Upload media before dependent events.
- Resume interrupted uploads after restart.
- Deduplicate Matrix events and handle redactions.
- Handle federation delays without duplicate local entities.
- Surface sync state in UI.

Conflict rules:

- Profiles: latest valid state wins.
- Segments: immutable versions; updates reference previous version hash.
- Attempts: immutable after submission; corrections create superseding attempts.
- Challenges: explicit draft, active, ended, cancelled state machine.

## ORS Architecture

Split the current `OrsService` and `GeocodingService` into provider-layer services:

- `OrsConnectionService`: secure API key, endpoint, validation, quota/error state.
- `OrsRoutingService`: routes, profiles, alternatives, avoid options, metadata.
- `OrsGeocodingService`: search, ranking, near bias, cancellation.
- `OrsElevationService`: elevation where available.
- `OrsQuotaService`: 401/403/429 and usage-state messaging.

Saved routes, prepared routes, and offline navigation must not require an ORS key.

## Navigation Architecture

Canonical pipeline:

Route response -> normalized geometry -> matched road edges -> route topology -> ORS maneuvers -> semantic sectors -> route-owned road features -> callout candidates -> mode filtering -> scheduler.

Persist:

- Raw route geometry.
- Simplified overview geometry.
- Normalized analysis geometry.
- Matched route edges.
- Route chunks.
- Semantic sectors.
- Pacenotes.
- Road warnings.
- Speed limits.
- Analysis diagnostics.

Map rendering, TTS, warnings, and route preview must consume this canonical result instead of independently classifying route semantics.

## Long-Route Stability

- Display a simplified overview quickly.
- Analyze routes in 5-20 km chunks with 200-500 m overlap.
- Keep active driving memory to current chunk, previous chunk, and next 1-2 chunks.
- Persist successful chunks immediately.
- Mark chunks as pending, processing, ready, partial, or failed.
- Avoid global densification, huge Overpass bounding boxes, full-route nearest-point scans, and monolithic route objects.

## Segment And Attempt Architecture

Segments:

- Created from recorded trips.
- Include stable ID, version, name, description, creator, geometry, corridor, start/finish zones, distance, speed-limit coverage, road classes, safety status, visibility, region, rules, content hash, and signature.
- Visibility: private, friends, group, public directory where available.
- Public segments require stronger safety checks.

Attempts:

- Start on start-zone entry and finish on finish-zone crossing.
- Validate route order, corridor completion, shortcuts, GPS quality, timestamp monotonicity, impossible jumps, acceleration, mock-location indicator, speed-limit compliance, and off-route intervals.
- Statuses: valid clean, invalid speed limit, invalid route mismatch, invalid GPS quality, suspicious, rejected, manual review.
- Invalid attempts stay private by default and are never official rankings.

## Validation Architecture

Extract deterministic validation into `packages/ralroads_validation/` with no Flutter UI dependency.

Inputs:

- Segment definition.
- Trace.
- Speed-limit snapshot.
- Validation policy.
- Engine version.

Outputs:

- Status.
- Duration.
- Route match score.
- GPS quality.
- Speed-limit coverage.
- Violation reasons.
- Deterministic result hash.

Validation outputs are local evidence only. Matrix-shared attempt packages may include the local validation result hash, engine version, author/device signature, and package hash, but clients must label them `Shared / Unverified` unless a private group explicitly marks them `Group trusted`.

## Privacy Architecture

- Trips and invalid attempts are local by default.
- Raw location history is never public by default.
- Private zones mask or block export/share around sensitive places.
- Sharing is explicit per trip, segment, challenge, or attempt.
- Friend sharing uses Matrix direct/private rooms and avoids fastest-sorted invalid attempts.
- Public packages use hash and signature verification; private packages encrypt before upload.
- Settings include privacy defaults, private zones, data export, deletion, storage use, and Matrix social trust controls.

## UI Navigation Redesign

Primary destinations:

- Navigate: route planner, search, ordered stops, saved routes, offline maps, preview, simulation, DriveScreen, pacenotes, navigation settings.
- Challenges: personal segments, imported/shared segments, friend/group challenges, public regional segments, details, attempts, clean leaderboards.
- Trips: recording, history, summary, speed-limit compliance, matched segments, local attempts, segment creation, privacy controls.
- Community: Matrix profile, friends, requests, groups, invitations, directories, activity, reports, moderation status.
- Settings: Matrix, ORS, navigation, callouts, voice, offline maps, privacy, private zones, community sync, storage, export/delete, debug tools.

First launch:

- Offline-only path must enter the app immediately.
- Matrix setup must be clearly Matrix-powered.
- ORS setup must ask only for an API key and link to ORS signup/dashboard.
- Completion explains which capabilities are enabled.

## Phased Implementation Order

1. Stabilization and audit: complete.
2. Secure credentials: complete for ORS key; remaining Matrix/signing/recovery secrets depend on device identity and Matrix sessions.
3. Drift foundation: add database dependencies, schema versioning, all core tables, indexes, foreign keys, and migration tests.
4. Saved-route migration: normalize current Hive routes into SQLite without deleting Hive; depends on Drift foundation.
5. Central repositories: partially complete for navigation and trips; remaining repositories cover segments, attempts, challenges, social/profile, offline maps, and sync.
6. Product shell: primary Navigate, Challenges, Trips, Community, Settings destinations; depends on repositories to avoid widget-level storage/network wiring.
7. ORS provider split: connection/routing/geocoding/elevation/quota services; depends on secure credentials and repository boundaries.
8. Route analysis manifest: persist canonical analysis outputs and chunk statuses; depends on Drift and navigation repository.
9. Long-route chunking: bounded analysis and resumable chunk persistence; depends on route analysis manifest.
10. Trip recording: local trips, points, summaries, legal eligibility, privacy; depends on Drift and trip repository.
11. Segment model: create private local segments from trips with safety checks; depends on trip recording.
12. Attempt matching: local attempts and clean/invalid classification; depends on segment model and trip traces.
13. Validation package: pure Dart deterministic validation with comprehensive tests; depends on attempt model.
14. Device identity and signing: Ed25519 keys, event/package signatures; depends on secure credential extension.
15. Matrix SDK integration: account, session restore, sync loop, rooms, media; depends on secure Matrix session storage.
16. RalRoads event schemas: strict validation and local ingest; depends on signing and Matrix model tables.
17. Local-first sync: outgoing queues, media queues, conflict resolution; depends on Matrix services and event schemas.
18. Friends/groups/challenges UI: Matrix-backed social flows; depends on sync and product shell.
19. Shared leaderboards without validators: local, locally validated, shared/unverified, and group-trusted sections; depends on validation package, signing, Matrix media/events, group policy, moderation, and blocked-user state.
20. Offline package/media formats: `.rrsegment`, `.rrattempt`, verification, encryption; depends on signing, validation, and Matrix media.
21. Privacy/export/delete hardening; depends on complete local data model.

## Migration Checkpoints

- M0: Secure ORS key migration complete. Hive key removed only after secure write. No saved-route data changed.
- M1: Drift schema created with `schemaVersion = 1`; app opens database at startup without changing current UI behavior. Complete.
- M2: Saved-route snapshot migration writes all current Hive saved routes into SQLite in a transaction and can be run repeatedly without duplicate rows. Complete.
- M3: Route detail migration stores points, pacenotes, warnings, speed limits, maneuvers, and chunk metadata in normalized tables. Hive data remains readable.
- M4: Repository cutover reads saved routes from SQLite with Hive fallback. Rename/delete operations update the active store and preserve legacy compatibility.
- M5: Trip/attempt tables receive real foreground-recording data in transactions. No giant JSON trace blobs.
- M6: Matrix sync tables queue outgoing events and media uploads durably before any online send is attempted.

## Acceptance Criteria

- Every phase ends with `dart format`, `flutter analyze`, and `flutter test`.
- Android debug build is attempted only when an Android SDK is available; missing SDK is documented as an environment limitation.
- Existing offline app launch must continue to work with no ORS key and no Matrix account.
- Existing saved Hive routes must remain present after migration.
- Database migrations are idempotent and covered by tests.
- Repositories expose app-domain methods; widgets do not call Matrix APIs or raw Drift tables directly.
- Trip recording writes real GPS-derived points and can be summarized locally.
- Attempt validation never publishes invalid attempts by default and never creates top-speed/public illegal rankings.
- Matrix-backed features degrade gracefully when offline or unauthenticated.

## Testing Strategy

- Keep `flutter analyze` at zero issues.
- Keep unit tests for geometry, semantics, pacenote filtering, scheduler timing, route feature ownership, and route analysis.
- Add migration tests for legacy Hive settings and saved routes.
- Add secure credential tests with an injectable in-memory secure store.
- Add SQLite tests with in-memory Drift databases.
- Add ORS/geocoding tests with mocked Dio adapters for 401, 403, 429, network errors, quota state, alternatives, and cancellation.
- Add trip/attempt validation golden tests with deterministic traces.
- Add Matrix schema validation tests for each event type.
- Add package hash/signature verification tests.
- Add widget tests for onboarding, primary navigation, settings states, trip summary, segment details, challenge details, and DriveScreen calm-state HUD.
- Add integration tests for offline-only startup and saved-route navigation without Matrix or ORS.

## Security Risks

- Secrets in Hive or logs.
- Matrix token refresh and encrypted-room secrets mishandled.
- Device signing keys lost or exported insecurely.
- Trust confusion: signatures prove authorship/package integrity, not GPS truth.
- Malformed Matrix events or packages causing crashes or entity spoofing.
- Media package hash mismatch or replay.
- Public leaderboard abuse if validation policy is weak.
- Private location leakage through reports, media, screenshots, package metadata, or Matrix room history.

## Performance Risks

- Long routes can still overload memory if normalized/chunked data is duplicated across screens.
- Overpass queries can be slow, partial, rate-limited, or unavailable.
- Full-route nearest-point scans must not run on every GPS tick.
- Huge traces need indexed/chunked storage and streaming validation.
- Matrix sync/media queues need bounded retries and storage backpressure.
- MapLibre rendering can stutter if semantic sector overlays are too granular.
- TTS scheduling must avoid dense speech queues and late callouts.

## Current Implementation Slice

The first implementation slice after this plan is secure ORS credential storage with backward migration from the existing Hive settings key. This directly removes a known secret-storage flaw while preserving current app behavior and avoiding a broad architecture rewrite before the database and Matrix foundations are in place.
