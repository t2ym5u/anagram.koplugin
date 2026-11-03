-- Spec for the multiplayer match (party_game.lua): words, points, rounds,
-- save/restore.
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
package.loaded["i18n"] = function(s) return s end
package.loaded["ffi/util"] = { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local Match = assert(loadfile(DIR .. "party_game.lua"))()
local Board = assert(loadfile(DIR .. "board.lua"))()

local function sorted(w)
    local t = {}
    for i = 1, #w do t[i] = w:sub(i, i) end
    table.sort(t)
    return table.concat(t)
end

describe("Anagram party match", function()
    it("scores a word by its length", function()
        assert.are.equal(1, Match.wordPoints("STAR"))
        assert.are.equal(2, Match.wordPoints("STARE"))
        assert.are.equal(4, Match.wordPoints("STABLES"))
    end)

    it("lists every anagram the plugin knows, drawn word included", function()
        local list = Board.anagramsOf("en", "STABLE")
        local has = {}
        for _, w in ipairs(list) do has[w] = true; assert.are.equal(sorted("STABLE"), sorted(w)) end
        assert.is_true(has.STABLE)
        assert.is_true(has.TABLES)
        for i = 2, #list do assert.is_true(list[i - 1] < list[i]) end
    end)

    it("plays a match: reveal, award, next word, over after N words", function()
        local m = Match.new{ names = { "Ann", "Bob" }, total = 2, lang = "en", time_limit = 30 }
        assert.is_true(m:nextWord())
        assert.are.equal("playing", m.phase)
        assert.are.equal(1, m.scores.round)
        assert.are.equal(sorted(m.secret), sorted(m.letters))
        assert.are_not.equal(m.secret, m.letters)
        assert.is_false(m:nextWord())          -- not before the word is scored
        assert.are.equal(0, m:award(1))         -- nor awarded before the reveal

        assert.is_true(m:reveal())
        assert.are.equal("answer", m.phase)
        local found = false
        for _, w in ipairs(m.answers) do if w == m.secret then found = true end end
        assert.is_true(found)
        local first = m.secret
        assert.are.equal(Match.wordPoints(first), m:award(2))
        assert.are.equal("scored", m.phase)
        assert.are.same({ 0, Match.wordPoints(first) }, m.scores.points)

        assert.is_true(m:nextWord())
        assert.are_not.equal(first, m.secret)   -- no word twice in a match
        m:reveal()
        m:award(nil)                            -- nobody
        assert.is_false(m.finder)
        assert.is_true(m:isOver())
        assert.is_false(m:nextWord())
    end)

    it("runs the timer down to time's up", function()
        local m = Match.new{ names = { "A", "B" }, total = 3, time_limit = 30 }
        m:nextWord()
        assert.are.equal(30, m.time_left)
        assert.is_false(m:setTimeLeft(12.6))
        assert.are.equal(12, m.time_left)
        assert.is_true(m:setTimeLeft(-3))
        local untimed = Match.new{ names = { "A", "B" }, time_limit = 0 }
        untimed:nextWord()
        assert.is_false(untimed:setTimeLeft(0))
    end)

    it("shuffles without giving the word away", function()
        local m = Match.new{ names = { "A", "B" }, length = "7" }
        m:nextWord()
        for _ = 1, 10 do
            m:shuffle()
            assert.are.equal(sorted(m.secret), sorted(m.letters))
            assert.are_not.equal(m.secret, m.letters)
        end
    end)

    it("saves and restores a match in progress, and a finished one", function()
        local m = Match.new{ names = { "Ann", "Bob", "Cy" }, total = 1, time_limit = 60 }
        m:nextWord()
        m:setTimeLeft(41)
        local r = Match.load(m:serialize())
        assert.are.equal("playing", r.phase)
        assert.are.equal(m.secret, r.secret)
        assert.are.equal(m.letters, r.letters)
        assert.are.equal(41, r.time_left)
        assert.are.same({ "Ann", "Bob", "Cy" }, r.scores.names)
        assert.is_true(r.used[m.secret])

        r:reveal()
        local a = Match.load(r:serialize())
        assert.are.equal("answer", a.phase)
        assert.are.same(r.answers, a.answers)
        a:award(3)
        local over = Match.load(a:serialize())
        assert.is_true(over:isOver())
        assert.are.equal(3, over.finder)
        assert.are.equal(Match.wordPoints(m.secret), over.scores.points[3])
    end)

    it("rejects broken saves", function()
        assert.is_nil(Match.load(nil))
        assert.is_nil(Match.load({ phase = "playing" }))
        assert.is_nil(Match.load({ phase = "nope", scores = { names = { "A" }, points = { 0 } } }))
        assert.is_nil(Match.load({ phase = "playing", secret = "ABC", letters = "AB",
            scores = { names = { "A" }, points = { 0 } } }))
    end)
end)
