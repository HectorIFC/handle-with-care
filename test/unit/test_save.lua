local save = require "main.core.save"

return function()
	describe("save.new", function()
		test("a fresh save has only level 1 unlocked and nothing completed", function()
			local state = save.new(10)
			assert(state.unlocked == 1)
			assert(save.is_unlocked(state, 1) == true)
			assert(save.is_unlocked(state, 2) == false)
			assert(save.is_completed(state, 1) == false)
			assert(save.all_complete(state) == false)
		end)

		test("level 0 and negative levels are never unlocked", function()
			local state = save.new(10)
			assert(save.is_unlocked(state, 0) == false)
			assert(save.is_unlocked(state, -1) == false)
		end)
	end)

	describe("save.complete_level", function()
		test("completing a level unlocks the next", function()
			local state = save.complete_level(save.new(10), 1, 42)
			assert(save.is_completed(state, 1) == true)
			assert(save.is_unlocked(state, 2) == true)
			assert(save.is_unlocked(state, 3) == false)
		end)

		test("does not mutate the state it was given", function()
			-- Rule 2: require() caches this module, so a mutating API would
			-- quietly share one save between every caller.
			local before = save.new(10)
			save.complete_level(before, 1, 42)
			assert(before.unlocked == 1)
			assert(before.completed[1] == nil)
		end)

		test("cannot unlock past the last level", function()
			local state = save.complete_level(save.new(3), 3, 10)
			assert(state.unlocked == 3)
			assert(save.is_completed(state, 3) == true)
		end)

		test("replaying an early level does not move progression backwards", function()
			local state = save.new(10)
			state = save.complete_level(state, 1, 50)
			state = save.complete_level(state, 2, 50)
			assert(state.unlocked == 3)
			state = save.complete_level(state, 1, 50) -- replay level 1
			assert(state.unlocked == 3)
		end)

		test("keeps the best time and ignores a slower one", function()
			local state = save.complete_level(save.new(10), 1, 50)
			assert(state.best_times[1] == 50)
			state = save.complete_level(state, 1, 70)
			assert(state.best_times[1] == 50)
			state = save.complete_level(state, 1, 30)
			assert(state.best_times[1] == 30)
		end)

		test("a completion with no time still counts as completed", function()
			local state = save.complete_level(save.new(10), 1, nil)
			assert(save.is_completed(state, 1) == true)
			assert(state.best_times[1] == nil)
		end)
	end)

	describe("save.all_complete", function()
		test("true only once every level is completed", function()
			local state = save.new(3)
			state = save.complete_level(state, 1, 10)
			state = save.complete_level(state, 2, 10)
			assert(save.all_complete(state) == false)
			state = save.complete_level(state, 3, 10)
			assert(save.all_complete(state) == true)
		end)
	end)

	describe("save.record_attempt and has_progress", function()
		test("attempts accumulate per level", function()
			local state = save.new(10)
			state = save.record_attempt(state, 1)
			state = save.record_attempt(state, 1)
			state = save.record_attempt(state, 2)
			assert(state.attempts[1] == 2)
			assert(state.attempts[2] == 1)
		end)

		test("a fresh save has no progress, so the menu hides Continue", function()
			assert(save.has_progress(save.new(10)) == false)
		end)

		test("a single attempt already counts as progress", function()
			local state = save.record_attempt(save.new(10), 1)
			assert(save.has_progress(state) == true)
		end)
	end)

	describe("save.wipe", function()
		test("New Game clears everything back to a fresh save", function()
			local state = save.complete_level(save.new(10), 1, 10)
			state = save.record_attempt(state, 2)
			local wiped = save.wipe(state)
			assert(wiped.unlocked == 1)
			assert(save.is_completed(wiped, 1) == false)
			assert(save.has_progress(wiped) == false)
			assert(wiped.total_levels == 10) -- level count survives the wipe
		end)
	end)

	describe("save.sanitize", function()
		test("nil or non-table input yields a fresh save rather than an error", function()
			-- A save file is the one input the game reads that it did not
			-- write this run: absent, truncated or hand-edited must all be
			-- survivable, never a crash on boot.
			assert(save.sanitize(nil, 10).unlocked == 1)
			assert(save.sanitize("garbage", 10).unlocked == 1)
			assert(save.sanitize(42, 10).unlocked == 1)
		end)

		test("a valid save round-trips intact", function()
			local original = save.complete_level(save.new(10), 1, 33)
			original = save.record_attempt(original, 2)
			local restored = save.sanitize(original, 10)
			assert(restored.unlocked == 2)
			assert(restored.completed[1] == true)
			assert(restored.best_times[1] == 33)
			assert(restored.attempts[2] == 1)
		end)

		test("an unlocked level beyond the level count is clamped", function()
			local restored = save.sanitize({ unlocked = 99 }, 10)
			assert(restored.unlocked == 10)
		end)

		test("completion records re-derive unlocked if that field was lost", function()
			local restored = save.sanitize({ completed = { [1] = true, [2] = true } }, 10)
			assert(restored.unlocked == 3)
		end)

		test("malformed entries are dropped instead of poisoning the state", function()
			local restored = save.sanitize({
				unlocked = "not a number",
				completed = { ["one"] = true, [2] = "yes", [3] = true },
				best_times = { [1] = "fast", [2] = -5, [3] = 12 },
				attempts = { [1] = 1.5, [2] = 3 },
			}, 10)
			assert(restored.completed[3] == true)
			assert(restored.completed["one"] == nil)
			assert(restored.completed[2] == nil) -- "yes" is not true
			assert(restored.best_times[1] == nil)
			assert(restored.best_times[2] == nil) -- negative
			assert(restored.best_times[3] == 12)
			assert(restored.attempts[1] == nil) -- fractional
			assert(restored.attempts[2] == 3)
			-- unlocked was unusable, so it comes from the completion records
			assert(restored.unlocked == 4)
		end)
	end)
end
