# Mycelio TD: the roadmap to a polished release

What stands between the game as it is (see `README.md` for what is in) and a
release that looks and plays like a premium one, on **mobile (Android, then
iOS)** and **desktop (Windows, macOS, Linux / Steam Deck)**: the content still
to come from `DESIGN.md` (Phase 7), and everything around it.

Each item says which platforms it is for: **[M]** mobile, **[D]** desktop,
**[M/D]** both. Phases go in order; inside a phase, the order is the priority.

---

## Phase 0: don't lose the player's progress (do first, small)

- [x] **[M/D] Atomic saves.** `save.txt` ends on an `end` line, so one cut
  short is caught; the last good save is kept as `save.bak`, the new one
  written to `save.tmp` and then over `save.txt`, and loading takes the first
  of the three that reads whole. (No rename: `love.filesystem` has none, and
  three writes leave a whole copy at every moment without it.)
- [x] **[M/D] A save version.** `version 3`, and a step in `MIGRATE`
  (`src/profile.lua`) per bump, saved at once. A save from a newer version is
  read for what this one knows, and kept as `save.v<N>.txt` first.
- [x] **[M] Resume a run.** `src/resume.lua` keeps the whole run in `run.txt`
  at each build phase, on `love.focus(false)` / `love.visible(false)` and on
  quitting, and lets it go on a win or a loss; CONTINUE on the home screen
  picks it up (paused, if in the middle of a wave). A run read back plays on
  exactly as it would have (`tests/resume_test.lua`). A change to the shape of
  a run's tables wants `R.VERSION` bumped: a run kept before is then let go
  rather than misread.
- [x] **[M] The Android back button** (Esc to LÖVE) goes back a screen
  everywhere, opens the pause menu in a run, and from the home or
  title screen asks first: back again within two seconds leaves the game.
- [x] **[M/D] Crash reporting.** `src/crash.lua`: the error, the stack and the
  device to `crash.txt` in the save directory, and a screen in the game's
  colours with COPY REPORT and QUIT, instead of LÖVE's blue screen. Still to
  add: a mail link, once there is an address to send reports to.
- [x] Fix the stale comment in `.github/workflows/android.yml`: it says conf.lua
  turns the audio modules off, and it turns them on.

## Phase 1: the first ten minutes (onboarding)

The game has a lot to learn (links, cutting, pruning, regrowing, pocket
richness, Fairy Rings, the Spore Pulse, Brine, mutations, weather, the loadout,
a network of about 100 nodes, seeds). The guide (`src/ui/guide.lua`) now
teaches it, a thing at a time; what is left is to watch new players with it.

- [x] **[M/D] A guided first level.** A first run goes from the title straight
  into the Crack with only the Spore Puffer: the game pauses on a card, points
  (a hand on mobile, a cursor on desktop) and waits for the player to do the
  one thing: grow a link, plant a puffer, start the wave, regrow a cut link,
  prune one. Skippable, and replayable from settings.
- [x] **[M/D] One idea per level.** Each new mechanic gets its moment the first
  time it matters (a cut, the first mutation, rich and poor pockets, rings on
  the Rotting Log, low ground before rain, high ground on the Pond Edge, the Puddle's ford, the
  pulse once grown), not all at once. The weathers come one a level too: the
  Crack only rain, then night, drought and frost (`D.weathersOf`).
- [x] **[M/D] First-meeting cards.** The first time an enemy, a boss or a weather
  is forecast (or hatches), a short card with its picture, its text and what
  answers it. Once each, kept in the save (`taught`), with an off switch
  (SETTINGS: TIPS).
- [x] **[M/D] The network's first visit** points at the cheapest useful node and
  says what spores are and where they come from; a run over, a card first says
  what the bank holds and what is open on the network now.
- [x] **[M] Touch-first wording and gestures.** The guide's lines are written for
  the finger through `say`; prune and the pulse put down by their key as by
  their button. The Spore Pulse's button is only on the toolbar once grown.

## Phase 2: menus and settings players expect

- [x] **[M/D] A pause menu** (`src/ui/pause.lua`): RESUME, RESTART (asks
  first), SETTINGS, ENCYCLOPEDIA, QUIT TO MENU (the run kept for CONTINUE),
  over the run under a veil. Opened by `P` / `Esc`, the top bar and the back
  button on mobile, and by itself when the app goes to the background. The
  settings and the encyclopedia opened from it come back to it.
