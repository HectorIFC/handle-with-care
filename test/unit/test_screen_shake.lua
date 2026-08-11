local shake = require "main.core.screen_shake"

return function()
	describe("Screen shake trauma", function()
		test("a fresh shake is inert", function()
			local s = shake.new()
			assert(s.trauma == 0)
			assert(shake.is_active(s) == false)
			local x, y = shake.offset(s, 1.0)
			assert(x == 0 and y == 0)
		end)

		test("events accumulate, so overlapping hits shake harder", function()
			local s = shake.add(shake.add(shake.new(), 0.3), 0.4)
			assert(math.abs(s.trauma - 0.7) < 1e-9)
		end)

		test("trauma saturates at 1 so the view cannot fly off screen", function()
			local s = shake.new()
			for _ = 1, 10 do
				s = shake.add(s, 0.5)
			end
			assert(s.trauma == 1)
		end)

		test("add does not mutate the state passed in (rule 2)", function()
			local s = shake.new()
			shake.add(s, 0.5)
			assert(s.trauma == 0)
		end)

		test("trauma decays to exactly zero and never below", function()
			local s = shake.add(shake.new(), 0.5)
			for _ = 1, 120 do
				s = shake.update(s, 1 / 60)
			end
			assert(s.trauma == 0)
			assert(shake.is_active(s) == false)
		end)

		test("decay is configurable and faster decay settles sooner", function()
			local start = shake.add(shake.new(), 1.0)
			local slow = shake.update(start, 0.1, { decay = 1 })
			local fast = shake.update(start, 0.1, { decay = 5 })
			assert(fast.trauma < slow.trauma)
		end)
	end)

	describe("Screen shake offset", function()
		test("is bounded by max_offset even at full trauma", function()
			local s = shake.add(shake.new(), 1.0)
			for step = 0, 200 do
				local x, y = shake.offset(s, step * 0.013, { max_offset = 6 })
				assert(math.abs(x) <= 6 + 1e-9, "x out of bounds: " .. x)
				assert(math.abs(y) <= 6 + 1e-9, "y out of bounds: " .. y)
			end
		end)

		test("is deterministic for a given time, which is what makes it testable", function()
			local s = shake.add(shake.new(), 0.8)
			local x1, y1 = shake.offset(s, 3.25)
			local x2, y2 = shake.offset(s, 3.25)
			assert(x1 == x2 and y1 == y2)
		end)

		test("falls off quadratically, so a big hit settles fast", function()
			-- Half the trauma must give a QUARTER of the displacement, not
			-- half — that is the whole reason for squaring.
			local full = shake.add(shake.new(), 1.0)
			local half = shake.add(shake.new(), 0.5)
			local xf = select(1, shake.offset(full, 2.0))
			local xh = select(1, shake.offset(half, 2.0))
			assert(math.abs(xf * 0.25 - xh) < 1e-9)
		end)

		test("x and y do not move as one, which would read as a diagonal slide", function()
			local s = shake.add(shake.new(), 1.0)
			local same = 0
			for step = 1, 100 do
				local x, y = shake.offset(s, step * 0.017)
				if math.abs(x - y) < 1e-6 then
					same = same + 1
				end
			end
			assert(same == 0)
		end)

		test("actually moves in both directions rather than drifting one way", function()
			local s = shake.add(shake.new(), 1.0)
			local pos, neg = 0, 0
			for step = 1, 200 do
				local x = select(1, shake.offset(s, step * 0.011))
				if x > 0.1 then pos = pos + 1 end
				if x < -0.1 then neg = neg + 1 end
			end
			assert(pos > 20 and neg > 20)
		end)
	end)
end
