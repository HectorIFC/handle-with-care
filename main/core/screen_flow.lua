-- Screen flow and menu navigation (PRD 6.1/6.2). Pure Lua, no Defold API
-- calls (rule 1): this module decides which screen is active, what a menu
-- offers, where the cursor is and what selecting an entry means. The
-- adapters under main/ui/ draw it and load the actual collections.
--
-- State in, new state out (rule 2) — nothing lives as a module upvalue.
-- No clock and no math.random here (rule 3): the result screen's quip is
-- chosen by an injected rng.

local M = {}

M.MENU = "menu"
M.LEVEL_SELECT = "level_select"
M.PLAYING = "playing"
M.PAUSED = "paused"
M.RESULT = "result"

-- Menu actions, returned by select() so the adapter knows what to do
-- without having to match on label text (which is display copy and will be
-- translated one day).
M.ACTION_NEW_GAME = "new_game"
M.ACTION_CONTINUE = "continue"
M.ACTION_LEVEL_SELECT = "level_select"
M.ACTION_QUIT = "quit"
M.ACTION_RESUME = "resume"
M.ACTION_RETRY = "retry"
M.ACTION_NEXT_LEVEL = "next_level"
M.ACTION_TO_MENU = "to_menu"
M.ACTION_PLAY_LEVEL = "play_level"
M.ACTION_NONE = "none"

function M.new()
	return { screen = M.MENU, cursor = 1, selected_level = 1 }
end

-- PRD 6.1's main menu. "Continuar" is present only when a save exists, so
-- the entry list is derived from save state rather than fixed — which is
-- also why the cursor is an index into THIS list, never a fixed slot.
-- Options and Credits are deliberately absent: the roadmap puts them in
-- phase 21 with the audio work, and offering a dead entry is worse than
-- not offering it.
function M.menu_entries(save_state)
	local entries = {}
	if save_state and save_state.has_progress then
		table.insert(entries, { label = "Continue", action = M.ACTION_CONTINUE })
	end
	table.insert(entries, { label = "New Game", action = M.ACTION_NEW_GAME })
	table.insert(entries, { label = "Level Select", action = M.ACTION_LEVEL_SELECT })
	table.insert(entries, { label = "Quit", action = M.ACTION_QUIT })
	return entries
end

function M.pause_entries()
	return {
		{ label = "Resume", action = M.ACTION_RESUME },
		{ label = "Restart", action = M.ACTION_RETRY },
		{ label = "Main Menu", action = M.ACTION_TO_MENU },
	}
end

-- The result screen offers "Next Level" only when there is a next level and
-- it is actually unlocked — which, right after a win, it always is, but not
-- when replaying an already-beaten level that is also the last one.
function M.result_entries(save_state, level, won)
	local entries = {}
	if won and save_state and level < save_state.total_levels then
		table.insert(entries, { label = "Next Level", action = M.ACTION_NEXT_LEVEL })
	end
	table.insert(entries, { label = "Retry", action = M.ACTION_RETRY })
	table.insert(entries, { label = "Main Menu", action = M.ACTION_TO_MENU })
	return entries
end

-- Wraps at both ends: with a handful of entries and no mouse, wrapping is
-- what makes "press down four times" reach the top again instead of
-- sticking.
function M.move_cursor(state, delta, entry_count)
	if entry_count <= 0 then
		return state
	end
	local new_state = { screen = state.screen, cursor = state.cursor, selected_level = state.selected_level }
	local zero_based = (state.cursor - 1 + delta) % entry_count
	new_state.cursor = zero_based + 1
	return new_state
end

-- Level select moves over a grid of levels, and only unlocked ones can be
-- landed on — PRD 6.1 says the screen shows "fases desbloqueadas".
function M.move_level_cursor(state, delta, save_state)
	local total = save_state.total_levels
	local new_state = { screen = state.screen, cursor = state.cursor, selected_level = state.selected_level }
	local candidate = state.selected_level + delta
	if candidate < 1 then
		candidate = save_state.unlocked
	elseif candidate > save_state.unlocked then
		candidate = 1
	end
	new_state.selected_level = candidate
	return new_state
end

function M.set_screen(state, screen)
	return { screen = screen, cursor = 1, selected_level = state.selected_level }
end

-- Formats an attempt duration for the result screen. Seconds with one
-- decimal below a minute, m:ss.s above it — a 40-second target time reads
-- worse as "0:40.2" than as "40.2s".
function M.format_time(seconds)
	if seconds < 60 then
		return string.format("%.1fs", seconds)
	end
	local minutes = math.floor(seconds / 60)
	return string.format("%d:%04.1f", minutes, seconds - minutes * 60)
end

-- PRD 6.2's "frase engraçada" on the result screen. rng is injected (rule 3)
-- and must return an integer in [1, n]; tests pass a stub so the chosen line
-- is deterministic.
M.WIN_QUIPS = {
	"Delivered. Somehow.",
	"The package remains suspicious of you.",
	"Signature not required. Sanity was.",
	"Another satisfied, deeply unstable customer.",
}

M.LOSS_QUIPS = {
	"The package regrets nothing.",
	"That went about as well as expected.",
	"Fragile. Handle with care. You did not.",
	"Somewhere, a customer is still waiting.",
}

function M.quip(won, rng)
	local pool = won and M.WIN_QUIPS or M.LOSS_QUIPS
	return pool[rng(1, #pool)]
end

return M