- [x] **[M/D] Settings, in sections** (`src/options.lua`, `src/ui/settings.lua`).
  - Audio: effects and ambience as sliders under the overall LOUD / QUIET /
    OFF, and mute in the background. The music slider comes with the music
    (Phase 3): there is nothing for it to turn down yet.
  - Gameplay: the speed a wave starts at, auto-start the next wave, confirm
    before clearing a tower or lifting a mat, range circles for every tower.
    Damage numbers come with them (Phase 4).
  - Comfort: screen shake on / off, reduce motion, a colour-blind mode (shapes
    on dead, cut and hurt links, BOSS and SEED in words), text size (the HUD a
    zoom step up).
  - **[D]** Display: fullscreen / window, the window's size, vsync, frame cap;
    key remapping for thirteen of a run's keys.
  - **[M]** Display: haptics on / off (and the first buzzes, see Phase 3),
    battery saver (30 fps, half the sparks and motes), left-handed layout.
  - Language: still to come with the translations (Phase 5).
- [x] **[M/D] Credits** (CREDITS on the home screen) and a version number on
  the title and the home screen (`src/version.lua`; the build workflows stamp
  the commit into `build.txt`). The credits still want the tileset's artist
  named.
- [x] **[M/D] An ending.** The Compost Heap, the last level now, won the first
  time: the sprout grows, the mycelium runs out under the whole garden to a
  node for every level, the credits roll, and then challenge mode's Hornet is
  named as open (`src/ui/ending.lua`). Seen again from the credits.

## Phase 3: sound and music

Everything is synthesised at load (`src/sfx.lua`), which is good; what is
missing is music.

- [ ] **[M/D] A score.** A title theme, a calm build-phase bed, a wave layer
  that builds as the wave goes, a boss theme, win and loss stings. Adaptive:
  layers fade in and out with the phase, the weather and the sprout's health.
  It can be synthesised like the rest or composed and shipped as `.ogg`
  (budget the download size on mobile).
- [ ] **[M/D] A mixing pass.** Every sound levelled against the others, a
  limiter on the master, priorities and voice limits so a big wave never
  clips or turns to mush, ducking under banners and bosses.
- [ ] **[M] Phone speakers.** Check the mix on a phone speaker (little bass,
  everything comes through the mids) as well as on headphones.
- [ ] **[M] Haptics.** The first are in, behind the setting (a tower grown, a
  link cut, a boss, the sprout hit, a win, a loss: `BUZZ` in
  `src/ui/audio.lua`); tune their lengths on a real phone.

## Phase 4: feel and presentation

The game already has hit sparks, stains, shock rings, flashes, banners and
shake. To go further:

- [ ] **[M/D] Juice on the big moments:** a short hit-stop on a boss phase
  change or death, the camera leaning to a boss as it comes in, a slow-motion
  last kill on a win, a sprout death with weight to it.
- [ ] **[M/D] Readability in a crowd:** damage numbers (setting), clear range
  previews before planting, the next wave's path lit before START, and the
  enemy health bars readable at the furthest zoom.
- [ ] **[M/D] UI transitions and states everywhere:** every button with
  pressed / hover / disabled looks, and nothing that pops in without a move.
