local loc = require "main.core.save_location"

return function()
	describe("save_location", function()
		test("has one app id, shared by both adapters", function()
			-- The whole point of extracting this: the literal used to live in
			-- two adapters, free to drift.
			assert(type(loc.APP_ID) == "string" and #loc.APP_ID > 0)
		end)

		test("progress and settings are distinct files", function()
			-- Same lesson as keeping the two adapters separate: one must never
			-- overwrite the other.
			assert(loc.filename("progress") ~= loc.filename("settings"))
		end)

		test("defaults to the sys backend", function()
			-- Web, editor, DRM-free desktop: sys.save covers all of them, and
			-- Defold maps it to localStorage on Web on its own.
			assert(loc.backend() == loc.BACKEND_SYS)
			assert(loc.backend({}) == loc.BACKEND_SYS)
			assert(loc.backend({ steam = false }) == loc.BACKEND_SYS)
		end)

		test("uses the Steam backend only when the build opts in", function()
			-- Opt-in, not platform-sniffed: the same desktop binary can ship
			-- DRM-free and on Steam, and only the build knows which.
			assert(loc.backend({ steam = true }) == loc.BACKEND_STEAM)
		end)

		test("filename falls back to progress for an unknown kind", function()
			assert(loc.filename("progress") == loc.PROGRESS_FILE)
			assert(loc.filename("whatever") == loc.PROGRESS_FILE)
		end)
	end)
end
