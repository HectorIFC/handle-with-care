local wait = require "test.support.wait"
local flow = require "main.core.screen_flow"

-- Menu, level select, pause and result screens (PRD 6.1/6.2).
--
-- The screens object in test/test.collection runs with test_mode = true, so
-- every collectionproxy message is suppressed: the shared fixture has no
-- proxy, and loading a real level into it would duplicate the player and
-- package every other suite depends on. What IS covered is the whole screen
-- state machine and the key routing into it. What is NOT covered — the proxy
-- actually loading, enabling and time-stepping a level — stays a
-- manual-checklist item, and last_requested_level is how a test still
-- asserts that the right level WOULD have been loaded.

local function press(action)
	msg.post("/screens#script", "test_input", { action = action })
	wait.frames(2)
end

local function goto_screen(screen)
	msg.post("/screens#script", "test_set_screen", { screen = screen })
	wait.frames(2)
end

local function reset_all()
	msg.post("/save_adapter#script", "new_game")
	msg.post("/screens#script", "test_set_screen", { screen = flow.MENU })
	wait.frames(3)
end

return function()
	describe("Screens: menu, level select, pause, result (integration)", function()
		before(reset_all)

		test("the game opens on the main menu", function()
			assert(go.get("/screens#script", "screen") == hash(flow.MENU))
			assert(go.get("/screens#script", "cursor") == 1)
		end)

		test("menu_down moves the cursor and wraps around the entry list", function()
			-- A fresh save has no Continue, so the list is New Game / Level
			-- Select / Quit — three entries, and the fourth press wraps.
			press("menu_down")
			assert(go.get("/screens#script", "cursor") == 2)
			press("menu_down")
			assert(go.get("/screens#script", "cursor") == 3)
			press("menu_down")
			assert(go.get("/screens#script", "cursor") == 1)
		end)

		test("menu_up from the first entry wraps to the last", function()
			press("menu_up")
			assert(go.get("/screens#script", "cursor") == 3)
		end)

		test("New Game starts level 1", function()
			press("confirm") -- cursor is on New Game for a fresh save
			assert(go.get("/screens#script", "screen") == hash(flow.PLAYING))
			assert(go.get("/screens#script", "last_requested_level") == 1)
		end)

		test("Level Select opens the level grid and Esc returns to the menu", function()
			press("menu_down") -- New Game -> Level Select
			press("confirm")
			assert(go.get("/screens#script", "screen") == hash(flow.LEVEL_SELECT))

			press("pause") -- Esc backs out
			assert(go.get("/screens#script", "screen") == hash(flow.MENU))
		end)

		test("level select cannot move onto a locked level", function()
			-- PRD 6.1 shows unlocked levels only. With a fresh save just
			-- level 1 is unlocked, so moving right stays put rather than
			-- selecting something unplayable.
			goto_screen(flow.LEVEL_SELECT)
			press("move_right")
			assert(go.get("/screens#script", "selected_level") == 1)
		end)

		test("Esc pauses a running level and Esc again resumes it", function()
			press("confirm") -- New Game -> PLAYING
			assert(go.get("/screens#script", "screen") == hash(flow.PLAYING))

			press("pause")
			assert(go.get("/screens#script", "screen") == hash(flow.PAUSED))

			press("pause")
			assert(go.get("/screens#script", "screen") == hash(flow.PLAYING))
		end)

		test("the pause menu can return to the main menu", function()
			press("confirm") -- start playing
			press("pause")
			press("menu_down") -- Resume -> Restart
			press("menu_down") -- Restart -> Main Menu
			press("confirm")
			assert(go.get("/screens#script", "screen") == hash(flow.MENU))
		end)

		test("Restart from the pause menu reloads the same level", function()
			press("confirm") -- New Game starts level 1
			press("pause")
			press("menu_down") -- Resume -> Restart
			press("confirm")
			assert(go.get("/screens#script", "screen") == hash(flow.PLAYING))
			assert(go.get("/screens#script", "last_requested_level") == 1)
		end)

		test("finishing a level shows the result screen", function()
			press("confirm") -- start playing
			msg.post("/screens#script", "level_finished", {
				won = true, level = 1, time = 42.5, attempts = 3,
			})
			wait.frames(2)
			assert(go.get("/screens#script", "screen") == hash(flow.RESULT))
		end)

		test("a loss also reaches the result screen, not a dead end", function()
			-- A death with no way out but the R key would strand the player
			-- with no route back to the menu.
			press("confirm")
			msg.post("/screens#script", "level_finished", {
				won = false, level = 1, time = 12.0, attempts = 1,
			})
			wait.frames(2)
			assert(go.get("/screens#script", "screen") == hash(flow.RESULT))
		end)

		test("the result screen's Retry replays the same level", function()
			press("confirm")
			msg.post("/screens#script", "level_finished", {
				won = false, level = 1, time = 12.0, attempts = 1,
			})
			wait.frames(2)
			press("confirm") -- a loss offers Retry first (no Next Level)
			assert(go.get("/screens#script", "screen") == hash(flow.PLAYING))
			assert(go.get("/screens#script", "last_requested_level") == 1)
		end)

		test("Continue appears once there is progress and resumes the furthest level", function()
			-- Drive the save forward directly rather than by playing, so this
			-- tests the menu's reaction to progression, not the gameplay.
			msg.post("/save_adapter#script", "level_completed", { level = 1, time = 30 })
			msg.post("/screens#script", "test_set_screen", { screen = flow.MENU })
			wait.frames(3)
			assert(go.get("/save_adapter#script", "unlocked") == 2)

			press("confirm") -- Continue is now the first entry
			assert(go.get("/screens#script", "screen") == hash(flow.PLAYING))
			assert(go.get("/screens#script", "last_requested_level") == 2)
		end)

		test("gameplay keys are ignored by the screens object while playing", function()
			-- The level owns the keyboard once it is live; the screens object
			-- must not eat a jump or move as menu navigation.
			press("confirm") -- start playing
			local cursor_before = go.get("/screens#script", "cursor")
			press("menu_down")
			assert(go.get("/screens#script", "cursor") == cursor_before)
			assert(go.get("/screens#script", "screen") == hash(flow.PLAYING))
		end)
	end)
end
