-- Lets a deftest test coroutine block until real engine frames elapse, so
-- integration tests can assert on effects of update()/physics that only
-- become observable after one or more actual `update()` ticks. deftest
-- always runs test bodies inside a coroutine (see deftest.lua), so this
-- only works when called from inside a test/before/after body.
local M = {}

-- Coroutines waiting on M.frames(), ticked down by M.tick().
local pending_frame_waits = {}

-- Monotonic count of coroutines resumed, for the runner's stall watchdog.
-- Deliberately observed from test_runner.script's own update() rather than
-- only from inside tick(): a stall was reproduced in which tick()'s own
-- detector never fired at all over ~57,000 frames, which only makes sense
-- if tick() itself was not running — so the watchdog must live outside it
-- to be able to tell those two cases apart.
local total_resumes = 0

-- Returns the resume counter and how many coroutines are parked, so the
-- runner can distinguish "update() stopped being called" (nothing prints at
-- all) from "update() runs but nothing is ever resumed" (counter frozen)
-- from "resumed every frame without progressing" (counter climbing).
function M.stats()
	return total_resumes, #pending_frame_waits
end

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
		total_resumes = total_resumes + 1
		local ok, err = coroutine.resume(co)
		if not ok then
			-- Never discard this result. Lua 5.1's pcall can't yield, so
			-- deftest's own pcall/resume only ever wraps a test body up to
			-- its FIRST M.frames() call — everything after that resumes
			-- here instead. Swallowing the error would both hide it and
			-- leave deftest waiting forever on a coroutine that is already
			-- dead, turning an ordinary test failure into a silent,
			-- permanent hang of the whole suite (which is exactly what it
			-- did: the run stalled mid-suite at ~1.5% CPU with a healthy
			-- engine and not one line of error output). Exiting non-zero
			-- here matches deftest's own os.exit-on-failure contract, so
			-- run_tests.sh still reports the failure through its exit code.
			print("ERROR:TEST: " .. tostring(err))
			print(debug.traceback(co))
			os.exit(1)
		end
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