- [ ] **[M] Thumb reach and sizes.** Every touch target at least about 9 mm
  (roughly 44 pt); the main actions in the bottom third; nothing that needs two
  hands on a phone held upright. Test on a small phone (5.5"), a big one, a
  foldable and a tablet.
- [ ] **[D] Hover and cursor.** Tooltips on hover for everything, a custom
  cursor that changes with the tool in hand, right-click menus where they help.
- [ ] **[D] Wide and big screens.** 21:9 and 32:9 without stretching or empty
  bars that look like a bug, and 4K with the pixel art kept sharp.

## Phase 5: reach (input, language, accessibility)

- [ ] **[D] Gamepad, and Steam Deck verified.** No joystick code exists yet. A
  cursor moved by the stick that snaps to pockets and nodes, a radial menu for
  the species, shoulder buttons for speed and turning the board, glyphs that
  match the pad. The Deck's screen (1280×800) and its touch screen both work.
- [ ] **[M/D] Translations.** Every player-facing line is written straight into
  the code (`say(...)`, `D.GLOSSARY`, `about`). Move them to a strings file per
  language, and give the font accented letters (and later other alphabets).
  Spanish first; then French, German, Portuguese (Brazil), and the store
  languages that sell best for the genre.
- [ ] **[M/D] Accessibility review** against the Game Accessibility Guidelines:
  the colour-blind mode, text size, no information carried by sound alone, a
  slower speed (×0.5) for anyone who needs it, and holds replaced by taps.

## Phase 6: performance and devices

The board is painted by the CPU, pixel by pixel.

- [ ] **[M] A low-end Android target.** Pick the oldest supported phone (say a
  4 GB, 2019-era device) and hold 60 fps there in the biggest endless wave;
  profile the painter and the effects, and drop to 30 fps cleanly when it can't.
- [ ] **[M] Battery and heat.** Measure an hour of play; cap the frame rate on
  menus and in the build phase, sleep the loops when nothing moves.
- [ ] **[M] Load time.** Rendering the sounds and the boards at start costs
  time: measure it on a slow phone, cache what can be cached to the save
  directory, and show a loading screen that is part of the game.
- [ ] **[M/D] Memory.** No growth over a long endless run (images made per
  remap in `src/ui/pixels.lua` are kept for good: bound them).
- [ ] **[M/D] A device matrix**, tested before every release: the phones and
  tablets above, iPhone with and without a notch, a low-end and a high-end PC, a
  Mac, Linux, the Deck.

## Phase 7: content and balance (the rest of `DESIGN.md`)

- [x] The Compost Heap with Green Mold, after the Puddle and the Old Stump
  (levels 7-9), with the Diving Beetle, Wireworm, Leafcutter Ant, the Dragonfly
  Nymph / Dragonfly, the Rhinoceros Beetle and the Hornet challenge.
- [ ] Balance the last three by hand: they are tuned only against the bot so far.
- [ ] Elite modifiers (Fungicidal, Scent-masked, Armored shell, Hive-minded).
- [ ] Colony traits.
- [ ] Props and new pocket kinds, if the tileset gets tiles for them.
- [ ] **Balance by hand**, again: the last figures (over 20 runs the bot won
  the Crack 18, the Flowerpot 17, the Rotting Log 16, the Shed Floor and the
  Pond Edge 15, the Lawn 12; the Stag Beetle usually got through, and challenge
  mode was rarely won) are from before the loadout, three bosses a level and
  the newer enemies. Then the bot's campaign
  (`B.campaign`) set to the new numbers.
- [ ] **Playtests with people.** Five to ten who have never seen it, on a phone
  and on a computer, watched and not helped: where they get stuck in the first
  ten minutes is the next thing to fix. Then a closed beta (Play Console
  internal testing, TestFlight, a Steam playtest).
- [ ] **[M/D] Daily or weekly challenge** (a fixed seed, a fixed loadout, a
  leaderboard): cheap to build on the seeded dice, and a reason to come back.

## Phase 8: platform builds

Today: Windows, macOS and Linux fused builds, unsigned, and an Android APK /
bundle (`.github/workflows/`).

- [ ] **[M] iOS.** A LÖVE for iOS build in CI (needs a macOS runner and an
  Apple Developer account), TestFlight first. Check the notch and home bar
  insets, the audio session (silent switch, other apps' music) and the app
  being killed in the background (Phase 0's resume).
- [ ] **[M] Android for the Play Store.** The signing secrets set (so the
  `.aab` is built), target the current API level, a 64-bit build, the size
  under the store's limit, and the data safety form filled in.
- [ ] **[D] Signed desktop builds.** A Windows code-signing certificate (no
  SmartScreen warning), a notarised macOS app (an Apple Developer ID), and the
  Linux AppImage left as it is.
- [ ] **[D] Steam.** Steamworks: achievements, cloud saves, the Deck's
  verification, a store page. (itch.io as well, with the same builds.)
- [ ] **[M/D] One name.** The save folder is `underfoot`, the app id
  `com.cmatute.groute`, the game Mycelio TD. Keep the ids that keep updates
  working, but make sure no player ever sees the old names, and that every
  old save carries over.

## Phase 9: store and launch

- [ ] **[M/D] Business model**, decided before the store pages: premium (one
  price, everything in it) fits the game best on desktop; on mobile, premium or
  a free demo (the first two levels) with one purchase to unlock the rest. No
  ads and no pay-to-win: the network is earned in play.
- [ ] **[M/D] Achievements** for the store's own systems (Game Center, Google
  Play Games, Steam): every level won, every boss, every seed, endless depths,
  challenge mode.
- [ ] **[M/D] Cross-device saves**, so a run started on the phone carries on at
  the computer (the platform's cloud save, or an exported save code).
- [ ] **[M/D] Store material:** a capsule / icon set per store, screenshots for
  every store's sizes (`--shots` can make them), a 30-60 s trailer, a press kit,
  a short description in every language shipped.
- [ ] **[M/D] Privacy policy and age rating** (IARC on Google Play, the App
  Store's own, PEGI / ESRB for consoles later).
- [ ] **[M/D] A plan after launch:** a way to hear from players (a Discord or a
  feedback button), and the first update planned before launch (the Compost
  Heap is a good one).

---

## In short: what to do first

1. Phase 0 (saves and resuming a run): small, and the worst thing that can
   happen to a player is losing their progress.
2. Music: what reviews mention first (the pause menu, the settings and the
   ending are in).
3. Performance on a low-end phone, then iOS and the stores.
