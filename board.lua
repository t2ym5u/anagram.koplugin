local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Time = require("ui/time")

-- Reseed with microsecond resolution: the app-wide seed (os.time(), 1s
-- resolution) can repeat across quick relaunches, always picking the same
-- first word.
math.randomseed(Time.to_us(Time.realtime()))

local function loadWordList(name)
    local fn = loadfile(_dir .. name .. ".lua")
    return fn and fn() or {}
end

-- A language's word data -- its word list, the list by length, the drawn
-- words grouped by their letters and the rarer answers -- loads the first
-- time that language is played, not with the module, and only that
-- language's. AnagramBoard.release() (the screen closing) drops it all: the
-- lists are quick to read again and are only needed while a game is open.
local DATA = {}

local function groupByLength(list)
    local by_len = {}
    for _, word in ipairs(list) do
        local len = #word
        by_len[len] = by_len[len] or {}
        local bucket = by_len[len]
        bucket[#bucket + 1] = word
    end
    return by_len
end

local function langData(lang)
    lang = lang == "fr" and "fr" or "en"
    local d = DATA[lang]
    if not d then
        local words = loadWordList("words_" .. lang)
        d = { words = words, by_len = groupByLength(words) }
        DATA[lang] = d
    end
    return d
end

local function sortedLetters(word)
    local t = {}
    for i = 1, #word do t[i] = word:sub(i, i) end
    table.sort(t)
    return table.concat(t)
end

-- The drawn words grouped by their letters: a puzzle shows one answer row per
-- drawn word made of its letters (STABLE, TABLES: two rows). Built on the
-- first puzzle of a language.
local function wordsWithLetters(lang, letters)
    local d = langData(lang)
    if not d.by_letters then
        local index = {}
        for _, w in ipairs(d.words) do
            local k = sortedLetters(w)
            index[k] = index[k] or {}
            table.insert(index[k], w)
        end
        d.by_letters = index
    end
    return d.by_letters[sortedLetters(letters)] or {}
end

-- Other real words made of the same letters (answers_<lang>.lua, generated
-- from boggle's full dictionary). Loaded on the first answer.
local function otherAnswers(lang)
    local d = langData(lang)
    if not d.answers then
        d.answers = loadWordList("answers_" .. (lang == "fr" and "fr" or "en"))
    end
    return d.answers
end

-- Puzzles already played, remembered in the plugin settings (game-common
-- seen_history.lua), one history per language whatever the length setting:
-- a new word is one not seen yet, and a word only comes back once its whole
-- list has been played (about 3,000 puzzles: the oldest are forgotten past
-- SEEN_MAX). A word is remembered by its letters, so STABLE played means
-- TABLES -- the same puzzle -- waits too.
local SeenHistory = require("seen_history")
local SEEN_MAX = 3000

-- Memoised: a draw looks up the letters of every word of the pool.
local LETTER_SETS = {}
local function letterSet(word)
    local k = LETTER_SETS[word]
    if not k then
        k = sortedLetters(word:upper())
        LETTER_SETS[word] = k
    end
    return k
end

-- ---------------------------------------------------------------------------
-- AnagramBoard
-- ---------------------------------------------------------------------------

local AnagramBoard = {}
AnagramBoard.__index = AnagramBoard

-- opts.plugin : settings holder for the puzzle history (none: plain random,
--               as in the specs); opts.data : a saved game to restore instead
--               of drawing a word (obj.loaded tells whether it worked);
--               opts.exclude : set of letter sets (AnagramBoard.letterSet)
--               this board must not draw -- a party match's earlier words.
function AnagramBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        plugin   = opts.plugin,
        exclude  = opts.exclude,
        lang     = opts.lang or "en",
        length   = opts.length or "random",
        secret   = "",
        scrambled = {},
        current  = {},
        wins     = opts.wins   or 0,
        losses   = opts.losses or 0,
        result   = nil,   -- nil while playing, "win" or "lost" once over
    }, self)
    obj.loaded = opts.data ~= nil and obj:load(opts.data) or false
    if not obj.loaded then obj:newGame() end
    return obj
end

function AnagramBoard:_wordList()
    return langData(self.lang).words
end

function AnagramBoard:_wordListByLen()
    return langData(self.lang).by_len
end

