# Route Awareness Follow-Up Plan

## Current Failures

- Intersections and roundabouts are still sometimes classified as severe ordinary curves.
- OpenRouteService is requested with `instructions: true`, but the route creation path discarded those maneuver steps before pacenote generation.
- Roundabouts therefore depended on Overpass route-membership warnings or geometry, and missed ORS-confirmed roundabouts.
- Junctions likewise depended on nearby curve geometry unless later metadata existed.
- Callout timing was based on a small speech-duration lead and a low minimum distance, so severe calls could be queued too close to the maneuver entry.

## Implementation

- Parse ORS `segments[].steps[]` into canonical `RouteManeuver`s during route creation.
- Preserve the parsed maneuvers on `OrsService.lastRouteManeuvers`.
- Pass maneuvers through `PacenoteBackgroundParams` into background pacenote generation.
- Let `RouteSemanticEngine` convert nearby curve notes or insert missing maneuver notes for confirmed junctions/forks/roundabouts.
- Include roundabout exit text when ORS instruction text exposes it.
- Keep warning-only traffic controls from creating junctions.
- Increase callout trigger distance based on speed, speech duration, priority, severity, and semantic type.

## Expected Behavior

- Actual ORS turn maneuvers become junction/keep/fork notes instead of severe curve notes.
- Actual ORS roundabout maneuvers become exactly one roundabout note, with exit number when reliable.
- Overlapping internal curve notes are suppressed by the semantic engine.
- Severe corners, junctions, hairpins, and roundabouts are called early enough for the driver to hear and react before entry.

## Regression Coverage

- Matched left-turn maneuver converts nearby curve to junction.
- Matched roundabout maneuver inserts a roundabout note.
- Severe corner callout queues with enough lead distance.
- Existing multi-corner segmentation, roundabout ownership, hairpin, and warning-only junction tests continue to pass.
