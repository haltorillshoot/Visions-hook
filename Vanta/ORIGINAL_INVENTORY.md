# Visions-hook menu inventory against Vanta

Generated from the 517 controls the older menu in `Visions-hook.lua` creates (`menu_references[...]:create_element`), grouped by the section that holds them. **Implemented** means the underlying behaviour exists in Vanta and is wired to a menu control; the live test results are in `FEATURES.md`. Everything not marked is **No**.

Status: **Yes** = implemented, **Partial** = a working core with options missing, **No** = not implemented, **Declined** = deliberately not reproduced (reason given).

**Totals (517 controls):** Yes 152, Partial 24, No 326, Declined 15.

## panel_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| purchase item | button | No |  |
| ammo amount | slider | No |  |
| purchase ammo | button | No |  |

## movement_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| remove jump cooldown | toggle | No |  |
| remove slowdowns | toggle | No |  |
| lock walk speed | toggle | No |  |
| jump power | toggle | Yes | Movement |
| anti trip | toggle | No |  |
| anti sit | toggle | Yes | Movement |
| noclip | toggle | Yes | Movement |
| speed | toggle | Yes | Movement |
| flight | toggle | Yes | Movement |
| pushback guard | toggle | No |  |

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
| animation breaker | toggle | No |  |
| animation player | toggle | No |  |
| trash talk | toggle | No |  |
| spinbot | toggle | No |  |
| hide player nametags | toggle | No |  |

## animation_breaker_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| lag | slider | No |  |
| jitter | slider | No |  |

## animation_player_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| animation | dropdown | No |  |
| asset id | textbox | No |  |

## trash_talk_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| message list | dropdown | No |  |
| always | toggle | No |  |
| activate when | dropdown | No |  |

## spinbot_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| speed | slider | No |  |

## utility_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| remove flintlock knockback | toggle | No |  |
| unlock custom crosshair | toggle | No |  |
| unlock animation packs | toggle | No |  |
| unlock camera distance | toggle | No |  |
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
| auto save friendlies | toggle | No |  |
| auto set statuses | toggle | No |  |

## auto_save_friendlies_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| ignore range | slider | No |  |

## auto_set_statuses_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| set friendly if | dropdown | No |  |
| set enemy if | dropdown | No |  |
| notifications | toggle | No |  |

## lighting_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| background noise | toggle | No |  |
| lighting mode | toggle | No |  |
| world time | toggle | No |  |
| atmosphere | toggle | No |  |
| saturation | toggle | No |  |
| contrast | toggle | No |  |
| textures | toggle | No |  |
| ambient | toggle | No |  |
| weather | toggle | No |  |
| skybox | toggle | No |  |
| tint | toggle | No |  |

## background_noise_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| sound | dropdown | No |  |
| volume | slider | No |  |

## atmosphere_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | No |  |
| decay | colorpicker | No |  |
| haze | slider | No |  |
| glare | slider | No |  |
| offset | slider | No |  |
| density | slider | No |  |

## textures_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| pack | dropdown | No |  |

## ambient_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| outdoor color | colorpicker | No |  |
| color | colorpicker | No |  |

## weather_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| type | dropdown | No |  |
| color | colorpicker | No |  |
| rate | slider | No |  |

## skybox_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| sky | dropdown | No |  |

## hud_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| server position indicator | toggle | No |  |
| crosshair animations | toggle | No |  |
| drawing crosshair | toggle | No |  |
| center panel | toggle | No |  |
| aspect ratio | toggle | No |  |
| show chat | toggle | No |  |
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
| follow target | toggle | No |  |
| style | dropdown | No |  |
| target indicator | toggle | No |  |
| indicator color | colorpicker | No |  |
| animation style | dropdown | No |  |
| speed | slider | No |  |
| target outline color | colorpicker | No |  |
| target line color | colorpicker | No |  |
| outline color | colorpicker | No |  |
| line color | colorpicker | No |  |
| line thickness | slider | No |  |
| line size | slider | No |  |
| gap size | slider | No |  |
| rotating | slider | No |  |

## center_panel_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| show state | toggle | No |  |
| primary color | colorpicker | No |  |
| show target | toggle | No |  |
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
| hide game crosshair | toggle | No |  |
| disable rendering | toggle | No |  |
| motion blur | toggle | No |  |

## motion_blur_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| intensity | slider | No |  |

## skins_editor_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| skin changer | toggle | No |  |
| weapon | dropdown | No |  |

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
| chams | toggle | No |  |
| material | toggle | No |  |
| tool text | toggle | Yes | Esp |
| tool icon | toggle | No |  |
| distance | toggle | Yes | Esp |
| highlight | toggle | No |  |
| armor bar | toggle | Yes | Esp |
| health bar | toggle | Yes | Esp |
| health text | toggle | Yes | Esp |

## esp_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| render statuses | dropdown | No |  |

## box_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| outline | colorpicker | No |  |
| color | colorpicker | Partial | Esp (one colour, one target colour) |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

## name_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| use display name | toggle | Yes | Esp |
| color | colorpicker | Yes | Esp |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

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
| behind walls | toggle | No |  |
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

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
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |

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
| behind walls | toggle | No |  |
| color | colorpicker | No |  |
| enemy color | colorpicker | No |  |
| friendly color | colorpicker | No |  |
| outline color | colorpicker | No |  |
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
| character highlight | toggle | No |  |
| character material | toggle | No |  |
| custom character | toggle | No |  |
| skinny | toggle | No |  |
| material tools | toggle | No |  |
| rainbow weapon chams | toggle | No |  |
| china hat | toggle | No |  |
| particle aura | toggle | No |  |

