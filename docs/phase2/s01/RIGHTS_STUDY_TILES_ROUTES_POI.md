# Rights study: map tiles, route data, routing, POI, elevation, user routes

Sprint S01, part (b). Study only: no code, no account was opened, no provider was contacted.
Date of the study: 2026-10-15. Decisions D-6 (map tile provider and licence) and D-7 (route data sources and first-release region): on 2026-10-16 the operator answered 'open source' for both, which matches the recommendation of section 9 (self-hosted OpenStreetMap-derived tiles; own tracks plus OpenStreetMap-derived routing and points of interest). The first-release region is still not named. The legal re-read of the original provider pages remains required.
This is an engineering summary of provider pages, not legal advice. Section 11 lists the questions for counsel.

## 0. Method and evidence grades

- Grade A = the provider's own current terms or policy page. Grade B = official documentation or official project page that is not the contract itself. Grade C = secondary (not used for any claim below).
- Every statement carries a source URL and grade. UNKNOWN means the page could not be fetched, did not say, or the text was not available to the study. UNKNOWN is never a "yes".
- Pages were read through an automatic fetch-and-summarise tool, so quotations come from a summary of the page and must be re-read in the original by counsel before any decision is final. Pages change; the Stadia terms already announce a new version effective 2026-11-09.
- Product context (from `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` and `04_UI_UX_DIRECTION_2026-10-15.md`): Flutter app, Firebase backend, maps in RIDE and EXPLORE, GPS recording, route sharing, nearby routes, offline maps (S11, own gate, "only if the licence study allows offline use"). T2 recording works with no map service at all, so none of this blocks S04-S06.
- Fallbacks already in the roadmap: D-6 default "no map service; recording and lists only"; D-7 default "own users' tracks only".

## 1. Map tiles

### 1.1 OpenStreetMap community tile servers (tile.openstreetmap.org)

- Terms: best effort, no SLA; commercial services "should be especially aware that access may be withdrawn at any point"; access may be blocked without notice. Source: https://operations.osmfoundation.org/policies/tiles/ (A)
- Offline: "Offline use is not permitted on tile.openstreetmap.org". Bulk downloading is defined as any pre-emptive fetching of tiles other than those a user is actively viewing; offline download buttons, region preloading and multi-zoom prefetching are banned. Same source (A)
- Attribution: must be visible on the map, typically bottom-right; not hidden in a menu or behind a toggle. Same source (A)
- Other: a distinct, stable User-Agent naming the app is mandatory; library defaults are blocked. Same source (A)
- Cost at small scale: free, but with no guarantee. Not an option for the S11 offline feature. Acceptable at most for development.
- Key risk: the offline feature is explicitly forbidden, and the commercial app can be cut off with no notice.

### 1.2 MapTiler Cloud

- Terms (general): free-plan quota only; map content may not be altered; no resale or sublicensing without written agreement; on termination stored copies must be destroyed. Source: https://www.maptiler.com/terms/ (A)
- Cloud terms: a device-side "temporary personal cache" for a single end user is allowed; server-side caching is prohibited; "batch or excessive bulk downloading of map tiles is prohibited"; the Free Plan is limited to non-commercial use, including research and development of commercial products. Source: https://www.maptiler.com/cloud/terms/ (A)
- Offline: not addressed for mobile SDK tile packs; anything beyond a per-user app cache needs a custom agreement. Same source (A). Whether a "download this area" feature fits is UNKNOWN.
- Attribution: "© MapTiler" with link; free accounts show the MapTiler logo; plus "© OpenStreetMap" with link when OSM-based; must stay visible on small screens (a one-tap popup is allowed). Source: https://www.maptiler.com/terms/ (A)
- Cost: Free $0 (100k API requests/month, 5k sessions; not for commercial use); Flex $30/month incl. 25k sessions, overage $2.50 per 1k sessions; Custom (SLA) on request. Source: https://www.maptiler.com/cloud/pricing/ (A)
- Key risk: offline would need a written agreement; commercial launch needs at least the paid plan.

