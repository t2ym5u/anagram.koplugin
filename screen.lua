local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local ScreenBase           = require("screen_base")
local MenuHelper           = require("menu_helper")
local AnagramBoard         = lrequire("board")
local AnagramBoardWidget   = lrequire("board_widget")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- AnagramScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Anagram — Rules

Rearrange the scrambled letters to form a valid word.

All letters must be used exactly once.
Tap a scrambled letter to add it to your answer, or tap a letter in the answer to return it to the scramble.
Submit your answer when you think you have the right word.
]])

local GAME_RULES_FR = [[
Anagramme — Règles

Réarrangez les lettres mélangées pour former un mot valide.

Toutes les lettres doivent être utilisées exactement une fois.
Appuyez sur une lettre mélangée pour l'ajouter à votre réponse, ou sur une lettre de la réponse pour la remettre dans le mélange.
Soumettez votre réponse quand vous pensez avoir trouvé le bon mot.
]]

local AnagramScreen = ScreenBase:extend{}

function AnagramScreen:init()
    local state = self.plugin:loadState()
    local lang  = self.plugin:getSetting("lang", "en")
    self.board  = AnagramBoard:new{ lang = lang }
    if not self.board:load(state) then
        -- fresh game
    end
    ScreenBase.init(self)
end

function AnagramScreen:serializeState()
    return self.board:serialize()
end

function AnagramScreen:buildLayout()
    local sw           = DeviceScreen:getWidth()
    local sh           = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local btn_width = is_landscape
        and math.max(math.floor(sw * 0.38), 120)
        or  math.floor(sw * 0.9)

    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("New"),    callback = function() self:onNewGame() end },
            { id = "lang_btn", text = self:_langLabel(),
              callback = function() self:openLangMenu() end },
            { text = _("Submit"), callback = function() self:onSubmit() end },
            { text = _("Clear"),  callback = function() self:onClear() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.lang_btn = top_buttons:getButtonById("lang_btn")

    local margin      = Size.margin.default
    local padding     = Size.padding.large
    local frame_extra = (padding + margin) * 2

    local board_max_w = is_landscape and math.floor(sw * 0.55) or sw - frame_extra
    local board_max_h = math.floor(sh * 0.25)
    board_max_w = math.max(board_max_w, 80)
    board_max_h = math.max(board_max_h, 60)

    self.board_widget = AnagramBoardWidget:new{
        board       = self.board,
        max_width   = board_max_w,
        max_height  = board_max_h,
        onLetterTap = function(i) self:onLetterTap(i) end,
    }

    local board_frame = FrameContainer:new{
        padding = padding,
        margin  = margin,
        self.board_widget,
    }

    if is_landscape then
        local right = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:updateStatus()
end

function AnagramScreen:onLetterTap(i)
    self.board:tapLetter(i)
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function AnagramScreen:onSubmit()
    local result = self.board:submit()
    if result == "too_short" then
        self:updateStatus(_("Not enough letters!"))
    elseif result == "win" then
        self:updateStatus(T(_("Correct! Wins: %1"), self.board.wins))
        self.plugin:saveState(self.board:serialize())
    elseif result == "wrong" then
        self:updateStatus(T(_("Wrong! The word was: %1  Losses: %2"),
            self.board.secret, self.board.losses))
        self.plugin:saveState(self.board:serialize())
    end
    self.board_widget:refresh()
end

function AnagramScreen:onClear()
    self.board:clearCurrent()
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function AnagramScreen:onNewGame()
    local lang = self.plugin:getSetting("lang", "en")
    self.board.lang = lang
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

function AnagramScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    else
        status = T(_("Wins: %1  Losses: %2"), self.board.wins, self.board.losses)
    end
    ScreenBase.updateStatus(self, status)
end

function AnagramScreen:_langLabel()
    local lang = self.plugin:getSetting("lang", "en")
    return lang == "fr" and "FR" or "EN"
end

return AnagramScreen
