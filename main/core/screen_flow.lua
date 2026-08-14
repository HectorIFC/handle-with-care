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
M.OPTIONS = "options"
M.CREDITS = "credits"
M.CONTROLS = "controls"

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
M.ACTION_OPTIONS = "options"
M.ACTION_CREDITS = "credits"
M.ACTION_VOLUME_MASTER = "volume_master"
M.ACTION_VOLUME_MUSIC = "volume_music"
M.ACTION_VOLUME_SFX = "volume_sfx"
M.ACTION_CONTROLS = "controls"
M.ACTION_REBIND = "rebind"
M.ACTION_NONE = "none"

function M.new()
	return { screen = M.MENU, cursor = 1, selected_level = 1, capturing = nil }
end

-- PRD 6.1's main menu. "Continuar" is present only when a save exists, so
-- the entry list is derived from save state rather than fixed — which is
-- also why the cursor is an index into THIS list, never a fixed slot.
-- Options and Credits joined the list in phase 21, when they became real
-- screens; they were deliberately withheld until then, since offering a
-- dead entry is worse than not offering it.
function M.menu_entries(save_state)
	local entries = {}
	if save_state and save_state.has_progress then
		table.insert(entries, { label = "Continue", action = M.ACTION_CONTINUE })
	end
	table.insert(entries, { label = "New Game", action = M.ACTION_NEW_GAME })
	table.insert(entries, { label = "Level Select", action = M.ACTION_LEVEL_SELECT })
	table.insert(entries, { label = "Options", action = M.ACTION_OPTIONS })
	table.insert(entries, { label = "Credits", action = M.ACTION_CREDITS })
	table.insert(entries, { label = "Quit", action = M.ACTION_QUIT })
	return entries
end

-- PRD 6.1's Opções. Volume rows are adjusted with left/right rather than
-- confirmed, so they carry their own action and the adapter knows which
-- channel a row belongs to without matching on the label text.
--
-- `fullscreen_hint` is the OS shortcut for toggling fullscreen, passed in by
-- the adapter (which is the only thing allowed to ask what platform this
-- is). The row is INFORMATIONAL, not a toggle: this engine version exposes
-- window.set_size/get_size/set_position/set_title but NO set_fullscreen, so
-- the game cannot toggle it. It used to try, through a pcall that swallowed
-- the missing-function error, which meant the menu offered a switch that
-- did nothing at all. Telling the player the real shortcut is worth more
-- than a control that lies.
function M.options_entries(fullscreen_hint)
	return {
		{ label = "Master Volume", action = M.ACTION_VOLUME_MASTER, kind = "master", slider = true },
		{ label = "Music Volume", action = M.ACTION_VOLUME_MUSIC, kind = "music", slider = true },
		{ label = "SFX Volume", action = M.ACTION_VOLUME_SFX, kind = "sfx", slider = true },
		{ label = "Fullscreen", action = M.ACTION_NONE,
		  info = fullscreen_hint or "use your OS shortcut" },
		{ label = "Controls", action = M.ACTION_CONTROLS },
		{ label = "Back", action = M.ACTION_TO_MENU },
	}
end

-- PRD 6.1's "Controles". One row per remappable action plus Back. The rows
-- are derived from input_bindings.ACTIONS rather than listed here, so adding
-- a remappable action is a change in one place.
function M.controls_entries(actions)
	local entries = {}
	for _, action in ipairs(actions) do
		table.insert(entries, { label = action, action = M.ACTION_REBIND, bind = action })
	end
	table.insert(entries, { label = "Back", action = M.ACTION_OPTIONS })
	return entries
end

-- While capturing, the screen is waiting for the player to press the key
-- they want. The cursor must not move and Back must not be selectable, so
-- the adapter routes every key into the rebind instead of into navigation —
-- otherwise binding "Move Left" to Down would also scroll the menu.
function M.begin_capture(state, action)
	return {
		screen = state.screen,
		cursor = state.cursor,
		selected_level = state.selected_level,
		capturing = action,
	}
end

function M.cancel_capture(state)
	return {
		screen = state.screen,
		cursor = state.cursor,
		selected_level = state.selected_level,
		capturing = nil,
	}
end

-- Renders a 0..1 gain as a fixed-width bar, so the options screen shows a
-- level rather than a number the player has to interpret.
function M.volume_bar(value, width)
	width = width or 10
	local filled = math.floor(value * width + 0.5)
	return string.rep("#", filled) .. string.rep(".", width - filled)
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
	-- `capturing` is carried through explicitly: this constructor lists its
	-- fields, so anything not named here would be silently dropped.
	local new_state = {
		screen = state.screen,
		cursor = state.cursor,
		selected_level = state.selected_level,
		capturing = state.capturing,
	}
	local zero_based = (state.cursor - 1 + delta) % entry_count
	new_state.cursor = zero_based + 1
	return new_state
end

-- Level select moves over a grid of levels, and only unlocked ones can be
-- landed on — PRD 6.1 says the screen shows "fases desbloqueadas".
function M.move_level_cursor(state, delta, save_state)
	local total = save_state.total_levels
	local new_state = {
		screen = state.screen,
		cursor = state.cursor,
		selected_level = state.selected_level,
		capturing = state.capturing,
	}
	local candidate = state.selected_level + delta
	if candidate < 1 then
		candidate = save_state.unlocked
	elseif candidate > save_state.unlocked then
		candidate = 1
	end
	new_state.selected_level = candidate
	return new_state
end

-- Changing screen always drops any pending capture: leaving the Controls
-- screen mid-rebind and coming back should not still be waiting for a key.
function M.set_screen(state, screen)
	return { screen = screen, cursor = 1, selected_level = state.selected_level, capturing = nil }
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
