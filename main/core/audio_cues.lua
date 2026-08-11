-- The catalogue of every sound the game triggers (PRD section 8). Pure data
-- plus a lookup — no Defold API here (rule 1); main/ui/audio.script is what
-- actually plays a sound component, and it reads this to know which cue maps
-- to which group and clip.
--
-- This exists NOW, before any .ogg exists, on purpose: it makes the full
-- list of required cues reviewable against the PRD in one place, and lets
-- every gameplay adapter post its cue by name today. When the audio assets
-- land, only the adapter's clip table changes — none of the trigger sites,
-- which already name the right cue.

local M = {}

-- group is which mixer channel a cue plays on (so the settings screen's
-- music/sfx sliders route correctly); every entry here is a PRD section 8
-- requirement, grouped by its heading so nothing is silently missing.
M.CUES = {
	-- Player
	step        = { group = "sfx" },
	jump        = { group = "sfx" },
	land        = { group = "sfx" },
	player_death = { group = "sfx" },
	-- Package
	package_shake    = { group = "sfx" },
	package_panic    = { group = "sfx" },
	package_explode  = { group = "sfx" },
	package_heavy    = { group = "sfx" },
	package_light    = { group = "sfx" },
	package_sleep    = { group = "sfx" },
	package_wake     = { group = "sfx" },
	package_magnet   = { group = "sfx" },
	-- Environment
	hazard       = { group = "sfx" },
	platform_fall = { group = "sfx" },
	delivery     = { group = "sfx" },
	-- UI
	ui_move    = { group = "sfx" },
	ui_confirm = { group = "sfx" },
	ui_back    = { group = "sfx" },
	-- Music (looping)
	music_menu     = { group = "music", loop = true },
	-- The fallback for any level with no theme of its own. screens.script
	-- checks exists() before asking for music_level_N, so adding an
	-- eleventh level cannot silently produce a silent level.
	music_gameplay = { group = "music", loop = true },
	music_win      = { group = "music" },
	music_gameover = { group = "music" },
	-- One theme per level. Listed individually rather than generated in a
	-- loop so this table stays what it claims to be: a flat catalogue that
	-- can be read against PRD section 8 without running anything.
	music_level_1  = { group = "music", loop = true },
	music_level_2  = { group = "music", loop = true },
	music_level_3  = { group = "music", loop = true },
	music_level_4  = { group = "music", loop = true },
	music_level_5  = { group = "music", loop = true },
	music_level_6  = { group = "music", loop = true },
	music_level_7  = { group = "music", loop = true },
	music_level_8  = { group = "music", loop = true },
	music_level_9  = { group = "music", loop = true },
	music_level_10 = { group = "music", loop = true },
}

function M.exists(cue)
	return M.CUES[cue] ~= nil
end

function M.group_of(cue)
	local entry = M.CUES[cue]
	return entry and entry.group or nil
end

return M
