local parallax = require "main.core.parallax"

return function()
	describe("Parallax layer_x", function()
		test("factor 1 is world-locked: the layer never moves on screen", function()
			for _, camera_x in ipairs({ 0, 100, 960 }) do
				local world_x = parallax.layer_x(camera_x, 1)
				assert(world_x - camera_x == -camera_x)
				assert(world_x == 0)
			end
		end)

		test("factor 0 is view-locked: the layer follows the camera exactly", function()
			for _, camera_x in ipairs({ 0, 100, 960 }) do
				assert(parallax.layer_x(camera_x, 0) == camera_x)
			end
		end)

		test("a middling factor drifts by exactly that fraction", function()
			-- Screen position is world - camera; at factor 0.5 the layer must
			-- appear to move half as far as the camera did.
			local camera_x = 200
			local screen_x = parallax.layer_x(camera_x, 0.5) - camera_x
			assert(math.abs(screen_x - (-100)) < 1e-9)
		end)

		test("a nearer layer always drifts more than a farther one", function()
			local camera_x = 500
			local near = parallax.layer_x(camera_x, 0.7) - camera_x
			local far = parallax.layer_x(camera_x, 0.2) - camera_x
			assert(near < far) -- both negative; nearer is more negative
		end)
	end)

	describe("Parallax wrapped_x", function()
		test("the first copy is never to the right of the camera", function()
			for camera_x = 0, 1200, 37 do
				local x = parallax.wrapped_x(camera_x, 0.35, 192)
				assert(x <= camera_x)
			end
		end)

		test("the first copy is never more than a tile behind the camera", function()
			for camera_x = 0, 1200, 37 do
				local x = parallax.wrapped_x(camera_x, 0.35, 192)
				assert(camera_x - x < 192)
			end
		end)

		test("wrapping preserves the unwrapped drift, modulo the tile", function()
			local camera_x, factor, tile = 500, 0.5, 192
			local raw = parallax.layer_x(camera_x, factor)
			local wrapped = parallax.wrapped_x(camera_x, factor, tile)
			assert(math.abs((wrapped - raw) % tile) < 1e-9)
		end)

		test("a zero or negative tile width degrades instead of dividing by it", function()
			assert(parallax.wrapped_x(300, 0.5, 0) == 300)
			assert(parallax.wrapped_x(300, 0.5, -8) == 300)
		end)

		test("camera at the origin puts the first copy at the origin", function()
			assert(parallax.wrapped_x(0, 0.5, 192) == 0)
		end)
	end)

	describe("Parallax copies_needed", function()
		test("always covers the screen with one to spare", function()
			assert(parallax.copies_needed(384, 384) == 2)
			assert(parallax.copies_needed(384, 192) == 3)
			assert(parallax.copies_needed(384, 128) == 4)
		end)

		test("a tile wider than the screen still needs two", function()
			assert(parallax.copies_needed(384, 512) == 2)
		end)

		test("a zero tile width does not loop forever or divide by zero", function()
			assert(parallax.copies_needed(384, 0) == 1)
		end)
	end)
end
