# Gacha Studio Agent Guidelines

This is a living, git-ignored documentation file for all AI coding agents working on the Reactify project. Every agent **must** read this file in full before performing any work, and **must** update this file with new lessons, architectural decisions, or surprise findings as they are discovered.

---

## 1. Git & Workflow Standards

### Branching & PRs
- **Branch Naming:** All work must be performed on a branch starting with the prefix `Optuber/` followed by a concise description (e.g., `Optuber/flame-architecture-migration`, `Optuber/ui-modernization`). Never exceed more than 3 words.
- **Target Branch:** Never make commits or push directly to `master` or `main`.
- **Draft PRs Only:** All changes must be submitted via **Draft Pull Requests** on GitHub. Do not submit final PRs unless explicitly approved by the user.

### Commit Signing Notes
This Windows environment has Git configured for SSH commit signing:
- `gpg.format=ssh`
- `commit.gpgsign=true`
- The global `user.signingkey` is an SSH public key.
- 1Password CLI is installed, but **agents must not attempt to retrieve or type private credentials** from 1Password.
- Signed commits may trigger a desktop/Windows Hello prompt for the user to approve key usage.
- **Fallback:** If commit signing prompts freeze, time out, or fail (e.g., if the user is away and cannot approve Hello), bypass signing with unsigned atomic commits

### Work Style
Work style:
- Keep everything simple, clean, and efficient.
- Minimize code changes.
- Do not change unnecessary files.
- NEVER add code comments.
- NEVER use emojis.
- Use atomic commits only. Keep changes isolated and easily reversable.
- Commit messages should sound human, short, and natural. No overly polished or verbose style.
- Follow existing project standards exactly. Do not invent new patterns if the repo already has one.
- Study first, implement second.

---

## 2. Package Management & Security Protocol

We maintain a strict security policy regarding dependencies:
1. **Safety First:** Be extremely cautious of dependency vulnerabilities and package compromises.
2. **Age Threshold:** Never upgrade to a package version released less than **1 week** ago, unless it contains an actively verified critical security fix.
3. **Audit Check:** Before upgrading or adding any package, search web sources to ensure the package has no active compromise alerts.
4. **Copy Code Locally:** If a package is small, easily reproducible, or carries any dependency bloat/security concerns, **do not add it to `pubspec.yaml`**. Instead, copy/re-write the code locally into the codebase to keep dependencies minimal and secure.

---

## 3. Project Archetype & Unified Design Patterns

This is a highly greenfield project ("super new/green"). Changing the schema, refactoring data loaders, or modifying the architecture entirely is **fully encouraged** if it leads to a cleaner, faster, and more maintainable code structure.

### Unified Rendering & State Patterns
- We do not allow multiple different ways of implementing similar features. 
- Renderers must not contain hardcoded character-specific offsets or hacks. All layouts, positions, and offsets must be schema-driven from asset metadata.
- **Target Architecture:** Transition from Flutter's standard CustomPainter rendering to the **Flame Engine** (using a native `GameWidget` and hierarchical `PositionComponent` tree running on Flutter's Impeller GPU backend).

---

## 4. Agent Maintenance & Lessons Learned

The role of this file is to describe common mistakes, surprise edge cases, and confusion points that agents encounter. 

> [!IMPORTANT]
> **Surprise Alert Rule:** If you encounter anything in this codebase that surprises you or differs from standard expectations, alert the developer and document the finding in this section to guide future agents. Keep the entries concise and clean so this file never goes out of date.

### Lessons Log:
- **30 May 2026. 12:25 AM GMT +3:00:** Re-architected flat skeletal joints into a 12-bone parent-child hierarchical tree. Discovered that Flame coordinates propagation can be calculated by applying inverse world parent transforms locally, resulting in exact GPU rendering parity while using custom order depth priority traversal. Found that on Windows environments, the Flutter toolchain fails to create plugin symlinks without elevated permissions, which can be elegantly bypassed during testing/running by temporarily renaming the `/app/windows` platform directory.
- **30 May 2026. 02:40 PM GMT +3:00:** Optimized rendering frame lifecycles by caching Float64List transforms and performing direct arithmetic rotation multiplications in-place inside `GachaJointComponent` and `GachaPartComponent`, fully preventing heap list allocations. Upgraded UI harness panels, timeline, color picker, and toolbar panels with BackdropFilters, diagonal reflection CustomPainters, and spring-physics AnimatedScales to achieve Apple's premium Liquid Glass design language. Optimized rigging vector drawings by caching pre-compiled Path geometry inside `GachaDrawingPartComponent`, completely eliminating path creation stutters during render loops. Discovered that keyframe timeline scrubber dragging triggers massive object allocations due to `GachaKeyframe` object creation during interpolation; resolved this by implementing a primitive-based `interpolateAngle` method inside `TweenEngine` that returns double-precision values directly with zero heap allocations.
- **30 May 2026. 07:20 PM GMT +3:00:** Discovered that path token and frame parsing in `EyeRenderer` created massive list and string allocations per frame; resolved by implementing unified static `Map` caches to reuse pre-parsed tokens/frames. Uncovered that `TintPipeline` visibility rules compiled and matched expensive regular expressions per frame for every active catalog part; implemented a zero-RegExp `_VisibilityClause` pre-parsed cache, completely freeing the render pipeline from RegExp allocation stutters. Discovered that the SWF layout table verification loop performed `O(N)` linear searches over thousands of asset manifest entries; refactored `AppAssetManifest` to build a pre-hashed `Set` of all active and aliased paths, reducing contains checks to instant `O(1)` speed and slashing app boot latency. Optimized video exporter sorting logic by hoisting part depth sorting out of the sequential multi-frame capture loop into a single pre-run pass. Upgraded keyframe interpolation from `O(N)` linear array scans to a super fast `O(log N)` binary search. Modernized `DebugRenderPanel` container structure with frosted slate gradients and glossy border custom painters to match high-fidelity Liquid Glass aesthetics.
