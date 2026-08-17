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

		test("Options and Credits are offered now that they are real screens", function()
			-- They were withheld until phase 21 on purpose: a menu entry that
			-- goes nowhere is worse than no entry.
			local actions = {}
			for _, entry in ipairs(flow.menu_entries({ has_progress = true })) do
				actions[entry.action] = true
			end
			assert(actions[flow.ACTION_OPTIONS] == true)
			assert(actions[flow.ACTION_CREDITS] == true)
		end)
	end)

	describe("screen_flow.options_entries", function()
		test("carries the three volume channels the PRD names", function()
			local kinds = {}
			for _, entry in ipairs(flow.options_entries()) do
				if entry.kind then kinds[entry.kind] = true end
			end
			assert(kinds.master and kinds.music and kinds.sfx)
		end)

		test("the fullscreen row informs rather than pretending to toggle", function()
			-- This engine exposes no window.set_fullscreen, so the row can
			-- only tell the player the OS shortcut. It used to be a toggle
			-- wired to a pcall that swallowed the missing function, i.e. a
			-- control that did nothing at all.
			local row
			for _, entry in ipairs(flow.options_entries("ctrl+cmd+F")) do
				if entry.label == "Fullscreen" then row = entry end
			end
			assert(row, "the Fullscreen row is gone")
			assert(row.info == "ctrl+cmd+F")
			assert(row.toggle == nil)
			assert(row.action == flow.ACTION_NONE)
		end)

		test("the fullscreen row still says something without a hint", function()
			for _, entry in ipairs(flow.options_entries()) do
				if entry.label == "Fullscreen" then
					assert(type(entry.info) == "string" and #entry.info > 0)
				end
			end
		end)

		test("volume rows are marked as sliders so the adapter uses left/right", function()
			for _, entry in ipairs(flow.options_entries()) do
				if entry.kind then assert(entry.slider == true) end
			end
		end)

		test("the last entry gets the player back out", function()
			local entries = flow.options_entries()
			assert(entries[#entries].action == flow.ACTION_TO_MENU)
		end)

		test("offers Controls, since PRD 6.1 lists it among the options", function()
			local found = false
			for _, entry in ipairs(flow.options_entries()) do
				if entry.action == flow.ACTION_CONTROLS then found = true end
			end
			assert(found)
		end)
	end)

	describe("screen_flow.controls_entries", function()
		test("one rebindable row per action, in the order given", function()
			local entries = flow.controls_entries({ "move_left", "jump" })
			assert(#entries == 3) -- two actions plus Back
			assert(entries[1].bind == "move_left")
			assert(entries[1].action == flow.ACTION_REBIND)
			assert(entries[2].bind == "jump")
		end)

		test("Back returns to Options, not all the way to the menu", function()
			local entries = flow.controls_entries({ "jump" })
			assert(entries[#entries].action == flow.ACTION_OPTIONS)
		end)
	end)

	describe("screen_flow capture", function()
		test("begin_capture records which action is waiting for a key", function()
			local state = flow.set_screen(flow.new(), flow.CONTROLS)
			assert(state.capturing == nil)
			state = flow.begin_capture(state, "jump")
			assert(state.capturing == "jump")
		end)

		test("cancel_capture clears it without moving the cursor", function()
			local state = flow.begin_capture(flow.set_screen(flow.new(), flow.CONTROLS), "jump")
			state = flow.move_cursor(state, 1, 4)
			local cursor = state.cursor
			state = flow.cancel_capture(state)
			assert(state.capturing == nil)
			assert(state.cursor == cursor)
		end)

		test("moving the cursor does not silently drop a pending capture", function()
			-- move_cursor builds a new state by naming its fields, so a field
			-- it forgets disappears without any error — worth pinning.
			local state = flow.begin_capture(flow.set_screen(flow.new(), flow.CONTROLS), "jump")
			state = flow.move_cursor(state, 1, 4)
			assert(state.capturing == "jump")
		end)

		test("changing screen always ends a pending capture", function()
			local state = flow.begin_capture(flow.set_screen(flow.new(), flow.CONTROLS), "jump")
			state = flow.set_screen(state, flow.OPTIONS)
			assert(state.capturing == nil)
		end)
	end)

	describe("screen_flow.volume_bar", function()
		test("renders a level rather than a number", function()
			assert(flow.volume_bar(0, 10) == "..........")
			assert(flow.volume_bar(1, 10) == "##########")
			assert(flow.volume_bar(0.5, 10) == "#####.....")
		end)

		test("always returns the requested width", function()
			for _, v in ipairs({0, 0.13, 0.5, 0.87, 1}) do
				assert(#flow.volume_bar(v, 12) == 12)
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

		test("theme_page maps rooms to their five-room pages", function()
			assert(flow.theme_page(1) == 1)
			assert(flow.theme_page(5) == 1)
			assert(flow.theme_page(6) == 2)
			assert(flow.theme_page(40) == 8)
		end)

		test("move_level_page jumps to the first room of the next theme", function()
			local state = flow.new()
			state.selected_level = 3
			state = flow.move_level_page(state, 1,
				{ total_levels = 40, unlocked = 40 })
			assert(state.selected_level == 6)
		end)

		test("move_level_page clamps on the unlock, not the page", function()
			-- With only 7 rooms unlocked, asking for page 2 lands on 6 (its
			-- first room), and asking again lands on 7 — the furthest room
			-- reachable — never on 11, which would select a locked room.
			local save_state = { total_levels = 40, unlocked = 7 }
			local state = flow.new()
			state.selected_level = 1
			state = flow.move_level_page(state, 1, save_state)
			assert(state.selected_level == 6)
			state = flow.move_level_page(state, 1, save_state)
			assert(state.selected_level == 7)
		end)

		test("pages do not wrap at either end", function()
			-- move_level_cursor wraps because one room past the end reads as
			-- "around"; a PAGE flip past the end reads as a stuck button. So
			-- prev on page 1 stays, and next on the last page stays.
			local save_state = { total_levels = 40, unlocked = 40 }
			local state = flow.new()
			state.selected_level = 2
			state = flow.move_level_page(state, -1, save_state)
			assert(flow.theme_page(state.selected_level) == 1)
			state.selected_level = 38
			state = flow.move_level_page(state, 1, save_state)
			assert(flow.theme_page(state.selected_level) == 8)
			assert(state.selected_level == 36)
		end)
	end)
end
