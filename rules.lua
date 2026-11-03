-- rules.lua — the two rules texts, shown by ScreenBase:makeModeRulesButtonConfig
-- (the mode being played first, a button for the other one).

local _ = require("i18n")

local SOLO_EN = _([[
Anagram — Rules

Rearrange the scrambled letters to form a valid word.

All letters must be used exactly once.
Tap a letter tile (bottom row) to add it to your answer, or tap a letter in the answer to return it to the tiles.
Submit your answer when you think you have the right word.
Some letters make several words: there is one answer row per word to find, and the round is won once every row is filled. Any real word that uses all the letters fills a row.
A wrong answer costs nothing: the letters go back, try again. Give up shows the words you missed and counts as a loss.
]])

local SOLO_FR = [[
Anagramme — Règles

Réarrangez les lettres mélangées pour former un mot valide.

Toutes les lettres doivent être utilisées exactement une fois.
Appuyez sur une tuile (rangée du bas) pour l'ajouter à votre réponse, ou sur une lettre de la réponse pour la remettre avec les tuiles.
Soumettez votre réponse quand vous pensez avoir trouvé le bon mot.
Certaines lettres forment plusieurs mots : il y a une ligne de réponse par mot à trouver, et la partie est gagnée quand toutes les lignes sont remplies. Tout vrai mot qui utilise toutes les lettres remplit une ligne.
Une mauvaise réponse ne coûte rien : les lettres reviennent, réessayez. Abandonner montre les mots manqués et compte comme une défaite.
]]

local PARTY_EN = _([[
Anagram · multiplayer — Rules

A shouting game for 2 to 8 players around one reader laid in the middle of the table.

Setup
In the menu, choose Players (2–8) and type their Player names (remembered for next time), the number of Words in the match (5–20), the Timer per word (off, or 30 s to 2 min), the Language and the Length of the words.

A word
The reader shows the scrambled letters. Everyone looks; the first player to shout a real word that uses every letter exactly once claims it. One player — the host — handles the reader: when someone shouts, the host taps Answer. Every word these letters make appears: the drawn word in black, the other real words in grey — any of them counts. The host then taps the name of the player who shouted the right word first, or Nobody if the shout was wrong or no one found it. A wrong shout costs nothing.
With a timer, the answer appears by itself when time is up; the host can still give the point to a last-second shout, or tap Nobody. Shuffle mixes the letters again if the table is stuck. Next word goes on.

Scoring
A word is worth its length minus 3: 4 letters = 1 point, 5 = 2, 6 = 3, 7 = 4. Only the first right shout scores.

End of the match
After the last word the reader shows the final scoreboard: the player with the most points wins. Players with the same score share their place; if several share the first place, it's a tie. New game starts a new match with the same players.
]])

local PARTY_FR = [[
Anagramme · à plusieurs — Règles

Un jeu de rapidité pour 2 à 8 joueurs autour d'une liseuse posée au milieu de la table.

Préparation
Dans le menu, choisissez les Joueurs (2 à 8) et tapez leurs noms (Noms des joueurs, gardés pour la prochaine fois), le nombre de Mots de la partie (5 à 20), le Chrono par mot (inactif, ou 30 s à 2 min), la Langue et la Longueur des mots.

Un mot
La liseuse montre les lettres mélangées. Tout le monde cherche ; le premier joueur qui crie un vrai mot utilisant chaque lettre une seule fois le revendique. Un joueur — l'animateur — tient la liseuse : quand quelqu'un crie, il touche Réponse. Tous les mots que forment ces lettres s'affichent : le mot tiré en noir, les autres vrais mots en gris — chacun compte. L'animateur touche ensuite le nom du joueur qui a crié le bon mot en premier, ou Personne si la réponse était fausse ou si personne n'a trouvé. Une mauvaise réponse ne coûte rien.
Avec un chrono, la réponse s'affiche d'elle-même à la fin du temps ; l'animateur peut encore donner le point à une réponse criée à la dernière seconde, ou toucher Personne. Mélanger remélange les lettres si la table sèche. Mot suivant continue.

Points
Un mot vaut sa longueur moins 3 : 4 lettres = 1 point, 5 = 2, 6 = 3, 7 = 4. Seule la première bonne réponse marque.

Fin de partie
Après le dernier mot, la liseuse affiche le classement final : le joueur qui a le plus de points gagne. Des joueurs à égalité partagent leur place ; si plusieurs sont premiers ex aequo, c'est une égalité. Nouvelle partie relance une partie avec les mêmes joueurs.
]]

return {
    solo  = { SOLO_EN, SOLO_FR },
    party = { PARTY_EN, PARTY_FR },
}
