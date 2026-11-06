# i2View

**i2View** is a dual-viewport map comparison application for iOS built with SwiftUI and MapKit, enabling users to inspect, compare, and synchronize two geographic locations side-by-side (Landscape) or stacked vertically (Portrait).

## Features

- **Responsive Dual Panes**: Stacked vertically in Portrait and side-by-side in Landscape.
- **Camera Lock & Synchronization**:
  - **Zoom Level Syncing**: Locking synchronizes the zoom level of the least recently moved map to the most recently moved map while preserving distinct locations.
  - **Relative & Exact Sync Modes**: Toggle between `RELATIVE` offset movement and `EXACT` coordinate mirroring.
- **Auto-Unlock on Search**: Searching on either map pane automatically unlocks the cameras so searching on one map never alters the other.
- **Unified Engine Switch**: Toggle both panes between **Apple Maps** (`MapKit`) and **OpenStreetMap** (`MKTileOverlay`).
- **Per-Pane Floating Controls**: Embedded search bar with live autocomplete results, plus floating Zoom In (`+`), Zoom Out (`-`), and My Location buttons on each pane.
- **Modern Geocoding**: Uses MapKit's `MKGeocodingRequest` with automatic fallback to the OpenStreetMap Nominatim REST API.

## Releases

Prebuilt release packages (`i2View-v1.0.ipa` and `i2View.app.zip`) are available on the [Releases](https://github.com/drbart/i2View/releases) page.
