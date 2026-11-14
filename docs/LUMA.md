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

- `LumaDataSource`: days, nights, sessions, heart-rate and HRV series, routes, stress.
- `LumaDeviceControl`: pair, sync, buzz, live heart rate, Health access, battery alerts.
- `LumaRecorder`: start, pause and finish a recorded session.
- `LumaSecrets`: the coach's API key, held in the keychain.

## Rules

- **One readout per fact.** Recovery, strain and sleep are the scores the strap layer computed, read
  through `Repository`; Luma does not compute a second version. Strain is formatted only through
  `LScale`, so the 0–21 and 0–100 settings cannot disagree between screens. Widgets and the Lock
  Screen card take their numbers from the glance snapshot (`LumaGlance`), and withhold them once the
  snapshot is no longer for the current training day (the day turns over at 04:00).
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

`.github/workflows/hyroxlab-ios.yml` runs on a push to `main`: Release device build, the `.ipa` on the
rolling `latest` release, and `hyroxlab-source.json` for AltStore or SideStore.

None of this exercises a strap. Pairing, sync, buzzes, the double tap, live recording and the Lock
Screen card's real cadence have to be checked on a phone with a strap, as do Health access under a
sideload signature and a real coach request. A change is not verified on hardware until someone says
what they tried.
