-- The one place that reads and writes saved bytes (PRD 9.4). Adapter-tier,
-- not core (it calls Defold/native APIs), but kept as a plain module both
-- save_adapter.script and settings_adapter.script require, so there is a
-- SINGLE storage implementation to swap when Steam Cloud lands rather than
-- two.
--
-- core/save_location.lua already decided the identity and the backend; this
-- acts on that decision. Every function takes a `steam` boolean (from the
-- build) and routes accordingly.

local location = require "main.core.save_location"

local M = {}

-- Attempts the Steam extension, returning (ok, result). Guarded by pcall for
-- the same reason settings_adapter's set_group_gain is: the `steam` module
-- only exists in a build that includes the Steam Defold extension, so a bare
-- reference would be a nil-index crash in the editor, the headless tests,
-- and any non-Steam build. Failing here is not silent — the caller falls
-- back to sys and logs — it just must not crash a build the extension is
-- absent from.
local function steam_available()
	return type(_G.steam) == "table"
end

-- sys backend path: a real file on desktop, localStorage on Web, namespaced
-- by app id so two Defold games never collide.
local function sys_path(kind)
	return sys.get_save_file(location.APP_ID, location.filename(kind))
end

-- Writes `data` for `kind` ("progress"|"settings"). Returns true on success.
-- A Steam build tries Steam Cloud first and falls back to a local file if
-- the extension is missing or the cloud write fails, so progress is never
-- lost to a cloud hiccup — Steam's own auto-cloud still syncs the local
-- file as a backstop.
function M.save(kind, data, steam)
	if steam and steam_available() then
		local ok = pcall(function()
			_G.steam.write_file(location.filename(kind), sys.serialize(data))
		end)
		if ok then
			return true
		end
		print("WARNING: Steam Cloud write failed; falling back to local file")
	end
	return sys.save(sys_path(kind), data)
end

-- Loads `kind`, returning a table (empty when nothing is stored yet, which
-- the core sanitize() turns into a fresh state). Never errors: a missing
-- file, a missing extension, or a corrupt cloud blob all yield {} so the
-- game boots.
function M.load(kind, steam)
	if steam and steam_available() then
		local ok, result = pcall(function()
			local raw = _G.steam.read_file(location.filename(kind))
			if raw and #raw > 0 then
				return sys.deserialize(raw)
			end
			return nil
		end)
		if ok and type(result) == "table" then
			return result
		end
		-- Fall through to the local file rather than returning {}: a Steam
		-- build whose extension is momentarily unavailable should still see
		-- the last local save, not look like a wiped profile.
	end
	return sys.load(sys_path(kind))
end

return M
