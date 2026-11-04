"""One-off migration: replace the inline Follow Target placement code in Visions-hook.lua with calls into src/FollowTarget/Placement.lua.

Kept in the repository as the record of exactly what was replaced. Every anchor has to match exactly once, or nothing is written.
Run from the repository root:  python tools/build/wire_follow.py && python tools/build/bundle.py
"""
from pathlib import Path

target = Path(__file__).resolve().parents[2] / "Visions-hook.lua"
raw = target.read_bytes().decode("utf-8")
crlf = "\r\n" in raw
text = raw.replace("\r\n", "\n")


def region(start, end):
    """The text from `start` up to (not including) `end`, anchors matched exactly once."""
    assert text.count(start) == 1, "start anchor count %d: %r" % (text.count(start), start[:70])
    begin = text.index(start)
    assert text.count(end, begin) >= 1, "end anchor missing: %r" % end[:70]
    return text[begin:text.index(end, begin)]


def swap(old, new):
    global text
    assert text.count(old) == 1, "region count %d: %r" % (text.count(old), old[:70])
    text = text.replace(old, new)


# 1. where the generated module goes: right after the Lead model
lead_end = "-- @bundle-end src/Lead/LeadModel.lua\n"
swap(lead_end, lead_end + "-- @bundle-begin src/FollowTarget/Placement.lua\n-- @bundle-end src/FollowTarget/Placement.lua\n")

# 2. orbit shapes
old = region('        hide_manager["orbit_offset"] = function(shape, share, radius)\n', "\n\n        -- Visualize: a flat disc over the strafe's radius")
assert 'shape == "heart"' in old, "unexpected orbit block"
swap(old, '        hide_manager["orbit_offset"] = hide_manager["follow_placement"]["orbitOffset"]')

# 3. Zig Zag timing
old = region("        local zigzag_every = function()\n", "\n\n        -- how long the Shot Lock holds one place")
assert "rad(55)" in old, "unexpected zig zag block"
swap(
    old,
    '''        local zigzag_every = function()
            return hide_manager["follow_placement"]["zigzagEvery"](distance, tonumber(flags["follow_target_zigzag_speed"]) or 35)
        end''',
)

# 4. reach of a style
old = region('        hide_manager["follow_reach"] = function()\n', '\n\n        hide_manager["follow_cframe"] = function(aim, window, quiet)')
assert 'follow_target_style == "strafe above"' in old, "unexpected reach block"
swap(
    old,
    '''        hide_manager["follow_reach"] = function()
            return hide_manager["follow_placement"]["reach"](follow_target_style, distance, height["Y"], flags, adjust_state["offset"])
        end''',
)

# 5. Adjust's search (and the ways it used, now inside the module)
old = region("                local wanted = position - aim\n                local candidates = {}\n", '\n            end\n\n            local offset = adjust_state["offset"]\n')
assert "table.sort(candidates" in old and "adjust_ways" in old, "unexpected adjust search block"
swap(old, '                adjust_state["offset"] = hide_manager["follow_placement"]["adjustSearch"](aim, position, range, lift, clear)')

old = region("        local adjust_ways = {}\n\n", '        hide_manager["follow_adjust"] = function(cf, aim)')
assert old.count("adjust_ways") == 3 and "{0, -1, 0}" in old, "unexpected adjust ways block"
swap(old, "")

target.write_bytes((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))
print("Visions-hook.lua: Follow Target placement wired")
