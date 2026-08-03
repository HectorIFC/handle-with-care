local magnetism = require "main.core.magnetism"

return function()
	describe("magnetism.attraction_force", function()
		test("zero force when the target is outside the default radius", function()
			local force = magnetism.attraction_force(0, 0, 200, 0)
			assert(force.x == 0)
			assert(force.y == 0)
		end)

		test("a target beyond the radius on the y axis is not attracted", function()
			-- Every other out-of-radius case so far is on the +x axis, so a
			-- radius check restricted to one axis (e.g. only |dx| > radius)
			-- would pass all of them undetected.
			local force = magnetism.attraction_force(0, 0, 0, 200)
			assert(force.x == 0)
			assert(force.y == 0)
		end)

		test("a target beyond the radius to the left is not attracted", function()
			-- Every other out-of-radius case so far has the target to the
			-- right (+x), so a radius check on signed dx (e.g. only
			-- dx > radius, never -dx) would pass all of them undetected.
			local force = magnetism.attraction_force(0, 0, -200, 0)
			assert(force.x == 0)
			assert(force.y == 0)
		end)

		test("target exactly at the default radius (no custom config) is still attracted", function()
			-- Pins DEFAULT_RADIUS to exactly 95, not just "somewhere between
			-- 90 and 200" as the other default-radius tests leave it.
			local force = magnetism.attraction_force(0, 0, 95, 0)
			assert(force.x < 0)
		end)

		test("target just past the default radius (no custom config) is not attracted", function()
			local force = magnetism.attraction_force(0, 0, 95.001, 0)
			assert(force.x == 0)
			assert(force.y == 0)
		end)

		test("nonzero force when the target is within the default radius", function()
			local force = magnetism.attraction_force(0, 0, 50, 0)
			assert(force.x ~= 0 or force.y ~= 0)
		end)

		test("pulls the target toward the package along the x axis", function()
			-- Target sits to the right of the package (positive x); the
			-- force should point back toward the package, i.e. negative x.
			local force = magnetism.attraction_force(0, 0, 50, 0)
			assert(force.x < 0)
			assert(math.abs(force.y) < 1e-9)
		end)

		test("pulls the target toward the package along the y axis", function()
			local force = magnetism.attraction_force(0, 0, 0, 50)
			assert(force.y < 0)
			assert(math.abs(force.x) < 1e-9)
		end)

		test("force magnitude equals the configured strength anywhere within radius", function()
			local force = magnetism.attraction_force(0, 0, 30, 0, { strength = 150 })
			local magnitude = math.sqrt(force.x * force.x + force.y * force.y)
			assert(math.abs(magnitude - 150) < 1e-9)
		end)

		test("magnitude does not fall off with distance, only direction changes", function()
			local near = magnetism.attraction_force(0, 0, 10, 0)
			local far = magnetism.attraction_force(0, 0, 90, 0)
			local near_magnitude = math.sqrt(near.x * near.x + near.y * near.y)
			local far_magnitude = math.sqrt(far.x * far.x + far.y * far.y)
			assert(math.abs(near_magnitude - far_magnitude) < 1e-9)
		end)

		test("zero force (not NaN) when the target is exactly at the package's position", function()
			local force = magnetism.attraction_force(10, 10, 10, 10)
			assert(force.x == 0)
			assert(force.y == 0)
		end)

		test("target exactly at the radius boundary is still attracted (inclusive)", function()
			local force = magnetism.attraction_force(0, 0, 95, 0, { radius = 95 })
			assert(force.x < 0)
		end)

		test("target just past the radius boundary is not attracted", function()
			local force = magnetism.attraction_force(0, 0, 95.001, 0, { radius = 95 })
			assert(force.x == 0)
			assert(force.y == 0)
		end)

		test("a diagonal target inside the radius is attracted even when its axes sum past it", function()
			-- (60,60): Euclidean distance ~84.85 <= 95 (attracted), but
			-- |dx|+|dy| = 120 > 95 — a Manhattan-distance radius check
			-- would wrongly reject this, and every other test's diagonal
			-- case (30,40) sits too far inside the radius under any of the
			-- three metrics to tell them apart.
			local force = magnetism.attraction_force(0, 0, 60, 60)
			assert(force.x < 0)
			assert(force.y < 0)
		end)

		test("a diagonal target outside the radius is not attracted even though each axis alone is inside", function()
			-- (70,70): Euclidean distance ~98.99 > 95 (rejected), but
			-- max(|dx|,|dy|) = 70 <= 95 — a Chebyshev-distance radius check
			-- would wrongly attract this.
			local force = magnetism.attraction_force(0, 0, 70, 70)
			assert(force.x == 0)
			assert(force.y == 0)
		end)

		test("respects a custom radius", function()
			local force = magnetism.attraction_force(0, 0, 40, 0, { radius = 30 })
			assert(force.x == 0)
			assert(force.y == 0)
		end)

		test("respects a custom strength", function()
			local force = magnetism.attraction_force(0, 0, 50, 0, { strength = 60 })
			local magnitude = math.sqrt(force.x * force.x + force.y * force.y)
			assert(math.abs(magnitude - 60) < 1e-9)
		end)

		test("diagonal attraction points along the correct combined direction", function()
			-- Target up-and-right of the package; force should pull down-and-left.
			local force = magnetism.attraction_force(0, 0, 30, 40, { radius = 95 })
			assert(force.x < 0)
			assert(force.y < 0)
			-- 30-40-50 triangle: x component should be 3/5 and y 4/5 of the
			-- total strength (default 150), matching the known ratio exactly.
			assert(math.abs(force.x - (-150 * 30 / 50)) < 1e-9)
			assert(math.abs(force.y - (-150 * 40 / 50)) < 1e-9)
		end)

		test("pulls a target left of and below the package back up and to the right", function()
			-- Every other directional test so far has the target above/right
			-- of the package, always producing a negative force component —
			-- an abs()-flavored bug (pulling away from, not toward, the
			-- package on this side) would pass every one of them unnoticed.
			local force = magnetism.attraction_force(0, 0, -30, -40)
			assert(math.abs(force.x - (150 * 30 / 50)) < 1e-9)
			assert(math.abs(force.y - (150 * 40 / 50)) < 1e-9)
		end)

		test("force is relative to the package's position, not the world origin", function()
			-- Every other test keeps the package at (0, 0), so a bug that
			-- silently ignored package_x/package_y (using target position
			-- alone) would still pass them all.
			local force = magnetism.attraction_force(100, 200, 130, 240)
			assert(math.abs(force.x - (-150 * 30 / 50)) < 1e-9)
			assert(math.abs(force.y - (-150 * 40 / 50)) < 1e-9)
		end)
	end)
end
