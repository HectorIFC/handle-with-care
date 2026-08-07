-- Delivery zone and win condition (PRD 3.4: "Entregar o pacote dentro da
-- Zona de Entrega"). Pure Lua, no Defold API calls (rule 1) — see
-- main/delivery/delivery_zone.script for the adapter that reads live
-- positions and calls this, and rule 9 for why this is plain AABB geometry
-- rather than an engine physics query.
--
-- Rects use the same live, centered shape as core/hazards.lua's:
-- { x, y, half_width, half_height }.

local M = {}

-- Is `rect` completely within `zone`? Containment, not mere overlap: PRD 3.4
-- says the package must be *dentro* (inside) the zone, and a zone is
-- authored large enough to hold the package comfortably. Requiring
-- containment avoids handing the player a win for a package that is only
-- clipping the zone's edge while the rest of it dangles over a pit — which
-- overlap alone would happily accept. This is deliberately stricter than
-- hazards.rect_overlap, where touching at all is exactly the point.
function M.is_inside(rect, zone)
	return rect.x - rect.half_width >= zone.x - zone.half_width
		and rect.x + rect.half_width <= zone.x + zone.half_width
		and rect.y - rect.half_height >= zone.y - zone.half_height
		and rect.y + rect.half_height <= zone.y + zone.half_height
end

-- Has the level been won this frame? Separate from is_inside so the "what
-- counts as delivered" policy lives here rather than being reassembled by
-- each adapter (and so it stays unit-testable without the engine).
--
-- `package_state` carries the two disqualifiers the PRD implies but geometry
-- can't see: a package that already detonated is destroyed, not delivered
-- (PRD 3.3 lists it as a fail condition, and a fail must never also register
-- as a win on the same frame), and a dead player can't complete a delivery
-- even if the package's corpse happens to come to rest inside the zone.
function M.is_delivered(package_rect, zone, package_state)
	if package_state.detonated or package_state.player_dead then
		return false
	end
	return M.is_inside(package_rect, zone)
end

return M
