-- Where saved data lives, per platform (PRD 9.4: "LocalStorage (Web),
-- Arquivo local (Steam)").
--
-- Pure Lua, no Defold API (rule 1): this decides the save's IDENTITY (app
-- folder, filenames) and WHICH BACKEND a platform should use, never how the
-- bytes reach the medium. The adapters read this and do the IO — which is
-- also what removes the duplicated "handle_with_care"/"progress"/"settings"
-- string literals that were sitting in two adapters (rule 5).
--
-- The backend decision matters for Steam specifically: sys.save writes a
-- real local file (fine for a DRM-free desktop build and for Steam's own
-- auto-cloud, which watches the save directory), but a build that wants
-- Steam Cloud via ISteamRemoteStorage routes through the Steam extension
-- instead. This module names that choice; main/ui/storage.lua acts on it.

local M = {}

-- One place, not two: both adapters were passing this literal to
-- sys.get_save_file independently.
M.APP_ID = "handle_with_care"

M.PROGRESS_FILE = "progress"
M.SETTINGS_FILE = "settings"

M.BACKEND_SYS = "sys"       -- sys.save/sys.load: local file or Web localStorage
M.BACKEND_STEAM = "steam"   -- ISteamRemoteStorage via the Steam extension

-- Which backend a platform should use. Steam is opt-in via an explicit flag
-- rather than sniffed from the platform, because the same desktop binary can
-- ship both DRM-free (sys) and on Steam (steam), and only the build knows
-- which. Everything else — Web, editor, a plain desktop build — uses sys,
-- whose Defold mapping already covers localStorage on Web.
function M.backend(config)
	config = config or {}
	if config.steam then
		return M.BACKEND_STEAM
	end
	return M.BACKEND_SYS
end

-- Steam Cloud addresses files by a plain name, not a filesystem path, so the
-- Steam backend needs the bare filename; the sys backend needs a full path
-- from sys.get_save_file. Returning the identity here (and letting the
-- adapter build the sys path) keeps this module free of any Defold call.
function M.filename(kind)
	if kind == "settings" then
		return M.SETTINGS_FILE
	end
	return M.PROGRESS_FILE
end

return M
