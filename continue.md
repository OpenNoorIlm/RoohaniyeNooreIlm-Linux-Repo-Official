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
- `qml/SettingsView.qml` — Brightness slider + Volume slider/mute switch
  (added this session, see "Brightness/volume settings + hardware
  keybindings" below) + WiFi toggle + network list + password dialog +
  restart/shutdown buttons with confirm dialogs + Account & Security
  section (added the auth session — see "User accounts / login system"
  below).
- `qml/LockScreen.qml` — **NEW.** Full-screen login/unlock overlay, wired
  into `Main.qml` above everything else via a `Loader` active only when
  `authBackend.locked`. See "User accounts / login system" below.
- `brightnessbackend.h/.cpp` — **NEW this session.** Wraps the sysfs
  backlight interface (`/sys/class/backlight/<device>/brightness` +
  `max_brightness`, auto-detected — `amdgpu_bl1` on this dev machine).
  `brightness` property (0–100, normalized), `setBrightness()`,
  `increase()`/`decrease()` (10% steps, for hardware keys), `available`
  (false if no backlight device found — Settings hides the whole
  section in that case). Writes attempt the sysfs path directly first
  (silently fails on permission-denied), falling back to
  `pkexec tee <path>` only when needed — debounced to fire on slider
  *release* (`onPressedChanged`), not every drag tick, to avoid spamming
  polkit prompts. **Known follow-up, not done**: a udev rule granting
  the `video` group write access to the backlight device (so no
  `pkexec` fallback is ever needed at all) was designed but only as
  something the *installer* script could set up on the target system —
  not actually added to `installerbackend.cpp`'s provisioning script
  yet.
- `volumebackend.h/.cpp` — **NEW this session.** Wraps `wpctl` (PipeWire,
  confirmed present on this system) for the default sink: `volume`
  property (0–100), `muted`, `setVolume()`, `setMuted()`, `toggleMute()`,
  `increase()`/`decrease()` (10% steps). `available` false if `wpctl`
  isn't found.
- `reminderbackend.h/.cpp` — **NEW this session.** Recurring reminders
  (`{id, title, hour, minute, days, enabled}`) persisted as one JSON
  array in `shell_settings.ini`. A `QTimer` polls every 30s and emits
  `reminderDue(id, title)` once per matching minute per day (guarded by
  a `lastFiredDate` field). `addReminder()`/`updateReminder()`/
  `removeReminder()`/`setEnabled()`/`suggestedTitles()`. See "Reminders
  app" below for the full writeup.
- `authbackend.h/.cpp` — **NEW this session.** Username/password
  accounts, PBKDF2-HMAC-SHA256 hashing via `QPasswordDigestor`, own
  dedicated `accounts.dat` file (not `shell_settings.ini`), inactivity
  auto-lock via a global event filter. `hasAccounts`/`loggedInUser`/
  `loggedInIsAdmin`/`locked`/`autoLockMinutes` properties;
  `createAccount()`/`login()`/`unlock()`/`logout()`/`lockNow()`/
  `listUsers()`/`changePassword()`/`deleteAccount()`/
  `setAutoLockMinutes()`. **Follow-up session added**: one-time
  recovery-code scheme (`regenerateRecoveryCode()`, `recoverPassword()`
  — see "Password recovery + installer-wizard account step" below) and
  a `static exportAccountForInstall()` used only by
  `InstallerBackend`/`InstallerWizard.qml`'s optional account-creation
  step. See "User accounts / login system" below for the full writeup.

## Hadith reader overhaul, mirroring the Quran app (this session)


**The feature requested**: bring Hadith up to the same level as the Quran
app — was previously just "one random hadith + another button" (flagged
in Known Gaps for several sessions).

**What was already built, from an earlier interrupted session**, verified
and finished today:
- `quranbackend.h/.cpp` — full hadith backend, mirroring the verse-side
  API shape: `hadithBookList()`, `hadithTopics(book)`,
  `hadithsByTopic(book, topic)`, `hadithsInBook(book, afterId, limit)`
  (keyset-paginated continuous browse), `hadithById(id)`,
  `searchHadiths(query, limit)` (FTS5, prefix-matched per token),
  `hadithsForSelection(items)` (expands a multi-select of
  topics/individual hadiths into an ordered, de-duped list — the hadith
  equivalent of `versesForSelection()`, minus any audio/reciter step
  since this db has no hadith recitation audio), plus
  `saveHadithProgress(id)`/`lastHadithProgress()` (separate progress
  tracking from the Quran side, keyed by hadith id).
- `qml/HadithMenu.qml` — landing screen (continue-reading card, book
  tiles, Search, Random), mirrors `QuranMenu.qml`'s shape.
- `qml/HadithTopicPicker.qml` — topic/chapter picker overlay per book,
  with a "Select" multi-select mode (mirrors `JuzPicker.qml`), plus a
  "read whole book" shortcut.
- `qml/HadithView.qml` — the reader itself: three modes (`book`
  continuous/paginated, `topic` bounded list, `selection` caller-resolved
  list), English/Urdu/Arabic visibility toggles + font size (persisted
  via `preference()`/`setPreference()`), and its own in-reader multi-select
  (checkbox per hadith → confirm → filters the same view down to just
  those). No reciter-picker step, unlike the Quran side — confirming a
  selection goes straight to a filtered reading list.

**Two real bugs found and fixed today** (the interrupted session's work
was functionally complete but never actually wired up or fully tested):

1. **Not wired into the app at all.** `HadithMenu.qml` and
   `HadithTopicPicker.qml` existed on disk but were missing from
   `qml.qrc` — the Qt resource system never compiled them in, so they
   didn't exist at runtime. `Main.qml` was also missing the
   `navHadithBook`/`navHadithTopic`/`navHadithId`/`navHadithSelection`
   nav properties these screens read/write, and its `currentView` router
   still had `"hadith"` pointing straight at the old direct-to-reader
   `HadithView.qml` (the stub-era route) with no `"hadithreader"` route
   at all — so `HadithMenu.qml`'s own `openReader()` (which sets
   `currentView = "hadithreader"`) had nowhere to go. Fixed: added both
   files to `qml.qrc`, added the four nav properties to `Main.qml`, and
   split the router into `"hadith"` → `HadithMenu.qml` (landing screen)
   and `"hadithreader"` → `HadithView.qml` (the actual reader).
2. **`searchHadiths()` was broken** — always failed with a Qt-reported
   "Parameter count mismatch" (the real cause, confirmed directly against
   sqlite3, was `ambiguous column name: english`: the query joins
   `hadiths_fts` (alias `f`, an external-content FTS5 table that mirrors
   `english`/`urdu`/`arabic`) with `hadiths` (alias `h`), but the SELECT
   list only qualified one column (`h.id`) and left the rest bare, so
   `english`/`urdu`/`arabic` were ambiguous between the two tables; Qt's
   QSQLITE driver surfaces that prepare-time failure as a misleading
   parameter-count error instead of the real one). Fixed by fully
   qualifying every selected column with `h.`.

**Headless-verified after both fixes**: real-defaults boot (splash →
home, zero QML warnings), `HadithMenu` landing screen, the topic-picker
overlay, the search overlay (now actually returning results), and
`HadithView` in all three modes (book/topic/selection) — all clean, zero
QML warnings. All temporary `currentView`/`navHadith*` hardcodes used for
this were reverted and diffed clean against a backup before finishing.

**Not done / not asked for yet**: no audio/recitation for hadiths (never
requested, and this hadith db has no audio table); visual fidelity
against any reference design was never requested for this screen either
(unlike the App Center/splash, where the user does want a screenshot
comparison eventually).

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

## Installer app: "Try/Install RoohaniyeNooreIlm" (this session)

**The gap flagged**: there was a live/try boot flow but literally no way
for the user to actually install RoohaniyeNooreIlm to their own disk —
exactly the missing piece a real distro needs. The user asked for this
to be "very detailed", "as much customisable... as possible", and
"non-mistaker" — i.e. no shortcuts on safety.

