# NavigatorKit

**[📖 Overview page](https://memfrag.github.io/NavigatorKit/)**  ·  Android counterpart: **[NavigatorKitAndroid](https://github.com/memfrag/NavigatorKitAndroid)** ([overview](https://memfrag.github.io/NavigatorKitAndroid/))

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

**Requires iOS 18 / macOS 15, Swift 6.2.**

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

### Previewing and testing views

`Navigator` is a concrete `@Observable` `final class`, not a protocol — so
there's nothing to mock. Views read it type-based
(`@Environment(Navigator.self)`), and the swappable seam is one level down:
the `TransitionCoordinator`. Swap `UITransitionCoordinator` (awaits real
present/dismiss animations) for `ImmediateTransitionCoordinator` and you get a
fully real navigator — real executor, planner, and dismissal semantics — that
runs synchronously.

**Previews.** `@Environment(Navigator.self)` is non-optional, so it traps if
missing; inject a real navigator (and the registry, if the view uses
`RouteLink` or route destinations):

```swift
#Preview("Product detail") {
    let registry = DestinationRegistry {
        ProductsFeature.destinations
        ReviewsFeature.destinations
    }
    let navigator = Navigator(
        scene: SceneNavigator(root: .stack(NavigationContext(root: AnyRoute(ProductRoute.detail(id: 42))))),
        executor: IntentExecutor(transitions: ImmediateTransitionCoordinator()),
        registry: registry
    )
    ProductDetailView(id: 42)
        .environment(navigator)
        .environment(\.destinationRegistry, registry)
}
```

That renders the screen statically. To make navigation actually animate in the
preview (tap a button → sheet appears), host it in a `RoutedSceneRoot` with a
blueprint instead, so the `NavigationStack`/sheet modifiers are present.

**Testing a view's actions.** Assert on the resulting state tree rather than
recording calls — the scene is observable, so you check what actually
happened. Use the `async throws` variants for determinism (with the immediate
coordinator the tree is fully mutated once `await` returns):

```swift
@Test @MainActor
func writeReviewButtonPresentsSheet() async throws {
    let registry = DestinationRegistry { ReviewsFeature.destinations }  // registers .sheet placement
    let scene = SceneNavigator(root: .stack(NavigationContext(root: AnyRoute(ProductRoute.detail(id: 42)))))
    let navigator = Navigator(
        scene: scene,
        executor: IntentExecutor(transitions: ImmediateTransitionCoordinator()),
        registry: registry
    )

    try await navigator.navigate(to: ReviewRoute.compose(productID: 42))  // what the button calls

    #expect(scene.baseContext.sheet?.content.root == AnyRoute(ReviewRoute.compose(productID: 42)))
}
```

Most navigation tests skip the view entirely and drive the executor directly
(as the suite above does); asserting a button is *wired* to the navigator needs
ViewInspector or XCUITest, but the architecture keeps logic below the view so
that's rarely necessary.

The package ships `Navigator.testable(...)` so the two snippets above lose their
boilerplate:

```swift
// full control over the container shape:
let navigator = Navigator.testable(root: .tabs(tabsLayout), registry: registry)
// or the single-stack common case:
let navigator = Navigator.testable(stack: ProductRoute.detail(id: 42), registry: registry)
```

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
