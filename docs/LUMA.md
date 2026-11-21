# Luma

Luma is this fork's iPhone app: its own interface, analysis, food log, session modes and coach,
running over the strap layer the repository is built on (Bluetooth, on-device storage, and the
recovery, strain and sleep scoring). The strap layer is unchanged and stays in step with upstream;
everything described here sits beside it. [`AGENTS.md`](../AGENTS.md) still governs the strap layer.

## Layout

| Path | What lives here |
|---|---|
| `Packages/LumaCore` | Pure Foundation, no UI, builds and tests on Linux. Models, analysis (recovery, sleep, load, running, fitness, race readiness), the training log with its muscle model and progress read, the body figure's outlines, the food and supplement model, session state machines, and the coach's wire format and tools. |
| `Packages/LumaUI`, target `LumaKit` | Design tokens (colour, type, motion), the bundled fonts, primitives, the glance snapshot, the queue for things logged from outside the app, the companion's drawing (Glimm: `GlimmArt`, `GlimmSpec`, `GlimmRig`, `GlimmFigure`), and the views for widgets and the Lock Screen card. No dependencies, so the widget extension links it alone. |
| `Packages/LumaUI`, target `LumaUI` | Every screen, the charts, the environment object (`LumaEnv`), the session controllers and the coach engine. Depends on `LumaCore` and re-exports `LumaKit`. |
| `LumaGallery/` | A small host app that mounts `LumaUI` over demo data. Used only to build and photograph the screens quickly. |
| `StrandiOS/Luma/` | The bridge between Luma and the strap layer: `LumaRepoSource` (reads), `LumaBridge` (strap control, live state, widgets, Lock Screen card), `LumaWorkoutRecorder`, `LumaKeychain`, and `LumaShell`, which the app mounts as its root. |
| `StrandiOSWidgets/LumaWidgets.swift` | The widget bundle and the Live Activity, drawn with `LumaKit` views. |
| `Tools/glimm/` | Glimm described (`spec.js`), a reference renderer that draws that description in a headless browser (`render.js`, `shots.mjs`), and the step that carries it into the app (`build.mjs`). |
| `StrandiOSShared/LumaQuickIntents.swift` | Luma's App Intents (log water, tick supplements, log a weigh-in, the tap on the companion), compiled into the app and the widget extension. |

`LumaUI` knows nothing about Bluetooth, the database or HealthKit. It sees four protocols and the
bridge implements them:

- `LumaDataSource`: days, nights, sessions, heart-rate and HRV series, routes, stress, how far the
  recovery baseline has got, and the plain facts behind the data check.
- `LumaDeviceControl`: pair, sync, buzz and cue, live heart rate, being on screen, Health access, battery
  alerts, the wake alarm, heart rate for gym equipment, and the recording of raw motion.
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
- **An earlier effort is raced by the same sums as the target.** `RacePace.lead` gives the seconds
  ahead of any set of segment times, the prediction's targets or the last effort of the same shape
  (`RaceGhost`), worked out from the plan and the clock each time, so undoing a changeover undoes it
  in both. An effort is raced only when it is the same kind of session in the same format with every
  planned segment timed: one that was ended early has nothing to race past the point it stopped.
- **An official race is a session like any other.** A race run elsewhere is typed in from its results
  page, or read from a picture of it and then checked (`RaceEntry`, `CoachTools.raceEntry`), and kept
  as an `HXSession` with its `event` named: a full race in its format, every segment timed, the
  roxzone shared evenly over its transitions because a results page gives only their total. So the
  bests, the prediction, the comparison and the coach read it as they read a simulation. It is kept
  only when it adds up (`RaceEntry.problems`): sixteen times within what a kilometre and a station
  can take, and the splits within three seconds of the finish time when both are given. A time the
  reading did not get is left empty for the athlete to type, never worked out. Taking a session
  away, or correcting a race, works the bests out afresh from the sessions still kept
  (`Benchmarks.rebuilt`): a best does not outlive the session it came from.
- **Two efforts are set side by side only when they are the same shape** (`RaceComparison`): the same
  kind of session in the same format, runs by their order, stations by station, the roxzone as one
  line. Each line is what it took then and the difference; this effort's own times are in the cards
  above it and are not written again. The picture that is sent (`RaceShareCard`) is drawn from the
  report its screen shows, and leaves the phone only through the share sheet the athlete opens.
