# Visions-hook menu inventory against Vanta

Generated from the 517 controls the older menu in `Visions-hook.lua` creates (`menu_references[...]:create_element`), grouped by the section that holds them. **Implemented** means the underlying behaviour exists in Vanta and is wired to a menu control; the live test results are in `FEATURES.md`. Everything not marked is **No**.

Status: **Yes** = implemented, **Partial** = a working core with options missing, **No** = not implemented, **Declined** = deliberately not reproduced (reason given).

**Totals (517 controls):** Yes 273, Partial 37, No 181, Declined 26.

## panel_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| purchase item | button | No |  |
| ammo amount | slider | No |  |
| purchase ammo | button | No |  |

## movement_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| remove jump cooldown | toggle | Yes | Movement |
| remove slowdowns | toggle | Yes | Movement |
| lock walk speed | toggle | Yes | Movement |
| jump power | toggle | Yes | Movement |
| anti trip | toggle | Yes | Movement |
| anti sit | toggle | Yes | Movement |
| noclip | toggle | Yes | Movement |
| speed | toggle | Yes | Movement |
| flight | toggle | Yes | Movement |
| pushback guard | toggle | Yes | Movement |

## jump_power_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| power | slider | Yes | Movement |

## speed_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| speed multiplier | slider | Yes | Movement |

## flight_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| flight speed | slider | Yes | Movement |

## other_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| animation breaker | toggle | Declined | breaks the animation state other players see / automated chat messages |
| animation player | toggle | Yes | Movement / Misc |
| trash talk | toggle | Declined | breaks the animation state other players see / automated chat messages |
| spinbot | toggle | Yes | Movement / Misc |
| hide player nametags | toggle | Yes | Movement / Misc |

## animation_breaker_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| lag | slider | Declined | part of animation breaker |
| jitter | slider | Declined | part of animation breaker |

## animation_player_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| animation | dropdown | Yes | Misc |
| asset id | textbox | Yes | Misc |

## trash_talk_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| message list | dropdown | Declined | part of trash talk (automated chat) |
| always | toggle | Declined | part of trash talk (automated chat) |
| activate when | dropdown | Declined | part of trash talk (automated chat) |

## spinbot_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| speed | slider | Yes | Movement |

## utility_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| remove flintlock knockback | toggle | No |  |
| unlock custom crosshair | toggle | No |  |
| unlock animation packs | toggle | No |  |
| unlock camera distance | toggle | Yes | Misc |
| remove anti gun macro | toggle | No |  |
| auto vehicle | toggle | No |  |
| semi god | toggle | No |  |
| auto reload | toggle | Partial | Shop / Bounty / AntiStomp / AutoFire |
| detect staff | toggle | No |  |
| safe purchasing | toggle | Partial | Shop / Bounty / AntiStomp / AutoFire |
| auto loadout | toggle | Partial | Shop / Bounty / AntiStomp / AutoFire |
| follow target | toggle | Yes | Follow / AutoStomp / Bounty / Shop / Utility |
| auto stomp | toggle | Yes | Follow / AutoStomp / Bounty / Shop / Utility |
| anti bounty | toggle | Yes | Follow / AutoStomp / Bounty / Shop / Utility |
| auto bounty | toggle | Partial | Shop / Bounty / AntiStomp / AutoFire |
| auto ammo | toggle | Yes | Follow / AutoStomp / Bounty / Shop / Utility |
| auto armor | toggle | Partial | Shop / Bounty / AntiStomp / AutoFire |
| anti stomp | toggle | Partial | Shop / Bounty / AntiStomp / AutoFire |
| anti report | toggle | Declined | evades moderation reports / removes the client fire limiter |
| auto mask | toggle | Yes | Follow / AutoStomp / Bounty / Shop / Utility |
| auto heal | toggle | Partial | Shop / Bounty / AntiStomp / AutoFire |
| anti taser | toggle | No |  |
| anti afk | toggle | Yes | Follow / AutoStomp / Bounty / Shop / Utility |
| rapid fire | toggle | Declined | evades moderation reports / removes the client fire limiter |
| control | toggle | Declined | chat auto replies |

