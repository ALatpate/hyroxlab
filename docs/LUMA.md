# Luma

Luma is this fork's iPhone app: its own interface, analysis, food log, session modes and coach,
running over the strap layer the repository is built on (Bluetooth, on-device storage, and the
recovery, strain and sleep scoring). The strap layer is unchanged and stays in step with upstream;
everything described here sits beside it. [`AGENTS.md`](../AGENTS.md) still governs the strap layer.

## Layout

| Path | What lives here |
|---|---|
| `Packages/LumaCore` | Pure Foundation, no UI, builds and tests on Linux. Models, analysis (recovery, sleep, load, running, fitness, race readiness), the training log with its muscle model and progress read, the body figure's outlines, the food and supplement model, session state machines, and the coach's wire format and tools. |
| `Packages/LumaUI`, target `LumaKit` | Design tokens (colour, type, motion), the bundled fonts, primitives, the glance snapshot, the queue for things logged from outside the app, the companion's drawing, and the views for widgets and the Lock Screen card. No dependencies, so the widget extension links it alone. |
| `Packages/LumaUI`, target `LumaUI` | Every screen, the charts, the environment object (`LumaEnv`), the session controllers and the coach engine. Depends on `LumaCore` and re-exports `LumaKit`. |
| `LumaGallery/` | A small host app that mounts `LumaUI` over demo data. Used only to build and photograph the screens quickly. |
| `StrandiOS/Luma/` | The bridge between Luma and the strap layer: `LumaRepoSource` (reads), `LumaBridge` (strap control, live state, widgets, Lock Screen card), `LumaWorkoutRecorder`, `LumaKeychain`, and `LumaShell`, which the app mounts as its root. |
| `StrandiOSWidgets/LumaWidgets.swift` | The widget bundle and the Live Activity, drawn with `LumaKit` views. |
| `StrandiOSShared/LumaQuickIntents.swift` | Luma's App Intents (log water, tick supplements, log a weigh-in, the tap on the companion), compiled into the app and the widget extension. |

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
- **The training log holds what was done, and only what is known of it.** A logged session
  (`LiftSession`) carries its kind, its movements and sets, where it was logged from and, when it was
  read from a photo, the photo and the board as it was written. A set counts reps, distance, time or
  calories. A load is only what was written for the athlete, said by them or typed in: reading a board
  never fills one in (`CoachPrompt.workoutExtraction`), and a set without a load counts as work and
  gives no estimated max. Photos are read in one go into separate sessions, each sorted into its kind,
  and nothing is saved until the athlete has checked it (`WorkoutPhotoSheet`). The checking step shows
  every exercise with a box for its weight: filled where the photo or the note gave one, and asking
  ("kg?") where an exercise that normally carries a load came without one (`LiftExercise.needsLoad`).
  Last time's weight is offered as a tap, never filled in. An exercise the reading missed, or a whole
  workout, can be typed in by hand (`LiftExercise.typed`). A logged session of a fitting kind marks
  that day's plan entry done through `Schedule.days`, which the calendar and the coach both read.
- **A movement has one name.** `ExerciseLibrary.match` files a movement under Luma's own name when it
  knows it by that wording, so its history lines up whether it came from a photo, the coach or the
  picker. A variation ("paused back squat") keeps the name it was given, takes the muscles of the lift
  it varies, and is not graded. "Row" alone is the machine; a row inside a longer name is a lift.
- **An estimated max has one definition** (`LiftMath.estimate`): Epley, from done sets of 12 reps or
  fewer with a load. A pull-up, chin-up or dip counts bodyweight plus whatever was added. Best lifts,
  the session screen, the Progress view and the coach all read it.
- **Strength levels are Luma's own yardstick, and say so.** `StrengthScale` grades a lift by its
  estimated max as a multiple of bodyweight against five fixed marks, set around milestones lifters
  commonly use; women's marks are scaled by a rule of thumb. It is not a population percentile and no
  screen calls it one. A lift's figure is the best of its last six weeks (or of the six before, when
  it has not been lifted since), and progress is that against the six weeks before. A muscle takes the
  level of the graded lift that measures it. A muscle no graded lift of the last twelve weeks measures
  is "not measured": a dashed outline on the figure, never drawn as low.
- **Sets for a muscle are counted one way** (`TrainingProgress.sets`): 1 where a movement trains the
  muscle directly, ½ where the muscle assists, and nothing for a run or an erg. That is the
  "fractional" count of Pelland et al. (SportRxiv, 2024). The groups shown beside it (under 5, 5 to 9,
  10 or more a week) are those Schoenfeld, Ogborn and Krieger compared (J Sports Sci, 2017); the app
  gives them as how studies grouped weekly sets, with their limits, not as a target.