## local_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| material | dropdown | No |  |
| color | colorpicker | No |  |

## character_highlight_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | No |  |
| outline | colorpicker | No |  |

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
| speed | slider | No |  |
| saturation | slider | No |  |
| brightness | slider | No |  |
| transparency | slider | No |  |
| material | dropdown | No |  |

## china_hat_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | No |  |
| light color | colorpicker | No |  |
| scale | slider | No |  |
| light brightness | slider | No |  |

## particle_aura_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| color | colorpicker | No |  |
| particle | dropdown | No |  |

## general_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| ragebot | toggle | Yes | Ragebot / AutoFire / AdStrafe / Target |
| auto fire | toggle | Yes | Ragebot / AutoFire / AdStrafe / Target |
| a/d | toggle | Yes | Ragebot / AutoFire / AdStrafe / Target |
| auto equip | toggle | Partial | AutoFire / Resolver |
| spam resolver | toggle | Partial | AutoFire / Resolver |
| target hitbox | dropdown | Yes | Ragebot / AutoFire / AdStrafe / Target |
| prediction | slider | Partial | AutoFire / Resolver |
| shot delay | slider | No |  |
| field of view | slider | Yes | Ragebot / AutoFire / AdStrafe / Target |
| fire cooldown | slider | No |  |

## auto_fire_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| at target vehicle | toggle | No |  |
| always fire | toggle | No |  |
| dont render | toggle | No |  |
| show fake bullets | toggle | No |  |
| pre fire | toggle | No |  |
| pre fire time | slider | No |  |
| bullet manipulation | toggle | No |  |
| fast retry | toggle | No |  |
| double tap | toggle | No |  |
| gun gap | slider | Yes | AutoFire |

## ad_strafe_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| interval | slider | Yes | AdStrafe |

## auto_equip_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| unequip when | dropdown | No |  |
| gun | dropdown | No |  |
| prioritize db | toggle | No |  |
| distance check | toggle | No |  |

## auto_fire_defensive_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| type | dropdown | Partial | Resolver (cluster, adaptive) |
| refresh time | slider | No |  |
| forgiveness | slider | No |  |
| out of void bonus | slider | No |  |
| normal position trust | slider | No |  |
| forget rate | slider | No |  |
| void trust | slider | No |  |
| accuracy | slider | No |  |
| distance based penalty | slider | Partial | Resolver (cluster, adaptive) |
| lerp % when close | slider | No |  |

## prediction_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| resolver rate | slider | No |  |
| strength | slider | Partial | Resolver lead |
| velocity source | dropdown | No |  |

## target_selection_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| notification | toggle | Yes | Target |
| automatic | toggle | Yes | Target |
| cooldown | slider | Yes | Target |
| target bind | keybind | Yes | Target |
| target when shot at | toggle | No |  |
| force | toggle | No |  |
| wait for spawn protection | toggle | No |  |
| void while waiting | toggle | No |  |
| untarget when | dropdown | Yes | Target |
| target statuses | dropdown | No |  |
| target players | dropdown | No |  |
| prioritize by | dropdown | Yes | Target |
| ignore if | dropdown | Yes | Target |
| target distance | slider | Yes | Target |

## visualization_section

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| information panel | toggle | No |  |
| crosshair follow | toggle | No |  |
| 3d target circle | toggle | Yes | Visuals |
| view target | toggle | Yes | Visuals |
| face target | toggle | No |  |
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
| stop when knocked | toggle | No |  |

## ragebot_field_of_view_show_fov_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| follow target | toggle | No |  |
| color | colorpicker | Yes | Visuals |
| outline | colorpicker | No |  |
| active color | colorpicker | Yes | Visuals |
| active outline | colorpicker | No |  |

## ragebot_tracer_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| thickness | slider | Yes | Visuals |
| color | colorpicker | Yes | Visuals |
| outline | colorpicker | No |  |
| origin | dropdown | Yes | Visuals |
| end point | dropdown | No |  |

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
| force when | dropdown | No |  |
| spam | toggle | Yes | VoidSpam |
| stop if forced | toggle | No |  |
| out with target | toggle | No |  |
| hide while target hides | toggle | No |  |
| offset | slider | Yes | VoidSpam |
| void time | slider | Yes | VoidSpam |
| teleport time | slider | Yes | VoidSpam |

## safe_purchasing_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| avoid statuses | dropdown | Partial | Shop (target / anyone) |

## auto_loadout_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| disable when | dropdown | No |  |
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
| target statuses | dropdown | No |  |
| wait for all targets knocked | toggle | No |  |
| prioritize over reloading | toggle | No |  |

## auto_ammo_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| disable when | dropdown | No |  |
| minimum clips | slider | Yes | Shop |
| purchase amount | slider | Yes | Shop |

## auto_armor_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| purchase if below | slider | Yes | Shop |
| try cooldown | slider | No |  |

## anti_stomp_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| teleport back | toggle | No |  |

## anti_report_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| kick | toggle | No |  |
| kick only if in a fight | toggle | No |  |
| fight window | slider | No |  |

## auto_mask_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| disable when | dropdown | No |  |

## auto_heal_settings

| Original control | Type | Vanta | Where / note |
|---|---|---|---|
| purchase if below | slider | Yes | Shop |
| try cooldown | slider | Yes | Shop |
| stop following while healing | toggle | No |  |

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
| target statuses | dropdown | No |  |
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

