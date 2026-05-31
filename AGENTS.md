# Reactify Agent Guide

Read this file before working in this repository. Keep it concise and update it only when a durable project lesson or architecture decision changes how future agents should work.

## Workflow Rules

- Work on branches named `Optuber/<short-topic>`, never directly on `master` or `main`.
- Submit work as draft PRs unless the user explicitly approves otherwise.
- Keep changes small, reversible, and source-backed.
- Do not add code comments.
- Do not use emojis.
- Do not hardcode per-character visual nudges.
- Do not claim full Gacha Club parity unless visual comparison supports it.
- Passing tests is necessary but not sufficient; visual correctness matters.
- Preserve user or previous-agent changes unless the user explicitly asks for cleanup.

## Dependency Rules

- Be cautious with new dependencies.
- Do not add or upgrade packages released less than one week ago unless there is a verified critical security fix.
- Before adding or upgrading a package, check current web sources for compromise/security alerts.
- If a package is small or easy to reproduce, prefer local code over dependency bloat.

## Current Product Direction

Reactify is a 2D character creator and reaction-video studio, not a 3D app.

The current Gacha Club renderer should be treated as a legacy compatibility layer and visual-reference adapter. The long-term product should use a Reactify-native 2D puppet architecture:

- Gacha Club 445-field code import/export remains supported for backwards compatibility.
- Imported Gacha characters should migrate into a richer Reactify character model.
- Reactify-native characters should use reusable rig templates, slots, anchors, tint channels, layer ordering, custom slots, and custom assets.
- Live editing should favor cached/rasterized layers for performance.
- Source/project data should preserve vector structure where possible for high-quality SVG/PNG/video export.
- The editor should eventually support editable scenes, multi-character reaction layouts, reusable expressions, poses, dialogue/timeline state, and later video assembly.

## Current Technical Baseline

Flutter app root:

- `app`

Original reference/source/assets:

- `D:\Client Projects\reactify\REFRENCES\Some gacha App`

Important areas:

- Code parsing/state: `app/lib/src/gacha/code`
- Data loading: `app/lib/src/gacha/data`
- Renderer: `app/lib/src/gacha/render`
- UI: `app/lib/src/gacha/ui`
- Generated app data: `app/assets/data`
- Fixtures: `app/fixtures`
- Render parity outputs: `app/tmp/render_exports`
- Generators: `tools`
- Research docs: `docs`

The current branch contains a Flame-based live renderer. It resolves a Flash-like draw list, then displays flattened drawable parts under a Flame root while keeping a logical joint tree for pose propagation. This is useful as a compatibility milestone, but it is not the final Reactify-native character architecture.

## Known Compatibility Status

- The app imports and exports canonical Gacha Club 445-field character codes.
- The app renders characters from generated catalogs/assets.
- Built-in fixtures and visual parity exports exist.
- Full visual parity is not achieved.
- Known remaining mismatch areas include hats/top accessories, face accessories, props/weapons, some lower clothing layers, pose/limb alignment, and unsupported `special` / `special2`.
- Do not trust "resolved family exists" as proof of compatibility. A family can resolve while using the wrong asset, frame, transform, tint, depth, host, or nested filter.

## Validation Commands

Run from `app` when Flutter is available:

- `dart format lib test`
- `flutter analyze`
- `flutter test`
- `$env:RUN_FULL_BUILTIN_EXPORT='1'; flutter test test\builtin_render_export_test.dart`
- `flutter test test\gacha_dj_girl_visual_parity_test.dart`
- `flutter build windows`

If Flutter is not on PATH, report that clearly instead of pretending validation passed.

## Important Lessons

- Flame coordinates can preserve GPU rendering parity when parent-child pose transforms are derived from inverse world parent transforms, but global draw ordering still needs an explicit flattened depth order.
- Windows Flutter plugin symlink creation can fail without elevated permissions; prior testing sometimes bypassed this by temporarily renaming `/app/windows`.
- The repo is asset-heavy. Most tracked files are static SVG/PNG assets; performance work should focus first on the small set of core Dart renderer/data/UI files.
- SVG registration/viewBox preservation is important for parity.
- `SvgAssetLoader` can stall in built web/headless verification; current loading uses `rootBundle.loadString` before SVG parsing.
- `fronthairrot` is a source-backed frame selector, not geometric rotation.
- Back hair and ponytail previously double-applied editable target transforms; similar bugs can occur when Flash runtime controls an inner editable target while generated local matrices also bake that target placement.
- Numeric transform comparison against source traces is preferred over guessed offsets.