**SCOPE NOTE — read `installerbackend.h`'s class comment before touching
this**: this project has no separate live-build/debootstrap/squashfs
pipeline. "The OS" is just this Qt shell running on top of whatever base
Linux the live USB happens to be. So "installing" here pragmatically
means: partition + format the target disk, `rsync` the CURRENTLY
RUNNING filesystem onto it (the live session IS the source image — the
same trick many lightweight live-USB installers use), copy over
`/opt/roohaniye/data` (with any user-picked replacement databases),
install GRUB, and drop in a systemd unit + autologin so the target disk
boots straight into `roohaniye-shell` fullscreen.

**Built:**
- `installerbackend.h/.cpp` — new backend, registered as
  `installerBackend` in `main.cpp`/`CMakeLists.txt`.
  - `listDisks()` — real `lsblk` enumeration (path/name/sizeLabel/
    sizeBytes/model/transport/isRemovable). **Always excludes whatever
    disk currently backs `/`** (resolved via `findmnt`, parses both
    `sdaN` and `nvmeXnYpZ`/`mmcblkXpY` naming schemes) — the running
    disk is never even selectable, live-boot or dev-box alike.
  - `listDirectory()` — browse removable storage for replacement
    `.db`/`.json` files, same shape as `DbConnectorBackend::listDirectory`
    so the QML delegate logic is interchangeable.
  - `startInstall()` — builds ONE reviewable shell script (not scattered
    pkexec calls) covering partition → format → clone → databases →
    bootloader → finishing, runs it via a single `pkexec sh <script>`,
    streams `installProgress(percent, stage, detail)` / `installLog(line)`
    / `installFinished(ok, error)` back to QML. Re-validates the disk
    path against a fresh `listDisks()` call and requires `confirmText`
    to be exactly `"ERASE"` server-side — never trusts the QML layer
    alone for something this destructive.
  - `isInstalled()` — one-time marker file
    (`/opt/roohaniye/data/.installed`) written by the script itself once
    it succeeds; drives the home-screen banner's visibility. Once true,
    the install prompt is gone for good (not per-boot, not
    dismissible-and-back) unless that file is manually removed.
  - `cancelInstall()` — best-effort `terminate()`/`kill()` of the running
    helper script.
- `qml/InstallerWizard.qml` — full 6-step wizard (registered as
  `currentView === "installer"`): welcome/what-to-expect → disk picker
  (real size/model/transport per disk, selection highlight) → optional
  database customization (browse a USB for replacement
  `quran_text.db`/`quran_audio.db`/`hadiths.db`, with a file-browser
  overlay reusing `installerBackend.listDirectory()`) → review + type
  `ERASE` to unlock the install button → animated progress screen
  (spinning ring, percent, per-stage copy, live scrolling log, progress
  bar) → success/error result screen. Every "next" action on a
  destructive path stays visually disabled until its precondition is
  actually met, not just suggested.
- `qml/HomeScreen.qml` — new banner, `visible:
  !installerBackend.isInstalled()`, "Install" button routes to
  `currentView = "installer"`.
- `qml/Main.qml`, `qml.qrc`, `CMakeLists.txt` — wired.

**Verified headlessly** (real hardware only has one disk — this dev
box's own `nvme0n1`, correctly excluded by `listDisks()`, so the disk
list is legitimately empty here; that itself confirms the exclusion
logic works against real `lsblk`/`findmnt` output):
- Clean build, zero QML warnings on the real splash → home boot flow.
- Home screen banner renders clean.
- Wizard step 0 (welcome) renders clean on its own.
- All remaining steps exercised via a temporary `--test-installer` CLI
  flag + `Timer` that fed the wizard fake-but-realistic state (a fake
  USB disk entry, a real `listDirectory("/tmp")` call for the
  file-browser overlay, a picked replacement database, `"ERASE"` typed,
  a fake in-progress log stream, and both success and error result
  screens) — zero QML warnings across all of them. Test hook fully
  reverted afterward (diffed clean, no `TEMP-DEBUG` left in
  `InstallerWizard.qml`).

**NOT yet done / genuinely unverified — read before trusting this on
real hardware:**
- `startInstall()`'s actual partition/format/`rsync`/GRUB script has
  been written and reviewed but **never executed for real** — doing so
  in this session would have meant handing `pkexec` a script that wipes
  a disk, and this dev machine only has the one (root) disk to test
  against, which `listDisks()` correctly refuses to offer. **Test this
  on a spare disk or a VM with a second virtual disk attached before
  trusting it on anything with data on it.**
