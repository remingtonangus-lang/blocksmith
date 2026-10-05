# Sable River (codename Frontier)

An original open-world Western set in the fictional Sable River country, autumn 1899. Godot 4.7 project; Mac is the
flagship, Meta Quest 3 gets the same game in VR.

## Playing the latest build
- **Mac (Apple Silicon):** download `SableRiver-mac-arm64.zip` from the `frontier-latest` pre-release, unzip, then
  right-click `SableRiver.app` → Open the first time (it is ad-hoc signed, not notarized), or run
  `xattr -dr com.apple.quarantine SableRiver.app`.
- **Quest 3:** `adb install -r SableRiver-quest.apk` (developer mode), launch from Unknown Sources.
- Benchmark: `SableRiver.app/Contents/MacOS/SableRiver -- --benchmark` writes
  `~/Library/Logs/Frontier/benchmark.json`.

## Controls
| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move / look | WASD / mouse | Left stick / right stick |
| Sprint (tap to speed up) | Shift | A or L3 |
| Walk toggle | Ctrl | — |
| Jump | Space | X |
| Crouch | C | B |
| Aim / fire | Right / left mouse | LT / RT |
| Nerve (while aiming; press again to fire marked shots) | Q | R3 |
| Reload / next weapon / holster | R / Tab / G | B / LB / — |
| Interact (skin, greet, campfire) | E | Y |
| Mount / call horse | F / H | Y / D-pad up |
| Map / journal / pause | M / J / Esc | View / — / Menu |
| Camera shoulder | V | R3 |

VR: left stick moves (head-relative), right stick snap-turns, right grip aims, right trigger fires, A interacts.

## Development
See `docs/status/frontier.md` (how to run, test, deliver) and `QUALITY_BAR.md` (what "done" means, per system).