- **The companion has one set of rules, and no figures of its own.** Its state is resolved in one
  place (`Buddy.look`) from facts every one of which some screen already shows (`LumaEnv.buddyFacts`
  reads them from where that screen does), in a fixed order: what is happening now, then how the body
  is, then what the logs are missing. The app writes every state from now until the morning after next
  into the glance (`Buddy.schedule`); a widget only looks up the moment that has begun
  (`BuddyTimeline`), so the Lock Screen cannot say something the app does not. On Today, where the
  recovery figure and the call already stand, a state that only repeats them is given by name alone.
  A change that follows the clock begins on the minute its own line names (winding down 45 minutes
  before lights-out, asleep at the usual bedtime). Bed and wake times are averages and seldom fall on
  a whole minute, so the rule and the schedule both read them rounded as the lines print them
  (`Buddy.onTheMinute`), and the clock is read to the second.
- **Glimm is described once and drawn from that description.** The companion's body, its clothes, the
  pose of each mood and every small thing it does are data (`Tools/glimm/spec.js`), carried into the
  app as `GlimmArt` and read by `GlimmSpec`. `GlimmRig` turns a mood and a moment into a flat list of
  parts, each a shape at a place and an angle; the app draws them on a canvas for every frame, and a
  widget is given them as a stack of shapes, so a change of pose is a change of position and angle
  that iOS can animate between two entries. `Tools/glimm/render.js` does the same in JavaScript,
  function for function, which is how a change to the art or the motion is looked at in seconds
  (`node Tools/glimm/shots.mjs moods`) before it is built. A change goes into `spec.js`, then
  `node Tools/glimm/build.mjs`; `Tools/test_glimm_spec.py` fails when the two have drifted, when the
  wardrobe offers a cut the drawing cannot draw, or when a mood exists on one side only. The
  character is the athlete's own design. No third-party artwork.
- **Glimm's state is the facts'; its clothes, its words and its taste are its own.** The state still
  comes from `Buddy.look`. What it wears for that state is Glimm's pick and nobody else's: there is
  no wardrobe screen, no button that changes, rates or holds an outfit, and no way to dress it by
  hand. The pick is made in one place (`LumaEnv.glimmOutfit`, from `GlimmState.outfit`), and is
  fixed by the day, the setting, how the day feels and how often it has changed its mind, so the
  app, the widgets and the Lock Screen card show the same clothes and a day keeps its look. The
  wardrobe is 64 cuts in 16 colours, every top in 6 patterns (`GlimmWardrobe`, 2,944 pieces), and is
  never listed on a screen.
- **Its clothes say nothing about the day that is not so.** Party clothes, a chef's coat and night
  clothes are worn on their own occasion and on no other day, and always then
  (`GlimmStylist.occasions`): a medal on an ordinary morning would read as a new best. For any other
  setting a piece made for it is taken outright a little under half the time and leant towards the
  rest (`GlimmStylist.dressing`), so it mostly looks dressed for what it is doing and not always the
  same. Nothing made for sun is worn on a cold or a wet day or in the cold months, and nothing made
  for cold on a sunny day or in the warm ones. When it gives the setting as its reason, something it
  has on was made for that setting.
- **Its taste is not set by anyone.** What pulls it towards a piece (`GlimmStylist.score`): the
  setting the state asks for; what it has always liked (`GlimmNature`, a fixed table: its hoodies,
  its trainers, its colours); the colour it is into for a run of nine days, which the calendar alone
  picks (`GlimmStylist.phase`); how the day feels, louder on a charged day and gentler on a drained
  one, by the recovery ring's own bands (`GlimmFeel`, set in `glimmKeepUp` from the same score); a
  top worn lately counts against itself; and one pick in seven ignores all of it. Two things are
  learnt, both from what happened and neither from a control: something kind said about its clothes
  in a chat makes it fonder of each piece (`GlimmState.enjoyed`), and the top it trained in on the
  day of a new best becomes its lucky one, worn to train in on some days from then on
  (`GlimmState.noteBest`). It says why it picked what it has on (`GlimmState.why`, one reason from
  those that hold, the same all day). Glimm has no way to know the weather, and on the days the
  season dresses it for rain or cold its lines claim neither.
