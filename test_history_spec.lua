-- Puzzles are not repeated: solo games and party matches draw through one
-- history per language kept in the plugin settings (game-common
-- seen_history.lua), remembered by letter set (STABLE played = TABLES seen);
-- a party match never repeats a puzzle. Also checks the word lists.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.preload["ui/time"] = function()
    return {
        realtime = function() return os.clock() end,
        to_us    = function(t) return math.floor(t * 1000000) end,
    }
end
package.loaded["i18n"] = package.loaded["i18n"] or function(s) return s end
package.loaded["ffi/util"] = package.loaded["ffi/util"] or { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local Match = assert(loadfile(DIR .. "party_game.lua"))()
local Board = assert(loadfile(DIR .. "board.lua"))()

local function fakePlugin(store)
    store = store or {}
    return {
        store = store,
        getSetting  = function(_self, k, d) local v = store[k]; if v == nil then return d end; return v end,
        saveSetting = function(_self, k, v) store[k] = v end,
    }
end

describe("puzzle history", function()
    it("does not repeat a puzzle (nor its anagram) across two sessions", function()
        local store, seen = {}, {}
        for _session = 1, 2 do
            local b = Board:new{ lang = "en", plugin = fakePlugin(store) }
            seen[Board.letterSet(b.secret)] = 1
            for _g = 1, 499 do
                b:newGame()
                local k = Board.letterSet(b.secret)
                assert.is_nil(seen[k], b.secret)
                seen[k] = 1
            end
        end
        assert.are.equal(1000, #store.seen_words_en)
    end)

    it("shares one history between lengths", function()
        local store = {}
        local b5 = Board:new{ lang = "fr", length = 5, plugin = fakePlugin(store) }
        local br = Board:new{ lang = "fr", plugin = fakePlugin(store) }
        assert.are.equal(5, #b5.secret)
        assert.are_not.equal(Board.letterSet(b5.secret), Board.letterSet(br.secret))
        assert.are.equal(2, #store.seen_words_fr)
    end)

    it("restores a saved game without drawing a word", function()
        local plugin = fakePlugin()
        local b = Board:new{ lang = "en", plugin = plugin }
        local again = Board:new{ lang = "en", plugin = plugin, data = b:serialize() }
        assert.is_true(again.loaded)
        assert.are.equal(b.secret, again.secret)
        assert.are.equal(1, #plugin.store.seen_words_en)
    end)

    it("party: no repeat within a match, saved and restored", function()
        local plugin = fakePlugin()
        local m = Match.new{ names = { "A", "B" }, total = 20, lang = "en", length = 4, plugin = plugin }
        local sets = {}
        for _r = 1, 20 do
            assert.is_true(m:nextWord())
            local k = Board.letterSet(m.secret)
            assert.is_nil(sets[k], m.secret)
            sets[k] = true
            m:reveal()
            m:award(nil)
            m = Match.load(m:serialize(), plugin)
        end
        assert.are.equal(20, #plugin.store.seen_words_en)
    end)

    it("party: the match's words are left out even once the list is used up", function()
        local m = Match.new{ names = { "A", "B" }, total = 5, lang = "en", length = 7 }
        -- Every 7-letter puzzle but two already played this match.
        local all, keep = {}, {}
        for _i, w in ipairs(dofile(DIR .. "words_en.lua")) do
            if #w == 7 then all[#all + 1] = w end
        end
        local a, z = Board.letterSet(all[1]), Board.letterSet(all[#all])
        for _i, w in ipairs(all) do
            local k = Board.letterSet(w)
            if k ~= a and k ~= z then m.used[w] = true end
        end
        m:nextWord(); keep[Board.letterSet(m.secret)] = true
        m:reveal(); m:award(nil)
        m:nextWord(); keep[Board.letterSet(m.secret)] = true
        assert.is_true(keep[a] and keep[z])
    end)
end)

describe("word lists", function()
    for _i, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": 4-7 letters A-Z, no duplicates", function()
            local list, set = dofile(DIR .. "words_" .. lang .. ".lua"), {}
            for _j, w in ipairs(list) do
                assert.is_truthy(w:match("^[A-Z][A-Z][A-Z][A-Z][A-Z]?[A-Z]?[A-Z]?$"), w)
                assert.is_nil(set[w], w)
                set[w] = true
            end
            assert.is_true(#list > 7000, tostring(#list))
        end)
    end
end)