### 1.3 Mapbox

- Terms of service: licence is non-exclusive, non-transferable, revocable; on termination all downloaded data must be destroyed; production use for vehicle-related or BI applications needs a separate licence; proprietary notices and logos may not be removed; attribution text not given on the page. Source: https://www.mapbox.com/legal/tos (A)
- Offline: the ToS page does not address it; rules live in the Product Terms PDF and offline guides, which could not be read. UNKNOWN. The Product Terms page was fetched and also did not answer. Source: https://www.mapbox.com/legal/product-terms (A, no offline text found)
- Cost: Mobile Maps SDK free up to 25,000 monthly active users, then from $4.00 per 1k MAU falling to $2.40; Directions API first 100,000 requests/month free, then $2.00 per 1k. Offline pricing not on the page (UNKNOWN). Source: https://www.mapbox.com/pricing (A)
- Key risk: offline terms unverified; MAU pricing couples cost to growth; vendor lock-in on style and SDK.

### 1.4 Stadia Maps

- Terms (version effective 2026-03-18; a new version takes effect 2026-11-09, text not reviewed): bulk downloading prohibited "except for caching small amounts of data for offline use in a mobile app, up to 100MB at a time per device"; client-side cache must stay on the device; free tier is non-commercial or evaluation only. Source: https://stadiamaps.com/terms-of-service/ (A)
- Attribution: must not be obscured; OSM attribution required (exact string not given on the page read). Same source (A)
- Cost: Free 200,000 credits/month, no commercial use; Starter $20/month, 1,000,000 credits, commercial allowed; Standard $80 (7.5M credits); Professional $250. Source: https://stadiamaps.com/pricing/ (A)
- Key risk: the 100 MB per device offline allowance is small for a multi-region ride; the terms are changing in November 2026.

### 1.5 Thunderforest (outdoor and cycle styles)

- Terms: tiles may be stored on devices so maps work offline; apps may keep tiles beyond HTTP expiry; "Bulk downloading, pre-downloading, and pre-caching require an appropriate paid plan" (bulk needs Small Business or higher); caching proxies and redistribution are not permitted; "Commercial use is permitted and encouraged". Source: https://www.thunderforest.com/terms/ (A)
- Attribution: "Maps © Thunderforest, Data © OpenStreetMap contributors" with working links to thunderforest.com and openstreetmap.org/copyright. Same source (A)
- Cost: Hobby free 150,000 tile requests/month (commercial status not stated on the pricing page); Solo Developer $125/month (1.5M); Small Business $255/month (15M, bulk downloads); Large Business $525/month. Source: https://www.thunderforest.com/pricing/ (A)
- Key risk: the only hosted option read that explicitly sells pre-download, but at $255/month minimum for bulk; the cycling and outdoor style fits the product.

### 1.6 Google Maps Platform

- Page fetches did not return usable terms (one 404, one truncated). Caching, offline and pre-fetching rules: UNKNOWN. Not recommended for study depth because the roadmap needs offline. Source attempted: https://cloud.google.com/maps-platform/terms (A, unread)

### 1.7 Self-hosted vector tiles: OSM extract, Protomaps PMTiles, MapLibre

