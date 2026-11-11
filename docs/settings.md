# Settings

The preferences that belong to the machine, not to a campaign. A setting is one
a player sets once and expects the next launch to keep, whichever world, save
slot or scene they come back to.

| Piece | Owns |
| --- | --- |
| `scripts/settings_store.gd` (autoload `Settings`) | the display mode, its file, and applying it to the window on boot and on every change |
| `scripts/ui/display_settings_button.gd` | the one fullscreen row, shared by both settings windows |
| `scripts/ui/settings_menu.gd` | the Escape window in the title and the campaign: the index, the SOUND page, the DISPLAY page and the KEYS sheet |
| `scripts/ui/sound_settings_page.gd` | the mix page: a level and a mute for `Music` and `SFX`, read from and written to `Audio` |

The mix is not in this file. It stays with `scripts/audio/audio_manager.gd`,
because a level is a bus write and the four values are the mixer's; the audio
doc owns its schema ([audio.md](audio.md)). The party's mode is not here either:
it is the warband's and travels with the campaign save. What this store holds is
the rest - today that is the display mode - and it is the home for every future
setting of the same kind.

## The file

`user://settings.json`:

```json
{"fullscreen": true, "version": 1}
```

`version` is the schema. A missing file is the defaults (windowed); an
unreadable file is a warning and the value already held, never a half-applied
file. The file is written on the change, not at quit, so a crash cannot lose a
mode the player set.

A headless run with `--script` swaps to `user://settings_test.json` and never
reads or writes the player's file, matching the mix and the other autoloads.

## The window

`Settings.apply_window()` puts the stored mode on the game window. It runs when
the autoload comes up, before the main scene builds, and again on every
`set_fullscreen()`. `window_fullscreen()` asks the window what it is actually
doing; a headless run has no window, so there the stored preference answers.
`toggle_fullscreen()` is the only writer the UI uses.

The title's Escape window has a DISPLAY page, so a player can choose the mode
before entering the world. The campaign's quick menu shows the same shared
row on its settings page, beside the mix, and reports the switch on its status
line. Both windows read and write the one autoload, so the label and the file
cannot disagree.

## Verifying

```powershell
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/settings_regression.gd
```

`settings_regression.gd` covers the file's schema, a fresh manager reading the
last mode back (the relaunch path), the boot load with no display to move, the
shared row's press and repaint, the title's DISPLAY page, the quick menu's row
and status line, and an unreadable file leaving the held mode alone.
