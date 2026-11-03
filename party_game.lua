-- party_game.lua — Anagram's multiplayer match, no UI (testable under busted).
--
-- The reader lies on the table and shows the scrambled letters; whoever
-- shouts a word using all of them first wins the word. A match is `total`
-- words. Each word goes through:
--   "playing"  letters shown, the timer (if any) running
--   "answer"   the words are revealed; waiting for "who found it?"
--   "scored"   the point is given (or nobody got it); next word
--   "over"     after the last word: final scores
-- A word is worth its length minus 3 points (4 letters = 1 … 7 letters = 4):
-- with "Length: Random" a long word is harder, so it is worth more.

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Party        = require("party")
local AnagramBoard = lrequire("board")

local Match = {}
Match.__index = Match

Match.WORD_CHOICES = { 5, 10, 15, 20 }
Match.TIME_CHOICES = { 0, 30, 60, 90, 120 }   -- seconds per word, 0 = no limit
Match.DEFAULT_WORDS = 10
Match.DEFAULT_TIME  = 60

function Match.wordPoints(word)
    return math.max(1, #(word or "") - 3)
end

-- opts: names, total, lang, length, time_limit, plugin (settings holder for
-- the puzzle history shared with the solo game; none in the specs)
function Match.new(opts)
    local m = setmetatable({
        plugin     = opts.plugin,
        scores     = Party.newScores(opts.names or {}),
        total      = opts.total or Match.DEFAULT_WORDS,
        lang       = opts.lang or "en",
        length     = opts.length or "random",
        time_limit = opts.time_limit or 0,
        phase      = "scored",   -- no word yet: nextWord() starts the first
        secret     = "",
        letters    = "",
        answers    = {},
        finder     = nil,        -- seat that found the current word, false = nobody
        time_left  = 0,
        used       = {},         -- secrets already drawn this match
    }, Match)
    return m
end

function Match:isOver()
    return self.phase == "over"
end

-- Draws the next word and scrambles it: never one already played this match
-- (nor its anagram: the same letters), and through the solo game's puzzle
-- history, so a word seen before waits until the list is used up.
function Match:nextWord()
    if self.phase ~= "scored" then return false end
    local exclude = {}
    for w in pairs(self.used) do exclude[AnagramBoard.letterSet(w)] = true end
    local board = AnagramBoard:new{ lang = self.lang, length = self.length,
                                    plugin = self.plugin, exclude = exclude }
    local letters = {}
    for i, s in ipairs(board.scrambled) do letters[i] = s.letter end
    self.secret    = board.secret
    self.letters   = table.concat(letters)
    self.answers   = {}
    self.finder    = nil
    self.used[self.secret] = true
    self.time_left = self.time_limit
    self.phase     = "playing"
    Party.nextRound(self.scores)
    return true
end

-- Reshuffle the letters on the table (never back to the word itself).
function Match:shuffle()
    if self.phase ~= "playing" or #self.letters < 2 then return end
    local t = {}
    for i = 1, #self.letters do t[i] = self.letters:sub(i, i) end
    local prev = self.letters
    for _try = 1, 20 do
        for i = #t, 2, -1 do
            local j = math.random(i)
            t[i], t[j] = t[j], t[i]
        end
        local s = table.concat(t)
        if s ~= self.secret and s ~= prev then break end
    end
    self.letters = table.concat(t)
end

-- The screen's clock says `left` seconds remain; true when time is up.
function Match:setTimeLeft(left)
    if self.phase ~= "playing" or self.time_limit <= 0 then return false end
    self.time_left = math.max(0, math.min(self.time_limit, math.floor(left)))
    return self.time_left == 0
end

-- Shows the answers: every word these letters make.
function Match:reveal()
    if self.phase ~= "playing" then return false end
    self.answers = AnagramBoard.anagramsOf(self.lang, self.secret)
    self.phase   = "answer"
    return true
end

-- seat (or nil for nobody) found the word. Returns the points given.
function Match:award(seat)
    if self.phase ~= "answer" then return 0 end
    local pts = 0
    if seat and self.scores.points[seat] then
        pts = Match.wordPoints(self.secret)
        Party.award(self.scores, seat, pts)
        self.finder = seat
    else
        self.finder = false
    end
    self.phase = (self.scores.round >= self.total) and "over" or "scored"
    return pts
end

-- ---------------------------------------------------------------------------
-- Persistence (a separate setting key from the solo game)
-- ---------------------------------------------------------------------------

function Match:serialize()
    local used = {}
    for w in pairs(self.used) do used[#used + 1] = w end
    return {
        scores     = Party.copyScores(self.scores),
        total      = self.total,
        lang       = self.lang,
        length     = self.length,
        time_limit = self.time_limit,
        phase      = self.phase,
        secret     = self.secret,
        letters    = self.letters,
        answers    = self.answers,
        finder     = self.finder,
        time_left  = self.time_left,
        used       = used,
    }
end

local PHASES = { playing = true, answer = true, scored = true, over = true }

function Match.load(t, plugin)
    if type(t) ~= "table" or not PHASES[t.phase] then return nil end
    local scores = Party.restoreScores(t.scores)
    if not scores or type(t.secret) ~= "string" or type(t.letters) ~= "string"
            or #t.secret ~= #t.letters then
        return nil
    end
    local m = Match.new{
        names = scores.names, total = tonumber(t.total), lang = t.lang,
        length = t.length, time_limit = tonumber(t.time_limit) or 0,
        plugin = plugin,
    }
    m.scores    = scores
    m.phase     = t.phase
    m.secret    = t.secret
    m.letters   = t.letters
    m.answers   = type(t.answers) == "table" and t.answers or {}
    m.finder    = t.finder
    m.time_left = tonumber(t.time_left) or m.time_limit
    for _i, w in ipairs(type(t.used) == "table" and t.used or {}) do m.used[w] = true end
    if m.phase == "answer" and #m.answers == 0 then
        m.answers = AnagramBoard.anagramsOf(m.lang, m.secret)
    end
    return m
end

return Match
