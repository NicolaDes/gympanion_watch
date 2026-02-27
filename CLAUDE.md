# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Garmin ConnectIQ watch app for gym exercise tracking, written in **Monkey C**. Targets the **fr265** device with `minApiLevel="5.2.0"`.

## Development Environment

The project uses a VS Code dev container (`.devcontainer/`) that mounts `app/` as `/workspace`. The container uses Ubuntu 22.04 with OpenJDK 17 and GUI libraries for running the Garmin simulator.

### First-time setup (once per machine)

1. Open the project in VS Code and select **Dev Containers: Reopen in Container**
2. Run the SDK Manager to download the ConnectIQ SDK and generate a developer key:
   ```bash
   ./scripts/setup-sdk.sh
   ```
   This opens the Garmin SDK Manager GUI. Sign in, install an SDK version, and generate a developer key via **Preferences → Developer Key** (save as `app/developer_key`).

### Build and simulate (every time)

From the host terminal (the devcontainer must be running in VS Code):
```bash
./scripts/simulate.sh
```
This compiles the app and launches the Garmin simulator in one command.

### How the build command actually works

The build runs inside the devcontainer via `docker exec`. The SDK is installed at
`~/.Garmin/ConnectIQ/Sdks/<version>/` inside the container. The actual compiler invocation is:

```bash
java -Xms1g -Dfile.encoding=UTF-8 -Dapple.awt.UIElement=true \
  -jar ~/.Garmin/ConnectIQ/Sdks/<version>/bin/monkeybrains.jar \
  -o bin/workspace.prg -f monkey.jungle -y developer_key -d fr265 -w
```

The developer key is at `app/developer_key` (gitignored; generated once per developer).

## Architecture

The app follows the standard Garmin ConnectIQ MVC pattern:

- **`gympApp.mc`** — Application entry point (`gympApp extends Application.AppBase`). Bootstraps the app and returns the initial `[gympView, gympDelegate]` pair.
- **`gympView.mc`** — Main screen (`gympView extends WatchUi.View`). Loads `MainLayout` and handles drawing via `onUpdate(dc)`.
- **`gympDelegate.mc`** — Input handler (`gympDelegate extends WatchUi.BehaviorDelegate`). Handles button events; `onMenu()` pushes the `MainMenu` with `gympMenuDelegate`.
- **`gympMenuDelegate.mc`** — Menu handler (`gympMenuDelegate extends WatchUi.MenuInputDelegate`). Handles menu item selections via `onMenuItem(item)`.

### Resources (`app/resources/`)

All UI resources are defined in XML:
- `strings/strings.xml` — Localizable strings (referenced as `@Strings.Id` in code/layouts)
- `layouts/layouts.xml` — Screen layouts (referenced as `Rez.Layouts.MainLayout(dc)`)
- `menus/menus.xml` — Menu definitions (referenced as `Rez.Menus.MainMenu()`)
- `drawables/drawables.xml` — Bitmap assets

### Key Conventions

- Resource IDs are accessed via the `Rez` namespace at runtime (e.g., `Rez.Layouts.MainLayout`, `Rez.Menus.MainMenu`).
- String references in XML use `@Strings.Id` syntax.
- New screens follow the View + BehaviorDelegate pair pattern and are pushed/popped via `WatchUi.pushView` / `WatchUi.popView`.
- The app ID is `f98a251f-fbbe-4b0b-85de-d893670af9fe` (in `manifest.xml`).

## Gitignored Paths

- `app/sdk/` — Garmin ConnectIQ SDK (install via sdkmanager)
- `app/bin/` — Build output
- `app/developer_key` — Signing key
- `.devcontainer/` — Dev container config
