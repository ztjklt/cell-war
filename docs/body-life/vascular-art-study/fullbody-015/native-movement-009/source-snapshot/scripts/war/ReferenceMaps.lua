-- Versioned geometry preserves saved positions and previous authored maps.
local M={}
function M.forState(s) return require(s.anatomyVersion==3 and 'war.LegacyReferenceMapV3' or 'war.ReferenceMap') end
function M.art(s) return require(s.anatomyVersion==3 and 'war.LegacyReferenceArtV3' or 'war.ReferenceArt') end
return M
