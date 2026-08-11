local settings = require "main.core.settings"
local input_bindings = require "main.core.input_bindings"

return function()
	describe("settings defaults", function()
		test("starts audible but not at full blast", function()
			local s = settings.new()
			for _, kind in ipairs(settings.VOLUMES) do
				assert(s[kind] > 0 and s[kind] <= 1)
			end
			assert(s.fullscreen == false)
		end)
	end)

	describe("settings.adjust_volume", function()
		test("steps a volume up and down", function()
			local s = settings.new()
			local before = s.music
			s = settings.adjust_volume(s, "music", 0.1)
			assert(math.abs(s.music - (before + 0.1)) < 1e-9)
		end)

		test("clamps to 0..1 so no caller can hand the mixer a bad gain", function()
			local s = settings.adjust_volume(settings.new(), "sfx", 99)
			assert(s.sfx == 1)
			s = settings.adjust_volume(s, "sfx", -99)
			assert(s.sfx == 0)
		end)

		test("touches only the named channel", function()
			local s = settings.new()
			local master_before = s.master
			s = settings.adjust_volume(s, "sfx", -0.5)
			assert(s.master == master_before)
		end)

		test("does not mutate the state it was given", function()
			local before = settings.new()
			settings.adjust_volume(before, "master", -1)
			assert(before.master > 0)
		end)
	end)

	describe("settings.toggle_fullscreen", function()
		test("flips and flips back", function()
			local s = settings.toggle_fullscreen(settings.new())
			assert(s.fullscreen == true)
			assert(settings.toggle_fullscreen(s).fullscreen == false)
		end)
	end)

	describe("settings.effective_gain", function()
		test("music and sfx are scaled by master", function()
			-- Otherwise pulling master to zero would leave both channels
			-- audible, and the master slider would mean nothing.
			local s = settings.new()
			s.master, s.music, s.sfx = 0.5, 1.0, 0.4
			assert(math.abs(settings.effective_gain(s, "music") - 0.5) < 1e-9)
			assert(math.abs(settings.effective_gain(s, "sfx") - 0.2) < 1e-9)
		end)

		test("master at zero silences everything", function()
			local s = settings.new()
			s.master = 0
			assert(settings.effective_gain(s, "music") == 0)
			assert(settings.effective_gain(s, "sfx") == 0)
			assert(settings.effective_gain(s, "master") == 0)
		end)
	end)

	describe("settings.sanitize", function()
		test("junk input yields usable defaults rather than an error", function()
			assert(settings.sanitize(nil).master > 0)
			assert(settings.sanitize("nope").fullscreen == false)
		end)

		test("out-of-range and non-numeric volumes fall back or clamp", function()
			local s = settings.sanitize({ master = 5, music = -3, sfx = "loud" })
			assert(s.master == 1)
			assert(s.music == 0)
			assert(s.sfx > 0) -- unusable, so the default stands
		end)

		test("rejects NaN, which would silently poison every gain", function()
			local nan = 0 / 0
			local s = settings.sanitize({ master = nan })
			assert(s.master == s.master)
			assert(s.master > 0)
		end)

		test("a valid table round-trips", function()
			local original = settings.toggle_fullscreen(
				settings.adjust_volume(settings.new(), "sfx", -0.3))
			local restored = settings.sanitize(original)
			assert(math.abs(restored.sfx - original.sfx) < 1e-9)
			assert(restored.fullscreen == true)
		end)

		test("bindings are present by default and survive sanitize", function()
			local s = settings.new()
			assert(input_bindings.resolve(s.bindings, "key_a") == "move_left")
			-- A settings file written before remapping existed has no
			-- bindings field at all; it must come back playable, not nil.
			local restored = settings.sanitize({ master = 0.5 })
			assert(input_bindings.resolve(restored.bindings, "key_a") == "move_left")
		end)
	end)

	describe("Settings rebind", function()
		test("a valid rebind is applied without touching the volumes", function()
			local s = settings.adjust_volume(settings.new(), "music", -0.2)
			local rebound, err = settings.rebind(s, "jump", "key_j")
			assert(err == nil)
			assert(input_bindings.resolve(rebound.bindings, "key_j") == "jump")
			assert(math.abs(rebound.music - s.music) < 1e-9)
		end)

		test("a rejected rebind returns the state unchanged, with the reason", function()
			local s = settings.new()
			local result, err = settings.rebind(s, "jump", "key_a")
			assert(err ~= nil)
			assert(result == s)
			assert(input_bindings.resolve(s.bindings, "key_a") == "move_left")
		end)

		test("a rebind survives a sanitize round trip", function()
			local rebound = select(1, settings.rebind(settings.new(), "jump", "key_j"))
			local restored = settings.sanitize(rebound)
			assert(input_bindings.resolve(restored.bindings, "key_j") == "jump")
		end)
	end)
end
