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

        it("respects a fixed word length", function()
            local b = Board:new({ length = "5" })
            assert.are.equal(5, #b.secret)
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

        it("returns win and increments wins when the secret is reassembled", function()
            local b = Board:new()
            -- Reconstruct the secret by tapping tiles in the order that
            -- spells it out (scrambled tiles carry the letters, in some order).
            local remaining = {}
            for i = 1, #b.secret do remaining[i] = true end
            for i = 1, #b.secret do
                local ch = b.secret:sub(i, i)
                for j, slot in ipairs(b.scrambled) do
                    if remaining[j] and slot.letter == ch then
                        b:tapLetter(j)
                        remaining[j] = nil
                        break
                    end
                end
            end
            assert.are.equal("win", b:submit())
            assert.are.equal(1, b.wins)
        end)
    end)

    describe("clearCurrent", function()
        it("empties current and un-marks tiles as used", function()
            local b = Board:new()
            b:tapLetter(1)
            b:clearCurrent()
            assert.are.same({}, b.current)
            assert.is_false(b.scrambled[1].used)
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

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
