-- Difficulty guarantees (docs/dev/TESTING.md, "Difficulty specs").
--
-- Anagram's level is the word length (Length: 4, 5, 6 or 7 letters, or
-- Random 4-7); a longer word is harder, so the multiplayer match scores it
-- higher. This checks the bands of both word lists (en, fr), that each
-- length draws only words of that length, the length points, that a seed
-- gives the same puzzle, and that the scramble does not give the word away.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
-- board.lua reseeds once from the clock when it loads (a fresh word on each
-- launch); the draws themselves only use math.random. A constant clock here
-- makes that explicit: any later read would not change the draws either.
package.preload["ui/time"] = function()
    return {
        realtime = function() return 0 end,
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

local LENGTHS = { 4, 5, 6, 7 }

local function scramble(b)
    local t = {}
    for i, s in ipairs(b.scrambled) do t[i] = s.letter end
    return table.concat(t)
end

describe("Anagram difficulty", function()
    teardown(function()
        Board.release()
    end)

    -- moved from test_history_spec.lua ("word lists")
    for _, lang in ipairs({ "en", "fr" }) do
        it(lang .. ": 4-7 letters A-Z, no duplicates", function()
            local list, set = dofile(DIR .. "words_" .. lang .. ".lua"), {}
            for _, w in ipairs(list) do
                assert.is_truthy(w:match("^[A-Z][A-Z][A-Z][A-Z][A-Z]?[A-Z]?[A-Z]?$"), w)
                assert.is_nil(set[w], w)
                set[w] = true
            end
            assert.is_true(#list > 7000, tostring(#list))
        end)

        -- 2026-11-09: en 1433 / 1933 / 2273 / 2306, fr 889 / 1840 / 2815 / 3343
        it(lang .. ": every length offers enough words", function()
            local by_len = {}
            for _, w in ipairs(dofile(DIR .. "words_" .. lang .. ".lua")) do
                by_len[#w] = (by_len[#w] or 0) + 1
            end
            for _, len in ipairs(LENGTHS) do
                assert.is_true((by_len[len] or 0) >= 800, lang .. " " .. len .. ": " .. tostring(by_len[len]))
            end
        end)
    end

    -- moved from test_board_spec.lua ("respects a fixed word length"), now
    -- every length and both languages
    it("each length draws only words of that length; Random draws 4 to 7", function()
        for _, lang in ipairs({ "en", "fr" }) do
            for _, len in ipairs(LENGTHS) do
                for seed = 1, 10 do
                    math.randomseed(seed)
                    local b = Board:new({ lang = lang, length = tostring(len) })
                    assert.are.equal(len, #b.secret, lang .. " " .. b.secret)
                    assert.are.equal(len, #b.scrambled)
                    for _, t in ipairs(b.targets) do assert.are.equal(len, #t) end
                end
            end
            local seen = {}
            for seed = 1, 60 do
                math.randomseed(seed)
                local n = #Board:new({ lang = lang, length = "random" }).secret
                assert.is_true(n >= 4 and n <= 7, lang .. " " .. n)
                seen[n] = true
            end
            for _, len in ipairs(LENGTHS) do assert.is_true(seen[len], lang .. " random never drew " .. len) end
        end
    end)

    -- moved from test_party_spec.lua, plus the order over every length
    it("party: a word scores its length minus 3, longer words more", function()
        assert.are.equal(1, Match.wordPoints("STAR"))
        assert.are.equal(2, Match.wordPoints("STARE"))
        assert.are.equal(4, Match.wordPoints("STABLES"))
        for i = 2, #LENGTHS do
            assert.is_true(Match.wordPoints(("A"):rep(LENGTHS[i - 1])) < Match.wordPoints(("A"):rep(LENGTHS[i])))
        end
    end)

    it("a seed draws the same word and the same scramble", function()
        for _, lang in ipairs({ "en", "fr" }) do
            for _, len in ipairs({ "4", "7", "random" }) do
                for seed = 1, 5 do
                    math.randomseed(seed)
                    local a = Board:new({ lang = lang, length = len })
                    math.randomseed(seed)
                    local b = Board:new({ lang = lang, length = len })
                    assert.are.equal(a.secret, b.secret)
                    assert.are.equal(scramble(a), scramble(b))
                end
            end
        end
    end)

    it("the scramble is never the drawn word itself", function()
        for _, lang in ipairs({ "en", "fr" }) do
            for _, len in ipairs(LENGTHS) do
                for seed = 1, 50 do
                    math.randomseed(seed)
                    local b = Board:new({ lang = lang, length = tostring(len) })
                    assert.are_not.equal(b.secret, scramble(b), lang .. " " .. b.secret)
                end
            end
        end
    end)

    -- Up to 1.6.3 newGame only rejected a scramble equal to the drawn word, so
    -- it could show another answer row as is (en, 4 letters, seed 63: MATE
    -- shown as MEAT): en 43 / 4 / 1 / 0 and fr 33 / 12 / 3 / 0 puzzles in
    -- 2000 seeds (4 / 5 / 6 / 7 letters), about 2 % of 4-letter puzzles.
    it("never shows an answer row as the scramble", function()
        for _, lang in ipairs({ "en", "fr" }) do
            for _, len in ipairs(LENGTHS) do
                for seed = 1, 300 do
                    math.randomseed(seed)
                    local b = Board:new({ lang = lang, length = tostring(len) })
                    local shown = scramble(b)
                    for _, t in ipairs(b.targets) do
                        assert.are_not.equal(t, shown, ("%s %d seed %d: %s shown as %s"):format(
                            lang, len, seed, b.secret, shown))
                    end
                end
            end
        end
    end)
end)