- Data: OSM extracts under ODbL 1.0, updated daily, free download. Source: https://download.geofabrik.de/ (A). The Geofabrik page lists no usage terms beyond the licence; the files omit user names and IDs.
- Protomaps: PMTiles is an open format read by HTTP range requests; the toolkit and basemap are released under BSD and ODbL. Source: https://docs.protomaps.com/ (A). The basemap is "an Open Database License (ODbL) Produced Work, and OpenStreetMap attribution is required"; daily planet builds are about 120 GB to zoom 15; users are told to copy the tileset to their own storage rather than hotlink; `pmtiles extract` makes regional files. Source: https://docs.protomaps.com/basemaps/downloads (B)
- Renderer: MapLibre Native is BSD 2-Clause. Source: https://github.com/maplibre/maplibre-native/blob/main/LICENSE.md (A). A Flutter binding, its maturity and PMTiles support on mobile were NOT verified in this study: UNKNOWN (needs a technical spike).
- Offline: no provider is involved, so no provider prohibition applies; a downloaded region file is the app's own copy of ODbL-derived data. The licence conditions are in section 3.
- Attribution: OpenStreetMap credit naming ODbL, linked to openstreetmap.org/copyright. Source: https://osmfoundation.org/wiki/Licence/Attribution_Guidelines (A). Text may be "© OpenStreetMap contributors" or "Map data from OpenStreetMap"; in a collapsed form the licence must still be reachable through an "(i)" or About entry. Same source (A)
- Cost: storage on Cloudflare R2 is $0.015 per GB-month, egress free, free tier 10 GB-month. Source: https://developers.cloudflare.com/r2/pricing/ (A). Real cost depends on one region size (UNKNOWN until a region is chosen; a country or a few states is a small fraction of the 120 GB planet). Operator effort: a monthly rebuild job and a style (Protomaps basemap style is one; a dedicated outdoor/cycling style would have to be built or sourced, UNKNOWN effort).
- Key risk: build and operations work for the team; style quality for outdoor use; no SLA beyond the team's own.

## 2. Hosted tile summary for offline

Only Thunderforest (paid, bulk plan) and Stadia (100 MB per device) state an offline allowance in the pages read. MapTiler: custom agreement. Mapbox and Google: UNKNOWN. OSM community servers: forbidden. Self-hosting removes the question.

## 3. OSM data licence (ODbL) and what it means for shared routes

- Condition summary: attribution on public use; share-alike if an adapted database (or works from it) is publicly used; produced works need attribution and share-alike applies when they derive from an adapted database; DRM is allowed only alongside an unrestricted copy. Source: https://opendatacommons.org/licenses/odbl/summary/ (B, the page says it is not the licence)
- OSMF guideline: a "Produced Work" is something made from the database that is not itself a database (a rendered map); a collection of independent databases is a "Collective Database", and OSM and non-OSM data stay independent "so long as a particular data type within a database consists entirely of non-OSM data within a regional cut". The guideline page read gave no guidance on routes. Source: https://osmfoundation.org/wiki/Licence/Community_Guidelines (B)
- Attribution: see 1.7. Source: https://osmfoundation.org/wiki/Licence/Attribution_Guidelines (A)
- Impact on this product (ENGINEERING INFERENCE, not verified with counsel):
  - A user's recorded GPS track is the user's own data and not an OSM database; storing and sharing it does not itself trigger share-alike.
  - Rendered tiles and a map screen are produced works: attribution only.
  - Risky area: a catalogue route built by snapping to or routing on OSM ways, or enriched with OSM tags (surface, difficulty, POI), may be an adapted database if published as a dataset (for example a public route API or a bulk export). Keeping OSM-derived attributes in separate fields from the app's own data (a separate "data type" in the OSMF wording) and publishing no bulk dataset reduces the risk. Whether in-app display of such routes triggers share-alike is a question for counsel (section 11).
  - The roadmap rule "every route shows source and freshness" and an in-app attribution file (S07) already match the attribution duty.

## 4. Routing engines

