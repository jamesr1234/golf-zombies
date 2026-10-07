# AGENTS.md

## Cursor Cloud specific instructions

Golf Zombies is a single **Godot 4.6.1** game project written in **GDScript** (no
Node/Python/DB/Docker). Standard run/test commands live in `README.md`; the notes
below only cover cloud-VM-specific caveats.

### Engine and tooling (already installed in the environment)

- The Godot editor/runtime binary is on `PATH` as `godot` (Godot 4.6.1-stable,
  Linux x86_64). Invoke it as `godot ...` rather than the macOS
  `/Applications/Godot.app/...` path shown in `README.md`.
- Headless test/import needs no display. Running the actual game does — use the
  pre-existing virtual X display: prefix game launches with `DISPLAY=:1`
  (e.g. `DISPLAY=:1 godot --path .`). That display is 1920x1200 and is what the
  computer-use desktop captures, so the game window is visible there.

### Rendering / audio caveats (GPU-less VM)

- There is no real GPU. Godot's Forward+ renderer runs on **software Vulkan
  (llvmpipe / lavapipe)**. The game boots and is fully playable, but software
  rendering can produce visual artifacts that do NOT occur on real GPU hardware —
  notably the 1-player view can render as a split view whose two halves show
  different sky/lighting. This is a renderer-backend quirk, not a game-logic bug;
  do not "fix" it in game code based on cloud-VM screenshots.
- There is no audio hardware. Godot logs ALSA errors and falls back to the dummy
  audio driver; a benign `add_child() ... busy` warning from `scripts/fx/music.gd`
  also prints at menu startup. These are harmless.

### Running the automated tests

- Command (GUT, headless) is in `README.md` under "Tests". It runs ~829 tests
  across `tests/unit/`.
- Judge results by the GUT **Run Summary / Totals** (`Passing Tests` /
  `Failing Tests`), not by scrolling to the end: on shutdown the run prints a
  large wall of benign `Leaked instance dependency` warnings and
  `RID allocations ... were leaked at exit` errors. The process still exits
  non-zero when any test fails (GUT sets the exit code from the failure count).
- A handful (~4-5) of the physics/procedural integration tests in
  `tests/unit/test_cart_path.gd` and `tests/unit/test_round_flow.gd` are
  **non-deterministic** (order-/timing-dependent) and fail intermittently — the
  exact set changes between runs and when run in isolation. Treat these as flaky,
  not as environment breakage.
- The Steam-backed multiplayer tests fail here because there is no Steam client /
  native runtime (`scripts/net/steam_lobby.gd` `start_up`). Steam is optional;
  online play over LAN/ENet (`NetSession`, UDP port 7777, probe 7778) does not
  need it.

### Asset import

- First run of the editor/game/tests imports assets into `.godot/` (gitignored).
  The startup update script pre-imports (`godot --headless --import`) so the first
  interactive launch is fast; Godot also auto-imports changed assets on demand.
