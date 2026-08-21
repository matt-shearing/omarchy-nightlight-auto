"""Tests for the parts that can be silently wrong: the solar math and the
shape of the generated ladder.

Run with:  python3 -m pytest tests/ -q      (or: python3 tests/test_schedule.py)
"""

import importlib.machinery
import importlib.util
import sys
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

REPO = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_loader(
    "nightlight_auto",
    importlib.machinery.SourceFileLoader("nightlight_auto", str(REPO / "bin" / "nightlight-auto")),
)
nl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nl)


def settings(**overrides):
    s = dict(nl.DEFAULTS)
    s.update(overrides)
    return s


def minutes(when):
    return when.hour * 60 + when.minute


# ------------------------------------------------------------------- solar

# Reference sunrise/sunset, from published almanac times. The low-precision
# equation is good to a minute or two, so allow three.
SOLAR_CASES = [
    # (tz, lat, lon, date, sunrise, sunset)
    ("Australia/Brisbane", -27.4667, 153.0333, date(2026, 8, 21), "06:13", "17:30"),
    ("Australia/Brisbane", -27.4667, 153.0333, date(2026, 6, 21), "06:38", "17:02"),
    ("Australia/Brisbane", -27.4667, 153.0333, date(2026, 12, 21), "04:51", "18:43"),
    # Northern hemisphere, and a zone that observes DST.
    ("Europe/London", 51.5074, -0.1278, date(2026, 6, 21), "04:43", "21:21"),
    ("Europe/London", 51.5074, -0.1278, date(2026, 12, 21), "08:04", "15:53"),
    # Crossing the prime meridian the other way, and a large UTC offset.
    ("America/New_York", 40.7128, -74.0060, date(2026, 3, 21), "07:00", "19:12"),
]


def parse_hhmm(text):
    hh, mm = (int(p) for p in text.split(":"))
    return hh * 60 + mm


def test_solar_times_match_almanac():
    for tz_name, lat, lon, day, expect_rise, expect_set in SOLAR_CASES:
        tz = ZoneInfo(tz_name)
        rise, sets = nl.sun_times(day, lat, lon, tz)
        assert rise is not None and sets is not None, f"{tz_name} {day}: no events"
        assert rise.date() == day, f"{tz_name} {day}: sunrise landed on {rise.date()}"
        assert sets.date() == day, f"{tz_name} {day}: sunset landed on {sets.date()}"
        for label, got, expected in (("sunrise", rise, expect_rise),
                                     ("sunset", sets, expect_set)):
            delta = abs(minutes(got) - parse_hhmm(expected))
            assert delta <= 3, (
                f"{tz_name} {day} {label}: got {got:%H:%M}, expected ~{expected}")


def test_polar_day_and_night_report_no_events():
    tz = ZoneInfo("Europe/Oslo")
    # Tromso: the sun neither sets in midsummer nor rises at midwinter.
    for day in (date(2026, 6, 21), date(2026, 12, 21)):
        rise, sets = nl.sun_times(day, 69.65, 18.96, tz)
        assert rise is None and sets is None, f"{day}: expected no events"


def test_equator_days_are_near_twelve_hours():
    tz = ZoneInfo("Africa/Nairobi")
    rise, sets = nl.sun_times(date(2026, 3, 21), -1.2921, 36.8219, tz)
    length = minutes(sets) - minutes(rise)
    assert 705 <= length <= 735, f"day length {length} min is not near 12 h"


# ---------------------------------------------------------------- location


def test_iso6709_parsing_handles_both_widths():
    # +DDMM+DDDMM
    lat, lon = nl._parse_iso6709("-2728+15302")
    assert abs(lat - -27.4667) < 0.001
    assert abs(lon - 153.0333) < 0.001
    # +DDMMSS+DDDMMSS
    lat, lon = nl._parse_iso6709("+404251-0740023")
    assert abs(lat - 40.7142) < 0.001
    assert abs(lon - -74.0064) < 0.001


def test_location_comes_from_the_time_zone():
    lat, lon = nl.location_from_timezone("Australia/Brisbane")
    assert -28 < lat < -27
    assert 152 < lon < 154


def test_zone_with_several_names_still_resolves():
    # zone1970.tab lists linked names comma-separated on one row.
    lat, lon = nl.location_from_timezone("Europe/London")
    assert 51 < lat < 52


# ------------------------------------------------------------------ ladder


def build(day=date(2026, 8, 21), tz_name="Australia/Brisbane", **overrides):
    tz = ZoneInfo(tz_name)
    s = settings(**overrides)
    return nl.build_schedule(s, day, -27.4667, 153.0333, tz), s


def test_ladder_ramps_down_to_the_night_temperature():
    (steps, info), s = build()
    temps = [t for _, t in steps if t is not None]
    assert temps[0] == s["evening_temp"]
    assert temps[-1] == s["night_temp"]
    assert temps == sorted(temps, reverse=True), "ramp must never warm back up"


