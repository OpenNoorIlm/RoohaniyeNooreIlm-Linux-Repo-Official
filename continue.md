# RoohaniyeNooreIlmLinux — continue.md

Context file for the next Claude picking this project up. Read this first.

## What this is

A custom Linux distro concept: a distraction-free device that boots straight
into a Quran/Hadith reader. No general browser, no arbitrary package manager —
apps can only be installed through a curated GitHub-hosted app center
(`OpenNoorIlm/RoohaniyeNooreIlmLinux-App-Center`), which only lists
FOSS-licensed apps pointing at their own official releases.

The "OS" right now is really: a Qt5/QML kiosk shell app (`roohaniye-shell`)
meant to run as the *only* GUI process on the machine, plus two SQLite
databases with the actual Quran/Hadith content.

## Where things live

- Project root: `~/Downloads/RoohaniyeNoorIlmLinux/`
- Shell source: `~/Downloads/RoohaniyeNoorIlmLinux/shell-src/`
- Build dir: `~/Downloads/RoohaniyeNoorIlmLinux/shell-src/build/`
- Data (on the dev machine, NOT the repo): `/opt/roohaniye/data/`
  - `quran_text.db` — ~0.8MB, the `verses` table only (6,236 verses)
  - `quran_audio.db` — ~21.5GB, `audio_files` (56,124 rows, 9 reciters) +
    `word_timings` (empty so far)
  - `quran_audio_embedded.db` — the OLD pre-split combined file (verses +
    audio_files + word_timings in one file). **No longer opened by the
    shell as of this session** (see "This session's work" below) but
    still sitting on disk, untouched, in case anything needs re-deriving
    from it. Safe to delete once you've confirmed the split files have
    been working for a while; nothing currently reads it.
  - `hadiths.db` — ~42MB, 15,152 hadiths from Bukhari + Muslim
  - Migration script that produced the split:
    `shell-src/scripts/split_quran_db.py` (re-runnable if you ever need
    to regenerate quran_text.db/quran_audio.db from the original combined
    file — refuses to run if the two output files already exist).
- App Center manifest repo (separate, on GitHub):
  `https://github.com/OpenNoorIlm/RoohaniyeNooreIlmLinux-App-Center`
  — has one real file, `apps.json`, format documented below.

Dev machine: Ubuntu 24 (2026-era point release), user `bismillah`,
IdeaPad-1-15ALC7 laptop. Real target hardware will eventually be old x86
laptops + ARM (Raspberry Pi-class), but all current work/testing is on
this Ubuntu laptop in windowed mode (`QT_QPA_PLATFORM=xcb`).

## Build & run (how the user actually tests this)

```bash
cd ~/Downloads/RoohaniyeNoorIlmLinux/shell-src/build
cmake ..   # only needed after CMakeLists.txt or new source files change
make
QT_QPA_PLATFORM=xcb ./roohaniye-shell
```

`main.cpp` forces `QT_QPA_PLATFORM=eglfs` (draws straight to framebuffer,
no window manager — for real kiosk deployment) UNLESS the env var is
already set, so `QT_QPA_PLATFORM=xcb` overrides it for windowed dev testing.

Esc quits the app (via a QML `Shortcut`) — this is dev-only; there's no
escape hatch by design in the final kiosk product.

**IMPORTANT WORKFLOW NOTE**: the user asked that after any code change,
Claude should build AND launch it itself via run_command (headless,
`timeout N env QT_QPA_PLATFORM=xcb DISPLAY=:0 ./roohaniye-shell 2>&1`)
to catch build errors and startup crashes before handing back to the user.
Claude cannot send mouse clicks or keypresses remotely — anything requiring
actual interaction (tapping a button, typing a WiFi password, confirming a
restart dialog) has to be tested by the user, not Claude.

**Testing screens Claude can't click into**: since the Loader-based view
stack in `Main.qml` only parses a QML file once `currentView` actually
switches to it, headless verification of *new* screens (nothing has
clicked the tile that reaches them yet) requires temporarily hardcoding
`currentView`'s default (and any relevant `nav*` property defaults) to the
target screen, rebuilding, running headless with
`QT_QPA_PLATFORM=offscreen` (works even with no real X server — more
reliable than `xcb` for this than `DISPLAY=:0`, which may not have a
running server), checking stderr for QML warnings, then reverting the
hardcoded defaults before handing back. This session used that technique
to individually verify QuranMenu, AboutQuran, ReciterPicker, and
QuranView's `navPage`/`navJuz`/`navLayoutMode`/audio-bar code paths — all
came back clean (no warnings). Always diff against a backup of the file
you temporarily edited before finishing, to make sure the revert was
exact.

## Architecture

- `main.cpp` — entry point. Opens all three DBs in C++ BEFORE loading QML
  (`quranBackend.openDatabases(quran_text.db, quran_audio.db,
  hadiths.db)` — see "Audio DB split" below for why it's three paths now,
  not two), registers backend objects into the QML context
  (`appCenter`, `quranBackend`, `audioBackend`, `wifiBackend`,
  `powerBackend`), forces eglfs unless overridden. Backend declaration
  order matters and is commented in the source: backends must outlive
  `QQmlApplicationEngine` (reverse C++ destruction order), and
  `AudioBackend` (holds a raw `QuranBackend*`) must be declared after
  `QuranBackend` so it's destroyed first.
