"""One-off migration: replace the inline lead code in Visions-hook.lua with calls into the Lead model.

Kept in the repository as the record of exactly what was replaced. Every anchor has to match exactly once, or nothing is written.
Run from the repository root:  python tools/build/wire_lead.py && python tools/build/bundle.py
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


# 1. where the generated module goes (after hide_manager is declared)
declaration = 'local hide_manager = {} -- hooks the ragebot section hands to earlier code (auto reload routes its requests through hide_manager.request_reload)\n'
swap(declaration, declaration + "-- @bundle-begin src/Lead/LeadModel.lua\n-- @bundle-end src/Lead/LeadModel.lua\n")

# 2. steady flight check
swap(
    '                        hide_manager["velocity_steady"] = previous ~= nil and previous["Magnitude"] > 1 and velocity["Magnitude"] > 1\n'
    '                            and previous["Unit"]:Dot(velocity["Unit"]) > 0.8 and math.abs(velocity["Magnitude"] - previous["Magnitude"]) < previous["Magnitude"]*0.6\n',
    '                        hide_manager["velocity_steady"] = hide_manager["lead_model"]["isSteady"](previous, velocity)\n',
)

# 3. the prediction's lead
old = region(
    "                local lead = vector3_zero\n                local trusted_fast = false\n",
    "\n                ragebot_aim_position = hitbox_position + lead\n",
)
assert old.count("trusted_fast") >= 4 and "floor_params" in old, "unexpected prediction block"
swap(
    old,
    '''                local lead = vector3_zero
                local trusted_fast = false

                if target_velocity then
                    -- The lead (trust in a fast movement, desync, Prediction, Lead Fast Targets, Prediction Strength, gravity, the caps and the floor)
                    -- is worked out in src/Lead/LeadModel.lua.
                    local floor_probe = hide_manager["lead_floor_probe"]

                    if not floor_probe then
                        floor_probe = function(origin, direction, character)
                            local floor_params = hide_manager["floor_params"]

                            if not floor_params then
                                floor_params = RaycastParams["new"]()
                                floor_params["FilterType"] = Enum["RaycastFilterType"]["Exclude"]
                                hide_manager["floor_params"] = floor_params
                            end

                            floor_params["FilterDescendantsInstances"] = {character, local_character, find_first_child(workspace, "Ignored")}

                            local below = workspace["Raycast"](workspace, origin, direction, floor_params)

                            return below and below["Position"]["Y"] or nil
                        end

                        hide_manager["lead_floor_probe"] = floor_probe
                    end

                    lead, trusted_fast = hide_manager["lead_model"]["compute"](
                        target_velocity,
                        hide_manager["target_delta_velocity"] or target_velocity,
                        torso and torso["AssemblyLinearVelocity"],
                        flags["auto_fire_defensive"],
                        prediction,
                        local_ping,
                        flags["ragebot_lead_fast"],
                        hide_manager["velocity_steady"],
                        tonumber(flags["prediction_strength"]) or 100,
                        workspace["Gravity"],
                        hitbox_position,
                        floor_probe,
                        target[3]
                    )
                end
''',
)

# 4. Follow Target's lead
old = region(
    "                -- Lead (Follow Target's gear, on by default): the aim already leads the target",
    '\n                local new_cframe = hide_manager["follow_cframe"](follow_aim, false, bypass)',
)
assert 'flags["follow_target_lead_time"]' in old and old.count("follow_aim") == 2, "unexpected follow lead block"
swap(
    old,
    '''                -- Lead (Follow Target's gear, on by default): the aim already leads the target by what this client sees late; the body put next to
                -- it reaches the server another one-way trip and a tick later, and a target going 100 studs/s or more has moved on by then, so the
                -- place goes that much further along (speed times Lead Time, at most 60 studs, only for a speed both readings agree on). It fades in
                -- between 30 and 40 studs/s, and together with the lead the aim already carries it stays inside one trusted cap (src/Lead/LeadModel.lua).
                local follow_aim = ragebot_aim_position
                local target_speed = hide_manager["aim_velocity"]

                if flags["follow_target_lead"] ~= false and not bypass and typeof(target_speed) == "Vector3" then
                    follow_aim = ragebot_aim_position + hide_manager["lead_model"]["followAhead"](target_speed, tonumber(flags["follow_target_lead_time"]) or 80, hide_manager["aim_trusted"] == true, hide_manager["aim_lead_vector"] or vector3_zero)
                end
''',
)

# 5. Auto Fire's Pre Fire lead
old = region("        local relative = theirs - mine\n", "\n    end\n\n    -- Where the shot hook starts a ragebot shot from")
assert old.rstrip().endswith("return math.min(closing * lead_time, 40)"), "unexpected pre fire block"
swap(
    old,
    '        return hide_manager["lead_model"]["preFire"](hide_manager["lead_model"]["closingSpeed"](way, theirs, mine), tonumber(flags["auto_fire_pre_fire_time"]) or 60)',
)

target.write_bytes((text.replace("\n", "\r\n") if crlf else text).encode("utf-8"))
print("Visions-hook.lua: 5 regions replaced")