- **Glimm's own words carry no figures.** Its lines (`GlimmVoice`) are written into the app and say
  nothing the data would have to back; a test fails on a line with a digit in it. The figure behind
  a state is the fact line beside it (`BuddyLook.line`). No line guilts, none claims Glimm watched
  while the app was closed, and none makes its affection depend on anything.
- **A chat with Glimm is the athlete's own key, a few shared facts, and a checked answer.** The model
  the coach is set to is given who Glimm is (`GlimmChat.system`), the message, and at most ten facts
  the app chooses (`GlimmChat.facts`); the reason for its state carries health figures, so it goes
  only while "Share my health data with the coach" is on. What comes back is used only after
  `GlimmChat.parse` has checked it: words of a length it can say, a mood it has, a setting to dress
  for and a colour only from the lists the app holds, and whether its clothes were admired. A
  change of clothes in a chat is its own decision: it is told that a suggestion is its call to take
  up or to turn down. Nothing else in a reply is acted on.
- **Glimm remembers only what it was told to.** A reply may suggest one thing to keep; it is kept
  only on a yes, and what was written in by hand or agreed to is listed on its screen and can be
  taken out (`GlimmState.remember`). It stays in `glimm.json`, in the vault with the other records.
- **A widget moves only as iOS lets it.** A widget is a list of dated pictures. The companion's are
  its changes of state, one of the mood's stills every five minutes (`BuddyTimeline.beats`), and the
  two steps of its answer straight after a tap (`PokeBuddyIntent`). The Lock Screen card stands it in
  the next still as readings arrive (`LumaLiveState.glimmBeat`). Continuous motion is in the app
  only. A still pose must always be a truthful one: there is no frame that would look wrong if the
  next one came late. The glance is rebuilt when its clothes change and not when it says a line
  (`GlimmState.dressesAs`), so a tap in the app spends none of the widgets' updates.
