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
    self.current = {}
end

-- Toggle letter i (1-based) in/out of current answer
function AnagramBoard:tapLetter(i)
    local slot = self.scrambled[i]
    if not slot then return end
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

-- Returns "win", "wrong", "too_short"
function AnagramBoard:submit()
    if #self.current < #self.secret then return "too_short" end
    local answer = {}
    for _, idx in ipairs(self.current) do
        answer[#answer + 1] = self.scrambled[idx].letter
    end
    if table.concat(answer) == self.secret then
        self.wins = self.wins + 1
        return "win"
    else
        self.losses = self.losses + 1
        return "wrong"
    end
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
    }
end

function AnagramBoard:load(data)
    if type(data) ~= "table" or not data.secret then return false end
    self.lang    = data.lang    or "en"
    self.length  = data.length  or "random"
    self.secret  = data.secret  or ""
    self.wins    = data.wins    or 0
    self.losses  = data.losses  or 0
    self.scrambled = {}
    for _, s in ipairs(data.scrambled or {}) do
        self.scrambled[#self.scrambled + 1] = { letter = s[1], used = s[2] or false }
    end
    self.current = {}
    for _, v in ipairs(data.current or {}) do
        self.current[#self.current + 1] = v
    end
    return true
end

return AnagramBoard
