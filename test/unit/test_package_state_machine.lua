local package_state_machine = require "main.core.package_state_machine"

return function()
	describe("package_state_machine.new", function()
		test("starts Stable", function()
			assert(package_state_machine.new().current_state == package_state_machine.STABLE)
		end)
	end)

	describe("package_state_machine.update_from_stress", function()
		local config = { nervous_threshold = 30, panic_threshold = 70, explosive_threshold = 100 }

		test("stays Stable below the nervous threshold", function()
			local state = package_state_machine.new()
			state = package_state_machine.update_from_stress(state, 29, config)
			assert(state.current_state == package_state_machine.STABLE)
		end)

		test("becomes Nervous exactly at the nervous threshold", function()
			local state = package_state_machine.new()
			state = package_state_machine.update_from_stress(state, 30, config)
			assert(state.current_state == package_state_machine.NERVOUS)
		end)

		test("becomes Panic exactly at the panic threshold", function()
			local state = package_state_machine.new()
			state = package_state_machine.update_from_stress(state, 70, config)
			assert(state.current_state == package_state_machine.PANIC)
		end)

		test("becomes Explosive exactly at the explosive threshold", function()
			local state = package_state_machine.new()
			state = package_state_machine.update_from_stress(state, 100, config)
			assert(state.current_state == package_state_machine.EXPLOSIVE)
		end)

		test("drops back down as stress decays", function()
			local state = package_state_machine.new()
			state = package_state_machine.update_from_stress(state, 80, config)
			assert(state.current_state == package_state_machine.PANIC)
			state = package_state_machine.update_from_stress(state, 20, config)
			assert(state.current_state == package_state_machine.STABLE)
		end)

		test("uses default thresholds when no config is given", function()
			local state = package_state_machine.new()
			state = package_state_machine.update_from_stress(state, 30)
			assert(state.current_state == package_state_machine.NERVOUS)
		end)

		test("does not touch a non-ladder state (e.g. Heavy)", function()
			local state = { current_state = package_state_machine.HEAVY }
			state = package_state_machine.update_from_stress(state, 100, config)
			assert(state.current_state == package_state_machine.HEAVY)
		end)
	end)

	describe("package_state_machine.set_state", function()
		test("directly overrides the current state regardless of stress ladder rules", function()
			local state = package_state_machine.new()
			state = package_state_machine.set_state(state, package_state_machine.SLEEPING)
			assert(state.current_state == package_state_machine.SLEEPING)
		end)
	end)

	describe("package_state_machine.shake_intensity", function()
		test("zero when Stable", function()
			local state = { current_state = package_state_machine.STABLE }
			assert(package_state_machine.shake_intensity(state) == 0)
		end)

		test("default 0.5 when Nervous", function()
			local state = { current_state = package_state_machine.NERVOUS }
			assert(package_state_machine.shake_intensity(state) == 0.5)
		end)

		test("default 1.0 when Panic", function()
			local state = { current_state = package_state_machine.PANIC }
			assert(package_state_machine.shake_intensity(state) == 1.0)
		end)

		test("zero for a state without defined shake (e.g. Explosive, for now)", function()
			local state = { current_state = package_state_machine.EXPLOSIVE }
			assert(package_state_machine.shake_intensity(state) == 0)
		end)

		test("respects custom config values", function()
			local state = { current_state = package_state_machine.PANIC }
			local intensity = package_state_machine.shake_intensity(state, { panic_shake_intensity = 0.8 })
			assert(intensity == 0.8)
		end)
	end)

	describe("package_state_machine.mass", function()
		test("1.0 for Stable and other non Heavy/Light states", function()
			assert(package_state_machine.mass({ current_state = package_state_machine.STABLE }) == 1.0)
			assert(package_state_machine.mass({ current_state = package_state_machine.PANIC }) == 1.0)
		end)

		test("default 2.5 when Heavy", function()
			local state = { current_state = package_state_machine.HEAVY }
			assert(package_state_machine.mass(state) == 2.5)
		end)

		test("default 0.4 when Light", function()
			local state = { current_state = package_state_machine.LIGHT }
			assert(package_state_machine.mass(state) == 0.4)
		end)

		test("respects custom config values", function()
			local state = { current_state = package_state_machine.HEAVY }
			assert(package_state_machine.mass(state, { heavy_mass = 3.0 }) == 3.0)
		end)
	end)

	describe("package_state_machine.offset_y_bonus", function()
		test("zero for Stable and other states", function()
			assert(package_state_machine.offset_y_bonus({ current_state = package_state_machine.NERVOUS }) == 0)
		end)

		test("negative (sits lower) when Heavy", function()
			local state = { current_state = package_state_machine.HEAVY }
			assert(package_state_machine.offset_y_bonus(state) == -6)
		end)

		test("positive (floats higher) when Light", function()
			local state = { current_state = package_state_machine.LIGHT }
			assert(package_state_machine.offset_y_bonus(state) == 6)
		end)
	end)

	describe("package_state_machine.vertical_force", function()
		test("zero for Stable and other states (e.g. Heavy)", function()
			assert(package_state_machine.vertical_force({ current_state = package_state_machine.STABLE }) == 0)
			assert(package_state_machine.vertical_force({ current_state = package_state_machine.HEAVY }) == 0)
		end)

		test("default 40 when Light", function()
			local state = { current_state = package_state_machine.LIGHT }
			assert(package_state_machine.vertical_force(state) == 40)
		end)

		test("respects custom config values", function()
			local state = { current_state = package_state_machine.LIGHT }
			assert(package_state_machine.vertical_force(state, { light_vertical_force = 60 }) == 60)
		end)
	end)
end
