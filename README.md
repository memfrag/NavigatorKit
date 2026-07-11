# NavigatorKit

Programmatic, deeply-linkable navigation for SwiftUI — across tab views,
navigation stacks, split views, sheets, full-screen covers, alerts, and
confirmation dialogs, in one declarative intent:

```swift
navigator.perform(
    NavigationIntent {
        SelectTab(AppTab.shop)
        SetStack(ProductRoute.list, ProductRoute.detail(id: 42))
        Present(ReviewRoute.compose(productID: 42), style: .sheet(detents: [.medium]))
        Push(ReviewRoute.photoPicker)
        Alert("Arrived!", message: "One intent, five containers.")
    }
)
```

**Requires iOS 26 / macOS 26, Swift 6.2.**

## Why

SwiftUI can't materialize nested presentations from a single state mutation,
`NavigationPath` is opaque, and deep links that need "switch tab, set the
stack, open a sheet" end up as fragile `DispatchQueue.asyncAfter` chains.
NavigatorKit solves this with:

- **An inspectable state tree** — one `@Observable` tree per scene (window)
  is the single source of truth; every SwiftUI container binds to it.
  Because paths are `[AnyRoute]`, not `NavigationPath`, the router can
  search them: pop-to-existing, "which window already shows this?", etc.
- **A staged intent executor** — intents are planned into stages (dismiss
  conflicts → base tab+path in one transaction → one stage per presentation
  level → overlays), each stage awaiting the UI transition before the next
  applies. All of it runs headlessly in tests via a swappable
  `TransitionCoordinator`.
- **Feature decoupling** — features own their route types and register
  route → view mappings; they never import each other or the app shell.
  Views see only `@Environment(Navigator.self)`.

## The pieces

### 1. Routes and destinations (feature modules)

```swift
public enum ProductRoute: Route {   // Hashable + Codable + Sendable
    case list
    case detail(id: Int)
}

public struct ProductsFeature: RoutableFeature {
    public static var destinations: DestinationGroup {
        Destination(for: ProductRoute.self) { route in
            switch route {
            case .list:            ProductListView()
            case .detail(let id):  ProductDetailView(id: id)
            }
        }
    }
}

// A feature can declare how its routes present by default:
Destination(for: ReviewRoute.self) { ... }
    .placement(.sheet(detents: [.medium, .large]))
```

One registration feeds three things: view resolution, `Codable` route
decoding (state restoration), and placement defaults.

### 2. Scene blueprint (app composition layer)

```swift
let registry = DestinationRegistry {
    ProductsFeature.destinations
    ReviewsFeature.destinations
    SettingsFeature.destinations
}

static let blueprint = SceneBlueprint {
    TabsRoot(initialSelection: AppTab.shop) {
        RoutedTab(AppTab.shop, "Shop", systemImage: "bag") {
            StackRoot(ProductRoute.list)
        }
        RoutedTab(AppTab.settings, "Settings", systemImage: "gear") {
            SplitRoot(sidebar: SettingsRoute.menu,
                      initialSidebarSelection: SettingsRoute.general)
        }
        RoutedTab(AppTab.search, "Search", systemImage: "magnifyingglass", role: .search) {
            StackRoot(SearchRoute.home)
        }
    }
}
```

Every window instantiates a fresh state tree from the blueprint — per-window
navigation state falls out by construction.

### 3. App shell

```swift
@main struct ShopApp: App {
    @State private var appNavigator = AppNavigator(
        destinations: registry,
        deepLinks: deepLinks,
        scenePolicy: ReuseSceneShowingRoutePolicy(fallback: .useActive)
    )

    var body: some Scene {
        WindowGroup(id: "main") {
            RoutedSceneRoot(app: appNavigator,
                            blueprint: blueprint,
                            restorationKey: "navigation")   // opt-in persistence
                .onOpenURL { appNavigator.open($0) }
        }
    }
}
```

### 4. Navigating from views

```swift
@Environment(Navigator.self) private var navigator

Button("Reviews") { navigator.navigate(to: ReviewRoute.list(productID: id), placement: .sheet()) }
Button("Done")    { navigator.dismiss() }
Button("Home")    { navigator.popToRoot() }

RouteLink(ProductRoute.detail(id: 3)) { Text("Product 3") }   // value-based push
```

