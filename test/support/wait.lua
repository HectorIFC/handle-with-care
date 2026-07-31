-- Lets a deftest test coroutine block for `seconds` of real, engine-ticked
-- time, so integration tests can assert on effects of update()/physics that
-- only become observable after one or more actual engine frames elapse.
-- deftest always runs test bodies inside a coroutine (see deftest.lua), so
-- this only works when called from inside a test/before/after body.
local M = {}

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