- OSRM: BSD 2-clause; supports driving, cycling and walking profiles; demo server policy not stated on the page. Source: https://project-osrm.org/ (B). Elevation-aware cycling profile: UNKNOWN.
- Valhalla: MIT licence; bicycle and pedestrian costing, elevation-influenced bicycle routing, a tiled graph designed for small memory and "offline routing", elevation service (Skadi). Source: https://valhalla.github.io/valhalla/ (B)
- GraphHopper hosted API: free plan EUR 0, 500 credits/day, non-commercial only; Basic EUR 69/month (5,000 credits/day), Standard EUR 199, Premium EUR 479; attribution not required on paid plans (20% discount for attributing). Credit cost per routing request not stated. Self-hosting licence and terms: not on the page (UNKNOWN; verify in the repository). Source: https://www.graphhopper.com/pricing/ (A)
- Mapbox Directions: see 1.3 (free 100,000 requests/month, then $2.00 per 1k; ToS caveats apply). Source: https://www.mapbox.com/pricing (A)
- Public OSM-hosted routing: no routing policy exists on the Nominatim policy page; OSRM demo policy not stated. UNKNOWN; do not use as a production backend. Source: https://operations.osmfoundation.org/policies/nominatim/ (A, no routing section)
- Offline: self-hosted engines carry no provider restriction; routing data inherits ODbL (section 3). On-device routing in Flutter is an unverified technical item (UNKNOWN).
- Cost at small scale: self-hosted = one small server plus monthly graph build (price UNKNOWN until sized); hosted = see plans above.
- Key risk: self-hosted operations; hosted free tiers are non-commercial.

## 5. POI and trail data

- OSM via public Overpass instance: expected maximum about 10,000 requests/day and 1 GB/day; building an app that relies on the public instances as backend is listed as problematic; for sustained use run your own instance or use a planet/extract. Source: https://dev.overpass-api.de/overpass-doc/en/preface/commons.html (B)
- OSM via Nominatim: 1 request/second per app, no autocomplete, no systematic queries or POI downloads, must be switchable off without an app update, ODbL share-alike noted. Source: https://operations.osmfoundation.org/policies/nominatim/ (A)
- OSM extract processed in own pipeline (Geofabrik): licence ODbL, free. Source: https://download.geofabrik.de/ (A). This is the only OSM POI path compatible with a commercial app at any scale.
- Overture Maps Places: Meta, Microsoft and other sources CDLA Permissive 2.0; Foursquare Apache 2.0; AllThePlaces CC0; "Data from" credit per provider; Transportation theme is ODbL. Source: https://docs.overturemaps.org/attribution/ (B). Quality of outdoor trail data in Overture: UNKNOWN.
- Wikidata: structured data CC0. Source: https://www.wikidata.org/wiki/Wikidata:Licensing (A). Coverage of trails: UNKNOWN.
- Waymarked Trails: legal page returned 404; terms UNKNOWN. Do not use.
- Third-party route catalogues (Komoot, AllTrails, Strava segments, Ride with GPS and similar): terms were NOT reviewed; no scraping or import is assumed allowed. Treat as prohibited until a written licence exists (matches the roadmap rule "no external data without a recorded licence").
- Cost: self-processed data is free apart from compute and storage (UNKNOWN until sized).
- Key risk: public APIs are not a production backend; trail quality varies by region (UNKNOWN).

## 6. Elevation data

- Copernicus data policy: "full, open and free access" with source credit, a statement of modifications, and no implied EU endorsement (wording quoted from the Land Monitoring Service policy). Source: https://land.copernicus.eu/en/data-policy (A). That page covers the Land Monitoring Service; whether the Copernicus DEM follows the same wording was NOT verified (the DEM page fetch returned 404): UNKNOWN.
- Mapterhorn terrain tiles (Terrarium-encoded, PMTiles): source datasets, licence and attribution not stated on the page read; an Attribution page exists. UNKNOWN. Source: https://mapterhorn.com/data-access (B)
- Valhalla includes an elevation service (Skadi). Source: https://valhalla.github.io/valhalla/ (B)
- Own alternative: barometric altitude from the phone and recorded GPS altitude need no external licence (engineering note, no source needed); accuracy is the product question.
- Recommendation for the study: verify one elevation source (Copernicus DEM or Mapterhorn) with its attribution page before S07; until then the app can show recorded altitude only.
- Cost: UNKNOWN.

## 7. User-generated route licence (what the app must take from users)

This is a design recommendation for the terms of use, not a quoted provider rule. Source: engineering proposal (no external source).