## auto_reload_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| activate when | dropdown | No |  |
| wait for stomp | toggle | No |  |
| void while reloading | toggle | No |  |

## player_interactions

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| auto save friendlies | toggle | Yes | Status |
| auto set statuses | toggle | Yes | Status |

## auto_save_friendlies_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| ignore range | slider | No |  |

## auto_set_statuses_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| set friendly if | dropdown | Partial | Status (friends, crew mates, friends of an enemy) |
| set enemy if | dropdown | Partial | Status (friends, crew mates, friends of an enemy) |
| notifications | toggle | No |  |

## lighting_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| background noise | toggle | No |  |
| lighting mode | toggle | Yes | World |
| world time | toggle | Yes | World |
| atmosphere | toggle | Yes | World |
| saturation | toggle | Yes | World |
| contrast | toggle | Yes | World |
| textures | toggle | No |  |
| ambient | toggle | Yes | World |
| weather | toggle | Yes | World |
| skybox | toggle | Yes | World |
| tint | toggle | Yes | World |

## background_noise_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| sound | dropdown | No |  |
| volume | slider | No |  |

## atmosphere_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | Yes | World |
| decay | colorpicker | Yes | World |
| haze | slider | Yes | World |
| glare | slider | Yes | World |
| offset | slider | Yes | World |
| density | slider | Yes | World |

## textures_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| pack | dropdown | No |  |

## ambient_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| outdoor color | colorpicker | Yes | World |
| color | colorpicker | Yes | World |

## weather_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| type | dropdown | Yes | World |
| color | colorpicker | Yes | World |
| rate | slider | Yes | World |

## skybox_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| sky | dropdown | Yes | World (5 skyboxes) |

## hud_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| server position indicator | toggle | Declined | part of the fake position feature |
| crosshair animations | toggle | No |  |
| drawing crosshair | toggle | Yes | Crosshair / World |
| center panel | toggle | Partial | Crosshair (state and target text) |
| aspect ratio | toggle | No |  |
| show chat | toggle | Yes | Crosshair / World |
| statistics window | toggle | No |  |

## server_position_indicator_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| smooth | toggle | No |  |
| always show | toggle | No |  |
| icon color | colorpicker | No |  |
| glow color | colorpicker | No |  |
| ghost character | toggle | No |  |
| ghost color | colorpicker | No |  |
| ghost material | dropdown | No |  |
| background color | colorpicker | No |  |

## crosshair_animations_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| fade in and out | toggle | No |  |
| spin | toggle | No |  |
| speed | slider | No |  |

## drawing_crosshair_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| follow target | toggle | Yes | Crosshair |
| style | dropdown | No |  |
| target indicator | toggle | Partial | Crosshair (target colour) |
| indicator color | colorpicker | Partial | Crosshair (target colour) |
| animation style | dropdown | No |  |
| speed | slider | No |  |
| target outline color | colorpicker | No |  |
| target line color | colorpicker | No |  |
| outline color | colorpicker | Yes | Crosshair |
| line color | colorpicker | Yes | Crosshair |
| line thickness | slider | Yes | Crosshair |
| line size | slider | Yes | Crosshair |
| gap size | slider | Yes | Crosshair |
| rotating | slider | Yes | Crosshair |

## center_panel_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| show state | toggle | Yes | Crosshair |
| primary color | colorpicker | Yes | Crosshair |
| show target | toggle | Yes | Crosshair |
| secondary color | colorpicker | No |  |

## game_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| player bullet volume | slider | No |  |
| mute gun sounds | toggle | No |  |
| player bullet tracers | toggle | No |  |
| local bullet impacts | toggle | Yes | Feedback |
| override armor pop | toggle | No |  |
| local bullet tracers | toggle | Yes | Feedback |
| shot notifications | toggle | Partial | Feedback (hit / no hit) |
| local bullet sound | toggle | No |  |
| damage number | toggle | Yes | Feedback |
| 3d hit marker | toggle | Yes | Feedback |
| 2d hit marker | toggle | Yes | Feedback |
| hit skeleton | toggle | Yes | Feedback |
| hit particle | toggle | Yes | Feedback |
| rpg warning | toggle | No |  |
| hit overlay | toggle | Yes | Feedback |
| hit sound | toggle | Yes | Feedback |
| hit chams | toggle | Yes | Feedback |

