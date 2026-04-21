### Commited Changes

**04/19/2026 `(inlretro-interface.ps1)`** — compared to `inlretro-interface-0.10q.ps1`

1. Added `-Force` to every `Import-Module` call for the core `INLinterface.*` modules so edits to `.psm1` files are reloaded on each launch of the script within the same PowerShell session (without `-Force`, `Import-Module` keeps the previously loaded copy).
2. Documented that behavior in a short comment block above the import section.

---

The items below expand on the same release window: they are condensed from working notes (`changelog-draft.md`) and cover the LUA host, the PowerShell module layer, and a couple of cautions.

## LUA host (`host/scripts/`)

- **`inl_ui.lua`** — Shared terminal styling: 30-column labels, ANSI colors, `print_kv`, and `use_ansi()` (honors `NO_COLOR`, `INLRETRO_FORCE_ANSI`, `inlretro_vt_ansi`, and terminal detection). `with_styled_print()` wraps global `print` so warnings, errors, and debug output share the same styling path.
- **`inlretro2.lua`** — Uses `inl_ui` for firmware version and unsupported-console messaging. Non-N64 runs go through `with_styled_print`; **N64 is left out** on purpose so global `print` is not hooked, as a mitigation for suspected USB/IPL header issues.
- **`n64/basic.lua`** — Full **0x40-byte IPL from ROM 0**, decoded header fields, **ROM size auto-detect** (game-code table, mirror heuristic, 64 MiB fallback), optional **`.n64` → `.z64`**, post-dump stats via `print_post_dump_rom_analysis`, explicit **save (-a/-b) not supported** messaging, and timing that skips duplicate stats when `INLRETRO_INTERFACE=1`.
- **`snes/v2proto_hirom.lua`** — Dump path unchanged; ROM header display uses `inl_ui.print_kv` instead of tabbed `print`.
- **`app/time.lua`** — Small elapsed-time / KB/s helper (`start` / `report`); still used on flows such as GBA while N64 keeps its own timing and analysis.
- **NES mapper scripts** (`mmc1`, `mmc3`, etc.) — No per-mapper edits for styling; appearance comes from `with_styled_print` and the host layer.

## PowerShell interface (`host/modules/`)

- **`HostScriptRoot`** (with **`PSScriptRoot` alias**) — Install root is threaded consistently for paths.
- **`Invoke-INLRetro`** — Sets **`INLRETRO_FORCE_ANSI`** and **`INLRETRO_INTERFACE`** around `inlretro.exe`; uses a **Stopwatch** for wall-clock dump time; **Process Summary** adds aligned **Average speed** and **Total time**; maps LUA ANSI sequences to **`Write-Host`** via `Write-INLHostAnsiLine`; **session dump-count banner** lives here instead of being duplicated per console.
- **`Write-AlignedSummaryLine`** and **FileAnalysis** — 30-character label column and **dark cyan** values to line up with LUA `inl_ui`.
- **N64 module** — ROM-only dumps to **`games\n64\*.z64`** through **`inlretro2.lua`** (no `-k`; LUA auto-detects), with failure handling and **ReDump** wired in.
- **UI** — Banner/version **0.11**; N64 menu entry enabled (white, not gray).
- **Deploy / iteration** — For day-to-day work on modules only, reloading via **`Import-Module -Force`** in the entry script (see the two items at the top of this file) avoids rebuilding `inlretro.exe` or reflashing firmware when you are only changing `.psm1` files.

## Host bundle

This release ships a rebuilt **`inlretro.exe`** and the updated **`host/scripts/`** LUA files together (LUA is loaded at runtime from the tree next to the executable). The **`Import-Module -Force`** notes at the top are PowerShell-only: they help when you edit **`.psm1`** files without restarting the shell. Use the new exe when you need the LUA and host-binary changes listed in the sections above.

## Clarifications (N64 output + dictionary alignment)

- **`with_styled_print` vs N64** — The split is **intentional**: N64 runs **without** the global `print` hook; every other console path uses **`inl_ui.with_styled_print`** when ANSI is on. **`inl_ui.lua`** and **`inlretro2.lua`** now document that explicitly so it is not mistaken for an unfinished workaround. The hook still **always restores** the previous `print` after the wrapped run (including on errors).
- **Dictionary / firmware alignment** — **`dict.lua`** now states at the top of the module that **`shared_dict*.h`**, **`dict.lua`**, and the **flashed firmware** must be updated together; **`shared_dictionaries.h`** already described the same workflow. Treat this as a **release discipline** note, not an open defect in this drop—ship matching host scripts and firmware when you change dictionary opcodes.
