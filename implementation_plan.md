# Second-Generation Route Awareness Plan

## Current Root Causes

- Runtime route analysis still usually has empty `MatchedRoute.edges`, `maneuvers`, and `intersections`, so the semantic engine must often work with geometry plus accepted Overpass warnings.
- The first semantic pass stopped warning-only junction conversion, but candidate diagnostics are still too thin: candidates do not yet carry competing scores, topology context, geometry context, or matched-edge ranges.
- Junction decisions from matched maneuvers/intersections are not yet checked against road continuity. A side road or graph node must not become a junction if the route follows the natural continuation.
- Roundabouts are now route-membership based, but accepted candidates need clearer interval diagnostics and edge/maneuver evidence.
- Hairpins are strict, but the engine should expose the ordinary-curve, hairpin, junction, and roundabout scores that explain why a hairpin won or lost.
- DriveScreen top HUD uses `note.text`; many canonical curve notes intentionally keep `text` empty and expose display content through `rallyText`, so the top card can show only an icon.

## Intended Evidence Model

Every semantic candidate should include:

- final classification
- confidence
- supporting and contradicting evidence
- route interval
- matched edge indexes
- topology context
- geometry context
- competing scores: ordinary curve, hairpin, junction, roundabout

Specific labels require strong evidence. When evidence is incomplete or ambiguous:

- ordinary curve beats junction
- ordinary curve beats hairpin
- generic maneuver beats roundabout
- omission beats a highly specific wrong callout

## Distinguishing Features

- Ordinary curve: continuous route geometry, no accepted roundabout, no topology-backed junction, no compact hairpin reversal.
- Hairpin: compact route reversal, tight radius/chord ratio, coherent same-direction curvature, and a clear margin over ordinary curve/junction/roundabout scores.
- Junction: topology or maneuver evidence plus departure from natural continuation. Warning-only traffic controls stay warnings.
- Fork: two plausible outgoing roads of similar importance, or explicit keep/fork maneuver.
- Roundabout: traversed OSM circular/roundabout way, route edge roundabout tag, or explicit ORS roundabout maneuver. Nearby circular geometry alone is rejected unless very high confidence.
- Intersection continue: route passes through a connected node while following the natural continuation; it should not create a turn callout.

## Route-Feature Ownership

Accepted features must belong to the traversed road or traversed intersection arm. Ownership is based on:

- route membership/overlap metadata
- matched edge indexes
- bearing alignment
- layer/bridge/tunnel compatibility
- direction tags
- incoming road control relationship

Side-road stop signs, crossing signals, parallel-road cameras, and untraversed roundabouts are rejected or retained only as diagnostics.

## Confidence And Ambiguity

- Candidate confidence is lowered by missing route ownership, weak overlap, side-road-only evidence, natural-continuation conflicts, and competing stronger candidates.
- Accepted roundabouts suppress overlapping curve, hairpin, and junction notes.
- Hairpins are downgraded to ordinary curves unless compact-reversal evidence is strong.
- Junction candidates from intersections are accepted only when route turn/departure evidence exceeds natural-continuation evidence.

## Heading HUD Restoration

- DriveScreen top HUD will render canonical note display text with `note.text` fallback to `note.rallyText`.
- The main line can use two lines.
- The secondary line shows distance plus useful modifiers/speed.
- The card keeps the existing right-side reserved space and uses `Expanded`/ellipsis to avoid overlap.
- Icon selection remains based on canonical `PaceNoteType`.

## Tests To Add

- Warning-only stop sign does not create a junction callout.
- Low-membership roundabout warning is rejected.
- Traversed roundabout warning creates exactly one roundabout note.
- Broad 180-degree sweep does not stay hairpin.
- Matched intersection that follows natural continuation does not convert a curve to junction.
- Matched turn maneuver converts a nearby curve to junction.
- Top HUD display helper returns readable text when `note.text` is empty.