## player_bullet_tracers_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| type | dropdown | No |  |
| style | dropdown | No |  |
| color | colorpicker | No |  |
| outline color | colorpicker | No |  |
| gradient color | colorpicker | No |  |
| lifetime | slider | No |  |

## local_bullet_impacts_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| animation | dropdown | No |  |
| pop color | colorpicker | No |  |
| style | dropdown | No |  |
| color | colorpicker | Yes | Feedback |
| outline color | colorpicker | No |  |
| lifetime | slider | Yes | Feedback |

## override_armor_pop_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| image color | colorpicker | No |  |
| image | dropdown | No |  |

## local_bullet_tracers_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| type | dropdown | No |  |
| style | dropdown | No |  |
| color | colorpicker | Yes | Feedback |
| outline color | colorpicker | No |  |
| gradient color | colorpicker | No |  |
| lifetime | slider | Yes | Feedback |
| one line for shotguns | toggle | No |  |

## shot_notifications_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| notify when | dropdown | Partial | Feedback |
| failed color | colorpicker | No |  |
| hit color | colorpicker | No |  |

## local_bullet_sound_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| in world | toggle | No |  |
| volume | slider | No |  |
| sound | dropdown | No |  |

## damage_number_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| font | dropdown | No |  |
| lifetime | slider | Yes | Feedback |
| color | colorpicker | Yes | Feedback |
| lethal color | colorpicker | Yes | Feedback |
| outline color | colorpicker | No |  |
| show ragebot data | toggle | No |  |

## d3_hit_marker_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| lifetime | slider | Yes | Feedback |
| thickness | slider | Yes | Feedback |
| color | colorpicker | Yes | Feedback |
| lethal color | colorpicker | Yes | Feedback |
| outline color | colorpicker | No |  |

## d2_hit_marker_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| lifetime | slider | Yes | Feedback |
| thickness | slider | Yes | Feedback |
| color | colorpicker | Yes | Feedback |
| lethal color | colorpicker | Yes | Feedback |
| outline color | colorpicker | No |  |

## hit_skeleton_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| animation | dropdown | No |  |
| lifetime | slider | Yes | Feedback |
| thickness | slider | Yes | Feedback |
| color | colorpicker | Yes | Feedback |

## hit_particle_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| behind walls | toggle | No |  |
| lethal color | colorpicker | Yes | Feedback |
| color | colorpicker | Yes | Feedback |
| particle | dropdown | No |  |

## rpg_warning_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| lifetime | slider | No |  |

## hit_overlay_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| lifetime | slider | Yes | Feedback |
| color | colorpicker | Yes | Feedback |
| lethal color | colorpicker | Yes | Feedback |

## hit_sound_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| sound | dropdown | Yes | Feedback (sounds fetched from this repository) |
| volume | slider | Yes | Feedback (sounds fetched from this repository) |

## hit_chams_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| only last hit | toggle | Yes | Feedback |
| animation | dropdown | No |  |
| type | dropdown | No |  |
| lifetime | slider | Yes | Feedback |
| color | colorpicker | Yes | Feedback |

## visuals_other_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| hide game crosshair | toggle | Partial | World (cursor icon / blur effect) |
| disable rendering | toggle | Yes | World |
| motion blur | toggle | Partial | World (cursor icon / blur effect) |

## motion_blur_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| intensity | slider | Yes | World |

## skins_editor_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| skin changer | toggle | Partial | Skins (guns and the bat; knives not reproduced) |
| weapon | dropdown | Partial | Skins (guns and the bat; knives not reproduced) |

## custom_skins_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| refresh custom skins | button | No |  |