- `appcenter.h/.cpp` — fetches `apps.json` from the GitHub repo, sha256-
  verifies downloads, installs via `pkexec dpkg -i`. This is the ONLY
  sanctioned way to add software. Manifest parsing also reads optional
  `category`/`publisher`/`icon_url` fields (default gracefully — the
  real manifest doesn't have them yet, only the VLC test entry). Also
  has a local installed-apps registry backing the Manage page:
  `installedApps()`, `isInstalled()` (QSettings-backed at
  `/opt/roohaniye/data/appcenter_installed.ini`), `uninstallApp()` (runs
  `pkexec dpkg -r <id>` — **assumes manifest `id` == dpkg package name**,
  true for the VLC test entry but not modeled as a separate field; if a
  future manifest entry's package name differs from its id, this breaks
  and needs a stored `packageName` field), and `availableUpdates()`
  (diffs each installed app's recorded version against the current
  manifest's version for that id — a manifest-version diff, not a real
  dpkg/apt check, but sufficient since the App Center is the only way to
  install anything on this OS). Verified for real (see below): seeding
  `appcenter_installed.ini` with a stale-versioned VLC entry correctly
  populated both `installedApps()` and `availableUpdates()`.
- `quranbackend.h/.cpp` — read-only SQLite layer over the Quran DBs (now
  `quran_text.db` as the main connection with `quran_audio.db` ATTACHed
  onto it as `audiodb` — see "Audio DB split" below) and `hadiths.db`.
  QSettings-
  backed for reading progress/preferences. Exposes `verse()`,
  `randomHadith()`, `randomVerse()`, `surahList()`, `surahInfo()`,
  `versesInSurah/Juz/Page/Manzil/Ruku()`, `totalJuz/Pages/Manzils/Rukus()`,
  `quranStats()` (counts backing `AboutQuran.qml`), `nextVerse()` /
  `previousVerse()` (sequential navigation, wraps at 1:1 — used by
  AudioBackend's range-repeat), `reciterList()` (reciters actually present
  in `audio_files`, with display name + Murattal/Mujawwad style),
  `audioBase64()` and `audioFilePath()` (writes/dedupes a verse's audio
  blob to a disk cache file and returns the path — this is what
  AudioBackend hands to QMediaPlayer instead of round-tripping base64),
  `versesForSelection()` (expands a multi-select of juz(s)/surah(s)/
  individual ayah(s) into an ordered, de-duplicated `{surah,ayah}` list —
  backs the "select then pick a reciter" playback feature, see below),
  and `saveProgress()`/`lastProgress()`/`setPreference()`/`preference()`.
  Schema:
  - `verses`: id, surah, ayah, text_uthmani, text_sahih, text_kanzuliman,
    text_jalalayn, juz, page, sajda. UNIQUE(surah,ayah) auto-indexed.
  - `audio_files`: verse_id, reciter_id, audio_data (BLOB) — this is why
    the db is 21GB.
  - `word_timings`: verse_id, reciter_id, timings_json
  - `hadiths` (separate db): id, book, hadith_num, topic, english, urdu,
    arabic, power. Also has FTS5 tables (hadiths_fts*) for search, unused
    by the shell so far.
- `audiobackend.h/.cpp` — wraps `QMediaPlayer` for verse-by-verse
  recitation playback, wired into `main.cpp`/`CMakeLists.txt`/QML context
  as `audioBackend`. Three loop modes: `Off` (play once), `RepeatVerse`
  (loop current verse), `RepeatRange` (walk forward verse-by-verse
  through a range — default the whole Quran — and wrap back to the
  start). `setReciter()` hot-swaps reciter mid-session, restarting the
  current verse if something's already loaded. **Playlist mode (added
  this session)**: `playSelection(verses, reciterId)` takes an ordered
  list of `{surah,ayah}` maps (from `QuranBackend::versesForSelection()`)
  and plays through it verse-by-verse, wrapping back to the start when it
  reaches the end (unless `loopMode` is `Off`, in which case it stops
  after one full pass — same "Off" semantics as single-verse playback).
  `usingPlaylist`/`playlistLength`/`playlistPosition` properties expose
  progress to QML. `clearSelection()` drops the active playlist (called
  automatically by `stop()` and by `playVerse()`, so a normal single-verse
  tap always cancels any in-progress selection playback). Header has a
  good writeup of a real hardware constraint worth re-reading before
  touching this file: audio keeps playing through screen blanking (same
  process, doesn't care about QML/window state) but NOT through full
  suspend-to-RAM, and whether the device is allowed to suspend at all
  while reciting is a system-level policy decision, not something this
  class can control.
- `wifibackend.h/.cpp` — wraps `nmcli` (no NetworkManager D-Bus lib linked,
  simpler this way). Scan, connect, toggle radio.
- `powerbackend.h/.cpp` — `systemctl poweroff` / `systemctl reboot`.
- `storagebackend.h/.cpp` + `dbconnectorbackend.h/.cpp` — the "Database
  Connector" feature (from a prior session, undocumented here until now).
  `StorageBackend` detects removable storage (USB/microSD/SD) via
  filesystem polling (same simple/no-D-Bus philosophy as wifibackend).
  `DbConnectorBackend` (holds a raw `QuranBackend*`) does the actual work:
  `listDirectory()` browses into a mounted device, `importPath()` accepts
  a `.db` file (imported as-is), a folder (searched for a `.db` inside),
  or a `.json` file (converted to `.db`) — copies the result into
  `/opt/roohaniye/data/imported/`, then reports which installed "apps"
  (Quran audio, hadith, etc — matched by table/column shape) the imported
  db is structurally compatible with. `connectToApp()` then hot-swaps that
  app's live db connection to the imported file via
  `QuranBackend::reattachAudioDb()`/`reattachHadithDb()` (DETACH/re-ATTACH
  or close/reopen on the existing connection, verified against the
  expected table before committing) and persists the choice in
  `shell_settings.ini` so it survives a restart. Reached from the home
  screen via `currentView: "dbconnector"` → `qml/DatabaseConnector.qml`.
  Verified end-to-end (folder→db discovery, JSON→db conversion, direct
  `.db` import, hot-swap, and persistence-across-restart) against a
  simulated `/tmp/usb_test` device in an earlier session — see "Bugs
  fixed" below for a real leftover bug from that session's test code that
  this session found and cleaned up.
- `qml/Main.qml` — fullscreen Window, Loader-based view stack with fade
  transitions, Esc-to-quit Shortcut. Boots to `currentView: "splash"`;
  `SplashScreen.qml` advances to `"home"` itself via an internal Timer.
  `currentView` values: `"splash"`, `"home"`, `"appcenter"`,
  `"quranmenu"`, `"quranreader"`, `"quran"` (legacy alias, also routes to
  QuranView.qml), `"aboutquran"`, `"hadith"`, `"settings"`,
  `"dbconnector"` — anything else falls through to `HomeScreen.qml`. Nav properties:
  `navSurah`/`navAyah` (existing) plus `navPage`/`navJuz`/`navLayoutMode`
  (added this session) — all one-shot, consumed and reset by
  `QuranView.qml`'s `Component.onCompleted`.
- `qml/HomeScreen.qml` — Quran tile now routes to `"quranmenu"` (was
  `"quran"` direct-to-reader — changed this session so the new landing
  menu is actually reachable). Hadith tile unchanged. App grid: App
  center and DB Connector work. Updates works (see "OS update checking"
  section below). **Prayer Times and Qibla now work too** — built and
  verified this session, see "Prayer Times / Qibla (this session)" below.
- `qml/QuranMenu.qml` — landing screen for "Quran" from the home screen:
  tiles for Hafizi (mushaf), Juz, Surah, Go to Page, About Quran, Random,
  plus a "Continue reading" card when `quranBackend.lastProgress()` has a
  surah. **Now in `qml.qrc` and reachable** (was dead code at the start of
  this session — written previous session, never wired in). Verified
  clean load this session via the temporary-default technique above.
- `qml/QuranView.qml` — the per-surah/mushaf reader. Reading mode:
  per-surah scroll with inline translations, now with a small play/pause
  icon per verse. Mushaf mode: Hafizi-style dense Arabic-only paginated
  Flow, RTL, prev/next + jump-to-page. Surah/juz picker overlays,
  reading-settings overlay (layout toggle, English/Urdu/Tafsir switches,
  3-step Arabic font size), resumes last position via
  `quranBackend.lastProgress()`, saves on `Component.onDestruction`.
  **This session's changes:**
  - `Component.onCompleted` now consumes `root.navJuz` / `root.navPage` /
    `root.navLayoutMode` in addition to the existing `navSurah`/`navAyah`,
    in priority order juz > page > surah > last-saved-progress, so
    QuranMenu.qml's Hafizi/Juz/Surah/Go-to-Page/Random tiles all land
    correctly.
  - Loads `quranBackend.reciterList()` and a `selectedReciterId`
    (persisted via `quranBackend.preference("reciterId", ...)`) on open.
  - Per-verse play/pause icon in reading mode (hidden entirely if the db
    has no reciters) calls `audioBackend.playVerse()` /
    `pause()`/`resume()` via a new `toggleVersePlayback()` helper.
  - A persistent mini audio bar (bottom of the view, appears once
    `audioSessionStarted` — i.e. the user has actually pressed play once
    this view instance) shows current surah:ayah, reciter name, a
    play/pause button, a loop-mode cycle button (Off → RepeatVerse →
    RepeatRange → Off), a button to open the new `ReciterPicker.qml`
    overlay, and a stop button. Playback errors from
    `audioBackend.playbackError` show inline in the bar for 4s then clear
    (`Connections` + `Timer`).
  - **Known minor cosmetic gap, not fixed this session**: the mini audio
    bar is anchored to the bottom of the whole view and can visually
    overlap the mushaf mode's prev/next-page button row when both are
    visible at once. Functionally fine (z-ordering means the audio bar
    wins clicks in the overlap area), just not polished — worth a layout
    pass if the user notices/cares.
  - **Multi-select playback (added a later session, see "Multi-select
    juz/surah/ayah playback" below)**: a checkbox-toggle button in the
    top bar (only shown once a reciter is available) puts reading mode
    into ayah-selection mode — tapping verses toggles them instead of
    playing/navigating, a "Play N selected ayahs" bar appears once
    something's checked, and confirming opens `ReciterPicker` in a
    special "for selection" mode (`reciterPickerForSelection`) that
    builds a playlist via `quranBackend.versesForSelection()` and starts
    it with `audioBackend.playSelection()` instead of the normal
    single-reciter-preference flow. The mini audio bar shows
    "N/M selected" next to the surah:ayah label whenever
    `audioBackend.usingPlaylist` is true.
- `qml/AboutQuran.qml` — **NEW this session.** Reached from QuranMenu's
  "About Quran" tile (was previously pointing at a nonexistent file).
  Pure read-only display of `quranBackend.quranStats()` in the same
  tile-grid visual style as QuranMenu — surahs, ayahs, juz, pages,
  manzils, rukus, hizb quarters, sajdas (+ obligatory-sajda count).
- `qml/ReciterPicker.qml` — **NEW this session.** Full-screen overlay
  listing `quranBackend.reciterList()` (name + Murattal/Mujawwad style),
  checkmark on the current selection, same visual pattern as
  SurahPicker/JuzPicker (`picked(reciterId)` / `closed()` signals).
  Opened from QuranView's mini audio bar; picking a reciter persists the
  preference and hot-swaps mid-playback via `audioBackend.setReciter()`
  if a session is already active.
- `qml/SurahPicker.qml` — full 114-surah list overlay (from
  `quranBackend.surahList()`), picks a surah (and optionally ayah). Also
  has a "Select" toggle (added this session) for multi-surah selection —
  see "Multi-select juz/surah/ayah playback" below.
- `qml/JuzPicker.qml` — Juz 1–30 picker overlay, jumps mushaf mode to
  that juz's starting page. Also has a "Select" toggle (added this
  session) for multi-juz selection — see below.
- `qml/HadithView.qml` — UNCHANGED, still VERY basic: one random hadith
  + "another" button. No book/topic browsing, no language toggle.
- `qml/AppCenter.qml` — REDESIGNED (GNOME-Software-style) in a later
  session, see "App Center redesign + splash screen" below. Left sidebar
  (Explore / Featured / category tabs / Manage / About — **no Games
  category, deliberately**), search bar, Explore page with a featured
  banner + app card grid (icon-letter avatar, name, publisher,
  description, Install/Installed button), Manage page with "Updates
  available" (per-item Update + "Update all") and "Installed apps" (with
  Uninstall) sections, and a simple About page. `activeSection` defaults
  to `"Explore"`. Two local inline `component`s: `SidebarItem`, `AppCard`.
