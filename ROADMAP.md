# Mycelio TD: the roadmap to a polished release

What stands between the game as it is (see `PLAN.md` for what is in) and a
release that looks and plays like a premium one, on **mobile (Android, then
iOS)** and **desktop (Windows, macOS, Linux / Steam Deck)**. `PLAN.md` stays
the list of content against `DESIGN.md`; this file is everything around it.

Each item says which platforms it is for: **[M]** mobile, **[D]** desktop,
**[M/D]** both. Phases go in order; inside a phase, the order is the priority.

---

## Phase 0: don't lose the player's progress (do first, small)

- [ ] **[M/D] Atomic saves.** `src/profile.lua` writes `save.txt` in place with
  `love.filesystem.write`; a crash, a dead battery or the OS killing the app
  mid-write leaves it empty or cut short. Write `save.tmp`, then rename it over
  `save.txt`, and keep the last good one as `save.bak` to fall back to when the
  file does not read.
- [ ] **[M/D] A save version.** A `version N` line at the top, and a migration
  per bump, so later changes (new nodes, renamed ids) never quietly drop what a
  player had.
- [ ] **[M] Resume a run.** On a phone the OS kills a backgrounded app freely: a
  call or a message in the middle of wave 12 now loses the run. Save the run's
  state on `love.visible(false)` / `love.focus(false)` and between waves, and
  offer CONTINUE on the home screen. (On desktop it is a nicety: quitting mid-run
  then picks up where it was.)
- [ ] **[M] The Android back button** goes back a screen everywhere, opens the
  pause menu in a run, and asks before leaving the game from the home screen.
- [ ] **[M/D] Crash reporting.** A `love.errorhandler` that writes the error and
  stack to `crash.txt` in the save directory and shows a friendly screen with a
  way to send it (mail link or copy to clipboard), instead of LÖVE's blue screen.
- [ ] Fix the stale comment in `.github/workflows/android.yml`: it says conf.lua
  turns the audio modules off, and it turns them on.

## Phase 1: the first ten minutes (onboarding)

The game has a lot to learn (links, cutting, pruning, regrowing, pocket
richness, Fairy Rings, the Spore Pulse, Brine, mutations, weather, the loadout,
a network of about 100 nodes, seeds). Today the only teacher is the one-line
hint at the bottom (`hint()` in `src/ui/hud.lua`).

- [ ] **[M/D] A guided first level.** The Crack's first waves as a tutorial:
  the game pauses, points (a hand on mobile, a cursor on desktop) and waits for
  the player to do the one thing: grow a link, plant a puffer, start the wave,
  see a link cut, regrow it, prune one. Skippable, and replayable from settings.
- [ ] **[M/D] One idea per level.** Each new mechanic gets its moment the first
  time it matters (rings on the Rotting Log, flooding on the Pond Edge, night,
  the pulse), not all at once.
- [ ] **[M/D] First-meeting cards.** The first time an enemy, a boss or a weather
  shows, a short card with its picture and the encyclopedia's text, and what
  answers it. Once each, kept in the save, with an off switch.
- [ ] **[M/D] The network's first visit** points at the cheapest useful node and
  says what spores are and where they come from.
- [ ] **[M] Touch-first wording and gestures.** Every hint written for the
  finger on mobile (most already are through `say`); check that every action has
  a touch path with no keyboard-only shortcut behind it.

## Phase 2: menus and settings players expect

- [ ] **[M/D] A pause menu.** Today a pause shows only "PAUSED"
  (`src/ui/hud.lua`). RESUME, RESTART, SETTINGS, ENCYCLOPEDIA, QUIT TO MENU,
  with a confirm on anything that loses the run. On mobile, opening it is the
  top bar (as now) and the back button; it also opens by itself when the app
  goes to the background.
- [ ] **[M/D] Settings, in sections.**
  - Audio: music, effects and ambience as three separate sliders (today one
    LOUD / QUIET / OFF), and mute when in the background.
  - Gameplay: the speed a wave starts at, auto-start the next wave, confirm
    before selling, show the damage numbers / range circles.
  - Comfort: screen shake on / off, reduce motion (the screen slides, the
    flashes), a colour-blind mode (bosses red, seed mutations green, lit and
    cut links: add a shape or a pattern, not just a colour), text size.
  - **[D]** Display: fullscreen / window / borderless, resolution, vsync, frame
    cap; key remapping.
  - **[M]** Display: haptics on / off, battery saver (30 fps, fewer particles),
    left-handed layout (the toolbar and panel mirrored).
  - Language (see Phase 5).
- [ ] **[M/D] Credits** and a version number on the title.
- [ ] **[M/D] An ending.** Winning the Lawn deserves its own moment (the
  sprout grown, the mycelium under the whole garden, the credits), before
  challenge mode opens.

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
- [ ] **[M] Haptics.** Short buzzes for a tower planted, a link cut, a boss
  arriving, the sprout hit (`love.system.vibrate`), behind the setting.

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

## Phase 7: content and balance (from `PLAN.md`)

- [ ] The Compost Heap (level 7) with Green Mold.
- [ ] Elite modifiers (Fungicidal, Scent-masked, Armored shell, Hive-minded).
- [ ] Colony traits.
- [ ] Props and new pocket kinds, if the tileset gets tiles for them.
- [ ] **Balance by hand**, again: PLAN's figures are from before the loadout,
  three bosses a level and the newer enemies. Then the bot's campaign
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
2. The guided first level and the pause menu: what every new player sees.
3. Music and the settings: what reviews mention first.
4. Performance on a low-end phone, then iOS and the stores.
