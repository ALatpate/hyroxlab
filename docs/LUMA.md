# Luma

Luma is this fork's iPhone app: its own interface, analysis, food log, session modes and coach,
running over the strap layer the repository is built on (Bluetooth, on-device storage, and the
recovery, strain and sleep scoring). The strap layer is unchanged and stays in step with upstream;
everything described here sits beside it. [`AGENTS.md`](../AGENTS.md) still governs the strap layer.

## Layout

| Path | What lives here |
|---|---|
| `Packages/LumaCore` | Pure Foundation, no UI, builds and tests on Linux. Models, analysis (recovery, sleep, load, running, fitness, race readiness), the food and supplement model, session state machines, and the coach's wire format and tools. |
| `Packages/LumaUI`, target `LumaKit` | Design tokens, primitives, the glance snapshot, and the views for widgets and the Lock Screen card. No dependencies, so the widget extension links it alone. |
| `Packages/LumaUI`, target `LumaUI` | Every screen, the charts, the environment object (`LumaEnv`), the session controllers and the coach engine. Depends on `LumaCore` and re-exports `LumaKit`. |
| `LumaGallery/` | A small host app that mounts `LumaUI` over demo data. Used only to build and photograph the screens quickly. |
| `StrandiOS/Luma/` | The bridge between Luma and the strap layer: `LumaRepoSource` (reads), `LumaBridge` (strap control, live state, widgets, Lock Screen card), `LumaWorkoutRecorder`, `LumaKeychain`, and `LumaShell`, which the app mounts as its root. |
| `StrandiOSWidgets/LumaWidgets.swift` | The widget bundle and the Live Activity, drawn with `LumaKit` views. |

`LumaUI` knows nothing about Bluetooth, the database or HealthKit. It sees four protocols and the
bridge implements them:

- `LumaDataSource`: days, nights, sessions, heart-rate and HRV series, routes, stress, how far the
  recovery baseline has got, and the plain facts behind the data check.
- `LumaDeviceControl`: pair, sync, buzz, live heart rate, being on screen, Health access, battery alerts.
- `LumaRecorder`: start, pause and finish a recorded session.
- `LumaSecrets`: the coach's API key, held in the keychain.

## Rules

- **One readout per fact.** Recovery, strain and sleep are the scores the strap layer computed, read
  through `Repository`; Luma does not compute a second version. Strain is formatted only through
  `LScale`, so the 0–21 and 0–100 settings cannot disagree between screens. Widgets and the Lock
  Screen card take their numbers from the glance snapshot (`LumaGlance`), and withhold them once the
  snapshot is no longer for the current training day (the day turns over at 04:00).
- **A night is only as complete as the record behind it.** A WHOOP 5.0 or MG may hand over nothing it
  stored, and then the phone holds only what the strap streamed while the app was running. A night that
  ends where the heart-rate record ends was not seen to end. `RecordCheck` (LumaCore) reads where the
  record has readings and classes the night: whole, still going, or cut off (an hour or more missing in
  it or right after it). A cut-off night keeps the figures that were measured, each marked, and feeds
  nothing else: no score of Luma's, no sleep debt, no average, no baseline, no trend (`NightMark`,
  kept on the phone, because the record is only looked at for a day and a half). Luma never fills the
  missing part in.
- **One reason, one notice.** Why there is no recovery score is resolved once (`RecordCheck.gap`), in
  a fixed order, and worded from that: the ring's caption, the day's call and the Recovery screen cannot
  give different reasons, and none names a cause that was not established. The same holds for the state
  of the data (`DataNotice.resolve`): Today and the strap screen carry the one card. Both state what
  the strap layer reports (`LiveState`), such as "holds data not yet read"; they do not re-derive it.
  A strap that has handed over nothing in repeated reads is not announced as "being read" each time
  another read is tried. A night with no heart-rate record behind it at all is `unjudged`: taken as
  stored and said to be that, never passed off as whole.
- **A missing figure is a dash.** No reading becomes a zero, and a figure from an earlier night says
  which night it is from. A heart-rate line is laid on the clock (`TimeGrid`, `RecordCheck.slots`), so
  time with no readings is a break in the line, not a stroke joining the two sides of it.
- **Recording all the time is the strap layer's continuous capture**, switched through its own
  preference and call (`LumaBridge.applyCapture`): one existing, reversible command, the realtime
  heart-rate toggle. It is on by default in Luma, because it is the only way such a strap's night is
  recorded, and it costs strap battery. With it off, the strap streams while Luma is on screen or a
  session is running. The app has to stay running in the background for either to record anything.
