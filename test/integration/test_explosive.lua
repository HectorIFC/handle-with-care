local wait = require "test.support.wait"

-- explosive_time defaults to 1.5s = 90 frames at the project's locked 60Hz.
local EXPLOSIVE_FRAMES = 90

local function reset_all()
	msg.post("/player#script", "test_reset")
	msg.post("/package#script", "test_reset")
	wait.frames(36) -- let the player land
end

local function set_stress(value)
	msg.post("/package#script", "debug_set_stress", { value = value })
	-- A couple of frames' margin, not just one: at exactly 100 (both the
	-- ceiling and the explosive threshold), accumulate_continuous_stress
	-- reads the machine's *stale* (pre-transition) current_state, so the
	-- very first frame after this message still takes the grounded-decay
	-- branch and briefly dips below 100 (re-deriving Panic) before Panic's
	-- own accumulation climbs it back to 100 and crosses into Explosive.
	wait.frames(3)
end

local function set_state(state_name)
	msg.post("/package#script", "debug_set_state", { state = state_name })
	wait.frames(1)
end

return function()
	describe("Explosive package state (integration)", function()
		before(reset_all)

		test("stress reaching the explosive threshold enters Explosive", function()
			set_stress(100)
			assert(go.get("/package#script", "current_state") == hash("explosive"))
		end)

		test("Explosive sticks even as stress would otherwise decay it away", function()
			-- Regression coverage for the sticky-ladder fix: without it,
			-- one frame of decay_safe drops stress just below the
			-- threshold and the state bounces back to Panic before the
			-- timer ever finishes.
			set_stress(100)
			wait.frames(30) -- half a second grounded — plenty of time to decay if it weren't frozen
			assert(go.get("/package#script", "current_state") == hash("explosive"))
		end)

		test("the timer detonates after explosive_time elapses and posts package_exploded", function()
			set_stress(100)
			wait.frames(EXPLOSIVE_FRAMES + 15) -- margin for real-engine dt jitter
			assert(go.get("/package#script", "detonated") == true)
			assert(go.get("/player#script", "package_exploded_count") == 1)
		end)

		test("does not detonate before explosive_time elapses", function()
			set_stress(100)
			wait.frames(EXPLOSIVE_FRAMES - 15)
			assert(go.get("/package#script", "detonated") == false)
			assert(go.get("/player#script", "package_exploded_count") == 0)
		end)

		test("a non-stress trigger (debug_set_state) also enters and sticks in Explosive", function()
			-- Stands in for a future phase-timer trigger (e.g. Hot
			-- Potato's cyclic heat-up, phase 14): entry with stress at
			-- zero must still stick and still eventually detonate,
			-- proving the dual-trigger requirement (CLAUDE.md
			-- architecture rule 6) actually holds today, not just in
			-- theory.
			set_state("explosive")
			assert(go.get("/package#script", "current_stress") == 0)
			wait.frames(30)
			assert(go.get("/package#script", "current_state") == hash("explosive"))

			wait.frames(EXPLOSIVE_FRAMES)
			assert(go.get("/package#script", "detonated") == true)
		end)

		test("re-arms after leaving and re-entering Explosive", function()
			-- Regression coverage: detonated/active used to only ever be
			-- set, never cleared, so a package that left Explosive (only
			-- reachable via debug_set_state today) and climbed back in
			-- would get stuck permanently active=false/detonated=true,
			-- unable to ever detonate again.
			set_stress(100)
			wait.frames(EXPLOSIVE_FRAMES + 15)
			assert(go.get("/package#script", "detonated") == true)

			-- Stress must drop too, not just the state: Explosive is sticky
			-- regardless of stress, but Stable (what we're forcing it back
			-- to) is still re-derivable — leaving stress at 100 would just
			-- have update_from_stress bounce it straight back to Explosive
			-- on this same frame.
			msg.post("/package#script", "debug_set_stress", { value = 0 })
			set_state("stable")
			wait.frames(1) -- margin: don't depend on package.script updating before this assert within the same frame
			assert(go.get("/package#script", "detonated") == false)

			set_stress(100)
			wait.frames(EXPLOSIVE_FRAMES + 15)
			assert(go.get("/package#script", "detonated") == true)
			-- 2, not just truthy: the flag from the FIRST detonation would
			-- already read "delivered" going in, so only a count actually
			-- proves this second explosion posted its own message too.
			assert(go.get("/player#script", "package_exploded_count") == 2)
		end)

		test("shake grows over the countdown (near zero at entry, visible before detonation)", function()
			set_stress(100)

			local early_min_x, early_max_x = math.huge, -math.huge
			for _ = 1, 5 do
				local pos = go.get_position("/package")
				early_min_x = math.min(early_min_x, pos.x)
				early_max_x = math.max(early_max_x, pos.x)
				wait.frames(1)
			end

			wait.frames(EXPLOSIVE_FRAMES - 20)

			local late_min_x, late_max_x = math.huge, -math.huge
			for _ = 1, 20 do
				local pos = go.get_position("/package")
				late_min_x = math.min(late_min_x, pos.x)
				late_max_x = math.max(late_max_x, pos.x)
				wait.frames(1)
			end

			assert((late_max_x - late_min_x) > (early_max_x - early_min_x))
		end)
	end)
end