## esp_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| enabled | toggle | Yes | Esp |
| box | toggle | Yes | Esp |
| name | toggle | Yes | Esp |
| image | toggle | No |  |
| chams | toggle | Yes | Esp |
| material | toggle | No |  |
| tool text | toggle | Yes | Esp |
| tool icon | toggle | No |  |
| distance | toggle | Yes | Esp |
| highlight | toggle | Yes | Esp |
| armor bar | toggle | Yes | Esp |
| health bar | toggle | Yes | Esp |
| health text | toggle | Yes | Esp |

## esp_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| render statuses | dropdown | Yes | Esp |

## box_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| outline | colorpicker | No |  |
| color | colorpicker | Partial | Esp (one colour, one target colour) |
| enemy color | colorpicker | Yes | Esp |
| friendly color | colorpicker | Yes | Esp |

## name_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| use display name | toggle | Yes | Esp |
| color | colorpicker | Yes | Esp |
| enemy color | colorpicker | Yes | Esp |
| friendly color | colorpicker | Yes | Esp |

## image_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| image | dropdown | No |  |
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

## chams_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| behind walls | toggle | Yes | Esp |
| color | colorpicker | Partial | Esp (one colour, one target colour) |
| enemy color | colorpicker | Yes | Esp |
| friendly color | colorpicker | Yes | Esp |

## material_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| material | dropdown | No |  |
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

## tool_text_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| casing | dropdown | No |  |
| color | colorpicker | Yes | Esp |
| enemy color | colorpicker | Yes | Esp |
| friendly color | colorpicker | Yes | Esp |

## tool_icon_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

## distance_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| unit | dropdown | Yes | Esp |

## highlight_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| behind walls | toggle | Yes | Esp |
| color | colorpicker | Partial | Esp |
| enemy color | colorpicker | Yes | Esp |
| friendly color | colorpicker | Yes | Esp |
| outline color | colorpicker | Yes | Esp |
| enemy outline color | colorpicker | No |  |
| friendly outline color | colorpicker | No |  |

## armor_bar_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| hide if no armor | toggle | Yes | Esp |
| gradient | toggle | No |  |
| enemy gradient | colorpicker | No |  |
| friendly gradient | colorpicker | No |  |
| outline | colorpicker | No |  |
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

## health_bar_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| gradient | toggle | No |  |
| enemy gradient | colorpicker | No |  |
| friendly gradient | colorpicker | No |  |
| outline | colorpicker | No |  |
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

## health_text_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| hide if full | toggle | Yes | Esp |
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

## fonts

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| main font | dropdown | No |  |
| small font | dropdown | No |  |

## local_character_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| character highlight | toggle | Yes | LocalChar |
| character material | toggle | Yes | LocalChar |
| custom character | toggle | No |  |
| skinny | toggle | No |  |
| material tools | toggle | No |  |
| rainbow weapon chams | toggle | Yes | LocalChar |
| china hat | toggle | Yes | LocalChar |
| particle aura | toggle | Yes | LocalChar |

## local_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| material | dropdown | Partial | LocalChar |
| color | colorpicker | Partial | LocalChar |

## character_highlight_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | Yes | LocalChar |
| outline | colorpicker | Yes | LocalChar |

## custom_character_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| model type | dropdown | No |  |
| user id or username | textbox | No |  |
| files | dropdown | No |  |

## skinny_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| amount | slider | No |  |

## material_tools_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| material | dropdown | No |  |
| color | colorpicker | No |  |

## rainbow_weapon_chams_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| speed | slider | Yes | LocalChar |
| saturation | slider | No |  |
| brightness | slider | No |  |
| transparency | slider | Yes | LocalChar |
| material | dropdown | No |  |

## china_hat_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | Yes | LocalChar |
| light color | colorpicker | No |  |
| scale | slider | Yes | LocalChar |
| light brightness | slider | No |  |

## particle_aura_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | Yes | LocalChar |
| particle | dropdown | No |  |

