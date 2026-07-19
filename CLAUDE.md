# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**NavigatorKit** — a Swift package for programmatic navigation in SwiftUI. One declarative
`NavigationIntent` expresses a destination across the whole container hierarchy at once: tab
selection → navigation-stack path → split-view columns → presented sheets/covers (recursively) →
alerts/dialogs. Also does deep links (URL-pattern DSL), multi-window scene coordination, and
`Codable` state restoration. Requires **iOS 18 / macOS 15, Swift 6.2** (strict concurrency).

There is a sibling repo, **NavigatorKitAndroid** (Kotlin/Compose), that implements the *same
navigation contract* — intent vocabulary, dismissal semantics, URL grammar, test scenarios. There
is **no code sharing**; parity is maintained by hand. A change to the contract (a new placement, a
dismissal rule, URL syntax) must be mirrored in both repos and both test suites. The two overview
pages (`docs/`) and READMEs cross-link and must stay consistent.

## Commands

```sh
swift build                     # build the library (macOS host)
swift test                      # run the full suite (~90 tests, headless, no simulator)

# run one suite or one test (swift-testing filter matches suite/test display names):
swift test --filter "Planner staging"
swift test --filter "canonicalHardIntentEndState"

# verify iOS-18 availability (the package compiles clean here; run after touching UI/):
xcodebuild build -scheme NavigatorKit -destination 'generic/platform=iOS Simulator' \
  -sdk iphonesimulator26.5 IPHONEOS_DEPLOYMENT_TARGET=18.0

# example app (separate SPM package under Examples/):
cd Examples/ShopExample && swift build     # runnable on macOS via `swift run ShopApp`
```

Tests use the **swift-testing** framework (`@Suite` / `@Test` / `#expect`), not XCTest.

## Architecture

The governing idea: **push all navigation logic below the SwiftUI seam so it's headless-testable**,
and make the state tree the single source of truth that SwiftUI merely binds to. Layers, in
dependency order (`Sources/NavigatorKit/<dir>`):

1. **Core** — `Route` (a feature's `Hashable+Codable+Sendable` route type with a stable
   `routeTypeID`), `AnyRoute` (type-erased box; deliberately **not** `NavigationPath` — paths must
   stay *inspectable* for pop-to-existing, scene matching, and diffing), and `RouteTypeRegistry`
   (decodes heterogeneous routes via `decoder.userInfo`).

2. **State** — the recursive tree of `@MainActor @Observable` classes. `NavigationContext` is the
   node: a stack `path: [AnyRoute]` plus optional `sheet`/`fullScreenCover` (each a
   `PresentedContext` whose content is *another* `NavigationContext` — this is the recursion) plus
   `alert`/`confirmationDialog`. `RootLayout` (`.stack`/`.tabs`/`.split`), `TabsLayout`,
   `SplitLayout` (sidebar = a *selection*, detail = a full context), and `SceneNavigator` (one per
   window/scene) sit above it. Persistence uses a *separate* `Codable` value mirror
   (`Restoration/NavigationSnapshot`), never the `@Observable` classes directly.

3. **Intent + Executor** — this is the crux; read it before changing navigation behavior.
   - A `NavigationIntent` is an **ordered list of `NavigationOperation`s** applied to a *moving
     cursor* (starts at the active context; `selectTab` retargets it, `present` descends into the
     new child). Backward ops (`pop`, `dismiss`) and forward ops compose in one intent — but
     `dismiss`/`dismissAll`/`activate` **may not follow `present`** in the same intent (the planner
     throws `NavigationError.invalidOperation`; those reason about the settled tree while `present`
     leaves a not-yet-attached cursor). Canonical order: tear down → select/set → present →
     push/overlay.
   - `Planner` (pure, in `Executor/`) diffs an intent against the current tree into an
     `ExecutionPlan` of **stages**: dismiss-conflicting → base (tab + path in one mutation) → one
     `present` stage per nesting level → overlay. This staging exists because **SwiftUI cannot
     materialize nested presentations from a single state mutation** — each presentation level needs
     its own transaction.
   - `IntentExecutor` applies each stage, then awaits a `TransitionCoordinator` before the next.
     **This protocol is the test seam.** `UITransitionCoordinator` (in `UI/`) awaits the real
     appear/disappear signals the routed views emit, bounded by a timeout;
     `ImmediateTransitionCoordinator` returns instantly, making the whole executor + planner run
     synchronously in tests and previews. Intents serialize per scene; a newer intent cancels the
     in-flight one at a stage boundary.

4. **UI** — the SwiftUI binding. `RoutedStack` binds a `NavigationContext` to a `NavigationStack`
   and installs `RoutedPresentationsModifier`, which is applied *recursively* at every level (a
   presented sheet's content is another `RoutedStack`) — that's how nested sheets work. `Navigator`
   is the `@Observable` facade views consume via `@Environment(Navigator.self)` — the **only** API a
   feature view sees (it's a concrete `final class`, not a protocol; there's nothing to mock — see
   `Navigator+Testable.swift` and the README's "Previewing and testing views"). `RoutedTabRoot` uses
   the iOS-18 `Tab(value:role:)` builder + `.search` role — **this is what sets the iOS-18 floor**;
   everything else is iOS 16–17.

5. **Destinations / DeepLink / Scenes / Restoration** — feature decoupling (`DestinationRegistry` +
   `RoutableFeature`: a feature registers route→view mappings knowing nothing about the app shell or
   siblings; one registration feeds view resolution, `Codable` decoding, and default placements);
   the `DeepLinkMap`/`URLPattern` DSL (`URL → NavigationIntent?`, pure and unit-testable);
   `AppNavigator` + `SceneSelectionPolicy` (cross-window routing, cold-launch mailbox); and the
   lossy snapshot coder (unknown route types truncate the path rather than failing the whole
   restore).

### Dismissal contract (invariants to preserve)

`navigate(to:placement:)` resolves placement as: explicit arg → the route type's registered default
→ `.push`. `dismiss()` closes the topmost presentation, `dismissAll()` unwinds to the base,
`pop()`/`popToRoot()` walk the stack. Invariants the planner enforces: sibling tabs' **stacks** are
never mutated by navigation; switching tabs dismisses the outgoing tab's presentations
(presentations are window-global in SwiftUI); mutating a stack under a presentation dismisses the
presentation first.

## Conventions

- **Everything under `UI/` is `@MainActor`**; the state tree classes are `@MainActor @Observable`.
  The pure logic (`Core`, `Intent`, `Executor/Planner`, `DeepLink`) is `Sendable` value types and
  headless-testable without SwiftUI.
- When adding a `NavigationOperation`, thread it through five places: the enum
  (`Intent/NavigationOperation.swift`), a DSL wrapper (`Intent/NavigationIntent.swift`), the
  `Planner`, the `ExecutionPlan` mutation set, and the `Navigator` facade if it warrants a
  convenience — plus a `PlannerTests`/`IntentExecutorTests` case.
- The example app under `Examples/ShopExample` is a *separate* SPM package (its own
  `Package.swift`); its feature targets depend only on `NavigatorKit` (cross-feature links go
  through a routes-only interface target) — that decoupling is the point of the example, so keep it.
- Git: don't self-credit in commits. Releases are bare-SemVer tags (`1.0.0`) so SwiftPM resolves
  `from:`.