- No visual/UX review by the user yet (Claude can't click/tap) — same
  caveat as App Center/splash/Hadith reader.
- `grub-install`/`update-grub` assume a Debian/Ubuntu-family base image
  (uses `update-grub`, not `grub-mkconfig` directly) — if the live base
  ends up being a different distro family, that step needs adjusting.
- No BIOS/legacy-boot fallback — script is EFI-only
  (`grub-install --target=x86_64-efi`), with a same-line fallback to a
  plain `grub-install <disk>` call if the EFI variant fails, but that
  fallback itself hasn't been tested either.

## Brightness/volume settings + hardware keybindings (this session)

**The feature requested**: screen brightness + volume controls, plus
keybindings — laptop Fn-row media keys as well as "normal phone like
btns" (a physical volume rocker).

Confirmed this was already fully built and wired on disk from an
in-progress prior session (backends, Settings UI rows, `Main.qml`
`Shortcut`s, and an on-screen OSD were all present) — nothing left
half-done this time. Verified rather than re-built:

- `BrightnessBackend`/`VolumeBackend` registered in `main.cpp`/
  `CMakeLists.txt` as `brightnessBackend`/`volumeBackend`.
- `qml/SettingsView.qml` — Brightness and Volume rows (slider +
  percentage label; Volume also has a mute `Switch`), each hidden
  entirely via `visible: ...Backend.available` if the underlying
  hardware/tool isn't present.
- `qml/Main.qml` — global (focus-independent) `Shortcut`s for
  `Qt.Key_VolumeUp/Down/Mute` and `Qt.Key_MonBrightnessUp/Down`. Laptop
  Fn-row keys and a phone-style hardware volume rocker both surface as
  the same Linux/Qt key constants, so one set of bindings covers both,
  per the comment in the source. A small phone-style OSD (icon + level
  bar, fades after 1.2s) pops up on any brightness/volume change,
  whether triggered by a hardware key or a Settings slider drag —
  driven by `Connections` on both backends' change signals, so it's a
  single code path regardless of source.

**Verified this session**: clean `cmake .. && make`, headless run of the
real boot flow (splash → home, zero QML warnings), and a temporary
`currentView` hardcode to `"settings"` (reverted and diffed clean
afterward) to confirm the new Brightness/Volume rows in
`SettingsView.qml` render with zero QML warnings.

**Not done / follow-ups**:
- No udev rule yet to let the `video` group write brightness without a
  `pkexec` prompt — currently falls back to `pkexec tee` on permission
  failure (debounced to slider-release, not per-drag-tick, so at least
  it's not spammy). Worth adding to the installer's provisioning script
  as a permanent fix — see the `brightnessbackend.h/.cpp` bullet in
  Architecture above.
- No real hands-on test of the *hardware* keys themselves (Claude can't
  press physical keys) — only confirmed the `Shortcut` bindings and OSD
  render/wire correctly; the user should confirm the actual Fn-row keys
  and/or volume rocker fire them on real hardware.
- Volume backend only controls the default PipeWire sink — no per-app
  volume mixing, no output-device switching UI.

## UI sound effects from user-provided assets (this session)

**What the user provided**: an `assets/` folder (audio/images) dropped in
the project root — `assets/audio/` had 5 files (a longer ringtone/nasheed
MP3 plus 4 short click/selection WAVs), `assets/images/` was empty
(user flagged they'll need Claude-written prompts to hand to an image
model when images are actually needed — nothing generated yet).

**Built**: a small global sound helper, not a new backend for the click
sounds — `QSoundEffect` from the QtMultimedia QML module (confirmed
already installed: `qml-module-qtmultimedia`) covers short WAVs entirely
in QML.
- Copied the 5 files into `shell-src/assets/audio/` and added them to
  `qml.qrc` (renamed `Ilm Noor Hai ringtone.mp3` →
  `ilm_noor_hai_ringtone.mp3` — spaces in qrc-embedded resource paths
  are asking for URL-encoding bugs later, not worth the risk).
- `Main.qml` gained `import QtMultimedia 5.15` and an `Item { id: sounds
  }` holding the effects, exposed as `property alias sounds: sounds` on
  the root Window. Any Loader-loaded screen calls `root.sounds.click()`
  etc — same context-chain resolution every other screen already relies
  on for `root.currentView`, no new plumbing needed. Final function set,
  after the user clarified two of the filenames:
  - `click()` → `SciFi-MouseClick.wav` — general button/tile taps.
  - `select()` → `SelectBtnClick.wav` — toggling a "Select" mode
    button itself (the three multi-select pickers' header toggle).
  - `itemSelecting()` → `SleecingSound.wav` — **the filename is a typo
    for "SelectingSound"**, per the user; this is the per-item
    check/uncheck tick *inside* an already-active selection mode, a
    distinct sound from `select()`. Wired into the per-item delegates
    in `JuzPicker.qml`, `SurahPicker.qml`, `HadithTopicPicker.qml`, and
    `QuranView.qml`'s ayah-selection checkboxes.
  - `ringtone()` → `ilm_noor_hai_ringtone.mp3` — per the user, this is
    for the new Reminders app's notification (see "Reminders app"
    section below), not a splash/boot sound.
- Sound coverage is still partial by design — home screen taps, the
  three Select-mode toggles, and the new per-item selecting sound are
  wired; other tap targets (dialogs, back arrows on non-listed screens,
  etc.) still have no sound. Straightforward to extend later with the
  same `root.sounds.click()` pattern.

**Real bugs found and fixed** (two separate ones, across the session):
1. `SciFi-MouseClick.wav` and `mouseClick.wav` were 24-bit PCM in
   `WAVE_FORMAT_EXTENSIBLE` containers (confirmed via `xxd` header
   inspection: format tag `0xFFFE` + a `fact` chunk) — the other WAVs
   were plain 16-bit PCM. `QSoundEffect`'s pulseaudio backend threw
   `Error decoding source` on the two 24-bit files, silently failing to
   play (no crash, no QML warning — only visible in stderr at play-
   time). Fixed with a one-off Python script (`wave` module) that
   downsamples 24-bit→16-bit PCM (keeps the top 2 bytes of each 3-byte
   sample), re-writing both as standard 16-bit PCM WAVs. Not run through
   proper dithering — fine for short UI clicks, wouldn't be acceptable
   for anything longer/more critical.
2. `ilm_noor_hai_ringtone.mp3` also failed via `QSoundEffect` (`Error
   decoding source`) — **`QSoundEffect` is not a compressed-format
   player**, it only reliably handles short uncompressed PCM on this
   pulseaudio backend; MP3 needs an actual decode pipeline. Fixed by
   using QML `Audio { }` (also from `QtMultimedia`) for the ringtone
   instead — this goes through the same GStreamer pipeline
   `AudioBackend` already uses for Quran recitation MP3 playback, and
   mp3 decode support (`mpg123`/`avdec_mp3`) is confirmed installed on
   this system. **Lesson for future sessions**: `SoundEffect` for short
   WAV click sounds, `Audio`/`MediaPlayer` for anything compressed or
   longer — don't reach for `SoundEffect` on an MP3 again.

**Verified**: clean build; real-defaults headless boot (zero QML
warnings, no decode errors) after both fixes; temporary `Timer`s in
`Main.qml` exercised `click()`/`select()`/`itemSelecting()`/`ringtone()`
individually, all confirmed playing without error. All test hardcodes
reverted and diffed clean; `grep -rn TEMP-DEBUG` confirmed nothing left
behind.

**Still not done**:
- Images folder is still empty — nothing to do until the user says what
  image(s) they want; Claude should write the actual image-model prompt
  text when that request comes in, not guess ahead of time.

## Reminders app (this session)

**The feature requested**: a home-screen app for recurring reminders
("reading Quran, hadiths etc etc"), using `ilm_noor_hai_ringtone.mp3` as
the notification sound (see above).

**Built**:
- `reminderbackend.h/.cpp` — new backend, registered as `reminderBackend`
  in `main.cpp`/`CMakeLists.txt`. Deliberately simple: no snooze, no
  per-instance history beyond "did this fire today" — matches the rest
  of the project's philosophy of wrapping simple mechanisms rather than
  building a full scheduling engine.
  - Reminders are `{id, title, hour, minute, days, enabled}`, persisted
    as one JSON array (via `QJsonDocument`) in a single QSettings key
    (`reminders/list` in the shared `shell_settings.ini`) rather than
    one key per field — easier to read/write as one blob given the list
    is small.
  - `days` is an array of `0`(Sun)`-6`(Sat); empty array = fires every
    day.
  - A `QTimer` polls every 30s (plus once immediately at construction,
    so a reminder due right at startup isn't missed for 30s) and emits
    `reminderDue(id, title)` the minute a reminder's time is reached —
    guarded by a `lastFiredDate` field per reminder so it only fires
    once per day, not every 30s while the clock matches. **A reminder
    due while the device was off/asleep is NOT caught up retroactively**
    — this only fires while the shell process is actually running.
  - `addReminder()`/`updateReminder()`/`removeReminder()`/`setEnabled()`,
    plus `suggestedTitles()` (a few canned quick-add strings: "Read
    Quran", "Read Hadith", "Morning Adhkar", "Evening Adhkar").
- `qml/RemindersView.qml` — list of reminders (time + repeat-days
  summary + enable `Switch` + edit/delete), a quick-add row of
  `suggestedTitles()` chips, a `+` button, and an add/edit `Dialog`
  (title field, hour/minute `SpinBox`es, a 7-day toggle grid). Since
  `reminderBackend.reminders()` is a plain invokable (not a live model),
  the view wraps it in a small local `reminderModel` `QtObject` with a
  `refresh()` function, re-pulled after every mutation — a direct
  `ListView.model` binding to the invokable call wouldn't be reactive.
- `qml/Main.qml` — new `"reminders"` route; a global `Connections` on
  `reminderBackend.reminderDue` (fires regardless of which screen is
  open, since the backend's timer is independent of QML navigation)
  plays `root.sounds.ringtone()` and shows a dismissible banner at the
  top of the screen. Unlike the small brightness/volume OSD, this banner
  does **not** auto-dismiss — a reminder that silently vanishes after a
  couple seconds while the user's away from the screen would defeat the
  point.
- `qml/HomeScreen.qml` — new "Reminders" tile in the app grid.

**Verified**: clean build; real-defaults headless boot (zero QML
warnings). Headless-tested via the established `currentView` hardcode
technique: the empty-state Reminders screen, a populated list + the
edit dialog pre-filled from an existing reminder (via a temporary
`property alias reminderModel: reminderModel` added to
`RemindersView.qml` so the test hook could reach it — this alias is a
real, permanent addition, not test-only scaffolding), and the reminder-
due banner + ringtone playback path (forced directly rather than
waiting on the 30s poll timer, which wouldn't fit in a short headless
run) — all clean, zero QML warnings, ringtone plays without error.
All temporary `Main.qml` hardcodes reverted and diffed clean. **Also
cleaned up test data that leaked into the real
`/opt/roohaniye/data/shell_settings.ini`** during this testing (a
`[reminders]` section with 5 seeded test entries, added across three
separate test runs) — removed with a small Python patch that preserved
the rest of the file's exact formatting, confirmed via diff.

**Follow-up verification (later session)**: the "ringtone plays without
error" claim above only ever checked stderr for a decode error under
`QT_QPA_PLATFORM=offscreen` — that proves the `Audio {}` element loaded
and decoded the MP3, not that it actually produced sound. Re-verified
properly this time: re-ran the same hardcoded ringtone-trigger test
while polling `wpctl status` in parallel, and confirmed a real,
`[active]` PipeWire audio stream named `roohaniye-shell` appears for the
duration of playback — genuine audible output through the actual sound
card, not just an absence-of-error check. Test hook reverted afterward;
source and the rebuilt binary both confirmed free of any `TEMP-DEBUG`
leftovers; final clean rebuild + real-defaults headless run shows zero
QML warnings.

**Not done / follow-ups**:
- No real hands-on test by the user yet (Claude can't tap the add/edit
  UI or wait through a real 30-second poll cycle in a persistent
  session) — this is "verified data-flow correct + zero QML warnings +
  playback confirmed", not "the user has added a real reminder and had
  it actually go off while using the device."
- No notification if the device is asleep/off at the scheduled time —
  documented limitation above, not a bug, just worth the user knowing.
- No per-reminder custom sound — every reminder uses the same
  `ilm_noor_hai_ringtone.mp3`.

## User accounts / login system (this session)

**What was built:**
- **`AuthBackend`** (`authbackend.h`/`.cpp`) — username/password accounts
  stored in a dedicated file, `/opt/roohaniye/data/accounts.dat`,
  **separate from** `shell_settings.ini` (all other backends share that
  one file; this one is secrets-sensitive so it's isolated), permissions
  forced to `0600` after every write.
  - Passwords hashed with `QPasswordDigestor::deriveKeyPbkdf2`
    (PBKDF2-HMAC-SHA256, 210,000 iterations — OWASP's 2023 minimum — 16
    random salt bytes per user via `QRandomGenerator`). Plaintext
    password is never written to disk or logged; it only exists in
    memory for the duration of the single `login()`/`unlock()`/
    `changePassword()` call that needs it.
  - `createAccount()` — first account ever created is always admin,
    regardless of the `isAdmin` argument passed, so there's never a
    zero-admin install. Creating *additional* accounts requires an
    active admin session, checked server-side (not just gated in QML).
  - `login()` / `unlock()` — `unlock()` re-checks against whichever user
    is already `loggedInUser`, for the fast re-entry path after an
    inactivity lock.
  - `deleteAccount()` — re-verifies the *acting* admin's own password
    (not just "is currently logged in as admin") before deleting
    anyone, and refuses to delete the last remaining admin account.
  - Auto-lock: a `QTimer` reset on any activity via a global
    `qApp->installEventFilter(this)` (mouse/touch/key events), default 5
    minutes, configurable (including "never" = 0).
  - **Honest limits, documented in the header itself**: this gates the
    shell UI, not the underlying Linux disk — physical access + a live
    USB can still read the disk (full-disk encryption at install time is
    a separate, much bigger feature, not in scope here). A fresh
    Try-session or an install with no account ever created means
    `hasAccounts()` is false, so the lock screen never appears — locking
    is opt-in, never forced onto a live/demo session.

- **`LockScreen.qml`** — a full-screen overlay wired directly into
  `Main.qml` (not routed through the normal `viewLoader`/`currentView`
  mechanism), sitting at `z: 5000` above absolutely everything, including
  the reminder banner and volume/brightness OSD, loaded via a `Loader`
  that's only `active` when `authBackend.locked` is true (so a
  no-accounts install never pays for instantiating it). Two modes off
  the same file:
  - **Login mode** (`authBackend.loggedInUser === ""`) — username +
    password fields.
  - **Unlock mode** (a user IS logged in, session just auto-locked or
    "Lock Now" was tapped) — avatar circle with the user's initial,
    just a password field for faster re-entry, plus a small "Not you? Log
    out" link back to full login mode.
  - Deliberately full password re-entry for both modes rather than a
    separate PIN system — `AuthBackend` only stores one PBKDF2 hash per
    user, and a second, weaker PIN-based unlock path would undercut the
    "very very very very securely" ask. Touch-friendly sizing (48px
    fields/buttons) is the compromise instead of a shorter PIN.

- **Settings → "Account & Security" section** — new card in
  `SettingsView.qml`:
  - No accounts yet: a "Set Up Account" prompt + dialog (creates the
    first account, then logs straight in — no immediate re-entry at a
    lock screen the person just set up).
  - Accounts exist: shows who's signed in, Lock Now / Log Out buttons,
    an auto-lock timing picker (1m/5m/15m/Never), a "Change Password"
    dialog for your own account.
  - Admin-only: a live user list (`authBackend.listUsers()`) with
    per-user "Remove" (opens a dialog that re-asks for *your own*
    password before deleting — defense in depth beyond just checking
    `loggedInIsAdmin`), and an "Add User" dialog with an admin toggle.
  - These three dialogs (`accountDialog`, `changePassDialog`,
    `deleteUserDialog`) use a plain button + manual validation instead of
    `DialogButtonBox`'s `AcceptRole` (which auto-closes regardless of
    outcome, fine for the WiFi/power dialogs elsewhere in this file but
    wrong here) — so a wrong password or duplicate username shows an
    inline error and keeps the dialog open instead of silently closing
    on failure.

**Real bugs caught and fixed while building this** (all headless-verified after each fix):
- `hasAccounts() const` and `loadAccounts() const` called
  `QSettings::beginReadArray()`/`endArray()`, which are non-`const` Qt
  methods, inside `const` member functions — wouldn't compile. Fixed by
  marking `m_settings` `mutable` in the header (these reads are
  logically const even if Qt's API isn't marked that way).
- `QStringLiteral(ACCOUNTS_PATH)` doesn't compile — `QStringLiteral`
  requires an actual string literal at that call site, not a `const
  char*` macro/variable. Switched to `QString::fromLatin1(ACCOUNTS_PATH)`.
- `hasAccounts()`'s first draft returned `beginReadArray(...) > 0`
  without a matching `endArray()` — left the settings object in an
  open-array state. Fixed to read the count then close the array before
  returning.
- Test-hook-only bug (not a real code bug, flagging so it's not
  reintroduced): a first test run created a second account before
  logging in as the first admin, which `createAccount()` correctly
  rejected server-side (no active admin session yet) — that's the
  intended gate working, not a bug. Fixed the test's call order (login
  before creating additional accounts) to actually exercise the
  multi-user path.

**Verification performed** (all headless, `QT_QPA_PLATFORM=offscreen`,
zero QML warnings in every case): real-defaults boot with zero accounts
(lock overlay correctly inactive); `createAccount()` via the real
Settings dialog code path (confirmed real PBKDF2 hash + salt written to
`accounts.dat`); a second boot with that account present landing
straight in `LockScreen`'s login mode automatically (proves
`hasAccounts()` at construction time works, not just the QML-visible
state); wrong-password login rejected, correct-password login succeeds;
`lockNow()` actually locks a logged-in session; wrong-password unlock
rejected, correct-password unlock succeeds (both `LockScreen` modes
rendered clean); the full Account & Security section in both "no
accounts" and "logged-in admin with a second user" states; all three
dialogs opening; and the actual delete-account logic end-to-end (2 users
→ wrong admin password rejected → correct admin password succeeds → 1
user left → deleting the last remaining admin correctly blocked). All
test accounts and hardcodes were reverted/removed and diffed clean
against a pre-test backup before this session's final rebuild.

**Not done, flagged honestly (at the time):**
- No installer-wizard step for account creation — first-run account
  setup happens via Settings instead, which fits the existing
  "locking is opt-in, never forced on a live/demo session" design intent
  already written into `authbackend.h`, but is worth confirming that's
  what's wanted rather than a wizard step.
- Real hands-on tap-through by the user (Claude can't click/tap) —
  everything above was verified by calling the same backend methods the
  UI calls, and by rendering every screen state headlessly, but nobody
  has physically typed into these fields on a touchscreen yet.
- No "forgot password" recovery path — by design, since there's no
  email/SMS/recovery-question infrastructure in this project and adding
  a weak recovery mechanism would undermine the hashing work. If a user
  forgets their password, the realistic recovery today is an admin
  resetting it via `changePassword()`, or (if there's no other admin)
  wiping `/opt/roohaniye/data/accounts.dat` to return to "no accounts."
  Worth deciding if that's acceptable or if a real recovery flow should
  be designed.

**Both of the above two were done in a follow-up session — see "Password
recovery + installer-wizard account step (follow-up session)" below.**

## Password recovery + installer-wizard account step (follow-up session)

Closed both items flagged as "not done" above.

**1. Password recovery.** Added a one-time recovery-code scheme to
`AuthBackend` — no email/SMS infrastructure exists on this device, so
recovery is a 12-character code (`XXXX-XXXX-XXXX`, unambiguous alphabet,
~62 bits of entropy) generated and shown to the user **exactly once**,
right when the account is created (or whenever it's regenerated). Only a
salted PBKDF2 hash of the code is ever stored — same treatment as the
password itself, in a new `recoverySalt`/`recoveryHash` pair per account.
- `createAccount()` now also returns `recoveryCode` in its result map
  (in addition to `ok`/`error`), shown once by the caller.
- `regenerateRecoveryCode(username, password)` — requires the current
  password, invalidates the old code, returns a fresh one.
- `recoverPassword(username, recoveryCode, newPassword)` — verifies the
  code, sets the new password, and (since the code is single-use) issues
  and returns a brand new recovery code in the same call so the user has
  something to write down again. Using a stale/already-used code is
  correctly rejected.
- `LockScreen.qml` — added a "Forgot password?" link (both login and
  unlock modes) that walks through a 2-step recovery flow inline (enter
  code → set new password → shows the fresh recovery code once), with a
  "Cancel" escape back to normal login/unlock at any point.
- Verified against the real backend, not just UI rendering: wrong code
  rejected, right code accepts and lets a subsequent login succeed with
  the new password, re-using the same (now-stale) code is correctly
  rejected, and `regenerateRecoveryCode()` works. All three `LockScreen`
  recovery-flow visual states (code entry, new-password entry, done/
  show-new-code) rendered headlessly with zero QML warnings.

**2. Installer-wizard account step.** `InstallerWizard.qml` gained a new
step 3, "Set up an account (optional)", between the database-
customization step and the review/confirm step (review, progress, and
result are now steps 4/5/6 — everything renumbered and re-verified, not
just the new step in isolation). Off by default — an install still boots
unlocked unless explicitly turned on, keeping the existing "never forced
on a live/demo session" principle for the *installed* system too, not
just the live one.
- New `AuthBackend::exportAccountForInstall(username, password, isAdmin)`
  — a **static** method that deliberately does not touch this live
  session's own `accounts.dat`/`QSettings` at all (confirmed: `hasAccounts`
  stayed `false` throughout a full exercise of this path). Returns
  salt/hash/recovery-salt/recovery-hash/recovery-code as plain values.
- `InstallerBackend::startInstall()` — if an `account` option is given,
  calls the export above *before* generating the install script, writes
  the result into a real accounts.dat-format staging file (via `QSettings`
  pointed at a `QTemporaryFile`, same array format `AuthBackend` itself
  uses), and emits a new `installAccountRecoveryCode(username, code)`
  signal immediately — the wizard holds onto it and only reveals it on
  the **result** screen, and only if the install actually succeeded.
  `buildInstallScript()` copies that staging file onto the target disk
  as `/opt/roohaniye/data/accounts.dat` and `chmod 600`s it, right after
  the extra-database copy step. The staging file is deleted afterward
  (success or failure) alongside the existing script-file cleanup.
- Real bug caught while building this: if disk validation failed *after*
  the account was already staged (or if the script temp-file write
  failed), the staged accounts temp file was never deleted — a small but
  real leak on every failed/refused install attempt with an account
  filled in. Fixed by cleaning up `accountStagingPath` on both early-
  return paths, not just the success path.
- Verified: called `exportAccountForInstall()` directly (confirmed a
  standalone, self-contained credential bundle with no live-session side
  effects) and separately called `startInstall()` with a deliberately
  invalid disk path + a real `account` option — confirmed
  `installAccountRecoveryCode` fires, the disk-validation refusal still
  correctly blocks anything destructive, `hasAccounts()` on the live
  session stayed `false` the whole time, and no temp files were left
  behind in `/tmp` afterward (the leak above, fixed, then reconfirmed
  clean). Also stepped through and rendered every wizard step 0–6
  headlessly (including the new step 3 with the toggle both off and on,
  and the result screen's recovery-code display) — zero QML warnings
  across all of them. All test hooks reverted and diffed clean; final
  rebuild + real-defaults headless run confirmed clean with no accounts
  and no leftover test data.

**Still not done / honest limits carried forward:**
- The install script's account-copy step (`cp` + `chmod 600` onto the
  target disk) has been reviewed but, like the rest of `startInstall()`,
  never executed against a real target disk (same "only one disk on this
  dev box, correctly excluded" situation as the base installer work) —
  test on a spare disk/VM.
- Recovery codes have no rate-limiting on guess attempts (same as
  passwords currently) — acceptable for a local single-device shell with
  no network attack surface on this path, but worth knowing.
- No real hands-on tap-through by the user of either new flow (Claude
  can't click/tap) — same caveat as everything else auth-related.

## On-screen keyboard + automatic screen-resize (this session)

**The feature requested**: a digital/virtual keyboard for touch devices
with a toggle button (while still fully supporting an external mouse/
keyboard), and automatic UI resizing to fit whatever screen size the
device actually has.

**On-screen keyboard**:
- Checked first whether the real Qt `QtVirtualKeyboard` module was
  available on this system before building anything custom — it's not
  installed (only cached Qt6 online-installer downloads exist, nothing
  usable by this Qt5 build), and installing a new system package doesn't
  fit this project's "works out of the box" philosophy. Built a small
  self-contained `qml/VirtualKeyboard.qml` instead: full QWERTY layout,
  shift/caps-lock, a 123/symbols page, space, repeating backspace (press-
  and-hold), and a Done key.
- Works with **any** text field in the app for free, with zero per-screen
  wiring: it writes directly into whatever item currently has
  `Window.activeFocusItem` (`TextField`/`TextArea` both expose
  `insert()`/`remove()`/`cursorPosition`, which is all it needs).
- `Main.qml` got a small always-present floating toggle button (bottom-
  right corner, keyboard glyph) that turns the feature on/off. Once on,
  it behaves like a phone keyboard: a `vkShouldShow` binding
  (`vkEnabled && the focused item is text-editable`) automatically slides
  it up whenever a real text field gets focus and back down otherwise —
  no need to manually summon it per field. Purely additive: since it
  never grabs or blocks input, an external mouse and physical keyboard
  keep working exactly as before regardless of whether this is toggled
  on.
- Toggle state is in-memory only (resets to off each launch) rather than
  persisted — `Qt.labs.settings` (the natural fit) also isn't installed
  on this system (confirmed by a real failed headless run:
  `module "Qt.labs.settings" is not installed"`), and adding a new
  QSettings-backed C++ property for one boolean felt like overkill versus
  just defaulting to off and letting the user tap it back on. Worth
  revisiting later if the user wants it remembered across reboots.

**Automatic screen-resize**:
- Every screen in this app was laid out against this dev machine's real
  1920x1080 resolution, with plenty of fixed-pixel icon/font/spacing
  values that don't reflow on their own — rewriting all ~20 QML files to
  use relative sizing would be a huge, risky change. Instead, `Main.qml`
  now renders the entire interactive UI (the view `Loader`, the OSD, the
  reminder banner, the keyboard + its toggle) inside a fixed
  1920x1080 `virtualCanvas` `Item`, then uniformly scales
  (`Math.min(width/1920, height/1080)`) and centers that whole canvas to
  fit whatever the real window size turns out to be. A 7" 1024x600 touch
  panel shrinks everything proportionally (still full design fidelity,
  just smaller); a 4K panel enlarges it. Qt Quick's item transforms
  handle touch/mouse hit-testing through the scale automatically, so
  nothing about input handling needed to change.
- The full-window custom background `Image` and the `LockScreen` overlay
  are deliberately kept **outside** `virtualCanvas`, unscaled — the
  background already adapts to any real window size on its own via
  `PreserveAspectCrop`, and a lock screen should never depend on the
  scaling math being correct.
- **Real bug caught while testing**: `uiScale` computed to exactly `0`
  for the first frame or two after launch, before the window manager
  assigns real geometry (`width`/`height` start at `0`) — which would
  have made the entire UI invisible for a brief flash on every real
  boot. Confirmed via a headless run that printed `uiScale` at
  `Component.onCompleted` (`0`) versus 300ms later (the correct
  `0.4166...` for an 800x600 test window). Fixed with a guard:
  `(width > 0 && height > 0) ? Math.min(...) : 1`, re-verified the same
  way.

**Verified**: clean build. Headless real-defaults boot: zero QML
warnings. A temporary test harness (a `TextField` + a
`Component.onCompleted` hook) confirmed the keyboard end-to-end against
real code, not just "renders clean" — turned the toggle on, force-focused
the field, confirmed `vkTargetIsText`/`vkShouldShow` both went `true`,
then called the keyboard component's own `insertText()` twice and
confirmed the target field's `.text` came back `"hi"`. Also confirmed the
zero-scale startup bug and its fix directly via `uiScale` print
statements, as described above. All test code was reverted afterward;
diffed clean against a pre-test backup (the only remaining difference is
the intentional zero-scale guard). Final rebuild + real-defaults headless
run confirmed clean.

**Not done / follow-ups**:
- No real hands-on test by the user on an actual touchscreen yet (Claude
  can't tap) — this confirms the data path (typing writes into the
  focused field, scaling math is correct and non-zero), not the felt
  experience of typing on real glass.
- Toggle state isn't persisted across launches (see above) — revisit if
  the user wants "keyboard on" remembered.
- The virtual keyboard's layout is QWERTY/English only — no Arabic/Urdu
  layout, which matters for this app given the Quran/Hadith Arabic text
  and Urdu translations elsewhere in the UI. Worth asking the user if
  that's needed, since the read-focused Quran/Hadith screens mostly don't
  need text *entry* in Arabic/Urdu, but it's an honest gap if a future
  screen does.
- This closes out Known Gap #5 ("Touch support — NOT AUDITED YET") only
  partially — a virtual keyboard and auto-resize are a meaningful chunk
  of touch-friendliness, but a full touch audit (tap target sizes across
  every screen, scroll/gesture behavior, etc.) still hasn't happened.

## Icon sizing pass (this session)

Quick follow-up: the user found the icons too small to see comfortably.
Bumped every icon in `HomeScreen.qml` and `SettingsView.qml` up roughly
30-50%: the header settings icon (22→28px in a 44→54px circle), the
install-banner icon (26→34px), the Quran/Hadith big-tile corner icons
(46→62px, 40→54px), the app-grid tile icons (26→40px, tile size bumped
100→112px tall so the bigger icon still has breathing room), and the
Settings brightness/volume row icons (18→26px). Verified with a clean
build and a headless run of both Home and Settings (temporary
`currentView` hardcode, reverted and diffed clean afterward) — zero QML
warnings. The rest of the app's icons (splash badge, reciter/App Center
icons, etc.) were left as-is since the user's feedback was specifically
about the ones they see most, but the same treatment is easy to repeat
elsewhere if more turn out to feel small too.

## Live .iso build pipeline (this session)

**The ask**: the user wants to actually compile a bootable `.iso` — a
genuinely different thing from what existed before. The installer
(`installerbackend.cpp`) clones the CURRENTLY RUNNING filesystem onto a
target disk; it doesn't produce a standalone image file someone could
write to a USB stick and boot on a different machine.

**Why Claude didn't just build it**: squashing a filesystem into a live
image has to run as root (every file needs to be read, including
root-only ones), and `sudo` over this Commander connection needs an
interactive password Claude can't supply — confirmed directly
(`sudo -n true` → "interactive authentication is required"). This is a
hard blocker for every real step of an ISO build, not a shortcut Claude
chose not to take.

**Also important**: the naive approach (squash this dev machine's own
213GB root filesystem) was deliberately rejected — that would ship the
whole dev environment (IDEs, caches, personal files) inside the
"distraction-free" OS, directly contradicting the existing "no dev
languages on the target image" requirement already in this file. Built
a proper `live-build`-based config instead (Debian/Ubuntu's standard
live-CD tool): a clean minimal Ubuntu base, package list derived
directly from `ldd` on the real compiled `roohaniye-shell` binary plus
the exact `libqt5*` package names already confirmed installed here, the
compiled binary + all three DBs copied in, a `roohaniye-shell.service`
systemd unit for autologin-straight-to-kiosk (no desktop, no login
prompt), and a first-boot hook creating the dedicated `roohaniye` Linux
user.

**Delivered**: `live-build/` in the project root —
- `README.md` — full explanation, the size warning below, and the
  honest untested-caveat.
- `build.sh` — the ONE script the user runs (`sudo bash build.sh`).
  Sanity-checks the binary/DBs exist first, installs `live-build` if
  missing, runs `lb config` (amd64, hybrid BIOS+UEFI iso), drops in the
  package list/binary/DBs/systemd unit/hook, runs `lb build`, and
  renames the result to `roohaniye-noorilm-amd64.iso`.
- `config-src/roohaniye.list.chroot` — the runtime package list (Qt5,
  GStreamer mp3 plugins, eglfs/KMS libs, NetworkManager, PipeWire,
  polkit, GRUB for both EFI and BIOS, wifi firmware).
- `config-src/roohaniye-shell.service` + `0100-setup-roohaniye.hook.chroot`
  — autologin-to-kiosk wiring.

Confirmed via read-only checks (no privileged commands run): `xorriso`,
`squashfs-tools`, `grub-efi-amd64-bin`, `genisoimage`, and
`qemu-system-x86_64` (for test-booting the result in a VM before
touching real hardware) are all already installed — only `live-build`
itself needs installing, which `build.sh` does as its first (and only
truly new-package) step. Verified the compiled binary and all three
data files actually exist at the paths the script expects.
`bash -n build.sh` confirms no syntax errors.

**Real, load-bearing limitation, flagged clearly in the README**: this
entire config is UNTESTED — it has never actually been built or booted,
since doing so needs the sudo password the user has to type themselves.
Written carefully against real dependency data rather than guessed, but
the most likely first-run gap is called out explicitly: this dev machine
runs the shell via `xcb`/X11, so a true `eglfs`-to-bare-framebuffer kiosk
boot (what the image is actually configured for) is genuinely
unexercised territory — `libgbm1`/`libdrm2`/KMS driver packages were
included based on general eglfs requirements, not confirmed against a
real eglfs boot on this hardware.

**Also flagged**: the ISO will land around 20-22GB, almost entirely
`quran_audio.db` (21.5GB of already-compressed MP3 blobs — squashfs
won't shrink it much). Needs a 32GB+ USB stick. A smaller "core" image
that relies on the DB Connector feature to import audio from a USB stick
post-boot, instead of shipping it in the image, is a reasonable future
option but wasn't built.

**Next step for the user**: `cd live-build && sudo bash build.sh`, then
`qemu-system-x86_64 -m 3072 -enable-kvm -cdrom roohaniye-noorilm-amd64.iso`
to test-boot before writing to a real USB stick. If it fails, the error/
log is the next thing to bring back — a first-pass failure on a from-
scratch image build is normal, not a sign of a fundamentally broken
approach.

### Follow-up: `--full`/`--lite` split + a real bug this surfaced

The user correctly pushed back on the ~21GB size — `quran_audio.db` is
the real, current, *supported* audio database (not the deprecated
`quran_audio_embedded.db`, which was double-checked and confirmed NOT
included in `build.sh`), so the size was real, not a leftover-file bug.
Rather than force an all-or-nothing choice, `build.sh` now takes a flag:

- `sudo bash build.sh --full` (default, same as before) — bundles all
  three DBs, ~20-22GB ISO, everything works offline from first boot.
- `sudo bash build.sh --lite` — bundles only `quran_text.db` +
  `hadiths.db` (~50MB total), ISO lands well under 1GB. Quran audio is
  added later via the existing Database Connector app (Home → Database
  Connector → pick `quran_audio.db` off a USB drive → Import) — no new
  feature needed, that's exactly the workflow it was built for.

Output filename reflects the variant: `roohaniye-noorilm-amd64-full.iso`
or `-lite.iso`. `README.md` documents both clearly. `bash -n build.sh`
confirms no syntax errors in the updated script.

**Real bug this caught and fixed**: building `--lite` and booting it
would have silently broken the ENTIRE Quran reader, not just audio.
`QuranBackend::openDatabases()` was already setting `quranOk`/opening
correctly when `quran_audio.db` is missing (via `m_audioDbAttached`),
but `audioFilePath()` — one of the three audio-dependent query paths —
had never gotten the same guard that `audioBase64()` and
`reciterList()`/`versesForSelection()` already had. It would have run a
doomed `ATTACH`-dependent query and returned a raw SQL error instead of
failing gracefully. Fixed: `audioFilePath()` now checks
`m_audioDbAttached` up front and returns empty with a clear log message
instead. Verified for real, not just compiled: renamed the actual
21.5GB `/opt/roohaniye/data/quran_audio.db` out of the way (simulating
a true `--lite` install), ran the real binary headless, confirmed
`openDatabases: quranOk= true hadithOk= true` and a clear
"audio DB not present (expected for the lite build)" log line instead
of any error — then renamed the file back and confirmed the size
matched exactly (21,568,946,176 bytes) and a normal `--full`-equivalent
headless run was still clean afterward.

### CPU architecture support — clarified, NOT expanded

The user asked directly whether the ISO supports x86_64/x64, ARM, Intel,
AMD, "any other CPU." Answered honestly rather than assuming:

- `build.sh`'s `lb config` hardcodes `--architectures amd64`. That's
  x86_64 — the terms "amd64" and "x86_64"/"x64" all refer to the same
  64-bit instruction set, and it covers BOTH Intel and AMD 64-bit CPUs
  (they implement the same ISA; this is not Intel-only or AMD-only).
  So: any modern 64-bit Intel or AMD PC/laptop — yes, supported, this is
  the actual built/documented target.
- ARM (Raspberry Pi, ARM laptops, etc.) — NOT supported. Nothing has
  been built or tested for it.
- 32-bit x86 (old/legacy CPUs) — NOT supported either, amd64 only.
- **Root reason ARM isn't just a config flag away**: `roohaniye-shell`
  itself has only ever been compiled on this dev machine as an x86_64
  binary (`cmake --build` here produces an x86_64 ELF). `build.sh` only
  packages an already-compiled binary — it does not cross-compile. A
  real ARM build would need the shell actually built for/on ARM (either
  native ARM hardware or a cross-compilation toolchain) as a
  prerequisite, THEN a second `lb config`/`build.sh` pass targeting
  `arm64`. Not started; would be a genuinely separate effort, not a
  quick addition.
- No code or script changes made for this — it was a documentation/
  scoping answer only, flagged here so no future session assumes ARM
  support exists or silently tries to bolt it on without the shell
  itself being cross-compiled first.

## Installer completion flow + touch-keyboard auto-show (this session)

Two real gaps closed:

1. **No way to actually finish an install.** The result screen (step 6)
   used to just say "restart, remove the USB" as text, with the only
   button being "Back to home" — no actual restart mechanism. Fixed:
   - `InstallerBackend::rebootSystem()` — new Q_INVOKABLE, tries
     `systemctl reboot` first, falls back to `pkexec reboot`.
   - The success screen now has an explicit "I've removed the USB
     drive" checkbox that must be ticked before a "Restart now" button
     enables (colored red as a deliberate destructive-action cue, same
     visual language as the disk-erase step). This is intentional
     friction — a reboot with the install USB still plugged in risks
     some firmware booting back into the live media instead of the
     freshly-installed disk, so the app never auto-reboots on its own.
   - Renamed the non-restart option to "Later, back to home" so it's
     clear that's the non-reboot path, not a confirmation of anything.
   - Verified headlessly: both `installOk: true` (checkbox gate, button
     enable/disable) and `installOk: false` (still just offers "Try
     again") render with zero QML warnings.

2. **On-screen keyboard didn't auto-appear for touchscreens.** It only
   ever showed if the user found and tapped the small toggle button.
   Fixed: added a real `hasTouchScreen` context property in `main.cpp`
   using `QTouchDevice::devices()` (reflects what xcb/eglfs actually
   detects as registered touch hardware — not a guess, not an env var
   check). `uiSettings.vkEnabled` now *defaults* to `hasTouchScreen`'s
   value at boot instead of always `false`. The manual toggle button
   still works exactly as before, in either direction, on any device —
   this only changes the starting point for touch hardware, it doesn't
   force anything or remove the ability to turn it off.
   - This dev machine has no touch hardware, so `hasTouchScreen` is
     `false` here and was verified as such (real defaults boot clean).
     Also verified with `vkEnabled` force-set to `true` at boot (the
     touchscreen case) — keyboard renders with zero QML warnings there
     too. **Not yet verified on an actual touchscreen device** — only
     the logic paths (touch-detected vs not) were exercised, since this
     dev box has no touch panel to confirm `QTouchDevice::devices()`
     actually populates on real hardware.

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

## Navigation stack + audio-stop-on-exit + Theme system (this session)

**Bug 1 fixed — back button landing on home instead of the previous
screen.** Root cause: the whole app used a single flat `currentView`
string with no history — every screen's back button was hardcoded to
one fixed destination. `QuranMenu.qml`'s `openReader()` and
`HadithMenu.qml`'s `openReader()` both set `root.currentView` directly
when jumping into the reader, and the readers' own back buttons were
hardcoded straight to `"home"` — so entering through the menu (picking
a surah/juz/page, or a book/topic) and then hitting back skipped the
menu entirely. Fixed properly rather than patching just those two
spots: added a real navigation stack to `Main.qml` —
`root.navigateTo(view)` pushes the screen you're leaving before
switching, `root.goBack()` pops it (falls back to `"home"` if the stack
is ever empty). Every forward-navigation call and every back button
across the app (`HomeScreen`, `QuranMenu`, `QuranView`, `HadithMenu`,
`HadithView`, `AppCenter`, `DatabaseConnector`, `PrayerTimesView`,
`QiblaView`, `RemindersView`, `SettingsView`, `UpdatesView`,
`AboutQuran`) now goes through these two functions instead of raw
`currentView = "..."` assignment. `InstallerWizard.qml`'s three
`"home"` exits were left as direct assignments — it's a self-contained
wizard with a single entry point (the home banner), not affected by
this bug. Verified with a temporary `Component.onCompleted` hook that
programmatically replayed `home → quranmenu → reader → back → back` and
`home → hadith → hadithreader → back`, printing `currentView`/stack to
stderr each step — confirmed the first back now correctly lands on the
menu (previously would have gone straight to home), and the second
back correctly reaches home. Zero QML warnings throughout. Hook
reverted, diffed clean against a pre-change backup.

**Bug 2 fixed — audio kept playing after leaving the Quran reader.**
`QuranView.qml`'s back handler called `saveCurrentProgress()` but never
touched `audioBackend` at all, so a verse/selection/range still
playing when you backed out just kept playing with no way to reach it
again. Fixed two ways: (1) the back handler now calls
`audioBackend.stop()` directly, and (2) as a redundant global safety
net, `Main.qml` now watches `currentView` and calls `audioBackend.stop()`
automatically any time you leave `"quranreader"`/`"quran"` for any other
screen, however that navigation happens — so this can't regress if a
future screen adds yet another way to exit the reader.

**New: Theme system (light/dark, accent color, custom background
image).** New `ThemeBackend` (`themebackend.h/.cpp`), following the
same `QSettings` pattern as every other backend
(`/opt/roohaniye/data/shell_settings.ini`, `[theme]` section):
`darkMode` (bool), `accentColor` (hex string), `backgroundImage` (a
`file://` url, empty = none), `backgroundOpacity` (0.05–0.6). Background
images are **copied** into `/opt/roohaniye/data/backgrounds/` (not
referenced in place on the USB/SD card) so the image survives the
source media being removed — same import-don't-just-point philosophy as
`DbConnectorBackend`. `setBackgroundImage()` validates the file is a
real decodable image via `QImageReader::canRead()` before committing to
it, and rejects anything else with a returned error string.

`Main.qml` gained a `root.theme` helper object (`bg`/`card`/`cardAlt`/
`text`/`subtext`/`accent`/`dark`/`hasBackground`) that screens read
colors from instead of hardcoding hex values, plus a full-window
background `Image` layer that sits behind the `Loader` and only shows
through screens whose root `color` is `"transparent"` when
`theme.hasBackground` is true.

**Scope note, read before assuming this is fully rolled out**: only
`HomeScreen.qml` and `SettingsView.qml` have actually been migrated to
`root.theme.*` colors and made background-transparent-aware. Every
other screen (`QuranView`, `HadithView`, `AppCenter`, `PrayerTimesView`,
etc.) still uses its original hardcoded dark palette — dark mode still
looks correct there (it's the same colors as before), but light mode
and the custom background currently only visibly apply on Home and
Settings. Rolling the same treatment out to the rest of the screens is
mechanical (swap hardcoded hex colors for `root.theme.*` equivalents,
same pattern used here) but touches ~15 more files and wasn't done yet
— don't let "Theme system: DONE" get written anywhere without that
caveat.

`SettingsView.qml` got a new "Appearance" section: a dark/light
`Switch`, six accent-color swatches, and a background-image row
("Choose" opens an inline file browser reusing
`dbConnectorBackend.listDirectory()` filtered client-side to image
extensions off the current USB/SD device, "Reset" clears it, a
"Strength" slider controls `backgroundOpacity` once a background is
set).

Verified end-to-end, not just "renders without error": a temporary
debug hook called `themeBackend.setDarkMode(false)`,
`setAccentColor(...)`, and `setBackgroundImage("/tmp/test_bg.png")`
against a real generated PNG — confirmed `{"ok":true}`, confirmed via
`md5sum` that the copied file in `/opt/roohaniye/data/backgrounds/` is
byte-identical to the source, and confirmed Home/Settings both render
with zero QML warnings in dark, light, custom-accent, and
custom-background states, plus the background-picker overlay itself.
All test hardcodes reverted and diffed clean; the seeded `[theme]`
section and the test `background.png` were removed from the real
settings file/data directory afterward so the real device boots with
its actual defaults (dark mode, default accent, no background) rather
than my test values.

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
3. **Hadith reader overhaul** — DONE this session. Book picker
   (Bukhari/Muslim), topic/chapter browsing, English/Urdu/Arabic
   visibility toggles (all three already stored per-row) + font size,
   search (FTS5), random, continue-reading, and multi-select
   topic/hadith → filtered reading list (mirrors the Quran side's
   multi-select, minus a reciter step since there's no hadith audio) —
   see "Hadith reader overhaul, mirroring the Quran app" above. Two real
   bugs fixed along the way: the new screens existed on disk but were
   never wired into `qml.qrc`/`Main.qml`'s router, and `searchHadiths()`
   was broken (ambiguous column name in the FTS join, misreported by Qt
   as a parameter-count error). Remaining polish: real hands-on
   verification by the user (Claude can't click/tap), and no visual
   design reference was ever requested for this screen (unlike App
   Center/splash).
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
5. **Touch support** — PARTIALLY DONE. An on-screen keyboard (toggle
   button, auto-show/hide on text-field focus, works with any field app-
   wide, external mouse/keyboard unaffected) and automatic screen-resize
   scaling (whole UI scales to fit any real screen size, not just this
   dev machine's 1920x1080) were added this session — see "On-screen
   keyboard + automatic screen-resize" above. Still not done: a full
   audit of tap-target sizes, scroll/gesture behavior, and an
   Arabic/Urdu keyboard layout for anywhere text entry in those languages
   might be needed.
10. **Brightness/volume settings + hardware keybindings** — DONE this
    session (see "Brightness/volume settings + hardware keybindings"
    above). Settings sliders, laptop Fn-key + phone-rocker bindings, and
    a phone-style OSD all confirmed wired with zero QML warnings.
    Follow-up: no udev rule yet for prompt-free brightness writes (falls
    back to `pkexec`), and hardware keys themselves are untested by
    Claude (can't press physical keys) — user should confirm on real
    hardware.
11. **UI sound effects + Reminders app** — DONE this session (see "UI
    sound effects from user-provided assets" and "Reminders app" above).
    Click/select/item-selecting sounds wired into the most common tap
    points (not exhaustive yet); a new recurring-reminders app (add/
    edit/delete, per-day repeat, enable toggle) that plays the user's
    ringtone asset and shows a dismissible banner regardless of which
    screen is open when a reminder fires. Follow-up: no real hands-on
    tap-through by the user yet, and no catch-up firing for a reminder
    that was due while the device was off — documented limitation, not
    a bug.
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

9. **"Try/Install" installer app** — BUILT this session (see "Installer
   app: Try/Install RoohaniyeNooreIlm" above). Real disk enumeration
   (excludes the running disk), optional replacement-database picker off
   USB, a hard `"ERASE"` confirm gate, and an animated progress + result
   screen, all wired end-to-end and headless-verified with zero QML
   warnings. **The actual partition/format/clone/GRUB script has not
   been run against a real disk** — this dev box only has one disk (its
   own root disk, correctly excluded), so there was nothing safe to test
   it against here. Test on a spare disk/VM before trusting it for real.

9. **"Try/Install" installer app** — BUILT this session (see "Installer
   app: Try/Install RoohaniyeNooreIlm" above). Real disk enumeration
   (excludes the running disk), optional replacement-database picker off
   USB, a hard `"ERASE"` confirm gate, and an animated progress + result
   screen, all wired end-to-end and headless-verified with zero QML
   warnings. **The actual partition/format/clone/GRUB script has not
   been run against a real disk** — this dev box only has one disk (its
   own root disk, correctly excluded), so there was nothing safe to test
   it against here. Test on a spare disk/VM before trusting it for real.
12. **Navigation stack + audio-stop-on-exit** — DONE this session (see
    "Navigation stack + audio-stop-on-exit + Theme system" above). Real
    back-history stack replaces the old hardcoded-per-screen
    `currentView` destinations; `audioBackend.stop()` now fires
    automatically on any exit from the Quran reader.
13. **Light/dark theme + accent color + custom background image** —
    PARTIALLY DONE this session. Backend (`ThemeBackend`) and Settings UI
    are complete and verified; **only `HomeScreen.qml` and
    `SettingsView.qml` actually render the theme** — every other screen
    is still hardcoded to the original dark palette regardless of the
    dark/light toggle. Rolling `root.theme.*` out to the remaining ~15
    QML files is the next step here, not yet started.
14. **User accounts + password authentication** — DONE, including the
    follow-up. `AuthBackend` with real PBKDF2-HMAC-SHA256 hashing
    (per-user salt, 210,000 iterations, `accounts.dat` forced to
    `0600`), a `LockScreen.qml` overlay that sits above everything and
    covers first-login, quick-unlock, AND password recovery (one-time
    recovery code, shown once, single-use), inactivity auto-lock, and a
    full account-management section in Settings (create/delete users,
    change password, regenerate recovery code, auto-lock timing). The
    installer wizard also has an optional "set up an account" step (step
    3 of the wizard) that stages a real `accounts.dat` onto the target
    disk without ever touching the live session's own login state.
    Every path (wrong password, correct password, lock, unlock,
    delete-with-wrong-admin-pw, delete-last-admin-blocked, wrong/right/
    reused recovery code, standalone installer export) was exercised
    against the real backend headlessly, not just "renders clean." Gates
    the shell UI only, not the underlying Linux disk — see "Password
    recovery + installer-wizard account step (follow-up session)" above
    for the full honest-limits list.
15. **Notification bar / notification center (requested, not started)**
    — user asked for "a notification bar," separate from the existing
    per-feature banners (reminder-due banner, brightness/volume OSD).
    Likely shape: a persistent bar/icon (top of screen?) that
    accumulates notifications from any backend (update available,
    install finished, database connected, reminder fired, etc.) into a
    dismissible list, rather than each feature showing its own one-off
    banner. Needs a design decision from the user on exactly where/how
    it should look before building — not started.
16. **ARM and 32-bit x86 ISO support (requested for the future, not
    started)** — the live `.iso` build (`live-build/build.sh`) only
    targets amd64/x86_64 (covers both Intel and AMD 64-bit CPUs). ARM
    (Raspberry Pi, ARM laptops, etc.) and 32-bit x86 are explicitly
    NOT supported today. Noted by the user as wanted eventually. Real
    prerequisite before any ISO-side work can start: `roohaniye-shell`
    itself has only ever been compiled as an x86_64 binary on this dev
    machine — `build.sh` packages an already-built binary, it doesn't
    cross-compile. An ARM build needs the shell actually built for/on
    ARM first (native ARM hardware or a cross-compilation toolchain),
    THEN a second `lb config --architectures arm64` pass. Not scoped
    beyond that yet.

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