function AnagramBoard:newGame()
    local list
    local len = tonumber(self.length)
    if len then
        list = self:_wordListByLen()[len]
    end
    list = list or self:_wordList()
    if self.exclude then
        local left = {}
        for _i, w in ipairs(list) do
            if not self.exclude[letterSet(w)] then left[#left + 1] = w end
        end
        if #left > 0 then list = left end
    end
    local word
    if self.plugin then
        word = SeenHistory.open(self.plugin, "words_" .. self.lang,
                                { max = SEEN_MAX, id_of = letterSet }):pick(list)
    else
        word = list[math.random(#list)]
    end
    self.secret = word:upper()

    -- scramble: shuffle until the result is none of the answer rows. Checking
    -- only the drawn word let another row show as is (MATE drawn, MEAT shown:
    -- about 2 % of 4-letter puzzles).
    local rows = { [self.secret] = true }
    for _, w in ipairs(wordsWithLetters(self.lang, self.secret)) do rows[w] = true end
    local letters = {}
    for i = 1, #self.secret do
        letters[i] = self.secret:sub(i, i)
    end
    local attempts = 0
    repeat
        for i = #letters, 2, -1 do
            local j = math.random(i)
            letters[i], letters[j] = letters[j], letters[i]
        end
        attempts = attempts + 1
    until not rows[table.concat(letters)] or attempts > 50

    self.scrambled = {}
    for _, ch in ipairs(letters) do
        self.scrambled[#self.scrambled + 1] = { letter = ch, used = false }
    end
    self.current  = {}
    self.result   = nil
    self:_setTargets()
end

-- targets: the drawn words this puzzle's letters make, one answer row each;
-- found: what the player has entered, row by row (any real word counts, so
-- a rare dictionary word can fill a row too); revealed: the targets shown
-- in the rows left empty after giving up.
function AnagramBoard:_setTargets()
    self.targets = {}
    for _, w in ipairs(wordsWithLetters(self.lang, self.secret)) do
        self.targets[#self.targets + 1] = w
    end
    if #self.targets == 0 then self.targets = { self.secret } end
    self.found    = {}
    self.revealed = {}
end

-- Every word made of exactly these letters that the plugin knows -- the
-- drawn words, then the rarer ones of answers_<lang>.lua -- alphabetical
-- (the multiplayer reveal lists them all).
function AnagramBoard.anagramsOf(lang, letters)
    letters = letters:upper()
    local key, seen, out = sortedLetters(letters), {}, {}
    local function add(w)
        if not seen[w] then seen[w] = true; out[#out + 1] = w end
    end
    for _, w in ipairs(wordsWithLetters(lang, letters)) do add(w) end
    for w in pairs(otherAnswers(lang)) do
        if #w == #key and sortedLetters(w) == key then add(w) end
    end
    if #out == 0 then add(letters) end
    table.sort(out)
    return out
end

function AnagramBoard:getRowCount()
    return #self.targets
end

function AnagramBoard:isOver()
    return self.result ~= nil
end

-- Toggle letter i (1-based) in/out of current answer
function AnagramBoard:tapLetter(i)
    local slot = self.scrambled[i]
    if not slot or self.result then return end
    if slot.used then
        -- remove from current
        for j = #self.current, 1, -1 do
            if self.current[j] == i then
                table.remove(self.current, j)
                slot.used = false
                return
            end
        end
    else
        slot.used = true
        self.current[#self.current + 1] = i
    end
end

function AnagramBoard:clearCurrent()
    for _, slot in ipairs(self.scrambled) do slot.used = false end
    self.current = {}
end

-- Returns "found" (a row filled, more to find), "win" (all rows filled),
-- "already", "wrong" or "too_short". Any real word made of all the letters
-- fills a row, not only the drawn ones (TABLES for STABLE). A wrong answer
-- costs nothing -- the letters go back and the player tries again; only
-- giving up counts as a loss.
function AnagramBoard:submit()
    if self.result then return self.result end
    if #self.current < #self.secret then return "too_short" end
    local answer = self:getAnswer()
    self:clearCurrent()
    for _, w in ipairs(self.found) do
        if w == answer then return "already" end
    end
    local valid = otherAnswers(self.lang)[answer]
    for _, w in ipairs(self.targets) do
        if w == answer then valid = true end
    end
    if not valid then return "wrong" end
    self.found[#self.found + 1] = answer
    if #self.found < #self.targets then return "found" end
    self.wins   = self.wins + 1
    self.result = "win"
    return "win"
end

-- Counts as a loss and fills the rows left empty with drawn words the player
-- did not find.
function AnagramBoard:giveUp()
    if self.result then return end
    self.losses = self.losses + 1
    self.result = "lost"
    self:clearCurrent()
    local found = {}
    for _, w in ipairs(self.found) do found[w] = true end
    self.revealed = {}
    for _, w in ipairs(self.targets) do
        if #self.found + #self.revealed >= #self.targets then break end
        if not found[w] then self.revealed[#self.revealed + 1] = w end
    end
end

function AnagramBoard:getAnswer()
    local answer = {}
    for _, idx in ipairs(self.current) do
        answer[#answer + 1] = self.scrambled[idx].letter
    end
    return table.concat(answer)
end

function AnagramBoard:getDisplay()
    local parts = {}
    for _, idx in ipairs(self.current) do
        parts[#parts + 1] = self.scrambled[idx].letter
    end
    while #parts < #self.secret do parts[#parts + 1] = "_" end
    return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function AnagramBoard:serialize()
    local sc = {}
    for _, s in ipairs(self.scrambled) do
        sc[#sc + 1] = { s.letter, s.used }
    end
    return {
        lang      = self.lang,
        length    = self.length,
        secret    = self.secret,
        scrambled = sc,
        current   = self.current,
        wins      = self.wins,
        losses    = self.losses,
        result    = self.result,
        targets   = self.targets,
        found     = self.found,
        revealed  = self.revealed,
    }
end

function AnagramBoard:load(data)
    if type(data) ~= "table" or not data.secret then return false end
    self.lang    = data.lang    or "en"
    self.length  = data.length  or "random"
    self.secret  = data.secret  or ""
    self.wins    = data.wins    or 0
    self.losses  = data.losses  or 0
    self.result  = data.result
    self.scrambled = {}
    for _, s in ipairs(data.scrambled or {}) do
        self.scrambled[#self.scrambled + 1] = { letter = s[1], used = s[2] or false }
    end
    self.current = {}
    for _, v in ipairs(data.current or {}) do
        self.current[#self.current + 1] = v
    end
    if data.targets then
        self.targets  = data.targets
        self.found    = data.found or {}
        self.revealed = data.revealed or {}
    else
        -- A game saved before answer rows existed: one row per drawn word.
        self:_setTargets()
    end
    return true
end

AnagramBoard.letterSet = letterSet

-- Drops every loaded word list (called when the game screen closes); the
-- next game reads its language's lists again.
function AnagramBoard.release()
    DATA = {}
    LETTER_SETS = {}
end

-- The languages whose word data is loaded now (for the specs).
function AnagramBoard.loadedLanguages()
    local out = {}
    for lang in pairs(DATA) do out[#out + 1] = lang end
    table.sort(out)
    return out
end

return AnagramBoard