- `qml/SplashScreen.qml` — boot splash shown first (`Main.qml`'s
  `currentView` starts at `"splash"`), holds ~2s with a crescent-and-star
  badge + wordmark + pulsing loading dots (Rectangles/Text glyphs, no
  image assets), then sets `root.currentView = "home"` itself via an
  internal Timer. **Visually unreviewed by the user** — only confirmed to
  render with zero QML warnings, never checked against a design
  reference.
- `qml/SettingsView.qml` — WiFi toggle + network list + password dialog +
  restart/shutdown buttons with confirm dialogs.

## Multi-select juz/surah/ayah playback + leftover-bug cleanup (this session)

**The feature requested**: a "Select" button reachable from juz, surah,
and ayah browsing that lets the user pick several of them, then tapping
it again opens the reciter picker and plays through just the selected
items (looping/repeat modes apply the same as normal playback).

**What was built**:
1. `QuranBackend::versesForSelection(items)` (new) — takes an array of
   `{type:"surah"|"juz"|"ayah", ...}` selection items and expands them
   into an ordered, de-duplicated `{surah,ayah}` list using a `QMap` keyed
   by `surah*10000+ayah` (dedup + natural Quran order for free, regardless
   of the order the user tapped things in, and regardless of overlapping
   selections across types).