- **A weak point comes with its evidence.** A lift graded well below the others, a lift whose
  estimate has fallen, muscle groups no logged session has reached in two weeks (said only once three
  sessions are logged in that time), and muscles at half their usual work: each names the lift or the
  count behind it (`TrainingProgress.weakNotes`).
- **A habit read from a log is only known on days that have the log** (`EffectFactor.known`). Alcohol,
  late caffeine and a late meal can be ticked in a check-in or read from the food log; each is one
  factor fed by both. A supplement is compared only from its first logged day. The food log is set
  against training only on days full enough to read (two entries and 1,000 kcal). Findings are worded
  as patterns with their counts, never as causes.
- **The body figure is Luma's own drawing** (`BodyMap`): closed smooth curves through hand-placed
  points, the right half written down and the left its mirror image. No third-party artwork.
- **Race predictions come from one resolver** (`RaceReadiness.assess`), and the live race screen takes
  its targets from the same model (`RaceReadiness.targets`).
- **The companion has one set of rules, and no figures of its own.** Its state is resolved in one
  place (`Buddy.look`) from facts every one of which some screen already shows (`LumaEnv.buddyFacts`
  reads them from where that screen does), in a fixed order: what is happening now, then how the body
  is, then what the logs are missing. The app writes every state from now until the morning after next
  into the glance (`Buddy.schedule`); a widget only looks up the moment that has begun
  (`BuddyTimeline`), so the Lock Screen cannot say something the app does not. On Today, where the
  recovery figure and the call already stand, a state that only repeats them is given by name alone.
  A change that follows the clock begins at the time its own line names (winding down 45 minutes
  before lights-out, asleep at the usual bedtime): the clock is read to the second, because those
  times are averages and seldom fall on a whole minute.
- **The companion's build is the athlete's strength levels, and an unmeasured part is plain.** Each of
  its six parts is the mean level of the muscles it stands for (`Buddy.build`), the same levels the
  body figure shows. A part no graded lift measures is drawn at the plain build, never smaller: "not
  measured" must not read as "weak". The drawing is Luma's own (`BuddyRig`): simple shapes turned
  about their joints, so a change of pose is a change of position and angle that a widget can animate
  between two entries. No third-party artwork.
- **A widget moves only as iOS lets it.** A widget is a list of dated pictures. The companion's are
  its changes of state, a shift of weight every five minutes, and a hop and a wave straight after a
  tap (`PokeBuddyIntent`). Continuous motion is in the app only. A still pose must always be a
  truthful one: there is no frame that would look wrong if the next one came late.
- **What is logged from outside the app is queued, not written.** A widget button or a shortcut may
  run in the widget extension, which cannot reach the app's records. It queues the entry in the App
  Group (`LumaQuickLog`) and moves the stored glance to match; the app files the queue before it next
  writes a glance (`LumaBridge.publishGlance`), so the widget that was tapped never steps back.
- **A trial is planned before it is read.** A supplement trial is blocks on and blocks off in pairs,
  the order inside each pair drawn at random when it is set up (`SupplementTrial.plan`), with the
  first days of every block left out. A day counts only when the plan was followed on it. The result
  is a difference with the range it most likely lies in, widened for nights that follow one another,
  and "not clear" is a result. One trial runs at a time.
- **A pattern in the athlete's days is not a cause, and is checked for chance.** Dose curves, the
  recovery model and the training-weeks read word everything as "goes with", give the days or nights
  each stands on, and call a pattern clear only when it survives a false-discovery check across
  everything tested together (`PatternStrength`). A difference on a percent scale is worded in points
  (`LMetric.gap`): "12% lower" can also be read as an eighth off. The recovery model fits its inputs side by side
  (`DriverModel`) and gives a forecast only when it predicts nights it was not fitted on.
- **One weight.** The weight log is read as a trend (`BodyWeight.read`), and the trend is the weight:
  a weigh-in moves it and the profile follows, so energy, protein and strength ratios all read one
  number. How fast it has moved is also asked in one place: a line through the last four weeks of
  weigh-ins (`BodyWeight.line`) gives both the change shown beside the trend and the rate real burn is
  built on, so the two are the same figure. Real burn (`EnergyModel`) is given with its range and says
  that unlogged food makes it higher.
- **The day's food and the day's targets name the day the same way.** `FuelMatch.read` is given the
  class the targets were built from, so the card and the targets beside it cannot disagree about what
  kind of day it was. A line is only marked short once the day is over.
