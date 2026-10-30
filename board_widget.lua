local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
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

local Screen = Device.screen

-- Largest face whose ink for `sample` fits max_w x max_h. Measured unbounded
-- (a max_width limit cuts the text, so the width test could never fail), ink
-- height is y_top + y_bottom, and Font:getFace scales its size by the DPI, so
-- the pixel bound is converted back first.
local function fitFace(name, sample, max_w, max_h)
    local lo = 6
    local hi = math.max(lo, math.floor(max_h * 1000 / Screen:scaleBySize(1000)) * 2)
    local best = lo
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), Font:getFace(name, mid), sample, true, false)
        if m.x <= max_w and m.y_top + m.y_bottom <= max_h then
            best, lo = mid, mid + 1
        else
            hi = mid - 1
        end
    end
    return Font:getFace(name, best)
end

-- Centre `text` on (cx, cy): the baseline sits half the ink height below cy.
local function drawCentered(bb, face, text, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false)
    RenderText:renderUtf8Text(bb, cx - math.floor(m.x / 2),
        cy + math.floor((m.y_top - m.y_bottom) / 2), face, text, true, false, color)
end

-- ---------------------------------------------------------------------------
-- AnagramBoardWidget
-- ---------------------------------------------------------------------------

local AnagramBoardWidget = InputContainer:extend{
    board             = nil,
    max_width         = 300,
    max_height        = 120,
    letterTapCallback = nil,
}

-- Layout, top to bottom: one answer row per word to find, then, a little
-- apart, the scrambled tiles -- at the bottom, next to the buttons and under
-- the thumb. The row being filled has a thick border.
function AnagramBoardWidget:init()
    local n = math.max(#self.board.scrambled, 1)
    local rows = math.max(self.board:getRowCount(), 1)
    -- A tile is never wider than a fifth of the room, so a 4-letter word does
    -- not get tiles twice the size of a 7-letter one. Rows are a tenth of a
    -- tile apart; the tiles sit half a tile below the last row.
    local cell = math.floor(math.min(self.max_width / math.max(n, 5),
        self.max_height / (rows + 1 + 0.1 * (rows - 1) + 0.5)))
    cell = math.max(cell, 14)
    self.cell     = cell
    self.row_gap  = math.max(2, math.floor(cell * 0.1))
    self.tile_gap = math.max(6, math.floor(cell * 0.5))
    self.n        = n
    self.rows     = rows
    self.w        = cell * n
    self.tiles_y  = rows * cell + (rows - 1) * self.row_gap + self.tile_gap
    self.h        = self.tiles_y + cell
    self.dimen = Geom:new{ w = self.w, h = self.h }
    self.paint_rect = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }

    self.letter_face = fitFace("smallinfofont", "W", math.floor(cell * 0.7), math.floor(cell * 0.55))

    self.ges_events = {
        LetterTap = { GestureRange:new{ ges = "tap", range = function() return self.paint_rect end } },
    }
end

function AnagramBoardWidget:_rowY(i)
    return (i - 1) * (self.cell + self.row_gap)
end

-- The answer row being filled, or nil once the round is over.
function AnagramBoardWidget:_activeRow()
    local board = self.board
    if board:isOver() then return nil end
    return #board.found + 1
end

function AnagramBoardWidget:onLetterTap(_, ges)
    if not (ges and ges.pos) or not self.paint_rect then return true end
    local rect = self.paint_rect
    local lx = ges.pos.x - rect.x
    local ly = ges.pos.y - rect.y
    if lx < 0 or ly < 0 or lx >= self.w or not self.letterTapCallback then return true end
    local idx = math.floor(lx / self.cell) + 1
    if ly >= self.tiles_y then
        -- a scrambled tile: add it to the answer (or take it back)
        if idx <= self.n then self.letterTapCallback(idx) end
        return true
    end
    -- a letter of the row being filled: return it to the tiles
    local active = self:_activeRow()
    local y0 = active and self:_rowY(active)
    if y0 and ly >= y0 and ly < y0 + self.cell then
        local current = self.board.current
        if idx <= #current then self.letterTapCallback(current[idx]) end
    end
    return true
end

local function drawBox(bb, x, y, size, bg, border, thickness)
    bb:paintRect(x, y, size, size, border)
    bb:paintRect(x + thickness, y + thickness, size - 2 * thickness, size - 2 * thickness, bg)
end

function AnagramBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local cell  = self.cell
    local half  = math.floor(cell / 2)
    local thick = math.max(2, math.floor(cell / 20))

    bb:paintRect(x, y, self.w, self.h, C_BG)

    -- Answer rows
    local current = {}
    for _, idx in ipairs(board.current) do
        current[#current + 1] = board.scrambled[idx].letter
    end
    local active = self:_activeRow()
    local len = #board.secret
    for r = 1, self.rows do
        local word, bg, border, color, t
        if board.found[r] then
            word, bg, border, color, t = board.found[r], C_ANSWER, C_BORDER, C_TEXT, 1
        elseif board.revealed[r - #board.found] then
            word, bg, border, color, t = board.revealed[r - #board.found], C_BG, C_DIM, C_DIM, 1
        elseif r == active then
            word, bg, border, color, t = table.concat(current), C_ANSWER, C_BORDER, C_TEXT, thick
        else
            word, bg, border, color, t = "", C_BG, C_DIM, C_TEXT, 1
        end
        local ry = y + self:_rowY(r)
        for i = 1, len do
            local cx = x + (i - 1) * cell
            drawBox(bb, cx, ry, cell, bg, border, t)
            local ch = word:sub(i, i)
            if ch ~= "" then
                drawCentered(bb, self.letter_face, ch, cx + half, ry + half, color)
            end
        end
    end

    -- Scrambled tiles, at the bottom
    local ty = y + self.tiles_y
    for i, slot in ipairs(board.scrambled) do
        local cx = x + (i - 1) * cell
        drawBox(bb, cx, ty, cell, slot.used and C_USED or C_CELL, C_BORDER, 1)
        drawCentered(bb, self.letter_face, slot.letter, cx + half, ty + half,
            slot.used and C_DIM or C_TEXT)
    end
end

function AnagramBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

return AnagramBoardWidget