Fire-and-forget from button actions; `async throws` variants
(`try await navigator.perform(...)`) when you need completion.

### 5. Deep links

```swift
static let deepLinks = DeepLinkMap {
    URLPattern("/products/:id") { params in
        try NavigationIntent {
            SelectTab(AppTab.shop)
            SetStack(ProductRoute.list, ProductRoute.detail(id: try params.id(Int.self)))
        }
    }
    URLPattern("shopapp://settings/**") { _ in
        NavigationIntent { SelectTab(AppTab.settings) }
    }
}
```

- `:name` captures (typed, throwing — a malformed value falls through to the
  next pattern), `*` matches one component, trailing `**` matches the rest.
- Custom-scheme URLs are normalized so `shopapp://products/42` and
  `https://shop.example.com/products/42` can share one path pattern.
- Most-specific match wins (literal > parameter > wildcard), declaration
  order breaks ties. Pure `URL → NavigationIntent?` — fully unit-testable.
- Cold launch is handled: a URL arriving before any scene exists is parked
  and claimed by the first scene to register.

### 6. Multi-window

Navigation state is per-scene. `AppNavigator` routes incoming intents via a
`SceneSelectionPolicy`:

- `ReuseActiveScenePolicy` — iPhone default.
- `ReuseSceneShowingRoutePolicy` — reuse a window already showing the route
  (exact, then by type); inspectable trees make this possible.
- `AlwaysNewWindowPolicy` — document-style macOS.
- Or conform yourself.

Callers can override per call:
`appNavigator.perform(intent, scenePreference: .newWindow())`. Window opening
is bridged through the view layer automatically (with graceful fallback on
single-window platforms).

### 7. State restoration

Pass `restorationKey:` to `RoutedSceneRoot` and the full tree (tab selection,
paths, sidebar selection, presentation chains — not alerts) persists per-scene
via `SceneStorage` and restores on launch. Routes from renamed/unregistered
types degrade gracefully: the path truncates before the first undecodable
element and presentations stacked above are dropped. Snapshots are versioned.

## Dismissal semantics (the contract)

`navigate(to:placement:)` resolves placement as: explicit argument → the
route type's registered default → `.push`. Placements:

| Placement | Behavior |
|---|---|
| `.push` | Push onto the deepest active context (sheet content if a sheet is up). |
| `.replaceStack` | Replace the active context's path with just this route. |
| `.present(style)` / `.sheet(...)` / `.fullScreenCover` | Present over the active context. |
| `.activateExisting(else:)` | If the route is anywhere in the scene, reveal it: select its tab, dismiss what covers it, pop to it. Otherwise apply the fallback. |

Invariants:

- Sibling tabs' **stacks** are never mutated by navigation.
- Presentations are window-global in SwiftUI, so switching tabs dismisses
  whatever the outgoing tab had presented (it would otherwise cover the new
  tab).
- Mutating a stack that has something presented over it dismisses the
  presentation first — no invisible-behind-the-sheet changes.
- A newer intent supersedes an in-flight one at its next stage boundary.

## Testing your navigation

Everything below the SwiftUI seam runs headlessly:

```swift
let scene = blueprint.makeSceneNavigator()
let executor = IntentExecutor(transitions: ImmediateTransitionCoordinator())
try await executor.execute(myDeepLinkIntent, on: scene)
#expect(scene.baseContext.path == [AnyRoute(ProductRoute.detail(id: 42))])
```

`swift test` in this repo runs 86 tests covering coding, tree queries,
planner staging, dismissal semantics, activation, cancellation, URL
matching, scene policies, and restoration — no simulator required.

## Example app

`Examples/ShopExample` is a workspace-free SPM app (runnable on macOS via
`swift run ShopApp`; add an iOS app target around `ShopApp.swift` to run on
iOS). It demonstrates:

- four feature modules that depend only on NavigatorKit (cross-feature links
  go through a routes-only `ReviewsInterface` target),
- tabs + split view + nested sheets + confirmation dialog + alert,
- a **Playground** tab firing the canonical hard intent,
- deep links (`shopexample://products/42/review`),
- open-in-new-window with scene-reuse policy,
- full state restoration.
