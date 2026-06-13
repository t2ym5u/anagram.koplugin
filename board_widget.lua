local Blitbuffer     = require("ffi/blitbuffer")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local C_BG      = Blitbuffer.COLOR_WHITE
local C_CELL    = Blitbuffer.COLOR_GRAY_E
local C_USED    = Blitbuffer.COLOR_GRAY_B
local C_ANSWER  = Blitbuffer.COLOR_GRAY_D
local C_BORDER  = Blitbuffer.COLOR_BLACK
local C_TEXT    = Blitbuffer.COLOR_BLACK
local C_DIM     = Blitbuffer.COLOR_GRAY_9

-- ---------------------------------------------------------------------------
-- AnagramBoardWidget
-- ---------------------------------------------------------------------------

local AnagramBoardWidget = InputContainer:extend{
    board       = nil,
    max_width   = 300,
    max_height  = 120,
    onLetterTap = nil,
}

function AnagramBoardWidget:init()
    local n    = #self.board.scrambled
    n = math.max(n, 1)
    local cell = math.floor(math.min(self.max_width / n, self.max_height / 2))
    cell = math.max(cell, 14)
    self.cell = cell
    self.n    = n
    self.w    = cell * n
    self.h    = cell * 2 + 8
    self.dimen = Geom:new{ w = self.w, h = self.h }
    self.paint_rect = nil

    local face_sz = math.max(7, math.floor(cell * 0.55))
    self.letter_face = Font:getFace("smallinfofont", face_sz)

    self.ges_events = {
        LetterTap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
end

function AnagramBoardWidget:onLetterTap(ges)
    if not self.paint_rect then return true end
    local rect = self.paint_rect
    local lx = ges.pos.x - rect.x
    local ly = ges.pos.y - rect.y
    if lx < 0 or ly < 0 or lx >= self.w then return true end
    -- only top row (scrambled) is tappable
    if ly >= 0 and ly < self.cell then
        local idx = math.floor(lx / self.cell) + 1
        if idx >= 1 and idx <= self.n then
            if self.onLetterTap then self.onLetterTap(idx) end
        end
    end
    return true
end

function AnagramBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local cell  = self.cell
    local gap   = 8

    bb:paintRect(x, y, self.w, self.h, C_BG)

    local pad  = math.max(1, math.floor(cell * 0.1))
    local cinn = cell - 2 * pad

    -- Row 1: scrambled letters
    for i, slot in ipairs(board.scrambled) do
        local cx = x + (i - 1) * cell
        local cy = y
        local bg = slot.used and C_USED or C_CELL
        bb:paintRect(cx + 1, cy + 1, cell - 2, cell - 2, bg)
        bb:paintRect(cx, cy, cell, 1, C_BORDER)
        bb:paintRect(cx, cy + cell - 1, cell, 1, C_BORDER)
        bb:paintRect(cx, cy, 1, cell, C_BORDER)
        bb:paintRect(cx + cell - 1, cy, 1, cell, C_BORDER)

        local color = slot.used and C_DIM or C_TEXT
        local m  = RenderText:sizeUtf8Text(0, cinn, self.letter_face, slot.letter, true, false)
        local tx = cx + pad + math.floor((cinn - m.x) / 2)
        local ty = cy + pad + math.floor((cinn + m.y_top - m.y_bottom) / 2)
        RenderText:renderUtf8Text(bb, tx, ty, self.letter_face, slot.letter, true, false, color)
    end

    -- Row 2: current answer
    local current_letters = {}
    for _, idx in ipairs(board.current) do
        current_letters[#current_letters + 1] = board.scrambled[idx].letter
    end
    local secret_len = #board.secret
    for i = 1, secret_len do
        local cx = x + (i - 1) * cell
        local cy = y + cell + gap
        bb:paintRect(cx + 1, cy + 1, cell - 2, cell - 2, C_ANSWER)
        bb:paintRect(cx, cy, cell, 1, C_BORDER)
        bb:paintRect(cx, cy + cell - 1, cell, 1, C_BORDER)
        bb:paintRect(cx, cy, 1, cell, C_BORDER)
        bb:paintRect(cx + cell - 1, cy, 1, cell, C_BORDER)

        local ch = current_letters[i]
        if ch then
            local m  = RenderText:sizeUtf8Text(0, cinn, self.letter_face, ch, true, false)
            local tx = cx + pad + math.floor((cinn - m.x) / 2)
            local ty = cy + pad + math.floor((cinn + m.y_top - m.y_bottom) / 2)
            RenderText:renderUtf8Text(bb, tx, ty, self.letter_face, ch, true, false, C_TEXT)
        end
    end
end

function AnagramBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

return AnagramBoardWidget
