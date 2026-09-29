# Focus Audit Lite

**Free version of [Focus Audit](https://theidlehands.itch.io/focus-audit) for Godot 4.4 – 4.7.**

Builds the scene you have open, walks its real arrow / D-pad focus graph by asking the engine, and reports controls a gamepad can never reach, places focus gets stuck, screens that open with nothing focused, and focus_neighbor paths that lead nowhere.

## Getting started

1. Copy `addons/focus_audit/` into your project.
2. **Project → Project Settings → Plugins**, enable **Focus Audit Lite**.
3. The dock appears bottom-right. Open a saved scene and press **Check open scene**.

The `demo/` folder is a small project with one of every fault planted in it.

## The full version adds

- **Check all scenes** in one press
- **Markdown and JSON reports** (pinned schema for a build server)

→ **[Focus Audit on itch.io](https://theidlehands.itch.io/focus-audit)**

The full version installs into the same `addons/focus_audit/` folder, so it replaces
this one in place.

## What it will not tell you

A clean report is a measurement against the checks above, not a guarantee.
The full version's page lists every limit in detail.

## Licence

The Lite version is MIT licensed (see `LICENSE`). The full version is sold
separately under its own licence.
