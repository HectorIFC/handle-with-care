local flow = require "main.core.screen_flow"
local save = require "main.core.save"

-- Deterministic stand-in for math.random (rule 3), so quip choice is a fact
-- rather than a coin flip.
local function fixed_rng(value)
	return function() return value end
end

return function()
	describe("screen_flow.menu_entries", function()
		test("a fresh save hides Continue", function()
			local entries = flow.menu_entries({ has_progress = false })
			assert(entries[1].action == flow.ACTION_NEW_GAME)
			for _, entry in ipairs(entries) do
				assert(entry.action ~= flow.ACTION_CONTINUE)
			end
		end)

		test("an existing save shows Continue first", function()
			-- PRD 6.1: "Continuar (só aparece se existir save)". First,
			-- because it is what a returning player wants — and putting it
			-- above New Game means the destructive entry is never the one
			-- under the cursor by default.
			local entries = flow.menu_entries({ has_progress = true })
			assert(entries[1].action == flow.ACTION_CONTINUE)
		end)

		test("Options and Credits are absent until phase 21 implements them", function()
			local entries = flow.menu_entries({ has_progress = true })
			for _, entry in ipairs(entries) do
				assert(entry.label ~= "Options")
				assert(entry.label ~= "Credits")
			end
		end)
	end)

	describe("screen_flow.move_cursor", function()
		test("moves down and up within range", function()
			local state = flow.new()
			state = flow.move_cursor(state, 1, 4)
			assert(state.cursor == 2)
			state = flow.move_cursor(state, -1, 4)
			assert(state.cursor == 1)
		end)

		test("wraps past the last entry back to the first", function()
			local state = flow.new()
			state = flow.move_cursor(state, -1, 3) -- up from the first
			assert(state.cursor == 3)
			state = flow.move_cursor(state, 1, 3) -- down from the last
			assert(state.cursor == 1)
		end)

		test("an empty entry list cannot move the cursor or error", function()
			local state = flow.move_cursor(flow.new(), 1, 0)
			assert(state.cursor == 1)
		end)

		test("does not mutate the state it was given", function()
			local before = flow.new()
			flow.move_cursor(before, 1, 4)
			assert(before.cursor == 1)
		end)
	end)

	describe("screen_flow.move_level_cursor", function()
		test("cannot land on a locked level", function()
			-- PRD 6.1's level select shows unlocked levels only; walking off
			-- the end wraps rather than selecting something unplayable.
			local save_state = { total_levels = 10, unlocked = 3 }
			local state = flow.new()
			state.selected_level = 3
			state = flow.move_level_cursor(state, 1, save_state)
			assert(state.selected_level == 1)
		end)

		test("moving back from the first level wraps to the last unlocked one", function()
			local save_state = { total_levels = 10, unlocked = 4 }
			local state = flow.new()
			state = flow.move_level_cursor(state, -1, save_state)
			assert(state.selected_level == 4)
		end)

		test("with only level 1 unlocked the cursor stays put", function()
			local save_state = { total_levels = 10, unlocked = 1 }
			local state = flow.new()
			state = flow.move_level_cursor(state, 1, save_state)
			assert(state.selected_level == 1)
		end)
	end)

	describe("screen_flow.result_entries", function()
		test("a win offers Next Level", function()
			local entries = flow.result_entries({ total_levels = 10 }, 1, true)
			assert(entries[1].action == flow.ACTION_NEXT_LEVEL)
		end)

		test("a loss does not offer Next Level", function()
			local entries = flow.result_entries({ total_levels = 10 }, 1, false)
			for _, entry in ipairs(entries) do
				assert(entry.action ~= flow.ACTION_NEXT_LEVEL)
			end
		end)

		test("winning the final level does not offer a non-existent next one", function()
			local entries = flow.result_entries({ total_levels = 10 }, 10, true)
			for _, entry in ipairs(entries) do
				assert(entry.action ~= flow.ACTION_NEXT_LEVEL)
			end
			assert(entries[1].action == flow.ACTION_RETRY)
		end)
	end)

	describe("screen_flow.format_time", function()
		test("sub-minute times read as seconds", function()
			assert(flow.format_time(40.24) == "40.2s")
			assert(flow.format_time(0) == "0.0s")
		end)

		test("times past a minute read as m:ss.s", function()
			assert(flow.format_time(60) == "1:00.0")
			assert(flow.format_time(95.5) == "1:35.5")
		end)
	end)

	describe("screen_flow.quip", function()
		test("draws from the win pool after a win", function()
			assert(flow.quip(true, fixed_rng(1)) == flow.WIN_QUIPS[1])
		end)

		test("draws from the loss pool after a loss", function()
			assert(flow.quip(false, fixed_rng(2)) == flow.LOSS_QUIPS[2])
		end)
	end)

	describe("screen_flow with a real save state", function()
		test("a save that has progress reaches the menu with Continue", function()
			-- Guards the seam between the two core modules: menu_entries
			-- reads has_progress, which is save.lua's own derived value, so
			-- a rename on either side should fail here rather than silently
			-- hiding Continue forever.
			local state = save.record_attempt(save.new(10), 1)
			local entries = flow.menu_entries({ has_progress = save.has_progress(state) })
			assert(entries[1].action == flow.ACTION_CONTINUE)
		end)
	end)
end
