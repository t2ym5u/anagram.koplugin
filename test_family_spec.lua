-- Family-friendly words: the game is also played at a family table, so no
-- word it draws (words_<lang>.lua) or lists in a reveal (answers_<lang>.lua)
-- may be one of tools/blocklist_<lang>.txt's vulgar, sexual, scatological,
-- slur or drug-related words. tools/build_words.py drops them; this checks
-- the generated files really are clean.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local function blocklist(lang)
    local set, n = {}, 0
    for line in io.lines(DIR .. "tools/blocklist_" .. lang .. ".txt") do
        local w = line:match("^(%u+)%s*$")
        if w then set[w] = true; n = n + 1 end
    end
    return set, n
end

local function wordsOf(name)
    local data, out = dofile(DIR .. name .. ".lua"), {}
    if #data > 0 then
        for _, w in ipairs(data) do out[#out + 1] = w end
    else
        for w in pairs(data) do out[#out + 1] = w end
    end
    return out
end

describe("family-friendly word data", function()
    for _, lang in ipairs({ "en", "fr" }) do
        local blocked, n = blocklist(lang)

        it("the " .. lang .. " blocklist covers the family-table sweep", function()
            assert.is_true(n > 250)
            assert.is_true(blocked[lang == "fr" and "CACA" or "SHIT"])
        end)

        for _, name in ipairs({ "words_" .. lang, "answers_" .. lang }) do
            it(name .. " has no blocklisted word", function()
                local words = wordsOf(name)
                assert.is_true(#words > 1000)
                for _, w in ipairs(words) do
                    assert.is_false(blocked[w:upper()] == true, w)
                end
            end)
        end
    end

    it("no longer draws the French words that prompted the sweep", function()
        local drawn = {}
        for _, w in ipairs(wordsOf("words_fr")) do drawn[w] = true end
        assert.is_nil(drawn.CACA)
        assert.is_nil(drawn.SUCEUR)
    end)
end)