- **Sleep times are not edited by hand.** The strap layer can re-stage a hand-set night only where it
  has movement data; elsewhere added time is stored as awake and the night is then frozen against
  re-detection. On a strap with no movement record that would make a corrected night worse and keep
  it so, so Luma has no such control until that is settled on hardware.
- **Sessions are never invented.** A stretch of raised heart rate that no session covers is a
  suggestion: `LumaRepoSource.suggestedSessions` runs the strap layer's own detector over the raw
  record, `SessionSuggestions` (LumaCore) decides which stretches reach training intensity, and nothing
  is stored until the athlete keeps one. A kept or hand-logged session is stored as a manual row, and
  the strap layer then fills its heart rate and strain from its own record at read time. The search
  reads days of raw heart rate, so it runs only while the app is on screen.
- **Race predictions come from one resolver** (`RaceReadiness.assess`), and the live race screen takes
  its targets from the same model (`RaceReadiness.targets`).
- **Stored identifiers are never renamed.** Bundle ids, the App Group, `noop.*` defaults keys, the
  keychain service, the `noop` URL scheme, widget kinds and `NOOPActivityAttributes` keep their names:
  renaming any of them orphans data or placed widgets on an installed phone. Only text a person reads
  says Luma. Luma's own files live under `Application Support/HYROXLab/` for the same reason.
- **The upstream credit stays.** About carries the open-source licence credit the licence requires.
- **What the earlier shell did on its own is not left running.** Its first-run screens, update check,
  coach and banners are marked settled, and automations with no Luma screen (alarm, reminders, haptic
  nudges) are switched off at launch and named to the athlete once (`LumaBridge`).
- **The coach sends data only with consent.** Requests go from the phone straight to Anthropic with
  the athlete's own key; health data is included only while "Share my health data with the coach" is on.
- **Demo data carries no personal details.** Screenshots are published to a branch of a public
  repository.

## Build and verify

There is no local Apple toolchain in the usual working environment; CI is the compiler.

`.github/workflows/luma-dev.yml` runs on every push to a `luma-*` branch and releases nothing:

| Job | What it proves |
|---|---|
| `core` | `swift test` for `LumaCore` on Linux. |
| `gallery` | `LumaUI` compiles; every screen in `Tools/luma_screens.txt` is photographed to the `screens` branch. |
| `app` | The whole app compiles (Debug, simulator) and runs over seeded strap-layer data; screens in `Tools/luma_screens_app.txt` land on `screens-app`. Runs when the commit message contains `[app]`. |
| `package` | A dry run of the release: Release device build and sideload packaging, nothing published. Runs with `app`. |

`.github/workflows/hyroxlab-ios.yml` runs on a push to `main`: Release device build, the `.ipa`
published as its own release (`build-<run number>`), and `hyroxlab-source.json` for AltStore or
SideStore pointing at that release.

- **A listing and the file it names are the same build, always.** AltStore refuses a download whose
  build number is not the listed one. A build's file is never replaced by another build's (there is no
  rolling download), the listing is written only after its file is published and checked, and
  `Tools/hyroxlab_source.py` rejects any other download URL (`Tools/test_hyroxlab_source.py`).
- **Publish once per finished piece of work.** Every push to `main` that touches the app is a build
  the phone is offered. Verify on a `luma-*` branch and merge when it is ready to install.
- **`docs/luma-whats-new.txt` is the next build's What's New**, shown in AltStore. Rewrite it with
  each change that ships. It is not in the release's path filter, so editing it alone publishes nothing.
- **The release workflow keeps its name and file name.** Its run number is the build number.

None of this exercises a strap. Pairing, sync, buzzes, the double tap, live recording and the Lock
Screen card's real cadence have to be checked on a phone with a strap, as do Health access under a
sideload signature and a real coach request. A change is not verified on hardware until someone says
what they tried.

Still to be confirmed on a strap: that recording all the time keeps the app receiving heart rate through
a whole night in the background, what it costs the strap's battery, and whether a given WHOOP 5.0 or MG
hands over any stored record or movement data. **Settings, Data check** is the instrument for this: it
shows the minutes of heart rate that reached the phone in each of the last 24 hours, the holes, the
nights and days as stored, and the strap layer's own sync state, and sends all of it as plain text.
The gallery's `partial` data (`-lumaData partial`) stages the case this was built from: asleep at 01:00,
the record stopping at 02:00.
