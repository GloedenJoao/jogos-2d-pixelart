# Créditos de assets

## Kenney Fonts
- Pasta: `ui/kenney-fonts/`
- Fonte: https://kenney.nl/assets/kenney-fonts
- Licença: Creative Commons CC0 (domínio público, uso livre sem atribuição obrigatória)
- Conteúdo: 12 fontes TTF, incluindo `Kenney Pixel.ttf` e `Kenney Pixel Square.ttf` (pixel fonts, boas para UITheme do framework)
- Baixado em: 2026-08-03

## Kenney Playing Cards Pack
- Pasta: `sprites/kenney-playing-cards/`
- Fonte: https://kenney.nl/assets/playing-cards-pack
- Licença: Creative Commons CC0 (domínio público, uso livre sem atribuição obrigatória)
- Conteúdo: baralho completo (52 cartas + verso + coringas) em pixel art, PNG individuais em 3 tamanhos (`PNG/Cards (small|medium|large)/`) e tilesheets (`Tilesheet/`)
- Baixado em: 2026-08-03
- Uso previsto: arte de cartas do `01-jogo-blackjack/`

## Kenney Tiny Dungeon
- Fonte: https://kenney.nl/assets/tiny-dungeon
- Licença: Creative Commons CC0 (domínio público, uso livre sem atribuição obrigatória)
- Conteúdo: tileset 16×16 (132 tiles) com piso/parede de masmorra, portas, baús, e personagens/criaturas (aventureiros, esqueletos, limos, morcegos, golems, fungos)
- Baixado em: 2026-08-03
- Uso previsto: visual de caverna do `02-jogo-roguelike/` (piso de terra/pedra reaproveitado como chão de caverna, criaturas de masmorra reaproveitadas como "criaturas da caverna"). Copiado diretamente para `02-jogo-roguelike/assets/dungeon/tilemap_packed.png` (cada projeto Godot é self-contained, sem referência cross-project).

## Kenney Pixel Platformer
- Pasta: `sprites/kenney-pixel-platformer/`
- Fonte: https://kenney.nl/assets/pixel-platformer
- Licença: Creative Commons CC0 (domínio público, uso livre sem atribuição obrigatória)
- Conteúdo: tileset 18×18 (180 tiles: terreno com grama/areia/neve, blocos industriais, espinhos, gemas, portas, alavancas, corações) e personagens 24×24 (aventureiros e criaturas, 2–3 quadros cada)
- Baixado em: 2026-08-04
- Uso: arte do `03-jogo-platformer/` (as três eras usam paletas diferentes do mesmo tileset). Copiado para `03-jogo-platformer/assets/platformer/`, mantendo cada projeto Godot self-contained.

## Kenney Tiny Town
- Pasta: `sprites/kenney-tiny-town/`
- Fonte: https://kenney.nl/assets/tiny-town
- Licença: Creative Commons CC0 (domínio público, uso livre sem atribuição obrigatória)
- Conteúdo: tileset 16×16 (132 tiles) com casas, lojas, cercas, árvores, estradas, ferramentas (picareta, forcado, martelo), baús, moedas e aldeões
- Baixado em: 2026-08-04
- Uso: construções e cenário do `04-jogo-civilizacao/`. Copiado para `04-jogo-civilizacao/assets/town/`. Esse projeto também reaproveita o tileset Tiny Dungeon (Projeto 2) em `assets/dungeon/`, para os ícones das eras primitivas. O `05-jogo-colonia/` usa os dois da mesma forma (chão, árvores, casas 2×2 e tonéis vêm daqui).

## Kenney Roguelike Characters
- Pasta: `sprites/kenney-roguelike-characters/`
- Fonte: https://kenney.nl/assets/roguelike-characters
- Licença: Creative Commons CC0 (domínio público, uso livre sem atribuição obrigatória)
- Conteúdo: spritesheet 16×16 com 1px de margem (54×12 tiles) — sistema modular de "paper doll" (cabelos, roupas, elmos, escudos) mais **personagens já montados** nas colunas 0–1, linhas 5–11
- Baixado em: 2026-08-05
- Uso: os moradores do `05-jogo-colonia/`. Só os 12 personagens montados das linhas 5–10 entram no elenco (as peças soltas não são usadas). Copiado para `05-jogo-colonia/assets/characters/`.