## general_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| ragebot | toggle | Yes | Ragebot / AutoFire / AdStrafe / Target |
| auto fire | toggle | Yes | Ragebot / AutoFire / AdStrafe / Target |
| a/d | toggle | Yes | Ragebot / AutoFire / AdStrafe / Target |
| auto equip | toggle | Yes | AutoFire |
| spam resolver | toggle | Partial | AutoFire / Resolver |
| target hitbox | dropdown | Yes | Ragebot / AutoFire / AdStrafe / Target |
| prediction | slider | Partial | AutoFire / Resolver |
| shot delay | slider | Yes | AutoFire |
| field of view | slider | Yes | Ragebot / AutoFire / AdStrafe / Target |
| fire cooldown | slider | Yes | AutoFire |

## auto_fire_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| at target vehicle | toggle | No |  |
| always fire | toggle | Declined | sends shots at targets out of reach; the server turns them away and counts them against a shotgun lockout |
| dont render | toggle | No |  |
| show fake bullets | toggle | No |  |
| pre fire | toggle | No |  |
| pre fire time | slider | No |  |
| bullet manipulation | toggle | Declined | changes the shot data claimed to the server / exceeds the server fire rate |
| fast retry | toggle | No |  |
| double tap | toggle | Declined | changes the shot data claimed to the server / exceeds the server fire rate |
| gun gap | slider | Yes | AutoFire |

## ad_strafe_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| interval | slider | Yes | AdStrafe |

## auto_equip_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| unequip when | dropdown | Yes | AutoFire |
| gun | dropdown | Yes | AutoFire |
| prioritize db | toggle | Yes | AutoFire |
| distance check | toggle | Partial | AutoFire (reach is always checked) |

## auto_fire_defensive_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| type | dropdown | Yes | Resolver (cluster, adaptive, weighted, hybrid) |
| refresh time | slider | Partial | Resolver (history window) |
| forgiveness | slider | Yes | Resolver (cluster, adaptive, weighted, hybrid) |
| out of void bonus | slider | Yes | Resolver (cluster, adaptive, weighted, hybrid) |
| normal position trust | slider | Yes | Resolver (cluster, adaptive, weighted, hybrid) |
| forget rate | slider | Yes | Resolver (cluster, adaptive, weighted, hybrid) |
| void trust | slider | Yes | Resolver (cluster, adaptive, weighted, hybrid) |
| accuracy | slider | Yes | Resolver (cluster, adaptive, weighted, hybrid) |
| distance based penalty | slider | Yes | Resolver (cluster, adaptive, weighted, hybrid) |
| lerp % when close | slider | Yes | Resolver (cluster, adaptive, weighted, hybrid) |

## prediction_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| resolver rate | slider | Yes | Resolver |
| strength | slider | Yes | Resolver |
| velocity source | dropdown | Yes | Resolver |

## target_selection_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| notification | toggle | Yes | Target |
| automatic | toggle | Yes | Target |
| cooldown | slider | Yes | Target |
| target bind | keybind | Yes | Target |
| target when shot at | toggle | Yes | Target / VoidSpam |
| force | toggle | Yes | Target / VoidSpam |
| wait for spawn protection | toggle | Yes | Target / VoidSpam |
| void while waiting | toggle | Yes | Target / VoidSpam |
| untarget when | dropdown | Yes | Target |
| target statuses | dropdown | Yes | Target |
| target players | dropdown | No |  |
| prioritize by | dropdown | Yes | Target |
| ignore if | dropdown | Yes | Target |
| target distance | slider | Yes | Target |

## visualization_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| information panel | toggle | Yes | Visuals / Movement / Crosshair |
| crosshair follow | toggle | Yes | Visuals / Movement / Crosshair |
| 3d target circle | toggle | Yes | Visuals |
| view target | toggle | Yes | Visuals |
| face target | toggle | Yes | Visuals / Movement / Crosshair |
| show fov | toggle | Yes | Visuals |
| tracer | toggle | Yes | Visuals |

## 3d_target_circle_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | Yes | Visuals |
| gradient color | colorpicker | No |  |

## view_target_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| stop when knocked | toggle | Yes | Visuals |

