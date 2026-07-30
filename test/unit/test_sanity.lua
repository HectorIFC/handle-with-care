return function()
	describe("Project bootstrap sanity check", function()
		test("Lua arithmetic works as expected", function()
			assert(1 + 1 == 2)
		end)
	end)
end
