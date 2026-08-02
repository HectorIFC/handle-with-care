-- Lets a deftest test coroutine block until real engine frames elapse, so
-- integration tests can assert on effects of update()/physics that only
-- become observable after one or more actual `update()` ticks. deftest
-- always runs test bodies inside a coroutine (see deftest.lua), so this
-- only works when called from inside a test/before/after body.
local M = {}

-- Coroutines waiting on M.frames(), ticked down by M.tick().
local pending_frame_waits = {}

-- Waits for exactly `n` real engine update() ticks, regardless of each
-- frame's dt. Prefer this over M.seconds() for anything that depends on a
-- specific number of simulation steps (e.g. lerp convergence): M.seconds()
-- only guarantees that much *accumulated* dt has passed, and a single
-- anomalously large dt (real GPU/shader/window startup hitches — never an
-- issue headless, since there's no real graphics context — can produce one)
-- can satisfy the whole duration in far fewer real ticks than intended,
-- starving whatever per-frame effect the wait was meant to give time to.
function M.frames(n)
	local co = coroutine.running()
	table.insert(pending_frame_waits, { remaining = n, co = co })
	coroutine.yield()
end

-- Must be called once per real engine frame (see test_runner.script's
-- update()) so M.frames() can resume waiting coroutines.
--
-- Snapshots which entries are due *before* resuming anyone: a resumed
-- coroutine that immediately calls M.frames() again (e.g. a test looping
-- "sample, wait 1 frame" many times) inserts a fresh entry into
-- pending_frame_waits mid-call. Iterating the live table directly would
-- visit that brand-new entry again within this same tick(), collapsing an
-- entire loop's worth of "1 frame" waits into a single real frame instead
-- of spreading them across as many real frames as intended.
function M.tick()
	local due = {}
	local still_pending = {}
	for _, entry in ipairs(pending_frame_waits) do
		entry.remaining = entry.remaining - 1
		if entry.remaining <= 0 then
			table.insert(due, entry.co)
		else
			table.insert(still_pending, entry)
		end
	end
	pending_frame_waits = still_pending
	for _, co in ipairs(due) do
		coroutine.resume(co)
	end
end

-- Waits for `seconds` of accumulated simulated time via go.animate. Kept
-- for cases where wall-clock/simulated duration genuinely matters more
-- than an exact tick count — prefer M.frames() otherwise (see above).
function M.seconds(seconds)
	go.cancel_animations(".", "position.z")
	local co = coroutine.running()
	local z = go.get_position().z
	go.animate(".", "position.z", go.PLAYBACK_ONCE_FORWARD, z, go.EASING_LINEAR, seconds, 0, function()
		coroutine.resume(co)
	end)
	coroutine.yield()
end

return M
