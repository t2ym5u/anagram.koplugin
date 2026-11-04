local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase           = require("screen_base")
local MenuHelper           = require("menu_helper")
local AnagramBoard         = lrequire("board")
local AnagramBoardWidget   = lrequire("board_widget")
local Mode                 = lrequire("mode")
local Rules                = lrequire("rules")

-- ---------------------------------------------------------------------------
-- AnagramScreen
-- ---------------------------------------------------------------------------

local AnagramScreen = ScreenBase:extend{}

function AnagramScreen:init()
    -- A saved game is restored; otherwise a fresh word is drawn.
    self.board = AnagramBoard:new{
        lang   = self.plugin:getSetting("lang", "en"),
        length = self.plugin:getSetting("length", "random"),
        plugin = self.plugin,
        data   = self.plugin:loadState(),
    }
    ScreenBase.init(self)
end

function AnagramScreen:serializeState()
    return self.board:serialize()
end

function AnagramScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Anagram"), function()
        return {
            { text = _("New game"),       callback = function() self:onNewGame() end },
            { text = self:_langLabel(),   callback = function() self:openLangMenu() end },
            { text = self:_lengthLabel(), callback = function() self:openLengthMenu() end },
            { text = Mode.label(self.plugin), callback = function() Mode.openMenu(self) end },
            self:makeModeRulesButtonConfig(Rules),
        }
    end)

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(self:_actionRows(is_landscape)),
    }

    local frame_pad   = Size.padding.large
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)

    self.board_widget = AnagramBoardWidget:new{
        board       = self.board,
        max_width   = math.max(budget_w - frame_extra, 80),
        max_height  = math.max(budget_h - frame_extra, 60),
        letterTapCallback = function(i) self:onLetterTap(i) end,
    }

    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self:updateStatus()
end

-- Three labels squeeze in the narrow landscape side panel, so there Submit
-- gets its own row above the two others.
function AnagramScreen:_actionRows(is_landscape)
    local submit  = { text = _("Submit"),  callback = function() self:onSubmit() end }
    local clear   = { text = _("Clear"),   callback = function() self:onClear() end }
    local give_up = { text = _("Give up"), callback = function() self:onGiveUp() end }
    if is_landscape then
        return { { submit }, { clear, give_up } }
    end
    return { submit, clear, give_up }
end

function AnagramScreen:onLetterTap(i)
    self.board:tapLetter(i)
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function AnagramScreen:onSubmit()
    local answer = self.board:getAnswer()
    local result = self.board:submit()
    if result == "too_short" then
        self:updateStatus(_("Not enough letters!"))
    elseif result == "wrong" then
        self:updateStatus(_("Not that one, try again."))
    elseif result == "already" then
        self:updateStatus(T(_("Already found: %1"), answer))
    elseif result == "found" then
        local left = self.board:getRowCount() - #self.board.found
        self:updateStatus(T(_("%1 found! %2 more to find."), answer, left))
    else
        self:updateStatus()
    end
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:refreshActionBar()
end

function AnagramScreen:onGiveUp()
    self.board:giveUp()
    self.plugin:saveState(self.board:serialize())
    self.board_widget:refresh()
    self:updateStatus()
    self:refreshActionBar()
end

function AnagramScreen:isRoundOver()
    return self.board:isOver()
end

function AnagramScreen:getRoundOverButtons()
    return { { text = _("Next word"), callback = function() self:onNewGame() end } }
end

function AnagramScreen:onClear()
    self.board:clearCurrent()
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function AnagramScreen:onNewGame()
    local lang   = self.plugin:getSetting("lang", "en")
    local length = self.plugin:getSetting("length", "random")
    self.board.lang   = lang
    self.board.length = length
    local wins   = self.board.wins
    local losses = self.board.losses
    self.board:newGame()
    self.board.wins   = wins
    self.board.losses = losses
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function AnagramScreen:openLangMenu()
    local items = {
        { id = "en", text = _("English") },
        { id = "fr", text = _("Français") },
    }
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = items,
        current_id = self.plugin:getSetting("lang", "en"),
        parent     = self,
        on_select  = function(lang)
            self.plugin:saveSetting("lang", lang)
            self.board.lang = lang
            if self.lang_btn then
                self.lang_btn:setText(self:_langLabel(), self.lang_btn.width)
            end
            self:onNewGame()
        end,
    }
end

function AnagramScreen:openLengthMenu()
    local items = {
        { id = "random", text = _("Random (4-7)") },
        { id = "4",       text = _("4 letters") },
        { id = "5",       text = _("5 letters") },
        { id = "6",       text = _("6 letters") },
        { id = "7",       text = _("7 letters") },
    }
    MenuHelper.openPickerMenu{
        title      = _("Length"),
        items      = items,
        current_id = self.plugin:getSetting("length", "random"),
        parent     = self,
        on_select  = function(length)
            self.plugin:saveSetting("length", length)
            self.board.length = length
            self:onNewGame()
        end,
    }
end

function AnagramScreen:updateStatus(msg)
    local status
    local b = self.board
    local rows = b:getRowCount()
    if msg then
        status = msg
    elseif b.result == "win" and rows > 1 then
        status = T(_("All %1 words found! Wins: %2"), rows, b.wins)
    elseif b.result == "win" and b.found[1] ~= b.secret then
        status = T(_("Correct! %1 works too. Wins: %2"), b.secret, b.wins)
    elseif b.result == "win" then
        status = T(_("Correct! Wins: %1"), b.wins)
    elseif b.result == "lost" and rows > 1 then
        status = T(_("Found %1 of %2."), #b.found, rows)
    elseif b.result == "lost" then
        status = T(_("The word was: %1"), b.secret)
    else
        status = self:joinStatus(
            rows > 1 and T(_("Words: %1/%2"), #b.found, rows) or nil,
            T(_("Wins: %1"),   b.wins),
            T(_("Losses: %1"), b.losses))
    end
    ScreenBase.updateStatus(self, status)
end

function AnagramScreen:_langLabel()
    local lang = self.plugin:getSetting("lang", "en")
    return T(_("Language: %1"), lang == "fr" and "FR" or "EN")
end

function AnagramScreen:_lengthLabel()
    local length = self.plugin:getSetting("length", "random")
    if length == "random" then
        return T(_("Length: %1"), _("Random"))
    end
    return T(_("Length: %1"), length)
end

-- The word lists are only needed while a game is open: drop them when the
-- screen closes (the next game reads its language's lists again).
function AnagramScreen:onCloseWidget()
    AnagramBoard.release()
end

return AnagramScreen
