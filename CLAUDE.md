# CLAUDE.md — ProjectKobeClient

## Project Overview

- **Name**: Kobe
- **Engine**: Godot 4.6
- **Renderer**: Forward Plus (D3D12 on Windows)
- **Physics**: Jolt Physics
- **Main scene**: `main_ui.tscn`
- **Export target**: Windows Desktop x86_64 → `../kobe.exe`

## Project Structure

```
ProjectKobeClient/
├── project.godot       # Engine config (edit via Godot editor, not by hand)
├── main_ui.tscn        # Main scene (Node2D root)
├── export_presets.cfg  # Export config — do not commit credentials
├── icon.svg            # Default Godot icon
├── kobe.svg            # Project icon
└── .godot/             # Generated cache — gitignored, never edit
```

## Conventions

- **Language**: GDScript (`.gd`) — use typed GDScript where possible (`var x: int`)
- **Scenes**: One root node per scene; name scenes after their purpose (e.g. `player.tscn`, `hud.tscn`)
- **Scripts**: Attach scripts directly to the relevant scene node; keep file names snake_case matching the scene
- **Signals**: Prefer signals over direct node references for decoupled communication
- **Node naming**: PascalCase for nodes, snake_case for variables and functions

## Key Engine Notes

- Godot 4.6 uses UIDs (`uid://...`) for resource references — do not manually edit UIDs
- `.godot/` is auto-generated; never commit it and never edit files inside it
- `export_presets.cfg` is committed but `export_credentials.cfg` is gitignored

## Running & Exporting

- Open the project in the Godot 4.6 editor and press **F5** to run
- Export: **Project → Export → Windows Desktop** → outputs to `../kobe.exe`
- Godot executable must be available on PATH for CLI operations

## What NOT to Do

- Do not manually edit `project.godot` UIDs or `uid://` resource paths
- Do not edit files inside `.godot/` — they are regenerated automatically
- Do not commit `.godot/`, `export_credentials.cfg`, or `*.translation` files
