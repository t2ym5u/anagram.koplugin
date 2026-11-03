-- party_screen.lua — Anagram · multiplayer: the reader lies on the table,
-- shows the scrambled letters big, runs the timer and keeps the scores; the
-- players shout their answers. The match itself is party_game.lua.

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Font            = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase  = require("screen_base")
local MenuHelper  = require("menu_helper")
local Party       = require("party")
local Timer       = require("timer")
local Match       = lrequire("party_game")
local PartyWidget = lrequire("party_widget")
local Mode        = lrequire("mode")
local Rules       = lrequire("rules")

local STATE_KEY = "party_state"

local function timeLabel(s)
    if s <= 0 then return _("Off") end
    if s % 60 == 0 then return T(_("%1 min"), s / 60) end
    return T(_("%1 s"), s)
end

local function clockText(s)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local PartyScreen = ScreenBase:extend{}

function PartyScreen:init()
    self.match = Match.load(self.plugin:loadState(STATE_KEY))
    if not self.match then self:_newMatch() end
    ScreenBase.init(self)
    self:_startClock()
end

function PartyScreen:_newMatch()
    local n = Party.loadCount(self.plugin)
    self.match = Match.new{
        names      = Party.loadPlayers(self.plugin, n),
        total      = self.plugin:getSetting("party_words", Match.DEFAULT_WORDS),
        lang       = self.plugin:getSetting("lang", "en"),
        length     = self.plugin:getSetting("length", "random"),
        time_limit = self.plugin:getSetting("party_time", Match.DEFAULT_TIME),
    }
    self.match:nextWord()
    self:_save()
end

function PartyScreen:serializeState()
    return self.match:serialize()
end

function PartyScreen:_save()
    self.plugin:saveState(self.match:serialize(), STATE_KEY)
end

-- ScreenBase:closeScreen saves under the solo game's key: keep them apart.
function PartyScreen:closeScreen()
    self:_stopClock()
    self:_save()
    self.plugin:onScreenClosed()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
end

function PartyScreen:isRoundOver()
    return self.match:isOver()
end

-- ---------------------------------------------------------------------------
-- Clock: once a second, only the countdown line is repainted.
-- ---------------------------------------------------------------------------

function PartyScreen:_startClock()
    self:_stopClock()
    local m = self.match
    if m.phase ~= "playing" or m.time_limit <= 0 then return end
    self.clock = Timer:new()
    self.clock:load{ elapsed = m.time_limit - m.time_left, was_running = true }
    local gen = self._clock_gen
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

function PartyScreen:_stopClock()
    self._clock_gen = (self._clock_gen or 0) + 1
    self.clock = nil
end

function PartyScreen:_onTick(gen)
    if gen ~= self._clock_gen or not self.clock then return end
    local m = self.match
    if m:setTimeLeft(m.time_limit - self.clock:getElapsed()) then
        self:_stopClock()
        self:onAnswer()
        return
    end
    if self.timer_widget then self.timer_widget:setText(clockText(m.time_left), self) end
    UIManager:scheduleIn(1, function() self:_onTick(gen) end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function PartyScreen:_menuItems()
    return {
        { text = _("New game"), callback = function() self:onNewGame() end },
        { text = T(_("Players: %1"), #self.match.scores.names),
          callback = function() Party.pickCount(self.plugin, function() self:onNewGame() end, self) end },
        { text = _("Player names"), callback = function()
            Party.editPlayers(self.plugin, self.match.scores.names, function()
                self:_save()
                self:_redraw()
            end, self)
        end },
        { text = T(_("Words: %1"), self.match.total), callback = function() self:openWordsMenu() end },
        { text = T(_("Timer: %1"), timeLabel(self.match.time_limit)),
          callback = function() self:openTimeMenu() end },
        { text = T(_("Language: %1"), self.match.lang == "fr" and "FR" or "EN"),
          callback = function() self:openLangMenu() end },
        { text = self:_lengthLabel(), callback = function() self:openLengthMenu() end },
        { text = Mode.label(self.plugin), callback = function() Mode.openMenu(self) end },
        { text = _("Scores"), callback = function() Party.showScoreboard(self.match.scores) end },
        self:makeModeRulesButtonConfig(Rules),
    }
end

-- While the answer is up, the bar holds one button per player (two per row)
-- and Nobody: the same choice as Party.askWhoFound, but a centred dialog
-- would hide the answers the table is checking.
function PartyScreen:_actionRows()
    local phase = self.match.phase
    if phase == "playing" then
        return { {
            { text = _("Shuffle"), callback = function() self:onShuffle() end },
            { text = _("Answer"),  callback = function() self:onAnswer() end },
        } }
    elseif phase == "answer" then
        local rows, row = {}, {}
        for i, name in ipairs(self.match.scores.names) do
            row[#row + 1] = { text = name, callback = function() self:onAward(i) end }
            if #row == 2 then rows[#rows + 1] = row; row = {} end
        end
        if #row > 0 then rows[#rows + 1] = row end
        rows[#rows + 1] = { { text = _("Nobody"), callback = function() self:onAward(nil) end } }
        return rows
    end
    return { { { text = _("Next word"), callback = function() self:onNextWord() end } } }
end

function PartyScreen:buildLayout()
    local is_landscape = self:isLandscape()
    local m = self.match
    local title_bar = self:buildTitleBar(_("Anagram"), function() return self:_menuItems() end)

    local controls_w = self:getControlsWidth()
    self.status_text:setMaxWidth(controls_w)
    local controls = VerticalGroup:new{ align = "center" }
    self.timer_widget = nil
    if m.phase == "playing" and m.time_limit > 0 then
        -- Readable from across the table: about a sixth of the short side.
        local short = math.min(self.dimen.w, self.dimen.h)
        self.timer_widget = PartyWidget.BigText:new{
            text   = clockText(m.time_left),
            width  = controls_w,
            height = math.floor(short * (is_landscape and 0.2 or 0.17)),
        }
        table.insert(controls, self.timer_widget)
        table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_large })
    end
    -- The scores on their own lines, bigger than the status: it wraps, where
    -- the portrait status line is cut at one line.
    table.insert(controls, TextBoxWidget:new{
        text      = Party.statusText(m.scores),
        face      = Font:getFace("infofont"),
        width     = controls_w,
        alignment = "center",
    })
    table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_default })
    table.insert(controls, self.status_text)
    table.insert(controls, VerticalSpan:new{ width = Size.span.vertical_large })
    table.insert(controls, self:buildActionBar(self:_actionRows()))

    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.party_widget = PartyWidget:new{
        match      = m,
        max_width  = math.max(budget_w, 80),
        max_height = math.max(budget_h, 60),
    }

    if is_landscape then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            self.party_widget,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, self.party_widget,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

