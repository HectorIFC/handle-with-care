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

		test("Explosive sticks even as stress decays back down", function()
			-- Regression test: Explosive used to be re-derivable like the
			-- rest of the ladder, so a single frame of stress decay from
			-- exactly the threshold would immediately bounce it back to
			-- Panic. See RE_DERIVABLE_STATES in package_state_machine.lua.
			local state = package_state_machine.new()
			state = package_state_machine.update_from_stress(state, 100, config)
			assert(state.current_state == package_state_machine.EXPLOSIVE)
			state = package_state_machine.update_from_stress(state, 0, config)
			assert(state.current_state == package_state_machine.EXPLOSIVE)
		end)

		test("Explosive forced via set_state also sticks, even at zero stress", function()
			-- This is the phase-timer trigger path (e.g. a future Hot
			-- Potato cyclic timer) — it must survive the very next
			-- update_from_stress call the same way the stress-driven path
			-- does, satisfying the dual-trigger requirement.
			local state = package_state_machine.set_state(package_state_machine.new(), package_state_machine.EXPLOSIVE)
			state = package_state_machine.update_from_stress(state, 0, config)
			assert(state.current_state == package_state_machine.EXPLOSIVE)
		end)
	end)

	describe("package_state_machine.set_state", function()
		test("directly overrides the current state regardless of stress ladder rules", function()
			local state = package_state_machine.new()
			state = package_state_machine.set_state(state, package_state_machine.SLEEPING)
			assert(state.current_state == package_state_machine.SLEEPING)
		end)
	end)

	describe("package_state_machine.wake_on_impact", function()
		test("wakes Sleeping to Stable", function()
			local state = package_state_machine.set_state(package_state_machine.new(), package_state_machine.SLEEPING)
			state = package_state_machine.wake_on_impact(state)
			assert(state.current_state == package_state_machine.STABLE)
		end)

		test("is a no-op for Stable", function()
			-- Asserts the exact same table comes back untouched, not just
			-- current_state == STABLE — that alone can't distinguish a real
			-- no-op from a broken implementation that unconditionally
			-- returns {current_state = STABLE} regardless of input.
			local state = package_state_machine.new()
			assert(package_state_machine.wake_on_impact(state) == state)
		end)

		test("does not knock Explosive off its one-way path", function()
			-- The whole point of an impact event is that it can happen at
			-- any time — including while a package is already mid-detonation.
			-- Explosive must stay sticky through it, the same way it's
			-- immune to update_from_stress (see RE_DERIVABLE_STATES).
			local state = package_state_machine.set_state(package_state_machine.new(), package_state_machine.EXPLOSIVE)
			state = package_state_machine.wake_on_impact(state)
			assert(state.current_state == package_state_machine.EXPLOSIVE)
		end)

		test("is a no-op for other non-ladder states (e.g. Heavy)", function()
			local state = package_state_machine.set_state(package_state_machine.new(), package_state_machine.HEAVY)
			state = package_state_machine.wake_on_impact(state)
			assert(state.current_state == package_state_machine.HEAVY)
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

		test("default 1.0 when Explosive", function()
			local state = { current_state = package_state_machine.EXPLOSIVE }
			assert(package_state_machine.shake_intensity(state) == 1.0)
		end)

		test("respects custom config values", function()
			local state = { current_state = package_state_machine.PANIC }
			local intensity = package_state_machine.shake_intensity(state, { panic_shake_intensity = 0.8 })
			assert(intensity == 0.8)

			state = { current_state = package_state_machine.EXPLOSIVE }
			intensity = package_state_machine.shake_intensity(state, { explosive_shake_intensity = 0.6 })
			assert(intensity == 0.6)
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