def test_ladder_starts_at_sunset_and_ends_untinted_at_sunrise():
    (steps, info), s = build()
    assert steps[0][0] == info["ramp_start"]
    assert info["ramp_start"] == info["sunset"]  # default offset is zero
    assert steps[-1][1] is None, "last profile should be the untinted day"
    assert steps[-1][0] == info["day_start"]


def test_no_duplicate_clock_times():
    # hyprsunset keys profiles on HH:MM, so a collision silently drops a step.
    for step_minutes in (1, 5, 20, 60):
        (steps, _), _ = build(step_minutes=step_minutes, ramp_minutes=300)
        keys = [when.strftime("%H:%M") for when, _ in steps]
        assert len(keys) == len(set(keys)), f"duplicate times at step={step_minutes}"


def test_ramp_never_runs_past_the_morning_profile():
    # A ramp longer than the night must be clamped, or the ladder would emit a
    # warm profile after the untinted one and hold the tint through the day.
    (steps, info), _ = build(ramp_minutes=2000)
    assert info["ramp_end"] < info["day_start"]
    for when, temp in steps:
        if temp is None:
            continue
        assert when < info["day_start"]


def test_sorted_by_clock_the_cycle_stays_consistent():
    # The rendered file is sorted by HH:MM and hyprsunset wraps past the last
    # entry. Sorting must not reorder the ramp relative to the day profile.
    (steps, _), _ = build()
    by_clock = sorted(steps, key=lambda item: item[0].strftime("%H:%M"))
    temps = [t for _, t in by_clock]
    day_index = temps.index(None)
    after_day = [t for t in temps[day_index + 1:] if t is not None]
    assert after_day == sorted(after_day, reverse=True)


def test_interpolation_is_even_in_mireds():
    # Even steps in mired space are what make the ramp read as smooth. Disable
    # the 50 K output rounding first, or quantisation noise swamps the check.
    (steps, _), _ = build(step_minutes=60, ramp_minutes=300, round_to_kelvin=1)
    mireds = [1e6 / t for _, t in steps if t is not None]
    gaps = [b - a for a, b in zip(mireds, mireds[1:])]
    assert max(gaps) - min(gaps) < 0.5, f"mired steps are uneven: {gaps}"


def test_rounding_stays_within_half_a_quantum():
    (rounded, _), s = build(step_minutes=60, ramp_minutes=300)
    (exact, _), _ = build(step_minutes=60, ramp_minutes=300, round_to_kelvin=1)
    for (_, got), (_, want) in zip(rounded, exact):
        if got is None or want is None:
            continue
        assert abs(got - want) <= s["round_to_kelvin"] / 2 + 1


def test_degenerate_location_falls_back_and_is_flagged():
    tz = ZoneInfo("Europe/Oslo")
    (steps, info) = nl.build_schedule(settings(), date(2026, 6, 21), 69.65, 18.96, tz)
    assert info["degenerate"] is True
    assert info["sunset"].strftime("%H:%M") == nl.DEFAULTS["fallback_sunset"]
    assert len(steps) > 1


def test_day_temp_emits_a_temperature_not_identity():
    (steps, _), _ = build(day_temp=6500)
    assert steps[-1][1] == 6500


# ------------------------------------------------------------------ render


def test_rendered_profiles_are_sorted_and_well_formed():
    (steps, info), s = build()
    text = nl.render_conf(steps, s, info, -27.4667, 153.0333, "test", "Australia/Brisbane")
    assert text.startswith(nl.MARKER)
    times, bodies = [], []
    block = None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("profile"):
            block = {}
        elif line == "}" and block is not None:
            bodies.append(block)
            block = None
        elif block is not None and "=" in line:
            key, value = (p.strip() for p in line.split("=", 1))
            block[key] = value
            if key == "time":
                times.append(value)
    assert times == sorted(times), "hyprsunset needs profiles in clock order"
    assert len(bodies) == len(steps)
    for body in bodies:
        assert "time" in body
        assert ("temperature" in body) ^ ("identity" in body)


def test_paused_conf_is_identity_only():
    text = nl.render_paused_conf("Australia/Brisbane")
    assert text.count("profile {") == 1
    assert "identity = true" in text
    assert "temperature" not in text


# ---------------------------------------------------------------- settings


def test_validate_rejects_nonsense():
    for bad in (dict(evening_temp=50), dict(night_temp=99999),
                dict(ramp_minutes=0), dict(step_minutes=0),
                dict(fallback_sunset="25:00"), dict(round_to_kelvin=0)):
        try:
            nl.validate(settings(**bad))
        except SystemExit:
            continue
        raise AssertionError(f"validate accepted {bad}")


def test_validate_accepts_the_defaults():
    nl.validate(settings())


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_") or not callable(fn):
            continue
        try:
            fn()
            print(f"ok   {name}")
        except Exception as exc:  # noqa: BLE001 - a test runner wants everything
            failures += 1
            print(f"FAIL {name}: {exc}")
    print(f"\n{failures} failure(s)")
    sys.exit(1 if failures else 0)
