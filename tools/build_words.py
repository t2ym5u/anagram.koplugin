#!/usr/bin/env python3
# Rebuilds Anagram's word data from boggle.koplugin's Scrabble-valid
# dictionary. Run from the monorepo root:  python3 anagram.koplugin/tools/build_words.py
#
# words_<lang>.lua   -- the words Anagram draws. Cleaned in place: a word must
#                       also be in the dictionary (drops the proper nouns and
#                       abbreviations the frequency list carries: DAVID, USSR)
#                       and not in tools/blocklist_<lang>.txt.
# answers_<lang>.lua -- every other real word Anagram accepts: dictionary words
#                       sharing their letters with a drawn word (TABLES for
#                       STABLE), minus the blocklist. Taken from every block
#                       of boggle.koplugin's list: in French its second block
#                       holds the Grammalecte lexicon's forms (that plugin's
#                       tools/lexicon_fr.py, which filters them for family
#                       play). The drawn words only use its first block.
# The number of answer rows a puzzle shows is how many drawn words share its
# letters; the game computes that itself from words_<lang>.lua.
import collections, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOGGLE = os.path.join(os.path.dirname(ROOT), "boggle.koplugin")
NAMES = {"en": "English", "fr": "French"}


def raw_block(text):
    m = re.search(r"\[\[(.*?)\]\]", text, re.S)
    return m


def all_words_of(text):
    # Every [[...]] block, not only the first.
    return [w.upper() for b in re.findall(r"\[\[(.*?)\]\]", text, re.S) for w in re.findall(r"[A-Za-z]+", b)]


def words_of(text):
    m = raw_block(text)
    return [w.upper() for w in re.findall(r"[A-Za-z]+", m.group(1) if m else text)]


def wrap(words):
    lines, line = [], ""
    for w in words:
        if len(line) + len(w) + 1 > 96:
            lines.append(line)
            line = ""
        line += ("," if line else "") + w
    lines.append(line)
    return "\n".join(lines)


def key(w):
    return "".join(sorted(w))


for lang, name in NAMES.items():
    blocked = {
        l.strip() for l in open(os.path.join(ROOT, "tools", f"blocklist_{lang}.txt"), encoding="utf-8")
        if l.strip() and not l.startswith("#")
    }
    boggle_text = open(os.path.join(BOGGLE, f"words_{lang}.lua"), encoding="utf-8").read()
    dictionary = set(words_of(boggle_text)) - blocked
    accepted = set(all_words_of(boggle_text)) - blocked

    path = os.path.join(ROOT, f"words_{lang}.lua")
    text = open(path, encoding="utf-8").read()
    kept = [w for w in words_of(text) if w in dictionary]
    m = raw_block(text)
    text = text[:m.start(1)] + "\n" + wrap(kept) + "\n" + text[m.end(1):]
    text = re.sub(r"^-- \d+ words(?: after cleaning)?:", f"-- {len(kept)} words after cleaning:", text, count=1, flags=re.M)
    open(path, "w", encoding="utf-8").write(text)

    keys = {key(w) for w in kept}
    groups = collections.defaultdict(set)
    for w in accepted:
        if key(w) in keys:
            groups[key(w)].add(w)
    others = sorted({w for g in groups.values() if len(g) > 1 for w in g})
    open(os.path.join(ROOT, f"answers_{lang}.lua"), "w", encoding="utf-8").write(
        f"""-- {name}: the answers Anagram accepts besides its own words (generated, do not edit).
-- Every word of boggle.koplugin/words_{lang}.lua (see there for the sources
-- and credits) that shares its letters with another word, for the letter sets of this
-- plugin's words_{lang}.lua: when the scramble of STABLE is answered TABLES, that
-- is a real word made of all the letters, so it counts. {len(others)} words.
-- Regenerate with tools/build_words.py (run from the monorepo root).
local words = {{}}
local raw = [[
{wrap(others)}
]]
for word in raw:gmatch("%a+") do
    words[word] = true
end
return words
""")
    print(lang, "drawn:", len(kept), "accepted extras:", len(others))