- The user keeps ownership of their tracks and photos.
- The user grants the operator a worldwide, non-exclusive, royalty-free licence, only for the visibility they choose (private / unlisted / public / friends), to host, process (simplify, trim, derive previews), display and distribute the route and its derived artefacts inside the service; the licence ends when the user deletes or unpublishes, except for copies others have already saved, which are detached per the lifecycle matrix (S09).
- The user warrants they recorded the track themselves or have the right to share it (no copied third-party catalogue, no trespass-sensitive data).
- Separate opt-in for any use beyond display (for example anonymised statistics or improving recommendations); never implied by publishing.
- Moderation, takedown and report rights for the operator; minors rule per D-17 (under-18 and unknown age: no public sharing).
- Photos: licence limited to display; EXIF stripped on upload (roadmap S09).
- Whether to license public routes to other users under a stated licence (for example "view and use for personal navigation only") is a choice for counsel (section 11).

## 8. Comparison table

| Option | Offline permitted | Licence or terms basis | Attribution | Cost at small scale | Key risk | Evidence |
|---|---|---|---|---|---|---|
| OSM community tile servers | No (explicitly banned) | OSMF tile policy, no SLA | OSM, visible on map | Free | Forbidden offline; can be cut off | A |
| MapTiler | Per-user cache only; more needs agreement | Cloud terms | MapTiler + OSM | Free (non-commercial), Flex $30/month | Offline needs custom deal | A |
| Mapbox | UNKNOWN | ToS, Product Terms (unread) | Proprietary notices must stay | Free to 25k MAU, then per MAU | Offline terms unverified; growth-coupled cost | A / UNKNOWN |
| Stadia Maps | Up to 100 MB per device | ToS (new version 2026-11-09) | OSM, not obscured | Free (non-commercial), Starter $20/month | Small offline cap; terms changing | A |
| Thunderforest | Yes on paid plans (bulk: $255/month) | Terms, commercial allowed | "Maps © Thunderforest, Data © OpenStreetMap contributors" | Free 150k tiles; $125 or $255 per month | Bulk plan price; vendor | A |
| Google Maps | UNKNOWN | Unread | UNKNOWN | UNKNOWN | Unverified | none |
| Self-hosted OSM extract + Protomaps PMTiles + MapLibre | Yes (own files) | ODbL + BSD | OSM credit naming ODbL | R2 storage $0.015/GB-month, egress free; ops cost UNKNOWN | Team builds and runs it; Flutter binding unverified; ODbL duties | A / B |
| Routing: Valhalla or OSRM self-hosted | Yes | MIT / BSD-2; data ODbL | OSM | UNKNOWN (server) | Operations; elevation profile detail | B |
| Routing: GraphHopper hosted | n/a | Plans | none on paid | EUR 69 to 479 per month | Free plan non-commercial | A |
| Routing: Mapbox Directions | n/a | ToS | per Mapbox | Free 100k/month | Lock-in; ToS | A |
| POI: own pipeline from OSM extract | Yes | ODbL | OSM | compute only, UNKNOWN | Share-alike for datasets | A |
| POI: public Overpass / Nominatim | No (not a backend) | Fair-use policies | OSM | Free, rate-limited | Cannot run a product on it | A / B |
| Overture Places | Yes (licences permit) | CDLA-P 2.0 / Apache / CC0 | per provider | Free | Outdoor quality UNKNOWN | B |
| Elevation: Copernicus DEM | UNKNOWN (policy open) | Open with credit (land service page) | Copernicus wording | Free | Applicability to DEM unverified | A (partial) |
| Third-party route catalogues | UNKNOWN | Not reviewed | n/a | n/a | Treat as prohibited | none |

## 9. Recommendation (D-6, D-7: operator answered 'open source' on 2026-10-16; region still open)

### D-6 (map tile provider and licence): recommend self-hosted tiles

Recommended: build vector tiles from an OSM extract for the first-release region only, as a Protomaps PMTiles file on Cloudflare R2 (or the equivalent storage already used with Firebase), rendered with MapLibre, with OSM attribution.

