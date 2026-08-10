-- Mirrored world (PRD section 10, level 9 "Mirror World": "nível espelhado
-- + reações invertidas do pacote", with the second layer being "memória
-- muscular + seção final não espelhada").
--
-- Pure Lua, no Defold API calls (rule 1).
--
-- Two separate things, deliberately not merged: mirroring WORLD GEOMETRY
-- (so a level authored left-to-right can be played right-to-left without
-- authoring it twice) and mirroring the PACKAGE'S REACTIONS (its offset and
-- horizontal impulses flip). A level can want either without the other —
-- the PRD's final section is un-mirrored geometry while the package stays
-- inverted, which is exactly what makes muscle memory betray the player.

local M = {}

-- Reflects an x coordinate about the level's midpoint. Self-inverse:
-- mirroring twice returns the original, which is what makes it safe to
-- apply to a whole level's authored positions without tracking whether it
-- has already been applied.
function M.mirror_x(x, level_width)
	return level_width - x
end

-- A rect mirrored about the level's midpoint. Width is unchanged — only the
-- centre moves — so extents stay valid without recomputing them.
function M.mirror_rect(rect, level_width)
	return {
		x = M.mirror_x(rect.x, level_width),
		y = rect.y,
		half_width = rect.half_width,
		half_height = rect.half_height,
	}
end

-- Is `x` inside the level's un-mirrored tail? PRD's "seção final não
-- espelhada": the last stretch plays normally, so the habits built over the
-- mirrored part stop working exactly when the player has stopped thinking
-- about them.
function M.in_normal_section(x, level_width, normal_section_width)
	if not normal_section_width or normal_section_width <= 0 then
		return false
	end
	return x >= level_width - normal_section_width
end

-- The package's horizontal reactions (its carry offset and Panic impulses)
-- flip while mirrored. Vertical is untouched: gravity does not care which
-- way the level runs, and flipping it would read as a bug rather than a
-- mirror.
function M.reaction_sign(mirrored)
	if mirrored then
		return -1
	end
	return 1
end

-- Whether the package should currently react mirrored, given where the
-- player is. Kept here rather than in the adapter so "mirrored geometry"
-- and "mirrored reactions" can disagree in exactly one place — the final
-- section un-mirrors the world but NOT the package, per the PRD.
function M.package_mirrored(config)
	config = config or {}
	if config.package_always_mirrored then
		return true
	end
	return not M.in_normal_section(config.player_x or 0,
		config.level_width or 0, config.normal_section_width)
end

return M
