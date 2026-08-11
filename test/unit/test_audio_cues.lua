local cues = require "main.core.audio_cues"

return function()
	describe("audio_cues", function()
		test("every cue routes to a real mixer group", function()
			-- A cue on an unknown group would silently never respond to any
			-- volume slider.
			for name, entry in pairs(cues.CUES) do
				assert(entry.group == "sfx" or entry.group == "music",
					name .. " has no valid group")
			end
		end)

		test("covers the PRD section 8 headings", function()
			-- A representative cue from each of the five headings, so a
			-- deletion is caught here rather than by a silent missing sound.
			for _, name in ipairs({
				"jump", "player_death",              -- player
				"package_explode", "package_wake",   -- package
				"hazard", "delivery",                -- environment
				"ui_confirm",                        -- UI
				"music_menu", "music_gameover",      -- music
			}) do
				assert(cues.exists(name), "missing cue: " .. name)
			end
		end)

		test("music cues are on the music group, effects on sfx", function()
			assert(cues.group_of("music_menu") == "music")
			assert(cues.group_of("jump") == "sfx")
		end)

		test("an unknown cue has no group rather than a wrong one", function()
			assert(cues.exists("not_a_cue") == false)
			assert(cues.group_of("not_a_cue") == nil)
		end)

		test("every level has its own theme, on the music group", function()
			-- screens.script builds this name from the level number, so a
			-- gap here is a level that loads in silence.
			for level = 1, 10 do
				local name = "music_level_" .. level
				assert(cues.exists(name), "missing theme: " .. name)
				assert(cues.group_of(name) == "music", name .. " is not music")
			end
		end)

		test("the fallback theme still exists for a level with no track", function()
			-- screens.script falls back to this when music_level_N is
			-- absent; losing it would turn that safe path into a crash.
			assert(cues.exists("music_gameplay"))
			assert(cues.group_of("music_gameplay") == "music")
		end)
	end)
end