## ragebot_field_of_view_show_fov_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| follow target | toggle | Yes | Visuals |
| color | colorpicker | Yes | Visuals |
| outline | colorpicker | Yes | Visuals |
| active color | colorpicker | Yes | Visuals |
| active outline | colorpicker | Yes | Visuals |

## ragebot_tracer_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| thickness | slider | Yes | Visuals |
| color | colorpicker | Yes | Visuals |
| outline | colorpicker | Yes | Visuals |
| origin | dropdown | Yes | Visuals |
| end point | dropdown | Yes | Visuals |

## anti_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| sender rate value | toggle | Declined | manipulates network replication / fakes server-visible state |
| network desync | toggle | Declined | manipulates network replication / fakes server-visible state |
| velocity desync | toggle | Declined | manipulates network replication / fakes server-visible state |
| fake position | toggle | Declined | manipulates network replication / fakes server-visible state |
| void hide | toggle | Partial | VoidSpam |

## sender_rate_value_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| value | dropdown | No |  |
| rate | slider | No |  |

## velocity_desync_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| rotate | toggle | No |  |
| disable when | dropdown | No |  |
| health | slider | No |  |
| type | dropdown | No |  |

## fake_position_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| position indicator | toggle | No |  |
| smooth | toggle | No |  |
| icon color | colorpicker | No |  |
| glow color | colorpicker | No |  |
| background color | colorpicker | No |  |
| notifications | toggle | No |  |
| safe mode | toggle | No |  |
| refresh every | slider | No |  |
| freeze time | slider | No |  |
| sleep rate | slider | No |  |

## void_hide_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| type | dropdown | Yes | VoidSpam |
| bait distance | slider | Yes | VoidSpam |
| bait cooldown | slider | Yes | VoidSpam |
| bait time | slider | Yes | VoidSpam |
| bait freeze | toggle | Yes | VoidSpam |
| bait spot | dropdown | Yes | VoidSpam |
| deep distance | slider | Yes | VoidSpam |
| disable when | dropdown | No |  |
| force when | dropdown | Yes | VoidSpam |
| spam | toggle | Yes | VoidSpam |
| stop if forced | toggle | Yes | VoidSpam |
| out with target | toggle | Yes | VoidSpam |
| hide while target hides | toggle | Yes | VoidSpam |
| offset | slider | Yes | VoidSpam |
| void time | slider | Yes | VoidSpam |
| teleport time | slider | Yes | VoidSpam |

## safe_purchasing_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| avoid statuses | dropdown | Yes | Shop |

## auto_loadout_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| disable when | dropdown | Partial | Shop (pause when target selected / alive) |
| guns | dropdown | Yes | Shop |
| ammo | slider | Yes | Shop |

## follow_target_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| follow style | dropdown | Yes | Follow |
| stop if | dropdown | Yes | Follow |
| distance | slider | Yes | Follow |
| adjust | toggle | No |  |
| lead | toggle | Yes | Follow |
| lead time | slider | Yes | Follow |
| reposition every | slider | Yes | Follow |
| height | slider | Yes | Follow |
| speed | slider | Yes | Follow |
| orbit shape | dropdown | Yes | Follow |
| teleport min | slider | Yes | Follow |
| teleport max | slider | Yes | Follow |
| height min | slider | Yes | Follow |
| height max | slider | Yes | Follow |
| zig zag height | slider | Yes | Follow |
| zig zag speed | slider | Yes | Follow |
| visualize | toggle | Yes | Follow |
| visualize color | colorpicker | Yes | Follow |

## auto_stomp_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| stop when target dead | toggle | Yes | AutoStomp |
| target statuses | dropdown | Yes | AutoStomp |
| wait for all targets knocked | toggle | Yes | AutoStomp |
| prioritize over reloading | toggle | No |  |

## auto_ammo_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| disable when | dropdown | Partial | Shop (pause when target selected / alive) |
| minimum clips | slider | Yes | Shop |
| purchase amount | slider | Yes | Shop |

## auto_armor_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| purchase if below | slider | Yes | Shop |
| try cooldown | slider | Yes | Shop |

## anti_stomp_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| teleport back | toggle | Yes | AntiStomp |

