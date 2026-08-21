# Sunset Night Light

Warm the screen on a ramp anchored to **real local sunset**, deepening through the
evening, back to untinted at sunrise.

Omarchy's built-in night light is a switch: `Super + Ctrl + N` flips between 4000 K and
6500 K. hyprsunset can also follow the clock, but only the clock — its profiles key on a
fixed `HH:MM` and there is no interpolation between them. So an evening that gets
gradually warmer means a ladder of profiles, and a ladder anchored to sunset has to be
rebuilt as sunset moves. That is what this does.

```
17:30  5000K     sunset
17:50  4800K
18:10  4600K
   …
22:30  3000K     five hours later, at the floor
06:13  untinted  sunrise
```

## Location comes from your time zone

tzdata ships a representative latitude and longitude for every zone in
`zone1970.tab`, so `Australia/Brisbane` is enough to place you within a few kilometres —
far inside the minute or two of precision sunset timing needs. Change the system time
zone and the schedule follows, with no second thing to update.

Set `latitude` / `longitude` in the config if you want your actual coordinates.

## Install

```bash
git clone https://github.com/matt-shearing/omarchy-nightlight-auto
cd omarchy-nightlight-auto
./install.sh
```

That symlinks the CLI into `~/.local/bin`, installs the bar widget, enables a daily
timer, adds a post-boot hook, and generates tonight's schedule.

## Use

```bash
nightlight-auto status         # what is on screen now, and what is next
nightlight-auto show           # tonight's whole ladder
nightlight-auto show --date 2026-12-21
nightlight-auto pause          # untinted until you resume
nightlight-auto resume
nightlight-auto generate       # rebuild now (the timer does this daily)
```

The bar widget shows a moon while the screen is tinted and a sun when it is not. Click
it for tonight's ladder with the current step marked, right-click to pause. It turns the
urgent colour only when hyprsunset is not running, because that is the one state where
nothing is being applied at all.

## Configuration

`~/.config/nightlight-auto/config.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `latitude`, `longitude` | `null` | `null` derives both from the system time zone |
| `evening_temp` | `5000` | Kelvin at the start of the ramp |
| `night_temp` | `3000` | Kelvin at the deepest point |
| `day_temp` | `null` | `null` means untinted; a number tints the day too |
| `ramp_start_offset_min` | `0` | Minutes relative to sunset; negative starts earlier |
| `ramp_minutes` | `300` | How long the ramp takes to reach `night_temp` |
| `step_minutes` | `20` | Ladder granularity |
| `morning_offset_min` | `0` | Minutes relative to sunrise for the return to day |
| `fallback_sunset`, `fallback_sunrise` | `18:00`, `06:00` | Used only where the sun does not rise or set |
| `round_to_kelvin` | `50` | Rounds emitted temperatures, to keep the file readable |

Run `nightlight-auto generate` after editing. Temperatures are interpolated in **mireds**
(reciprocal megakelvin), not Kelvin, because even steps there are what read as an even
ramp to the eye — linear Kelvin steps crowd all the visible change into the warm end.

## How it fits into Omarchy

It writes `~/.config/hypr/hyprsunset.conf`, which is Omarchy's documented place for a
night light schedule, and touches nothing under `/usr/share/omarchy`. Your existing file
is backed up the first time. `omarchy toggle nightlight` still works and still wins —
until the next step in the ladder fires, at most `step_minutes` later. For a hold that
lasts, use `nightlight-auto pause`.

### hyprsunset runs from systemd, not autostart.lua

The manual suggests `o.launch_on_start("hyprsunset")`. This uses
`systemctl --user enable hyprsunset.service` instead — the unit the hyprsunset package
already ships — for a specific reason.

hyprsunset reads its config only at startup, so applying a rebuilt schedule means
restarting it. `omarchy-restart-app` relaunches through uwsm, which asks the user manager
for a transient scope. **A scope created from inside a systemd service does not outlive
that service.** Run from the timer, hyprsunset comes up, answers on its socket, and is
then killed the instant the oneshot exits — reproducibly, even after waiting for it to
confirm it is up. Restarting the unit has no such problem.

Running both launch paths would just race for hyprsunset's socket, so there is only the
one. `~/.config/hypr/autostart.lua` carries a comment saying so.

## Tests

```bash
python3 tests/test_schedule.py
```

Covers the solar math against published almanac times for Brisbane, London (across a DST
boundary), New York and Nairobi; polar day and polar night; the ladder's shape, ordering,
clamping and mired spacing; and the rendered config's structure.

## Requirements

Omarchy 4, `hyprsunset`, Python 3.9+. No other dependencies — the solar calculation is
stdlib arithmetic.

## Licence

MIT.
