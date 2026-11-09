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
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

-- Places a fixed puzzle (secret word, tiles in the given order) on a board.
local function setPuzzle(b, secret, tiles)
    b.secret    = secret
    b.scrambled = {}
    for i = 1, #tiles do
        b.scrambled[i] = { letter = tiles:sub(i, i), used = false }
    end
    b.current = {}
    b.result  = nil
    b:_setTargets()
end

-- Taps the tiles that spell `word`, in order.
local function spell(b, word)
    for i = 1, #word do
        for j, slot in ipairs(b.scrambled) do
            if not slot.used and slot.letter == word:sub(i, i) then
                b:tapLetter(j)
                break
            end
        end
    end
end

describe("AnagramBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / newGame", function()
        it("picks a secret word made only of letters", function()
            local b = Board:new()
            assert.is_true(#b.secret > 0)
            assert.is_nil(b.secret:find("[^A-Z]"))
        end)

        it("scrambled tiles are a permutation of the secret's letters", function()
            local b = Board:new()
            local counts = {}
            for i = 1, #b.secret do
                local ch = b.secret:sub(i, i)
                counts[ch] = (counts[ch] or 0) + 1
            end
            assert.are.equal(#b.secret, #b.scrambled)
            for _, slot in ipairs(b.scrambled) do
                counts[slot.letter] = (counts[slot.letter] or 0) - 1
                assert.is_false(slot.used)
            end
            for _, remaining in pairs(counts) do
                assert.are.equal(0, remaining)
            end
        end)
    end)

    describe("tapLetter", function()
        it("moves a tile into current, then back out", function()
            local b = Board:new()
            b:tapLetter(1)
            assert.are.same({ 1 }, b.current)
            assert.is_true(b.scrambled[1].used)
            b:tapLetter(1)
            assert.are.same({}, b.current)
            assert.is_false(b.scrambled[1].used)
        end)
    end)

    describe("submit", function()
        it("returns too_short when not all letters are placed", function()
            local b = Board:new()
            assert.are.equal("too_short", b:submit())
        end)

        it("returns win and increments wins when a one-word puzzle is solved", function()
            local b = Board:new({ lang = "en" })
            setPuzzle(b, "ZEBRA", "RBZAE")
            assert.are.equal(1, b:getRowCount())
            spell(b, "ZEBRA")
            assert.are.equal("win", b:submit())
            assert.are.equal(1, b.wins)
            assert.is_true(b:isOver())
        end)

        it("shows one answer row per drawn word made of the letters", function()
            local b = Board:new({ lang = "en" })
            setPuzzle(b, "STABLE", "LBTEAS")
            assert.is_true(b:getRowCount() >= 2)   -- STABLE, TABLES...
            local has = {}
            for _, w in ipairs(b.targets) do has[w] = true end
            assert.is_true(has.STABLE and has.TABLES)
        end)

        it("fills a row per word found and wins once every row is filled", function()
            local b = Board:new({ lang = "en" })
            setPuzzle(b, "STABLE", "LBTEAS")
            local rows = b:getRowCount()
            for i, w in ipairs(b.targets) do
                spell(b, w)
                assert.are.equal(i < rows and "found" or "win", b:submit())
                assert.are.same({}, b.current)
            end
            assert.are.equal(1, b.wins)
            assert.is_true(b:isOver())
        end)

        it("refuses a word already found, at no cost", function()
            local b = Board:new({ lang = "en" })
            setPuzzle(b, "STABLE", "LBTEAS")
            spell(b, "STABLE"); b:submit()
            spell(b, "STABLE")
            assert.are.equal("already", b:submit())
            assert.are.equal(1, #b.found)
        end)

        it("accepts a rare dictionary word to fill a row", function()
            local b = Board:new({ lang = "fr" })
            setPuzzle(b, "FUSIBLE", "BLEUSIF")
            assert.are.equal(1, b:getRowCount())
            spell(b, "FIBULES")
            assert.are.equal("win", b:submit())
        end)

        it("lets the player retry after a wrong answer, at no cost", function()
            local b = Board:new({ lang = "en" })
            setPuzzle(b, "STABLE", "LBTEAS")
            spell(b, "SLBTEA")
            assert.are.equal("wrong", b:submit())
            assert.are.equal(0, b.losses)
            assert.are.same({}, b.current)
            assert.is_false(b:isOver())
        end)
    end)

    describe("giveUp", function()
        it("counts a loss and reveals the words not found in the empty rows", function()
            local b = Board:new({ lang = "en" })
            setPuzzle(b, "STABLE", "LBTEAS")
            spell(b, "TABLES"); b:submit()
            b:giveUp()
            assert.are.equal(1, b.losses)
            assert.is_true(b:isOver())
            assert.are.equal(b:getRowCount(), #b.found + #b.revealed)
            for _, w in ipairs(b.revealed) do assert.are_not.equal("TABLES", w) end
            b:tapLetter(1)  -- ignored once over
            assert.are.same({}, b.current)
        end)

        it("newGame starts a fresh round", function()
            local b = Board:new()
            b:giveUp()
            b:newGame()
            assert.is_false(b:isOver())
            assert.are.same({}, b.found)
            assert.are.same({}, b.revealed)
        end)
    end)

    describe("word lists", function()
        it("never draws proper nouns or blocked words", function()
            for _, lang in ipairs({ "en", "fr" }) do
                local words = dofile(DIR .. "words_" .. lang .. ".lua")
                local set = {}
                for _, w in ipairs(words) do set[w] = true end
                assert.is_nil(set.DAVID)
                assert.is_nil(set.SHIT)
                assert.is_nil(set.PUTE)
            end
        end)
    end)

    describe("serialize / load", function()
        it("round-trips secret, scrambled tiles and score", function()
            local b = Board:new()
            b:tapLetter(1)
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.secret, b2.secret)
            assert.are.same({ 1 }, b2.current)
            assert.are.equal(#b.scrambled, #b2.scrambled)
        end)

        it("round-trips a finished round", function()
            local b = Board:new()
            b:giveUp()
            local b2 = Board:new()
            assert.is_true(b2:load(b:serialize()))
            assert.is_true(b2:isOver())
            assert.are.equal(1, b2.losses)
            assert.are.same(b.revealed, b2.revealed)
        end)

        it("rebuilds the answer rows of a game saved before they existed", function()
            local b = Board:new({ lang = "en" })
            setPuzzle(b, "STABLE", "LBTEAS")
            local data = b:serialize()
            data.targets, data.found, data.revealed = nil, nil, nil
            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b:getRowCount(), b2:getRowCount())
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