## anti_report_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| kick | toggle | No |  |
| kick only if in a fight | toggle | No |  |
| fight window | slider | No |  |

## auto_mask_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| disable when | dropdown | Partial | Shop (pause when target selected / alive) |

## auto_heal_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| purchase if below | slider | Yes | Shop |
| try cooldown | slider | Yes | Shop |
| stop following while healing | toggle | Yes | Shop / Follow |

## rapid_fire_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| glory patch | toggle | No |  |
| hold to fire | toggle | No |  |
| fire delay | slider | No |  |
| speed | slider | No |  |

## control_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| chat replies | toggle | No |  |

## legitbot_target_selection_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| target swap cooldown | slider | Yes | Legit (sticky target) |
| target distance | slider | Partial | per-feature max distance |

## legitbot_settings_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| notification | toggle | No |  |
| automatic | toggle | No |  |
| target bind | keybind | No |  |
| untarget when | dropdown | No |  |
| target statuses | dropdown | Yes | Legit |
| ignore if | dropdown | Partial | Legit (shared ignore knocked / protected; per-feature FOV) |
| field of view | slider | Partial | Legit (shared ignore knocked / protected; per-feature FOV) |

## aim_assist_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| aim assist | toggle | Yes | AimAssist |
| smoothing | toggle | Yes | AimAssist |
| field of view | slider | Yes | AimAssist |

## aim_assist_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| hitbox | dropdown | Yes | AimAssist |
| method | dropdown | Yes | AimAssist |
| dont aim if | dropdown | Partial | AimAssist (knocked, protected, visibility) |
| max distance | slider | Yes | AimAssist |
| multipoint | slider | No |  |

## aim_assist_smoothing_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| type | dropdown | No |  |
| horizontal | slider | Yes | AimAssist |
| vertical | slider | Yes | AimAssist |

## aim_assist_field_of_view_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| dead zone | slider | No |  |
| show fov | toggle | Yes | Visuals |
| dead zone | colorpicker | No |  |
| outline | colorpicker | No |  |

## silent_aim_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| silent aim | toggle | Yes | SilentAim |
| field of view | slider | Yes | SilentAim |
| max curve | slider | Yes | SilentAim |
| bullet manipulation | toggle | Declined | changes the shot data claimed to the server / exceeds the server fire rate |
| range enhancer | toggle | Declined | changes the shot data claimed to the server / exceeds the server fire rate |
| double tap | toggle | Declined | changes the shot data claimed to the server / exceeds the server fire rate |

## silent_aim_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| hitbox | dropdown | Yes | SilentAim |
| max distance | slider | Yes | SilentAim |
| multipoint | slider | No |  |
| force hit | toggle | Declined | claims a hit the shot did not make |
| redirect chance | slider | Yes | SilentAim |

## silent_aim_field_of_view_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| show fov | toggle | Yes | Visuals |
| outline | colorpicker | No |  |

## silent_aim_max_curve_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| dont curve vertically | toggle | Yes | SilentAim |

## silent_aim_bullet_manipulation_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| hit checker | toggle | Declined | part of bullet manipulation |
| manipulated indicator | toggle | Declined | part of bullet manipulation |

## triggerbot_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| triggerbot | toggle | Yes | Triggerbot |

## triggerbot_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| max distance | slider | Yes | Triggerbot |
| hitboxes | dropdown | Yes | Triggerbot |
| refresh rate | slider | Yes | Triggerbot |
| hover time | slider | Yes | Triggerbot |
| cooldown | slider | Yes | Triggerbot |
| delay | slider | Yes | Triggerbot |

## legitbot_other_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| reduce shotgun spread | toggle | Declined | changes the shot data claimed to the server |
| remove recoil | toggle | No |  |
| range enhancer | toggle | Declined | changes the shot data claimed to the server |
| quick draw | toggle | Partial | QuickDraw |
| lead fast targets | toggle | Partial | Resolver lead |

## reduce_shotgun_spread_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| reduce amount | slider | No |  |

## quick_draw_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| guns | dropdown | Yes | QuickDraw |

