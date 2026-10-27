# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows desktop tool (no install, no CLI knowledge required) that converts iPhone `.HEIC` photos to `.jpg` and helps clean up a photo backup folder: duplicate photos, orphaned Live Photo `.MOV` files, `.aae` edit-metadata files, and misc. video files. A user double-clicks `HEIC_Donustur.bat`, which launches `HEIC_Donustur.ps1` in the folder it was copied into (recursing into subfolders). All user-facing text and comments are in Turkish.

## Commands

There is no build step — this is a script-based tool, run directly.

- **Run the tool interactively:** double-click `HEIC_Donustur.bat`, or from PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File HEIC_Donustur.ps1`
- **Run the test suite** (covers `PhotoDuplicateFinder.ps1` only — see Architecture): `Invoke-Pester -Path PhotoDuplicateFinder.Tests.ps1`
  - This machine has Pester 3.4.0 (Windows' built-in version), which uses the older `Should Be` assertion syntax, not the newer `Should -Be`. Match that syntax when adding tests.
  - `Invoke-Pester -Path` sometimes needs an **absolute path** to resolve correctly in this environment — a bare relative filename can silently fail to find tests.
- **Syntax-check a script without running it:**
  ```powershell
  $errs = $null
  [System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw "HEIC_Donustur.ps1"), [ref]$errs) | Out-Null
  if ($errs.Count -eq 0) { "OK" } else { $errs }
  ```
- **Releases:** version lives in `$Version` at the top of `HEIC_Donustur.ps1`. Tag as `vX.Y` and publish via `gh release create`.

## Architecture

Two PowerShell files, split by testability:

- **`HEIC_Donustur.ps1`** — the entire interactive tool. Everything here touches the filesystem, prompts the user (`Read-Host`/`Ask-YesNo`), or writes output — none of it is unit tested (matches how the whole file is written: a straight-line interactive script, not a library). Key structure:
  - Startup does a one-time check for the Windows **HEIF Image Extensions** / **HEVC Video Extensions** packages (`Get-AppxPackage`) and opens the Store to install them if missing, then exits.
  - `Ask-Menu` shows a numbered menu (currently 1-6) and returns the selected operation numbers; empty input = run everything.
  - The whole interactive flow is wrapped in `while ($devamEt) { ... }` — after finishing the selected operations, the user is asked whether to return to the menu (`Ask-YesNo "Ana menuye donup..."`) for another pass, or exit.
  - HEIC→JPG conversion uses the **WinRT** `Windows.Graphics.Imaging.BitmapDecoder`/`BitmapEncoder` APIs (not `System.Drawing`, which cannot decode HEIC) inside a runspace pool (`$ConvertScriptBlock`) so multiple files convert in parallel; each runspace re-imports the WinRT types since they don't share state across runspaces. `SetPixelData` writes pixels only, so EXIF metadata (DateTaken, GPS, camera) is copied separately property-by-property via `BitmapProperties.GetPropertiesAsync`/`SetPropertiesAsync` (one unsupported property fails a whole batch); GPS is the exception — WinRT can't read the array-typed `System.GPS.Latitude/Longitude` at all, so raw GPS IFD tags 0-31 are copied from `/ifd/gps/{ushort=N}` (HEIF) to `/app1/ifd/gps/{ushort=N}` (JPEG). Verified against real iPhone 14 Pro / 17 Pro Max photos. The JPG's file timestamps are set to DateTaken. The pool **must be MTA** — under STA those metadata calls deadlock when awaited with `.Wait()`.
  - All file discovery goes through `Get-FilesByExtension` (`-LiteralPath` + manual extension/folder filtering). Don't reintroduce `Get-ChildItem -Path ... -Include` or `-like "$folder*"`: `-Path`/`-like` treat `[ ]` in folder names as wildcards (finds nothing in e.g. `Yedek [2023]`), `-Include` is silently ignored with `-LiteralPath`, and under tr-TR `*.heic` doesn't match `IMG_0001.HEIC`.
  - Shared helpers used by several menu operations: `Move-ToFolder` (moves a file into a folder, auto-renaming on name collision — does **not** create the destination folder itself, callers must `Test-Path`/`New-Item` first), `Get-PairedMov` (finds a same-name `.mov` next to a photo, for Live Photo handling), `Write-Log` (prints to console *and* accumulates into `$logLines`, written to `HEIC_Donustur_Log_*.txt` once at the very end of the whole session).
  - Each menu operation follows the same two-step pattern: compute a destination folder path unconditionally, ask `Ask-YesNo` only if that operation was selected, then do the work if confirmed — this keeps folder-exclusion filters (e.g. "don't rescan the duplicates folder") valid regardless of which operations ran.
  - Menu option 6 ("Farkli cozunurlukte ayni fotograflari bul") is the one non-trivial block: it dot-sources and orchestrates `PhotoDuplicateFinder.ps1` (see below), then bridges pure fingerprint objects back to real files via `Add-Member -Name FileInfo` before calling `Move-ToFolder`/`Get-PairedMov`.

- **`PhotoDuplicateFinder.ps1`** — dot-sourced by `HEIC_Donustur.ps1` (`. (Join-Path $root "PhotoDuplicateFinder.ps1")`), a small library of pure, unit-tested functions with no interactive prompts, implementing the "same photo saved at two different resolutions" detector (e.g. an original phone JPEG vs. a re-encoded HEIC→JPEG copy — re-encoding changes every byte, so plain SHA-256 duplicate detection misses these). Pipeline, in call order:
  1. `Get-ImgKey` — extracts an `IMG_####` filename identifier used as a cheap candidate pre-filter (only files sharing this key are ever compared) — deliberately not full pairwise comparison across the whole library, for performance.
  2. `Get-ImageFingerprint` — opens a file (`System.Drawing.Bitmap`), calls `Get-OrientationCorrectedBitmap` (applies EXIF orientation via `RotateFlip` so a photo stored "rotated via EXIF tag" and one stored "pre-rotated into pixels" hash the same) then `Get-DHash` (9x8 grayscale difference hash → 64-bit perceptual hash), returns `{Path, Hash, Width, Height, FileSize}` or `$null` on any read failure (must never throw — this runs across an entire photo library and one bad file can't stop the batch).
  3. `Get-HammingDistance` — bit-distance between two hashes.
  4. `Resolve-DuplicateClusters` — groups a same-`IMG_####`-key candidate list into clusters via union-merge on Hamming distance (threshold hardcoded to `6`, set where it's called in `HEIC_Donustur.ps1`, not user-configurable); singletons that matched nothing are dropped.
  5. `Select-DuplicateWinnerAndLosers` — within one cluster, keeps the highest-resolution file (ties broken by larger file size), returns the rest as `Losers` to be moved (never deleted) to `Dusuk_Cozunurluklu_Kopyalar`.
  - **`Add-Type -AssemblyName System.Drawing` must be loaded before any of these functions run** — it's called once near the top of `PhotoDuplicateFinder.ps1` itself (not left to the caller), because `System.Drawing` isn't loaded by default in a fresh PowerShell process and this was once a real, silent-failure production bug (every image quietly reported "unreadable").
  - Raw `.heic` files are excluded from this scan (only `.jpg`/`.jpeg`/`.png`) because `System.Drawing`/GDI+ cannot decode HEIC — only the WinRT path in `HEIC_Donustur.ps1`'s conversion step can. Run menu option 1 first to convert HEIC files before they're eligible for this comparison.

## Environment quirks worth knowing before editing either file

- **This machine runs under Turkish (tr-TR) system culture**, which changes how PowerShell's default case-insensitive string comparisons behave (the "Turkish I problem": `i`/`I` are not case-equivalent under tr-TR). `Get-ImgKey` in `PhotoDuplicateFinder.ps1` works around this with `[System.Text.RegularExpressions.Regex]::Match(..., 'IgnoreCase, CultureInvariant')` instead of plain `-match`. Any new case-insensitive string matching should do the same.
- **Windows PowerShell 5.1** (not PowerShell 7+) is the actual runtime — binary literals (`0b1010`) are not valid syntax here, and wrapping a `List[object]` whose elements are themselves arrays in `@(...)` throws `ArgumentException` (`PSToObjectArrayBinder`) — use `$list.ToArray()` (with a leading comma, `, $list.ToArray()`, if returning it so PowerShell doesn't unroll the outer array) instead. See the comment above `Resolve-DuplicateClusters`'s `return` statement for the documented example.

## Design docs

Feature work in this repo has gone through a brainstorm → spec → plan process; past specs/plans are kept in `docs/superpowers/specs/` and `docs/superpowers/plans/` and are worth checking before starting related work — they capture *why* certain trade-offs were made (e.g. why the resolution-duplicate-finder uses a filename pre-filter instead of full pairwise comparison, why the Hamming threshold is `6`).
