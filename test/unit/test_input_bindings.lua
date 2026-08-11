local input_bindings = require "main.core.input_bindings"

return function()
	describe("Input bindings", function()
		test("defaults bind both WASD and the arrows", function()
			local b = input_bindings.new()
			assert(input_bindings.resolve(b, "key_a") == "move_left")
			assert(input_bindings.resolve(b, "key_left") == "move_left")
			assert(input_bindings.resolve(b, "key_d") == "move_right")
			assert(input_bindings.resolve(b, "key_right") == "move_right")
			assert(input_bindings.resolve(b, "key_w") == "jump")
			assert(input_bindings.resolve(b, "key_space") == "jump")
		end)

		test("an unbound key resolves to nothing rather than erroring", function()
			local b = input_bindings.new()
			assert(input_bindings.resolve(b, "key_q") == nil)
			assert(input_bindings.resolve(b, "not_a_key") == nil)
			assert(input_bindings.resolve(b, nil) == nil)
			assert(input_bindings.resolve(b, 42) == nil)
		end)

		test("rebinding replaces the action's keys with the new one", function()
			local b = input_bindings.new()
			local rebound, err = input_bindings.rebind(b, "jump", "key_j")
			assert(err == nil)
			assert(input_bindings.resolve(rebound, "key_j") == "jump")
			-- The old alternates are gone, which is what makes "unbound" unreachable.
			assert(input_bindings.resolve(rebound, "key_w") == nil)
			assert(input_bindings.resolve(rebound, "key_space") == nil)
		end)

		test("rebinding does not mutate the bindings passed in (rule 2)", function()
			local b = input_bindings.new()
			input_bindings.rebind(b, "jump", "key_j")
			assert(input_bindings.resolve(b, "key_w") == "jump")
			assert(input_bindings.resolve(b, "key_j") == nil)
		end)

		test("a key already owned by another action is rejected", function()
			local b = input_bindings.new()
			local result, err = input_bindings.rebind(b, "jump", "key_a")
			assert(err ~= nil)
			-- The rejected attempt returns the ORIGINAL bindings unchanged,
			-- so a caller that ignores the error cannot half-apply it.
			assert(input_bindings.resolve(result, "key_a") == "move_left")
			assert(input_bindings.resolve(result, "key_w") == "jump")
		end)

		test("rebinding an action to a key it already owns is allowed", function()
			local b = input_bindings.new()
			local rebound, err = input_bindings.rebind(b, "jump", "key_w")
			assert(err == nil)
			assert(input_bindings.resolve(rebound, "key_w") == "jump")
		end)

		test("an unbindable key and an unknown action are both refused", function()
			local b = input_bindings.new()
			local _, err = input_bindings.rebind(b, "jump", "key_esc")
			assert(err ~= nil)
			local _, err2 = input_bindings.rebind(b, "fly", "key_j")
			assert(err2 ~= nil)
		end)

		test("every action always ends up with at least one key", function()
			local b = input_bindings.new()
			for _, action in ipairs(input_bindings.ACTIONS) do
				assert(#b[action] > 0)
			end
		end)
	end)

	describe("Input bindings sanitize", function()
		test("junk and absent input fall back to the defaults", function()
			for _, raw in ipairs({ "nonsense", 7, {} }) do
				local b = input_bindings.sanitize(raw)
				assert(input_bindings.resolve(b, "key_a") == "move_left")
				assert(input_bindings.resolve(b, "key_w") == "jump")
			end
			local b = input_bindings.sanitize(nil)
			assert(input_bindings.resolve(b, "key_a") == "move_left")
		end)

		test("a valid stored binding survives a round trip", function()
			local stored = { move_left = { "key_j" }, move_right = { "key_l" }, jump = { "key_k" } }
			local b = input_bindings.sanitize(stored)
			assert(input_bindings.resolve(b, "key_j") == "move_left")
			assert(input_bindings.resolve(b, "key_l") == "move_right")
			assert(input_bindings.resolve(b, "key_k") == "jump")
		end)

		test("unknown key names inside a stored binding are dropped", function()
			local b = input_bindings.sanitize({ jump = { "key_k", "key_esc", 5, {} } })
			assert(input_bindings.resolve(b, "key_k") == "jump")
			assert(input_bindings.resolve(b, "key_esc") == nil)
		end)

		test("a key claimed twice is only honored once", function()
			-- move_left is listed first in ACTIONS, so it keeps the key and
			-- jump falls back rather than both answering to it.
			local b = input_bindings.sanitize({ move_left = { "key_k" }, jump = { "key_k" } })
			assert(input_bindings.resolve(b, "key_k") == "move_left")
			assert(#b.jump > 0)
		end)

		test("an action whose defaults were all stolen still gets a key", function()
			-- The pathological file: move_left claims every key jump defaults
			-- to. jump must still come out playable — an action with no key
			-- is one the player cannot perform, with no way to find out why.
			local b = input_bindings.sanitize({
				move_left = { "key_w", "key_up", "key_space" },
			})
			assert(#b.jump > 0)
			assert(input_bindings.resolve(b, b.jump[1]) == "jump")
		end)

		test("sanitize is deterministic for the same input", function()
			local raw = { move_left = { "key_w", "key_up", "key_space" } }
			local first = input_bindings.sanitize(raw)
			local second = input_bindings.sanitize(raw)
			assert(first.jump[1] == second.jump[1])
		end)
	end)

	describe("Input bindings display", function()
		test("keys are described with their labels, joined", function()
			local b = input_bindings.new()
			assert(input_bindings.describe_keys(b, "move_left") == "A / Left")
			assert(input_bindings.describe_action("move_left") == "Move Left")
		end)

		test("every remappable key has a label and vice versa", function()
			for _, key in ipairs(input_bindings.KEYS) do
				assert(input_bindings.KEY_LABELS[key], "no label for " .. key)
			end
			local ordered = {}
			for _, key in ipairs(input_bindings.KEYS) do
				ordered[key] = true
			end
			for key in pairs(input_bindings.KEY_LABELS) do
				assert(ordered[key], key .. " is labelled but not in KEYS")
			end
		end)
	end)
end
