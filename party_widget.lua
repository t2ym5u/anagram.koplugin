-- party_widget.lua — what the multiplayer table sees: the scrambled letters
-- as big as the room allows, then, once revealed, every word they make. Plus
-- BigText, a fixed-size line (the countdown) that repaints only itself.

local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Font       = require("ui/font")
local Geom       = require("ui/geometry")
local RenderText = require("ui/rendertext")
local UIManager  = require("ui/uimanager")
local Widget     = require("ui/widget/widget")

local C_BG     = Blitbuffer.COLOR_WHITE
local C_CELL   = Blitbuffer.COLOR_GRAY_E
local C_BORDER = Blitbuffer.COLOR_BLACK
local C_TEXT   = Blitbuffer.COLOR_BLACK
local C_DIM    = Blitbuffer.COLOR_GRAY_7

local Screen = Device.screen

-- Largest face whose ink for `sample` fits max_w x max_h (same measure as
-- board_widget.lua: unbounded width, ink height y_top + y_bottom, DPI undone).
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

local function drawCentered(bb, face, text, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, false)
    RenderText:renderUtf8Text(bb, cx - math.floor(m.x / 2),
        cy + math.floor((m.y_top - m.y_bottom) / 2), face, text, true, false, color)
end

local function drawBox(bb, x, y, size, bg, border, thickness)
    bb:paintRect(x, y, size, size, border)
    bb:paintRect(x + thickness, y + thickness, size - 2 * thickness, size - 2 * thickness, bg)
end

-- ---------------------------------------------------------------------------
-- BigText
-- ---------------------------------------------------------------------------

local BigText = Widget:extend{
    text   = "",
    width  = 100,
    height = 40,
    sample = "0:00",   -- the face is fitted once, on this sample
}

function BigText:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.face = fitFace("cfont", self.sample, math.floor(self.width * 0.95), math.floor(self.height * 0.8))
end

function BigText:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function BigText:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, C_BG)
    drawCentered(bb, self.face, self.text, x + math.floor(self.width / 2),
        y + math.floor(self.height / 2), C_TEXT)
end

-- Repaints this line only (the timer ticks once a second).
function BigText:setText(text, refresh_parent)
    if text == self.text then return end
    self.text = text
    if refresh_parent then
        UIManager:setDirty(refresh_parent, function()
            return "fast", Geom:new{ x = self.dimen.x, y = self.dimen.y, w = self.width, h = self.height }
        end)
    end
end

-- ---------------------------------------------------------------------------
-- PartyWidget
-- ---------------------------------------------------------------------------

local PartyWidget = Widget:extend{
    match      = nil,
    max_width  = 300,
    max_height = 300,
}

function PartyWidget:init()
    local m = self.match
    local n = math.max(#m.letters, 1)
    local w, h = self.max_width, self.max_height
    self.w, self.h = w, h
    self.dimen = Geom:new{ w = w, h = h }
    local revealed = m.phase ~= "playing"
    -- Letters first: as big as a 5-letter word would get, so a short word is
    -- not huge; once revealed they shrink to leave room for the answers.
    local gap  = math.max(4, math.floor(w / 60))
    local cell = math.floor((w - (math.max(n, 5) - 1) * gap) / math.max(n, 5))
    cell = math.min(cell, math.floor(h * (revealed and 0.3 or 0.6)))
    self.cell, self.gap = math.max(cell, 20), gap
    self.letter_face = fitFace("cfont", "W", math.floor(self.cell * 0.75), math.floor(self.cell * 0.6))

    self.words = revealed and m.answers or {}
    if #self.words > 0 then
        local top = self.cell + 2 * gap
        local avail_h = h - top
        -- The fewest columns that still give the tallest line; the drawn word
        -- is no bigger than the tiles.
        local best
        for cols = 1, 3 do
            local rows = math.ceil(#self.words / cols)
            local lh = math.min(math.floor(avail_h / rows), self.cell)
            local face = fitFace("cfont", string.rep("W", n), math.floor(w / cols * 0.9), math.floor(lh * 0.7))
            if not best or face.orig_size > best.face.orig_size then
                best = { cols = cols, rows = rows, lh = lh, face = face }
            end
        end
        self.list = best
        self.list_y = top
    end
end

function PartyWidget:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

function PartyWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local m = self.match
    bb:paintRect(x, y, self.w, self.h, C_BG)
    local n, cell, gap = #m.letters, self.cell, self.gap
    local row_w = n * cell + (n - 1) * gap
    local content_h = cell
    if self.list then content_h = self.list_y + self.list.rows * self.list.lh end
    local top = y + math.max(0, math.floor((self.h - content_h) / 2))
    local lx = x + math.floor((self.w - row_w) / 2)
    local thick = math.max(2, math.floor(cell / 25))
    for i = 1, n do
        local cx = lx + (i - 1) * (cell + gap)
        drawBox(bb, cx, top, cell, C_CELL, C_BORDER, thick)
        drawCentered(bb, self.letter_face, m.letters:sub(i, i),
            cx + math.floor(cell / 2), top + math.floor(cell / 2), C_TEXT)
    end
    local list = self.list
    if not list then return end
    local colw = math.floor(self.w / list.cols)
    for i, word in ipairs(self.words) do
        local col = math.floor((i - 1) / list.rows)
        local row = (i - 1) % list.rows
        -- The drawn word is the one in black; the others the letters also
        -- make are grey: any of them wins the point.
        drawCentered(bb, list.face, word, x + col * colw + math.floor(colw / 2),
            top + self.list_y + row * list.lh + math.floor(list.lh / 2),
            word == m.secret and C_TEXT or C_DIM)
    end
end

PartyWidget.BigText = BigText
return PartyWidget
