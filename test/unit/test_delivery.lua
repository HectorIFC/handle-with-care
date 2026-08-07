local delivery = require "main.core.delivery"

local function rect(x, y, half_width, half_height)
	return { x = x, y = y, half_width = half_width, half_height = half_height }
end

local ZONE = rect(200, 60, 20, 20) -- spans x 180..220, y 40..80

return function()
	describe("delivery.is_inside", function()
		test("a package fully within the zone is inside", function()
			assert(delivery.is_inside(rect(200, 60, 6, 6), ZONE) == true)
		end)

		test("a package far outside the zone is not inside", function()
			assert(delivery.is_inside(rect(50, 60, 6, 6), ZONE) == false)
		end)

		test("merely overlapping the zone's edge is NOT inside", function()
			-- The whole reason this is containment rather than overlap: at
			-- x=218 the package spans 212..224, so it pokes out past the
			-- zone's right edge (220) even though it clearly overlaps.
			local clipping = rect(218, 60, 6, 6)
			local hazards = require "main.core.hazards"
			assert(hazards.rect_overlap(clipping, ZONE) == true)
			assert(delivery.is_inside(clipping, ZONE) == false)
		end)

		test("a package exactly flush with the zone's bounds counts as inside", function()
			-- Flush edges are inside (>= / <=), unlike rect_overlap where
			-- exactly touching edges deliberately do NOT count — the two
			-- checks answer opposite questions, so their boundary handling
			-- differs on purpose.
			assert(delivery.is_inside(rect(214, 60, 6, 6), ZONE) == true) -- right edge at 220
			assert(delivery.is_inside(rect(186, 60, 6, 6), ZONE) == true) -- left edge at 180
			assert(delivery.is_inside(rect(200, 74, 6, 6), ZONE) == true) -- top edge at 80
			assert(delivery.is_inside(rect(200, 46, 6, 6), ZONE) == true) -- bottom edge at 40
		end)

		test("a package larger than the zone can never be inside", function()
			assert(delivery.is_inside(rect(200, 60, 30, 30), ZONE) == false)
		end)

		test("outside on only one axis is still not inside", function()
			assert(delivery.is_inside(rect(200, 200, 6, 6), ZONE) == false) -- y out, x in
			assert(delivery.is_inside(rect(0, 60, 6, 6), ZONE) == false) -- x out, y in
		end)
	end)

	describe("delivery.is_delivered", function()
		local INSIDE = rect(200, 60, 6, 6)

		test("an intact package inside the zone is delivered", function()
			assert(delivery.is_delivered(INSIDE, ZONE, {}) == true)
		end)

		test("a package outside the zone is not delivered", function()
			assert(delivery.is_delivered(rect(50, 60, 6, 6), ZONE, {}) == false)
		end)

		test("a detonated package inside the zone is destroyed, not delivered", function()
			-- A fail condition must never also register as a win on the same
			-- frame, however the debris happens to land.
			assert(delivery.is_delivered(INSIDE, ZONE, { detonated = true }) == false)
		end)

		test("a dead player cannot complete a delivery", function()
			assert(delivery.is_delivered(INSIDE, ZONE, { player_dead = true }) == false)
		end)

		test("both disqualifiers at once still means not delivered", function()
			assert(delivery.is_delivered(INSIDE, ZONE, { detonated = true, player_dead = true }) == false)
		end)
	end)
end
