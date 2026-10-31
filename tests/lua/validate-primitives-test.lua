-- Unit test for shared Validate primitives
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path
local V = require 'EmberRoutesProbe/Validate'

-- 1. Finite checks
if not V.finite(0) then error('0 should be finite') end
if not V.finite(123.456, 100, 200) then error('in range finite should pass') end
if V.finite(50, 100, 200) then error('below min finite should fail') end
if V.finite(250, 100, 200) then error('above max finite should fail') end
if V.finite(0/0) then error('NaN should fail finite') end
if V.finite(math.huge) or V.finite(-math.huge) then error('Infinity should fail finite') end
if V.finite('123') then error('string should fail finite') end

-- 2. Integer checks
if not V.integer(0) or not V.integer(100) or not V.integer(-50) then error('basic integers should pass') end
if V.integer(1.5) or V.integer(-0.1) then error('floats should fail integer') end
if not V.integer(10, 0, 100) then error('bounded integer should pass') end
if V.integer(-1, 0, 100) or V.integer(101, 0, 100) then error('out of bound integer should fail') end

-- 3. StringId checks
if not V.stringId('npc_alice') then error('valid stringId should pass') end
if V.stringId('') then error('empty stringId should fail') end
if V.stringId(nil) or V.stringId(123) then error('non-string stringId should fail') end
if V.stringId(string.rep('a', 257)) then error('too long stringId should fail') end
if not V.stringId(string.rep('a', 256)) then error('256-char stringId should pass') end

-- 4. ItemId checks
if not V.itemId(1) or not V.itemId(10005) or not V.itemId(0) then error('valid itemId should pass') end
if V.itemId(-1) then error('negative itemId should fail') end
if V.itemId(1.5) then error('float itemId should fail') end
if V.itemId(V.MAX_SAFE_INT + 1000) then error('oversized itemId should fail') end

-- 5. Coord checks
if not V.coord(0) or not V.coord(10500) or not V.coord(-500) then error('valid coord should pass') end
if V.coord(V.MAX_COORD + 1) or V.coord(-V.MAX_COORD - 1) then error('oversized coord should fail') end

-- 6. Dense checks
if not V.dense({'a', 'b', 'c'}, 5) then error('dense array should pass') end
local sparse = {[1]='a', [3]='c'}
if V.dense(sparse, 5) then error('sparse table should fail dense') end
if V.dense({'a', 'b', 'c'}, 2) then error('exceeding limit should fail dense') end

print('PASS Validate orthogonal primitives test')
