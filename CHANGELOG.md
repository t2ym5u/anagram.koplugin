# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

## [1.6.5] - 2026-11-09

### Fixed
- The game now starts in KOReader's language (French when KOReader is in
  French) instead of always English; a language picked in the game holds
  until KOReader's language changes.

## [1.6.4] - 2026-11-09

### Fixed
- The scrambled letters are never one of the answers any more. Only the
  drawn word was ruled out, so another answer could show as is (MATE drawn,
  MEAT shown), giving that row away in about 2 % of 4-letter puzzles.

## [1.6.3] - 2026-11-05

### Fixed
- "Lynch" and its forms are added to the family-friendly blocklist (English
  and French), so LYNCH is no longer drawn as an English word.

## [1.6.2] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.6.1] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.
- Uses less memory: the word lists load when the game opens, only for the
  language played, and are freed when it closes.

## [1.6.0] - 2026-11-03

### Changed
- No more repeated puzzles: the game remembers the words already played, per
  language, and draws a new one each time, whatever the length setting; a
  word only comes back once about 3,000 others have been played. A word's
  anagrams count as played too (after STABLE, no TABLES). The solo game and
  multiplayer matches share this memory.

## [1.5.0] - 2026-11-02

### Added
- A multiplayer mode, "Anagram · multiplayer" under Tools → Games → Party &
  quiz (or "Mode: Multiplayer" in the game's menu). The reader lies on the
  table and shows the scrambled letters big; the first player to shout a word
  using every letter wins it. "Answer" reveals every word the letters make
  (the drawn one and the rarer ones the dictionary knows), then one tap on the
  finder's name -- or Nobody -- gives the point.
- A word is worth its length minus 3 (4 letters = 1 point, 7 letters = 4), so
  with "Length: Random" a long word is worth more.
- Settings: players and their names (remembered), words per match (5 to 20),
  a timer per word (off, 30 s to 2 min: the answer shows by itself when time
  is up), Shuffle to mix the letters again. The match ends with the final
  scoreboard and "New game"; a match in progress is saved apart from the solo
  game and restored.
- Rules has two complete texts, solo and multiplayer: it opens the one of the
  mode being played, with a button to read the other.

### Changed
- Family-friendly words: `tools/blocklist_<lang>.txt` now covers vulgar,
  sexual, scatological, slur and drug-related words and their inflections,
  and the word data was rebuilt -- 25 English and 66 French words are no
  longer drawn, and the reveal no longer lists 21 English / 43 French
  blocked anagrams (e.g. NIGGER, TWAT, PISSER, FION).

## [1.4.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.4.0] - 2026-10-30

### Added
- One answer row per word the letters make: STABLE and TABLES give two rows,
  ARTISTE four. The round is won once every row is filled; the status shows
  "Words: 1/4". Any real word that uses all the letters fills a row -- a rare
  dictionary word counts too, but is never required.
- A "Give up" button: it shows the words you missed in the empty rows and
  counts a loss.

### Changed
- The letter tiles are at the bottom, next to the buttons and under the
  thumb; the answer rows read from the top, the one being filled framed in
  bold.
- A wrong answer no longer reveals the word and counts a loss: the letters go
  back to the tiles and you try again. A word already found is refused the
  same way. Only giving up counts as a loss. The rules say so.
- Once the round is over, the action bar shows "Next word" in place of
  Submit/Clear/Give up, and the letters stop moving.
- Redesigned play screen: tiles fill the room the controls leave, with
  letters fitted to and centred in their tile (a short word no longer gets
  tiles twice the size of a long one), and a full-width action bar (two rows
  in landscape). The status reads "Words: 1/4 · Wins: 3 · Losses: 1" and
  wraps in landscape.
- Title-bar menu: the language entry reads "Language: EN" instead of a bare
  "EN", and the length picker is titled "Length".

### Fixed
- The word lists no longer draw proper nouns or abbreviations (DAVID, USSR:
  1,312 English words dropped) nor vulgar words and slurs (a blocklist per
  language in `tools/`). `tools/build_words.py` cleans the lists against
  Boggle's Scrabble-valid dictionary and generates `answers_en.lua` /
  `answers_fr.lua`, the other words each puzzle accepts.

## [1.3.13] - 2026-10-07

### Fixed
- The Tools menu entry is translated again. `main.lua` took `_` from
  KOReader's `gettext`, which knows nothing of this plugin's strings, so the
  menu label stayed English while the game's own screen, which goes through
  `i18n`, was translated. `_` now comes from `i18n` here too.


## [1.3.12] - 2026-10-02

### Fixed
- `Word length` became `Word lengths`. `package.loaded` is keyed by module
  name alone, so every `require("i18n")` on the device resolves to one module
  and the first plugin loaded wins it. Every plugin's `i18n_fr.lua` merges
  into that one shared table, where plugins silently overwrite each other's
  translations. wordladder deals with a single word and translates this as
  "Longueur du mot", which was overwriting the plural this plugin needs.
  Distinct keys let both be right.

## [1.3.11] - 2026-10-01

### Fixed
- Picks up game-common v1.5.0. Play statistics were recorded under a key no
  tool could match: `ReaderUI`/`FileManager:registerModule()` rewrite a plugin
  instance's `name` to `reader<id>` / `filemanager<id>` right after it is
  built, so this game's sessions were split across two rows and neither
  carried its plugin id. Rows written under the old keys are merged back on
  first read. The same release brings the `stopPlugin()` /
  `deletePluginSettings()` hooks KOReader 2026.07 calls when a plugin is
  deleted from the device (PR #15240).

  No change to this plugin's own code -- it inherits all of it from the
  shared library.

## [1.3.10] - 2026-08-05

### Added
- Add ES and DE translations

### Changed
- Add screenshot to README
- Add issue/PR templates and CONTRIBUTING.md

## [1.3.9] - 2026-08-04

### Changed
- Symlink common/ to shared game-common

## [1.3.7] - 2026-07-29

### Fixed
- Drop deprecated name field from _meta.lua

## [1.3.6] - 2026-07-29

### Added
- Add word length selector (4-7 letters or random)

## [1.3.4] - 2026-07-28

### Changed
- Add GPL-3.0 LICENSE

## [1.3.0] - 2026-07-21

### Added
- Externalize word lists to words_en.lua/words_fr.lua, bump to 1.3.0
- Own translations locally instead of via game-common

## [1.2.1] - 2026-07-15

### Added
- Adopt TitleBar header, sync common/ with game-common

## [1.2.0] - 2026-07-10

### Changed
- Remove ../game-common/ fallback from package.path

### Fixed
- Gesture tap detection (GestureRange range function)

## [1.1.0] - 2026-07-08

### Added
- I18n FR/EN translation + bump to 1.1.0

## [1.0.1] - 2026-07-07

### Changed
- Remove redundant variable alignment in buildLayout
