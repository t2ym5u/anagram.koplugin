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

local WORDS_EN = loadWordList("words_en")
local WORDS_FR = loadWordList("words_fr")

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

local WORDS_EN_BY_LEN = groupByLength(WORDS_EN)
local WORDS_FR_BY_LEN = groupByLength(WORDS_FR)

local function sortedLetters(word)
    local t = {}
    for i = 1, #word do t[i] = word:sub(i, i) end
    table.sort(t)
    return table.concat(t)
end

-- The drawn words grouped by their letters: a puzzle shows one answer row per
-- drawn word made of its letters (STABLE, TABLES: two rows). Built on the
-- first puzzle of a language, not at startup.
local BY_LETTERS = {}
local function wordsWithLetters(lang, letters)
    if not BY_LETTERS[lang] then
        local index = {}
        for _, w in ipairs(lang == "fr" and WORDS_FR or WORDS_EN) do
            local k = sortedLetters(w)
            index[k] = index[k] or {}
            table.insert(index[k], w)
        end
        BY_LETTERS[lang] = index
    end
    return BY_LETTERS[lang][sortedLetters(letters)] or {}
end

-- Other real words made of the same letters (answers_<lang>.lua, generated
-- from boggle's full dictionary). Loaded on the first answer, not at startup.
local ANSWERS = {}
local function otherAnswers(lang)
    if not ANSWERS[lang] then
        ANSWERS[lang] = loadWordList("answers_" .. lang)
    end
    return ANSWERS[lang]
end

-- ---------------------------------------------------------------------------
-- AnagramBoard
-- ---------------------------------------------------------------------------

local AnagramBoard = {}
AnagramBoard.__index = AnagramBoard

function AnagramBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        lang     = opts.lang or "en",
        length   = opts.length or "random",
        secret   = "",
        scrambled = {},
        current  = {},
        wins     = opts.wins   or 0,
        losses   = opts.losses or 0,
        result   = nil,   -- nil while playing, "win" or "lost" once over
    }, self)
    obj:newGame()
    return obj
end

function AnagramBoard:_wordList()
    return self.lang == "fr" and WORDS_FR or WORDS_EN
end

function AnagramBoard:_wordListByLen()
    return self.lang == "fr" and WORDS_FR_BY_LEN or WORDS_EN_BY_LEN
end

function AnagramBoard:newGame()
    local list
    local len = tonumber(self.length)
    if len then
        list = self:_wordListByLen()[len]
    end
    list = list or self:_wordList()
    local word = list[math.random(#list)]
    self.secret = word:upper()

    -- scramble: shuffle and ensure result != original
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
    until table.concat(letters) ~= self.secret or attempts > 20

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

return AnagramBoard