- **Luma Doctor reads a week against the athlete's own range, and is not a doctor.** From Sunday
  00:00 it checks the week that ended the day before, at the first chance the app has to run
  (`DoctorSchedule.due`), and keeps the result in a log (`doctor.json`). Each overnight reading is
  held against the athlete's own range, and a night is judged by the rule the daily read applies
  (`BodyWatch.assess`), so the weekly and the daily check cannot disagree about a night. A reading
  with too little history says so and is not called steady. The check itself runs on the phone. A
  written read of it is asked of the most capable model the key reaches (`AIModel.byStrength`, from
  the line the Models API reports), whatever model the coach is set to, and only with leave to share
  health data. The screens say what moved and by how much; they name no illness, and say when
  something is worth showing to a doctor.
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
- **A record that could not be read is not an empty one.** What the athlete logs (their details,
  food, training, weigh-ins, the coach's conversation) is kept by `LumaVault` (LumaCore) as small
  files under `Application Support/HYROXLab/`. The strap starts the app in the background, often
  while the phone is locked, and a locked phone refuses to open files of the default class. Taking
  such a file for an empty one ended with the first-run screens shown to someone already set up and
  the real file saved over. So every read ends in one of five states (`VaultRead`): read, nothing
  saved yet, could not be read (`blocked`), could not be understood with a copy standing in, or with
  none. While any store is `blocked`, `LumaEnv.storesReady` is false: the app shows a holding screen
  in place of its interface, saves nothing (the vault refuses a store it has not read), writes no
  glance for the widgets, plans no reminder, and offers no setup. It reads again when iOS says the
  files are open, when the app comes to the front, and every second and a half while the holding
  screen is up. The files are also given the class that stays readable after the first unlock
  (`protect`), which a locked phone will not allow, so it is asked for at every read. A file that
  cannot be read with the phone unlocked can be moved aside (never deleted) from the holding screen.
- **One bad save is not the only copy.** Under `Backups/` the vault keeps a set for each of the last
  fourteen days a store was saved. A day's set is every store as it stood at the end of that day, not
  only what was saved on it: the first save of a day fills in the last day's set before changing
  anything. A save that would leave under half of a file keeps the file as a set of its own, and what
  is there before the first copy is kept as found. **Settings, Copies of your records** goes back to
  a set; what is there is kept first, so going back can be undone. A store a set does not hold is left
  as it is: nothing is deleted by going back. The vault logs what happens to the records in its own
  marker file, and the data check shows the log.
- **A row is reached by its id.** `ForEach($items)` hands each row a binding by position, and removing
  a row while a view still holds its binding asks for a position that is gone, which stops the app.
  Lists that can lose a row use `Binding.element(_:)`, which answers with the element as it last was.
- **A whole number is made with `LNum.int`** (`whole` in `LumaKit`), never `Int(x)` on a figure that
  was measured or divided: `Int` of a figure that is not a number stops the app, and one bad reading
  can make a figure that.
- **The whole of a control takes the tap.** A plain button around an icon in a frame is only as wide
  as the icon's glyph unless it is given a shape (`contentShape`); a minus sign is two points tall.
  Steppers use `LumaStepButton`, which also goes on stepping while held.
- **A field being typed in is above the keyboard, and nothing of Luma's sits on it.** SwiftUI moves a
  page or a sheet out of the keyboard's way by itself. The tab bar floats over the pages, so it rose
  with the keyboard and sat on top of the coach's box and of any field on a tab's page: it is now held
  at the foot of the screen and is out of sight while a keyboard is up (`LumaRootView`). Two checks
  stay behind SwiftUI. `lumaKeyboardRoom` reads where a page's foot really lies on the screen once
  SwiftUI has had its turn and adds whatever the keyboard still covers; it does not work that out from
  heights before and after, because the two hear of the keyboard in no fixed order and a "before"
  taken late doubles the move. And `LumaKeyboard` scrolls the field being typed in into view if it is
  still hidden. Where SwiftUI has done the whole job both come to nothing.
- **A set counts what the movement is counted in.** A lift counts reps at a load; a SkiErg, a rower,
  a bike, a run or a carry counts metres, time or calories (`ExerciseInfo.counts`,
  `LiftExercise.measure`). A movement with no load is never asked for a weight, and one read with
  nothing counted is asked for its amount in its own measure. What is typed is read by `AmountText`.
- **What iOS says about a stop is kept on the phone.** `LumaCrashLog` keeps what MetricKit delivers
  (a crash or a freeze with its frames, and the day's count of how the app was ended) for the data
  check. It is sent nowhere; the athlete can send the report.
- **The upstream credit stays.** About carries the open-source licence credit the licence requires.
- **What the earlier shell did on its own is not left running.** Its first-run screens, update check,
  coach and banners are marked settled, and automations with no Luma screen (reminders, haptic nudges,
  a wake time of its own for one weekday) are switched off at launch and named to the athlete once
  (`LumaBridge`).
- **The wake alarm has one time and one reading.** The alarm is the strap layer's: Luma stores it
  where that layer keeps it and has that layer act on it (`AppModel.applySmartAlarm`), and sends no
  command of its own. Every sentence about it is drawn from one value (`LumaAlarmState`, worked out in
  `LumaBridge.refreshAlarm`), whose next time comes from the function the strap layer itself sets the
  strap and plans the notification from (`AppModel.nextSmartAlarmDate`). The screen states what the
  app did, not what the strap will do: the strap is "told" only on the strap layer's own record of
  its last send (that time, to this strap, over a link that could carry it); otherwise it is waiting
  to be told, or not asked. A time is shown as a promise only when something is set to happen at it
  (`willGoOff`), and a strap still waiting does not count. The phone's part is one notification, and
  the screen says that a Focus can silence it. A time being picked is stored at once and passed to
  the strap once it has settled, so the strap is not written to for every turn of the wheel.
- **On a WHOOP 5.0 or MG the strap's own alarm is a trial, behind its own switch.** That switch is
  the strap layer's `PuffinExperiment.isEnabled`, whose one effect in this tree is to let
  `BLEManager.armStrapAlarm` send the wake time to such a strap. A second reader of that flag,
  arriving with a merge from upstream, would ride on a consent given for the alarm alone: check for
  one at every merge. Switching the trial off takes the strap's alarm off. A stop the strap could not
  be reached for is said on the screen (`strapOwesStop`) and sent when the strap is next reachable.
- **A cue is felt, so there are few of them** (`StrapCue`): one for breathe in; two for a change
  inside a session, go again, back in the zone, and breathe out; three for ease off. They are the
  strap layer's cue buzz with its count (`AppModel.buzz(loops:)`). On a 5.0 or MG the count is the
  number of buzzes, on a 4.0 the length of one, and the wording on screen follows the strap
  (`LumaStrap.cueText`). The zone guard (`ZoneGuard`) speaks after eight seconds above the zone and
  once more when heart rate is back under it by a margin, and never in an interval session; go-again
  (`GoAgain`) ends a rest when heart rate has come down, never under 15 seconds and never over three
  minutes. Both are off until switched on.
- **Breathing figures are read within one sitting only** (`BreathPace`, `LiveHRV`). Beat-to-beat
  variation is worked out over the last minute, from intervals each passed on once
  (`LumaBridge.takeBeats`, keyed on the strap layer's packet count as that layer requires). A sitting
  sets its first minute against its last, is never compared across days, and is not a medical reading.
- **Heart rate is on the air only while Luma is on screen or recording a session**
  (`LumaBridge.applyBroadcast`), through the strap layer's `HrBroadcaster`, which passes on the heart
  rate the app already has and writes nothing to the strap. It is off until switched on, and the app
  carries the `bluetooth-peripheral` background mode for this alone.
- **Raw motion is recorded, not read.** With its switch on, a session records the strap's raw motion
  through the strap layer's collector (its start and stop commands, its files), with a mark where each
  part of the session starts (`LumaBridge.startMotion`, `markMotion`). Nothing is worked out from it
  yet: counting reps or strokes waits for recordings to check a method against, as `AGENTS.md`
  requires of any signal derived from raw sensor data. A recording stays on the phone until it is
  shared as a file or deleted.
- **A led workout is read, shown, then led** (`GuidedWorkout`, `GuidedReading`). A workout that was
  typed or photographed is read into blocks of steps through a tool with a fixed shape, shown for
  checking, and can be started only when it has no problems (`GuidedWorkout.problems`). It is recorded
  like any other session.
- **A trend says what it is made of, and stays quiet without enough of it.** HRV is the week's mean
  of the logarithm of the nightly values, set against the athlete's own band (the sixty-day mean, give
  or take half the day-to-day spread), with its count of nights and no verdict on a week of fewer than
  three (`HRVTrendModel`). A rise in resting heart rate is a
  running sum of nights above the usual, capped for each night so that one bad night is not read as a
  rise, and raised only with three nights above and last night among them (`RestingDriftModel`). Sleep
  regularity is the share of the day spent in the same state, asleep or awake, as 24 hours earlier
  (`SleepRegularityModel`). Load is the week against the athlete's own usual week
  (`LoadState.weekShare`); the acute-to-chronic ratio is not shown as a warning. Sleep stages from the
  wrist are labelled a rough guide and are no part of Luma's sleep score (`SleepModel.composite`).
- **What is said about running comes from the runs** (`RunDepth.swift`). Heart rate at the athlete's
  own easy pace is read only from steady stretches (`EasyPace`). Critical speed is fitted to the
  fastest efforts found inside the runs of the last sixteen weeks (`CriticalSpeedEfforts`) and
  resolved once for the screens and the coach (`LumaEnv.criticalSpeed`). Durability is heart rate for
  the same speed late in a HYROX session against early in it (`Durability`), and the time shares are
  the session's own segments beside the shares in published results (`TimeSharesModel`).
- **The coach's extras are each a switch or a fallback.** Searching the web is off until switched on,
  has no cap, lists what it found under the answer, and is told to keep the athlete out of the search
  words (`CoachPrompt.webSearch`). Sums are done by a tool, not by the model (`CoachCalc`). When a
  request is refused over a feature the model does not take (a fixed tool shape, effort, a fixed
  answer shape), it is sent again without that feature, which is then left out for the rest of the
  run (`CoachEngine.refused`).
- **Glimm writes its day once, and learns only what it may** (`GlimmDaily`, `LumaEnv.glimmWriteDay`).
  Once a day its lines are written from what the day holds, on the athlete's own key; without a key,
  a connection or the switch it speaks from its fixed lines. Its own notebook is added to, and sent
  back with a chat, only while learning and the sharing of health data are both on; it holds a fixed
  number of lines and each can be read and taken out (`GlimmNotebook`). What it is told is kept only
  once confirmed. A small job it offers (logging water, opening a screen) is done only on a tap
  (`glimmPerform`). Speech is turned into words on the phone or not at all (`GlimmEars`).
- **A newer build is looked for only when that is switched on** (`NewBuild`,
  `LumaEnv.lookForNewerBuild`): one read of the public listing a day, with nothing about the athlete
  sent. It is off until switched on, and offered once on Today.
- **None of the strap features above has been felt on a wrist from the working environment.** Cues,
  the alarm, sharing heart rate and motion recording are built on the strap layer's own calls and
  compile; what they do on a strap is known only once it has been tried on one.
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
  workflow once more for just those (once in development, up to twelve times for the release). It
  reads the list itself because the result a job is handed for such a job is `abandoned`, which a
  condition on `cancelled` or `failure` does not match. For the release each asking is a new run, so its build number moves on and a
  number that never built is skipped. A job cancelled for any other reason is left alone. The fewer
  macOS jobs a push asks for, the sooner one gets a runner: leave `[app]` off until the gallery is
  green. `[intel]` asks an Intel runner for the gallery as well.
- **The Intel runner is the way round a shortage of arm64 ones.** Its image defaults to an Xcode too
  old for the app and carries Xcode 26 beside it; `Tools/luma_xcode.sh` selects that, and changes
  nothing on a runner that already defaults to Xcode 26. A build for the phone is the same arm64
  product whichever machine compiles it. Each time no runner took a gallery, the app, the package or
  the release, `again` asks for it on the other kind of runner (arm64, then Intel, then arm64). A release build
  that fails on the Intel runner for a reason of its own is asked for once more on arm64, and Intel is
  not gone back to. The Intel runner is several times slower (about half an hour for the Release
  build against ten minutes), so it is never where a push starts.

None of this exercises a strap. Pairing, sync, buzzes, the double tap, live recording and the Lock
Screen card's real cadence have to be checked on a phone with a strap, as do Health access under a
sideload signature and a real coach request. Reading workouts from photos is a coach request: the
gallery has no coach, so it opens the checking step on a read made up for it (`sheet.workouts.review`,
and `sheet.workouts.hand` for a workout typed in by hand),
and how well real boards and screens are read is only known from a phone. Reading a results page is
one as well: the gallery opens the form on a race made up for it (`sheet.race.filled`, and
`sheet.race.check` for one that does not add up yet), and whether a real page is read right is only
known from a phone. The weekly review is a coach request too; the gallery shows one worded from the
demo week's own figures.

Only a phone shows how the companion's widget really behaves: how promptly iOS draws each entry of its
timeline on the Lock Screen, whether the tap is answered within a second, and what it costs the
widget's refresh budget. The gallery draws the same views still (`dev.buddy`), every mood both ways a figure
is drawn (`dev.glimm`), every cut in the wardrobe (`dev.glimm.wear`) and frames of its motion at fixed
moments (`dev.glimm.motion`). How it moves, and how it answers a touch, is only seen on a phone.
Notifications, Siri phrases and the widget's water button are likewise only exercised on a phone. A change is not verified on hardware until someone says
what they tried.

The gallery also photographs screens as they are while being typed in: a list line can name a field
that takes the keyboard as the screen opens and text already in the coach's box
(`name|screen|scroll|data|wait|focus|draft`), and `Tools/luma_screens.sh` makes the simulator show its
on-screen keyboard. `-lumaData locked` and `stuck` stage the holding screen. What the gallery cannot
show is the thing the holding screen is for: an app started by the strap while the phone is locked.
That is only seen on a phone, in **Settings, Data check**, under "Record log".

Still to be confirmed on a strap: that recording all the time keeps the app receiving heart rate through
a whole night in the background, what it costs the strap's battery, and whether a given WHOOP 5.0 or MG
hands over any stored record or movement data. **Settings, Data check** is the instrument for this: it
shows the minutes of heart rate that reached the phone in each of the last 24 hours, the holes, the
nights and days as stored, and the strap layer's own sync state, and sends all of it as plain text.
The gallery's `partial` data (`-lumaData partial`) stages the case this was built from: asleep at 01:00,
the record stopping at 02:00.