- **Easing off is an offer.** After two low-recovery mornings in a row Luma offers an easier version
  of today's hard session (`EaseOff.offer`). It changes nothing until the athlete says so, and is not
  offered again for a session once answered.
- **Reminders are worked out, not scheduled.** Each is planned on the phone from the day's own
  numbers (`ReminderPlanner`) with a stable id, and the plan is handed to iOS each time a number behind
  it changes (`LumaReminders.sync`): one whose reason has gone is no longer in the plan and is
  removed. All are off until switched on. Nothing is planned or cleared before the strap data has been
  read once.
- **One set of timings.** Every animation takes its timing from `LumaMotion`, and each is nil under
  Reduce Motion, so the change simply happens. A heart only beats at a rate that is being read
  (`BeatingHeart`); with no live reading it is still.
- **Type.** Titles and figures are Barlow Condensed (SIL Open Font License 1.1; the fonts and their
  licence are in `LumaKit/Fonts`); labels and running text are the system face and follow the text size
  set in Settings, within limits the layouts hold at. A widget does not follow it. A missing font is
  not an error: the text falls back to the system face.
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
| `gallery-intel` | The same on an Intel runner with the previous Xcode, for days with no arm64 macOS runner to be had. Runs when the commit message contains `[intel]`; pictures land on `screens-intel`. |
| `app` | The whole app compiles (Debug, simulator) and runs over seeded strap-layer data; screens in `Tools/luma_screens_app.txt` land on `screens-app`. Runs when the commit message contains `[app]`, or `[app-intel]` to build it on the Intel runner. |
| `package` | A dry run of the release: Release device build and sideload packaging, nothing published. Runs with `app`, on the same runner. |

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
- **A cancelled macOS job is not a failed build.** When GitHub is short of macOS runners, a job that
  no runner takes within fifteen minutes is cancelled ("The job was not acquired by Runner of type
  hosted"), and the run reads as failed although nothing was compiled. Read the job's annotation
  before reading its log. Both workflows ask again by themselves: their last job (`again`) runs after
  every run, reads the list of jobs, finds those cancelled with that annotation and starts the
  workflow once more for just those (up to eight times in development, twelve for the release). It
  reads the list itself because the result a job is handed for such a job is `abandoned`, which a
  condition on `cancelled` or `failure` does not match. For the release each asking is a new run, so its build number moves on and a
  number that never built is skipped. A job cancelled for any other reason is left alone. The fewer
  macOS jobs a push asks for, the sooner one gets a runner: leave `[app]` off until the gallery is
  green. `[intel]` asks an Intel runner for the gallery as well.
- **The Intel runner is the way round a shortage of arm64 ones.** Its image defaults to an Xcode too
  old for the app and carries Xcode 26 beside it; `Tools/luma_xcode.sh` selects that, and changes
  nothing on a runner that already defaults to Xcode 26. A build for the phone is the same arm64
  product whichever machine compiles it. Each time no runner took the app, the package or the release,
  `again` asks for it on the other kind of runner (arm64, then Intel, then arm64). A release build
  that fails on the Intel runner for a reason of its own is asked for once more on arm64, and Intel is
  not gone back to. The Intel runner is several times slower (about half an hour for the Release
  build against ten minutes), so it is never where a push starts.

None of this exercises a strap. Pairing, sync, buzzes, the double tap, live recording and the Lock
Screen card's real cadence have to be checked on a phone with a strap, as do Health access under a
sideload signature and a real coach request. Reading workouts from photos is a coach request: the
gallery has no coach, so it opens the checking step on a read made up for it (`sheet.workouts.review`,
and `sheet.workouts.hand` for a workout typed in by hand),
and how well real boards and screens are read is only known from a phone. The weekly review is a coach
request too; the gallery shows one worded from the demo week's own figures.

Only a phone shows how the companion's widget really behaves: how promptly iOS draws each entry of its
timeline on the Lock Screen, whether the tap is answered within a second, and what it costs the
widget's refresh budget. The gallery draws the same views still (`dev.buddy`, `dev.buddy.builds`).
Notifications, Siri phrases and the widget's water button are likewise only exercised on a phone. A change is not verified on hardware until someone says
what they tried.

Still to be confirmed on a strap: that recording all the time keeps the app receiving heart rate through
a whole night in the background, what it costs the strap's battery, and whether a given WHOOP 5.0 or MG
hands over any stored record or movement data. **Settings, Data check** is the instrument for this: it
shows the minutes of heart rate that reached the phone in each of the last 24 hours, the holes, the
nights and days as stored, and the strap layer's own sync state, and sends all of it as plain text.
The gallery's `partial` data (`-lumaData partial`) stages the case this was built from: asleep at 01:00,
the record stopping at 02:00.