Why: it is the only option where offline downloads (the S11 requirement) are permitted by every document read, with no per-user caps, no commercial-use tier traps and no vendor termination; storage and egress costs are low and published. Consequence of choosing it: the team owns a monthly tile build, a style, and a Flutter map-rendering spike; if the spike fails (unverified), the fallback is Thunderforest paid plan for online maps (offline by bulk plan) or no map service (existing roadmap default). Consequence of rejecting it: any hosted provider requires an offline agreement or caps (MapTiler custom, Stadia 100 MB, Mapbox UNKNOWN).

Interim (S04-S10, online maps only, if the operator wants a map before S11): a paid hosted plan, not the OSM community servers; this is optional and can wait because recording needs no map.

### D-7 (route data sources and first-release region): recommend own users' tracks plus one OSM-derived region

Recommended: first release uses (1) users' own tracks and routes, (2) OSM-derived routing and POI data for one region chosen by the operator, processed from a Geofabrik extract on our side (routing by a self-hosted Valhalla, which carries MIT licensing and bicycle, pedestrian and elevation costing), and (3) no third-party route catalogue and no public Overpass or Nominatim backend. OSM-derived fields stay in separate data fields with a source label and the in-app attribution file; no bulk public dataset export in the first release.

Why: every source is under a licence read in this study (ODbL, MIT, BSD) and none needs a commercial negotiation. Consequence: catalogue content is thin at launch (only what the team generates and users publish), and the region choice drives data size and moderation load (region choice is the operator's). If counsel finds ODbL share-alike applies to in-app routes, the fallback is the existing roadmap default: users' tracks only, with OSM used for map display only.

## 10. Not verified (UNKNOWN list)

- Google Maps Platform caching and offline terms (page not usable).
- Mapbox offline rules (Product Terms PDF and offline guide not read).
- MapTiler free-plan commercial wording on the pricing page (cloud terms say non-commercial; pricing page unclear).
- GraphHopper self-hosting licence and per-request credit cost.
- OSRM demo server policy; elevation-aware OSRM cycling profile.
- Copernicus DEM terms (the Land Monitoring Service policy was read, the DEM page returned 404); Mapterhorn licence.
- Waymarked Trails terms (404); Overture trail coverage.
- OSMF geocoding guideline and any OSMF guidance on routes derived from OSM.
- Flutter MapLibre binding maturity and PMTiles mobile support; on-device routing.
- Stadia terms effective 2026-11-09.
- Costs of the self-hosted pipeline (server, build job) until the region is chosen.

## 11. Questions for legal review

1. Does an in-app route built by snapping to or routing on OSM ways, or carrying OSM tags, count as an adapted database under ODbL when displayed to users? Does it become one if exposed through an API or export?
2. If share-alike applies, what must be published (the derived route/POI database, or only the OSM-derived layer), and in which format and where?
3. Can the app record a user's track alongside OSM data and publish it under the app's own terms (Collective Database position under the OSMF guideline)?
4. Is the attribution in an About screen plus an "(i)" on the map enough for mobile, and what wording do store reviewers accept?
5. Which licence should the terms of use grant to other users for public routes (view only, personal navigation, derivative use)? What is the takedown and DMCA/notice procedure and the retention of cached copies others saved?
6. Do the terms need a separate statement for route photos and for users who record tracks on private land or in other jurisdictions?
7. What are the obligations when the operator receives a bulk or partial deletion request for a public route that has been downloaded offline by others (lifecycle matrix, S09)?
8. Is it acceptable to rely on a provider's offline allowance in a mobile app for commercial use (Stadia, Thunderforest) if the operator later wants a hosted fallback?
9. Does the app need a notice about data from Copernicus or other elevation sources, and does using them require a licence statement beyond the credit wording?
10. Are there regional restrictions (the chosen first-release region) on mapping data, trail liability or recreational-use statutes that affect publishing routes?