2. `AudioBackend` playlist mode (new): `playSelection(verses, reciterId)`,
   `clearSelection()`, plus `usingPlaylist`/`playlistLength`/
   `playlistPosition` properties. `advancePlaylist()` walks the list and
   wraps to the start on reaching the end (unless `loopMode == Off`, which
   stops after one full pass). `stop()` and `playVerse()` both call
   `clearSelection()` so a normal single-verse tap always cancels any
   selection playback in progress — no risk of stale playlist state
   confusing a later single-verse session.
3. `JuzPicker.qml` / `SurahPicker.qml`: each got a "Select" toggle in the
   header. In selection mode, tapping an item checks/unchecks it (✓
   badge) instead of navigating; a "Play N selected" bar appears at the
   bottom once something's checked, emitting `playSelected(items)`.
4. `QuranView.qml`: a new checkbox-toggle button in the top bar (reading
   mode only, hidden if there's no reciter available) puts the verse list
   into ayah-selection mode — same tap-to-check pattern, own "Play N
   selected ayahs" bar. `pendingSelection` + `reciterPickerForSelection`
   unify all three entry points: whichever picker's `playSelected` fires
   (or the ayah-selection confirm bar), the selection is stashed and
   `ReciterPicker` opens in "for selection" mode; picking a reciter there
   calls `quranBackend.versesForSelection()` then
   `audioBackend.playSelection()` instead of the normal
   set-reciter-preference flow. The mini audio bar shows "N/M selected"
   whenever a playlist is active.
5. Verified: clean `cmake .. && make`. Headless-tested each new/changed
   overlay individually via the established temporary-default technique
   (forced `showSurahPicker`/`showJuzPicker`/`showReciterPicker` all
   active plus `ayahSelectionMode` with a pre-populated selection in one
   pass, then separately forced `selectionMode: true` with pre-checked
   items in both `JuzPicker.qml` and `SurahPicker.qml`) — all came back
   with zero QML warnings. All temporary hardcodes reverted afterward;
   diffed every touched file against pre-test backups to confirm each
   revert was exact (empty diffs) and grepped for leftover debug strings.
   Final rebuild + headless run with real (unhardcoded) defaults also
   came back clean.

**Not done / follow-ups**:
- No real hands-on tap-through by the user yet (Claude can't click) —
  this is "verified data-flow correct + zero QML warnings", not "the user
  has actually selected three surahs and heard them play in order."
- Mushaf mode doesn't get ayah-selection (only reading mode does) — if
  the user wants to select ayahs while in mushaf/Hafizi view too, that's
  a follow-up, not yet built.
- No visual indicator of *which* juz/surah is playing when a playlist
  spans a boundary — the mini audio bar shows raw surah:ayah + "N/M
  selected", not e.g. "Juz 5, verse 12 of 340". Fine for now, worth
  polishing if the user finds it confusing in practice.

**Leftover bugs found and fixed from the previous (Database Connector)
session**, before starting on the above — that session's own cleanup
pass claimed everything was reverted, but two things were missed:
1. `Main.qml`'s `currentView` default was still hardcoded to
   `"dbconnector"` (not reverted to `"splash"` as documented) — every
   launch was booting straight into the Database Connector screen instead
   of the real splash → home flow. Fixed.
2. `main.cpp` still had a `TEMP-DEBUG` block that ran on **every
   startup**, silently importing a fake test hadith db from
   `/tmp/usb_test` and hot-swapping the app's live hadith connection to
   it via `dbConnectorBackend.connectToApp()`. Worse: that swap
   **persisted** — it wrote `hadithDbOverridePath=/tmp/usb_test/subdir/
   my_hadiths.db` into `/opt/roohaniye/data/shell_settings.ini`, so even
   after removing the debug code, the shell would have kept loading the
   one-fake-hadith test db forever instead of the real 15,152-hadith
   `hadiths.db`. Removed the debug block from `main.cpp` and manually
   cleared the stale `hadithDbOverridePath` line from
   `shell_settings.ini`. Confirmed via headless run that
   `openDatabases` still reports `hadithOk=true` against the real db and
   no `TEMP-DEBUG` output appears anymore.

**Lesson for future sessions**: when a previous session's `continue.md`
entry claims "reverted, confirmed clean," it's still worth an actual
`grep -rn "TEMP-DEBUG"` / spot-check of the relevant files before trusting
it and moving on — this is the second session in this project where that
claim turned out to be incomplete (see "Session A" under the App Center
section below for the first case, which is exactly why Session B existed).
Also worth checking QSettings-persisted state (`shell_settings.ini`), not
just source files — a debug session that calls a "persist this choice"
code path can leave behind stale runtime state that source-diffing alone
won't catch.

## GitHub distro-download repo — status check (this session)

Checked `https://github.com/OpenNoorIlm/RoohaniyeNooreIlm-Linux-Repo-Official`
(the repo the user asked about for "downloading updates"): it exists, is
public, MIT-licensed, and has exactly one commit containing only a
`README.md` and `LICENSE` — **no releases, no actual distro image, no
update manifest of any kind published yet.** So right now it can't
actually be used for downloading updates; it's just the placeholder/name
reserved. This is a **separate repo** from the App Center manifest repo
(`OpenNoorIlm/RoohaniyeNooreIlmLinux-App-Center`, which does have a real
`apps.json` with the VLC test entry) — don't conflate the two. If the
user wants an actual update-check/download mechanism for the OS image
itself (as opposed to app installs via the App Center), that would need:
(a) something published in this repo — a `manifest.json` + release
assets, e.g. squashfs/img files with version numbers and checksums — and
(b) new shell-side code (maybe an `OtaBackend`?) to check it and
download/apply updates. Neither exists yet. Worth asking the user whether
they want that built next, and if so, what they intend to publish there
first (full image releases? delta updates? just a version-check ping?).

## OS update checking (this session)

Built the `OtaBackend`-equivalent asked about above: `UpdateBackend`
(`updatebackend.h`/`.cpp`), wired into `main.cpp`,
`CMakeLists.txt`, `qml.qrc`, `Main.qml` (`"updates"` case), and the
`HomeScreen.qml` app grid ("Updates" tile). New `qml/UpdatesView.qml`
screen: shows installed version (reads `/opt/roohaniye/VERSION`, falls
back to `"0.0.0"`), a "Check for updates" button, and — if one's
available — release notes + a "Download & verify" button. Points at the
same repo confirmed above
(`OpenNoorIlm/RoohaniyeNooreIlm-Linux-Repo-Official`, `manifest.json` via
raw.githubusercontent.com).

Scope is deliberately narrow: **checks and downloads (with sha256
verification) but does not apply/flash the image** — that's a manual
step (`applyInstructions()` explains why: partition layout differs too
much across the target x86-laptop/ARM hardware range to do safely/
generically). Manifest format expected: `{"manifest_version":1,
"latest_version":"...", "release_notes":"...", "arch":{"x86_64":
{"url":"...","sha256":"...","type":"img"}, ...}}`. Unpublished manifest
(current real state of the repo, still just README+LICENSE) is handled
as a normal, non-error outcome — `statusMessage` says "No update
manifest has been published yet," not an error string.

Found and fixed one real compile bug during this work: `verifySha256()`
called `QByteArray::compare(QString, ...)`, which doesn't exist as an
overload — needed `expectedHex.toUtf8()` first. Wouldn't have been
caught without actually building.

Verified: clean build, headless run of the real boot flow (splash →
home) shows zero QML warnings. Separately hardcoded `currentView` to
`"updates"` (same project convention as always) and temporarily added a
`Component.onCompleted: updateBackend.checkForUpdate()` debug hook to
exercise the real network path — confirmed it hits the real repo and
correctly reports `avail=false, status="No update manifest has been
published yet."` rather than erroring. Both the hardcode and the debug
hook were reverted afterward; diffed clean against a `Main.qml` backup;
final rebuild + headless run confirmed real defaults restored and still
zero warnings.

Not done / open: nothing actually published in the repo yet (still just
README+LICENSE, per the status check above) so `checkForUpdate()` can't
be tested against a real "update available" response — only the
"nothing published" and general-error paths are exercised so far. The
happy path (real manifest → available update → download → sha256
verify → success) is implemented but untested against live data, since
there's no real manifest to test against.

## This session's work, summarized

Picked up the "split the 21.5GB quran_audio_embedded.db" item from Known
Gap #6 (previously "proposed, not done"). Done now:

1. Wrote `shell-src/scripts/split_quran_db.py` — a one-time migration
   script using SQLite `ATTACH` + `INSERT INTO ... SELECT` (runs entirely
   inside the SQLite engine, no row/blob data loaded into Python) to copy
   `verses` into a new `quran_text.db` and `audio_files`/`word_timings`
   into a new `quran_audio.db`. Includes row-count checks after each copy
   and a final cross-db join sanity check (re-opens both new files fresh
   and confirms `verses JOIN audiodb.audio_files` returns the expected
   row count) before declaring success.
2. Ran it against the real data: `quran_text.db` came out to 0.8MB (6,236
   verses), `quran_audio.db` to 21.57GB (56,124 audio_files rows, 0
   word_timings — matches source). Sanity check passed (56,124/56,124).
   Took ~85s. Original `quran_audio_embedded.db` left untouched on disk.
3. Updated `QuranBackend::openDatabases()` to take three paths
   (`quranTextDbPath`, `quranAudioDbPath`, `hadithDbPath` instead of the
   old `quranDbPath`, `hadithDbPath`). It opens `quran_text.db` as the
   main `quran_conn` connection, then runs
   `ATTACH DATABASE ? AS audiodb` on that same connection to bring in
   `quran_audio.db`. This means every existing query that joined
   `verses` with `audio_files` only needed a one-line change
   (`audio_files` → `audiodb.audio_files`) — no separate connection
   object, no manual two-step C++ lookup. Touched: `audioBase64()`,
   `audioFilePath()`, `reciterList()`.
4. Updated `main.cpp`'s `openDatabases()` call to pass
   `/opt/roohaniye/data/quran_text.db` and
   `/opt/roohaniye/data/quran_audio.db` instead of the old single
   `quran_audio_embedded.db` path.
5. Verified: clean `cmake .. && make`. Headless run
   (`QT_QPA_PLATFORM=offscreen`) confirmed `openDatabases` returns
   `quranOk=true` with no attach errors. Went further than a plain
   startup check — temporarily hardcoded `Main.qml`'s `currentView`
   default to `"quranreader"` (same technique as prior sessions) to
   force `QuranView.qml`'s `Component.onCompleted` to actually run
   `quranBackend.reciterList()` (the cross-db query), and separately
   added a temporary debug call to `audioFilePath(1, 1, "ar.alafasy")`
   in `main.cpp`. Both confirmed working for real: reciterList returned
   all 9 reciters, and audioFilePath wrote a real cache file that `file`
   confirmed as valid MPEG audio (146,830 bytes, 192kbps/44.1kHz/stereo)
   — i.e. the blob really did come back correctly through the attached
   `audiodb.audio_files` table. All temporary debug code and the
   `Main.qml` hardcode were reverted afterward; diffed `Main.qml` against
   a pre-test backup to confirm the revert was exact, and grepped the
   C++ for leftover `TEMP-DEBUG`/stale-path strings to confirm none
   remained. Final clean rebuild + headless run after revert also came
   back with `quranOk=true` and no warnings.

**Not done / follow-ups for a future session**:
- The old `quran_audio_embedded.db` (21.5GB) is still sitting on disk at
  `/opt/roohaniye/data/` — nothing reads it anymore, safe to delete once
  you've confirmed the split has been solid for a while.
- Real hands-on verification with actual playback through speakers/
  headphones on the target hardware hasn't happened — this session only
  confirmed the *data path* (attach, query, blob write) is correct, not
  perceived audio quality or latency.
- **Discovery, not this session's work**: `shell-src/prayerbackend.h`
  already exists — a fully-specced header (location, calculation
  settings, city list, `prayerTimesToday()`, `nextPrayer()`,
  `qiblaBearing()`) for what looks like exactly Known Gap #1's Prayer
  Times/Qibla work. There is **no `prayerbackend.cpp`** and it is **not
  referenced anywhere** in `CMakeLists.txt` or `main.cpp` — so it's
  declarations-only, unimplemented, unwired. Worth surfacing to the user
  next time gap #1 comes up: someone (a past session, or the user by
  hand) started designing this but never finished/wired it in.

## Prayer Times / Qibla (this session)

Implemented `prayerbackend.cpp` against the pre-existing
`prayerbackend.h` header (see the discovery note above), wired into
`CMakeLists.txt` and `main.cpp` (registered as `prayerBackend` in the
QML context), and built two new screens:

- `qml/PrayerTimesView.qml` — today's five prayer times + next-prayer
  countdown, plus a settings panel (calculation method preset,
  Asr factor/Hanafi-Shafii toggle, custom angle overrides). Caches
  `prayerBackend.calculationSettings()` into a local property and
  refreshes it explicitly on change, rather than binding directly to
  the C++ method call — direct binding to a method result doesn't
  re-evaluate reactively in QML and was silently going stale.
- `qml/QiblaView.qml` — static compass rose with a needle rotated to
  the qibla bearing, N/E/S/W labels. Dropped an earlier tick-mark
  `Repeater` with per-tick transform math (fragile, not essential —
  the labels and needle already communicate direction).
- `qml/LocationPicker.qml` — preset city list or manual lat/lon entry,
  feeds into both screens above.
- Home screen tiles for both now route correctly (`"prayertimes"`,
  `"qibla"` added to `Main.qml`'s Loader `source` cases).

**Real bug fixed**: the high-latitude fallback for Fajr/Isha (used when
the sun angle never reaches the target depression, e.g. UK in summer)
originally applied a fixed offset from Dhuhr, which put Fajr *after*
sunrise in London — nonsensical prayer ordering. Fixed with a
proportional angle-based fallback (Fajr/Isha computed from
sunrise/maghrib and night length) — verified correct ordering for
Mysuru, Makkah, London (high-latitude case), and New York via a
standalone test binary before touching the QML.

Verified headless (`QT_QPA_PLATFORM=offscreen`) via the temporary-
`currentView`-hardcode technique: zero QML warnings for
PrayerTimesView with no location set, with a location set (settings
panel data-refresh confirmed working), LocationPicker in both preset
and custom-entry modes, and QiblaView both with and without a location.
All temporary hardcodes (`Main.qml`'s `currentView` default, and a
`locpicker_test` Loader case) and a stray `[prayer]` section that
leaked into the real `/opt/roohaniye/data/shell_settings.ini` from the
standalone test binary were reverted/removed — confirmed via a final
clean headless run against real defaults (boots to splash, zero
warnings, no test data left in settings).

Known limitation carried forward: `qiblaBearing()`/prayer time math
hasn't been checked against a second independent source (e.g. a known
mosque's published prayer timetable) — only internally consistent
(correct ordering, plausible values) across the four test locations
above, not externally validated.

## App Center redesign + splash screen (spans two sessions)

**Session A** did the actual redesign work (backend + QML), got as far as
"compiles clean, headless run shows zero QML warnings" on both the
backend changes and the QML changes, but the Claude Commander connection
dropped mid-session before a final revert-and-verify pass could run,
leaving two test hardcodes stuck in the tree and one edit unapplied:
`Main.qml`'s `currentView` stuck at `"appcenter"`, `AppCenter.qml`'s
`activeSection` stuck at `"Manage"`, and a `"Games"` category-removal
edit that never landed. Backend changes (`appcenter.h/.cpp`: manifest
`category`/`publisher`/`icon_url` fields, `installedApps()`/
`isInstalled()`/`uninstallApp()`/`availableUpdates()`, the
`appcenter_installed.ini` registry) and the QML changes (`AppCenter.qml`
rewrite, new `SplashScreen.qml`, `Main.qml` routing update, `qml.qrc`
update) were otherwise real and already in the tree — see the Architecture
section above for what they actually are. Never visually compared against
the user's GNOME Software reference screenshots; only "renders without
QML errors" was checked, not real fidelity to the screenshots (rounded
card layout, spacing, exact "Featured" banner style, etc.), and the
splash screen's crescent-and-star design was never shown to the user at
all.

**Session B** (this session) picked up the cleanup:
1. Confirmed all three flagged spots were exactly as Session A described
   (read the files, didn't just trust the note) — `Main.qml`'s
   `currentView` really was still `"appcenter"`, `AppCenter.qml`'s
   `activeSection` really was still `"Manage"`, and `"Games"` really was
   still in `categories`.
2. Fixed all three: `currentView` → `"splash"`, `activeSection` →
   `"Explore"`, `categories` → `["Productivity", "Development"]`. Diffed
   against pre-edit backups to confirm these were the *only* changes.
   Clean `cmake .. && make`, headless run (`QT_QPA_PLATFORM=offscreen`)
   with the real defaults came back with zero QML warnings (times out
   mid-splash-hold as expected, same as Session A's last confirmed-good
   run).
3. Verified the Manage page's populated states for real (previously only
   the empty states were confirmed, since nothing had ever been installed
   through the App Center on this box). Did this **without** actually
   installing software — seeded `appcenter_installed.ini` directly with a
   stale-versioned VLC test entry (`version=3.0.20` vs the live
   manifest's `3.0.21`), temporarily hardcoded `currentView`/
   `activeSection` again plus a temporary `console.log` of
   `installedApps()`/`availableUpdates()`, rebuilt, ran headless. Both
   came back correctly populated with the right shape and zero QML
   warnings. Reverted all test code (diffed clean against backups) and
   deleted the seeded `appcenter_installed.ini` afterward — nothing was
   actually installed on the machine, no `pkexec`/`dpkg` was ever
   invoked. (Real installs go through an interactive `pkexec` password
   prompt that Claude can't drive headlessly anyway — worth remembering
   next time real install/uninstall verification comes up.)

**Still not done, for a future session**:
- **Visual fidelity check against the user's GNOME Software reference
  screenshots** — never done at all, by either session. Need the user to
  re-share the screenshots; nothing in this repo captures what they
  looked like.
- **Splash screen visual review** — same story, never shown to the user.
- A real end-to-end install/uninstall through the actual App Center UI
  (clicking Install on the VLC test entry for real) hasn't happened —
  only the registry-seeding shortcut above has been verified.

## apps.json manifest format

Hosted at `https://raw.githubusercontent.com/OpenNoorIlm/RoohaniyeNooreIlmLinux-App-Center/main/apps.json`

```json
{
  "manifest_version": 1,
  "apps": [
    {
      "id": "vlc",
      "name": "VLC Media Player",
      "description": "Open source media player",
      "license": "GPL-2.0",
      "version": "3.0.21",
      "arch": {
        "x86_64": {
          "url": "https://download.videolan.org/pub/videolan/vlc/3.0.21/vlc-3.0.21-amd64.deb",
          "sha256": "e617a7267a7e95f3d960359ce65409b9551d3043b6de4b51c41c406b171f954b",
          "type": "deb"
        }
      }
    }
  ]
}
```

Currently only has the one VLC entry (real, sha256-verified, used as a
test case). Repo intentionally has no LICENSE file — it's an index
pointing at other projects' own official releases, not original code, so
it shouldn't carry a license that'd override the listed apps' own licenses.

Policy (not code-enforced): only list FOSS-licensed apps, url must point
to the app's own official release, sha256 mandatory or the shell refuses
to install.

## Bugs fixed in earlier sessions (don't reintroduce these)

1. **Commander directory permissions**: `/opt/roohaniye/data` was created
   via `sudo mkdir`, staying root-owned even after the .db files inside
   were chowned to the user — SQLite couldn't open even read-only because
   it needs to write a temp/journal file in the same directory. Fixed with
   `sudo chown -R $USER:$USER /opt/roohaniye`.
2. **QQmlApplicationEngine::objectCreationFailed doesn't exist** on this
   Qt 5.15 packaging — use `objectCreated` signal instead, checking for a
   null object + matching URL.
3. **QtQuick.Window / QtQuick.Controls need separate apt packages**:
   `qml-module-qtquick-window2` etc — `qtdeclarative5-dev` alone isn't
   enough.
4. **eglfs env var was force-set unconditionally**, stomping the user's
   `QT_QPA_PLATFORM=xcb` override for windowed dev testing. Fixed with
   `qEnvironmentVariableIsEmpty` check before setting the default.
5. **Startup race condition**: `HomeScreen.qml` evaluates
   `quranBackend.randomHadith()` as a property binding at creation time,
   which could fire before `Main.qml`'s `Component.onCompleted` (which
   used to open the DBs) ran. Fixed by opening both DBs in `main.cpp`
   BEFORE `engine.load()`, not from QML at all.
6. **`ORDER BY RANDOM()` on hadiths table was slow** — forces a full
   table scan + sort of all 15,152 rows including large text columns.
   Fixed: get MIN/MAX id once, pick a random id, look up by primary key
   (`WHERE id >= ? ORDER BY id LIMIT 1`) — O(log n) instead of O(n log n).
7. **`Keys.onEscapePressed` on a plain Item didn't reliably quit the app**
   — only fires if that exact item has focus, easy to lose once other
   views/dialogs are loaded. Fixed with a window-level `Shortcut { sequence:
   "Esc" }` instead, which works regardless of focus.
8. **WiFi scan returning stale/empty results until a second visit** —
   `nmcli dev wifi list` without a forced rescan just returns whatever
   NetworkManager last cached. Fixed with `--rescan yes`, plus a guard so
   overlapping scan() calls don't stack up.
9. **Debug/test code left running in production after a session ended**
   — see "Multi-select juz/surah/ayah playback" above for the specific
   case (a `TEMP-DEBUG` block in `main.cpp` that silently swapped the
   live hadith db to a fake test file on every launch, and persisted that
   swap into `shell_settings.ini`). General lesson: always grep for
   `TEMP-DEBUG` and check `shell_settings.ini` for stale override paths
   as part of any "did the last session's cleanup actually work" check,
   not just diffing the QML/C++ source files that were mentioned.

## Known gaps / explicitly requested next work (from the user, in their words)

1. **Add functionality to remaining home-screen apps** — DONE. Updates,
   Prayer Times, and Qibla are all wired and working now (Prayer
   Times/Qibla built this session — see "Prayer Times / Qibla (this
   session)" above). All home-screen tiles now route to a real screen.
   Remaining loose end: qibla bearing/prayer time math has only been
   checked for internal consistency (correct ordering, plausible values
   across 4 test locations) — not cross-checked against a real published
   timetable. Worth doing before calling this fully trustworthy.
2. **Quran reader + audio** — reading/mushaf views, landing menu, About
   Quran panel, and recitation playback are all DONE and wired. Also DONE
   this session: multi-select juz/surah/ayah playback (select several,
   pick a reciter, it plays through just those in order) — see
   "Multi-select juz/surah/ayah playback" above. Remaining polish: the
   mini-audio-bar/mushaf-nav-row visual overlap noted above, ayah
   selection only works in reading mode (not mushaf mode) yet, and real
   hands-on verification by the user (Claude can't click/tap).
3. **Hadith reader overhaul** — NOT STARTED. Book picker
   (Bukhari/Muslim currently the only 2 in the db), topic browsing,
   language toggle (english/urdu/arabic — all three already stored
   per-row). This is now the most obviously unfinished major item.
4. **App Center redesign** — MOSTLY DONE (see "App Center redesign +
   splash screen" above). GNOME-Software-style layout implemented:
   sidebar (Explore/Featured/Productivity/Development/Manage/About — no
   Games category, deliberately), search bar, featured banner, app card
   grid, Manage page with Updates/Installed sections, backend registry
   support for install tracking and update diffing. Manifest fields
   (`category`/`publisher`/`icon_url`) are supported by the shell but the
   live `apps.json` hasn't been updated with them yet (separate GitHub
   repo, not this filesystem) — sidebar will show "Uncategorized"/
   "Community" placeholders until that repo's manifest is edited.
   Remaining: **visual fidelity check against the user's reference
   screenshots has never actually happened** — only "renders without QML
   errors" has been confirmed, not real layout/spacing/style fidelity.
   Ask the user to re-share the screenshots before calling this done.
5. **Touch support** — NOT AUDITED YET.
6. **Split the 21.5GB quran_audio_embedded.db** — DONE. Now
   `quran_text.db` (verses, ~0.8MB) + `quran_audio.db` (audio_files +
   word_timings, ~21.5GB), joined at runtime via `ATTACH DATABASE`. See
   "This session's work" above for details and the migration script.
7. **Boot splash screen** — DONE (not user-requested originally, added
   alongside the App Center redesign). `SplashScreen.qml`, see above.
   Visually unreviewed by the user.
8. **OS update/download mechanism** — BUILT this session (`UpdateBackend`
   + `UpdatesView.qml`, checks the manifest, downloads + sha256-verifies,
   does NOT auto-apply/flash — see "OS update checking" above for full
   detail). Untested against a real "update available" response since
   `OpenNoorIlm/RoohaniyeNooreIlm-Linux-Repo-Official` still has no
   `manifest.json` published (just README + LICENSE) — only the
   "nothing published yet" and generic-error paths have been exercised
   against the live repo so far.

## Things to watch out for

- User dislikes hand-holding/over-explaining and wants direct fixes over
  lots of questions — but DOES want specifics when reporting a bug is too
  vague to act on (e.g. "buggy" alone isn't enough, ask what specifically:
  slow/frozen/wrong-data/crash).
- User explicitly wants Claude to build+run the binary itself after every
  change (headless verification), not just hand back code and hope. See
  the "testing screens Claude can't click into" note above for how to do
  this for screens behind navigation that requires an actual tap.
- No dev languages (Python, gcc, interpreters) should ship on the actual
  target OS image — this only applies to the deployed device, not the dev
  laptop being used to build it right now.
- The App Center must never install closed-source apps — this is enforced
  by manifest curation policy, not by code, and should stay that way per
  the user's explicit reasoning (repo has no LICENSE file on purpose, see
  above).
- Two sessions in a row previously ended without updating this file
  despite real feature work landing — that streak is broken now, but stay
  disciplined about it: update this file before ending the session, not
  after.