function PartyScreen:_redraw()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function PartyScreen:updateStatus(msg)
    local m = self.match
    local scores = m.scores
    local head = msg
    if not head then
        if m.phase == "over" then
            local leaders = Party.leaders(scores)
            head = #leaders == 1 and T(_("%1 wins!"), scores.names[leaders[1]]) or _("It's a tie!")
        elseif m.phase == "answer" then
            head = (m.time_limit > 0 and m.time_left == 0) and _("Time's up!") or _("Who found it?")
        elseif m.phase == "scored" then
            head = m.finder and T(_("%1 found it: +%2"), scores.names[m.finder] or "?",
                Match.wordPoints(m.secret)) or _("Nobody found it.")
        end
    end
    ScreenBase.updateStatus(self, self:joinStatus(
        m.phase ~= "over" and T(_("Word %1/%2"), scores.round, m.total) or nil, head))
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function PartyScreen:onShuffle()
    self.match:shuffle()
    self:_save()
    self:_redraw()
end

function PartyScreen:onAnswer()
    if not self.match:reveal() then return end
    self:_stopClock()
    self:_save()
    self:_redraw()
end

function PartyScreen:onAward(seat)
    self.match:award(seat)
    self:_save()
    self:_redraw()
    if self.match:isOver() then
        Party.showScoreboard(self.match.scores, { final = true })
    end
end

function PartyScreen:onNextWord()
    if not self.match:nextWord() then return end
    self:_save()
    self:_redraw()
    self:_startClock()
end

function PartyScreen:onNewGame()
    self:_stopClock()
    self:_newMatch()
    self:_redraw()
    self:_startClock()
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function PartyScreen:openWordsMenu()
    local items = {}
    for _i, n in ipairs(Match.WORD_CHOICES) do items[#items + 1] = { id = n, text = tostring(n) } end
    MenuHelper.openPickerMenu{
        title = _("Words"), items = items, current_id = self.match.total, parent = self,
        on_select = function(n)
            self.plugin:saveSetting("party_words", n)
            self:onNewGame()
        end,
    }
end

-- Takes effect at once: the current word starts its countdown over.
function PartyScreen:openTimeMenu()
    local items = {}
    for _i, s in ipairs(Match.TIME_CHOICES) do items[#items + 1] = { id = s, text = timeLabel(s) } end
    MenuHelper.openPickerMenu{
        title = _("Timer"), items = items, current_id = self.match.time_limit, parent = self,
        on_select = function(s)
            self.plugin:saveSetting("party_time", s)
            local m = self.match
            m.time_limit, m.time_left = s, s
            self:_save()
            self:_redraw()
            self:_startClock()
        end,
    }
end

function PartyScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title = _("Language"),
        items = { { id = "en", text = _("English") }, { id = "fr", text = _("Français") } },
        current_id = self.match.lang, parent = self,
        on_select = function(lang)
            self.plugin:saveSetting("lang", lang)
            self:onNewGame()
        end,
    }
end

function PartyScreen:_lengthLabel()
    local length = self.match.length
    return T(_("Length: %1"), length == "random" and _("Random") or length)
end

function PartyScreen:openLengthMenu()
    MenuHelper.openPickerMenu{
        title = _("Length"),
        items = {
            { id = "random", text = _("Random (4-7)") },
            { id = "4", text = _("4 letters") }, { id = "5", text = _("5 letters") },
            { id = "6", text = _("6 letters") }, { id = "7", text = _("7 letters") },
        },
        current_id = self.match.length, parent = self,
        on_select = function(length)
            self.plugin:saveSetting("length", length)
            self:onNewGame()
        end,
    }
end

return PartyScreen
