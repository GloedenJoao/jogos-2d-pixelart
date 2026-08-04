# Contexto do projeto — jogos-2d-pixelart

Este arquivo é pra qualquer sessão do Claude (Code ou Cowork) que abrir este diretório entender o estado atual sem precisar reperguntar tudo.

## Objetivo

João quer gerar renda publicando jogos 2D pixel art, começando simples e evoluindo pra jogos mais complexos, reaproveitando um framework compartilhado em Godot. Plano completo em `docs/plano-90-dias.md` e ideias de tema em `docs/temas-e-evolucao.md`.

## Estado atual (2026-08-03)

- [x] Estrutura de pastas criada (`framework/`, `01-jogo-blackjack/` — antes `01-jogo-puzzle/`, `02-jogo-roguelike/`, `03-jogo-platformer/`, `04-jogo-civilizacao/`, `assets/`, `docs/`).
- [x] Plano de 90 dias e documento de temas escritos.
- [x] **Repositório git próprio e independente** (não faz mais parte do monorepo `projetos_claude`), publicado em https://github.com/GloedenJoao/jogos-2d-pixelart (público), branch `main`.
- [x] **Godot 4.7.1 (Standard) instalado via winget** (`GodotEngine.GodotEngine`). Não está no PATH deste shell — usar o caminho completo do exe (`C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe`) até reabrir o terminal.
- [x] **Projeto Godot em `framework/`** com os 5 sistemas implementados (`addons/framework/`, estruturado como addon Godot): SceneManager, SaveSystem, StateMachine, AudioManager, UITheme. Ver `framework/README.md`. Marco dos dias 1–15 atingido e validado (headless + visual no editor).
- [x] **Projeto 1 virou blackjack (21), não puzzle** — decisão do João em 2026-08-03 (pediu explicitamente pra trocar o tema). `01-jogo-blackjack/` é um projeto Godot jogável: apostar, pedir/parar/dobrar, dealer joga sozinho, blackjack paga 3:2, saldo/estatísticas persistem via SaveSystem, fases da rodada usam o StateMachine do framework. 28/28 testes headless passando (`01-jogo-blackjack/tests/`) e validado visualmente no editor (blackjack natural, hit/stand, dealer estourando/parando, empate). Ver `01-jogo-blackjack/README.md`.
- [x] Assets do Kenney.nl (CC0) baixados em `assets/` (fontes em `ui/kenney-fonts/`, cartas em `sprites/kenney-playing-cards/`, créditos em `assets/CREDITOS.md`) **e já aplicados** no blackjack: `UITheme` usa `Kenney Pixel.ttf`, e as cartas (`01-jogo-blackjack/scenes/main.gd` + `scripts/card.gd`) renderizam sprites reais em vez de desenho por código. Validado visualmente no editor (rodada completa: aposta, hit, dealer estourando, carta virada revelada) e os 28 testes headless continuam passando.
- [x] Polimento visual do blackjack: animação de "distribuir" cartas (escala/fade), aposta representada por pilha de fichas coloridas, mesas com painel/borda, e painel de "Estatísticas" (mãos jogadas/vencidas, melhor saldo) acessível por botão. Validado visualmente. Ver `01-jogo-blackjack/README.md`.
- [x] **Projeto 2 (roguelike) — marco inicial atingido:** João pediu pra pular a publicação do blackjack no itch.io por ora e seguir direto pro Projeto 2. `02-jogo-roguelike/` é um dungeon crawler top-down grid-based jogável: geração procedural de calabouço (`DungeonGenerator`, salas + corredores em L), combate por bump-attack, IA simples de inimigo (`EnemyAI`: ataca se adjacente, persegue dentro de um raio, senão parado), poções/ouro coletáveis, fases Playing/Victory/GameOver via StateMachine do framework, ouro total e corridas persistem via SaveSystem. Arte: tileset Kenney "Tiny Dungeon" (CC0) reaproveitado como visual de caverna. 39/39 testes headless passando (`02-jogo-roguelike/tests/run_tests.gd`, inclui BFS de conectividade do calabouço) e validado visualmente via `tests/visual_capture.gd` (explorando, combate, vitória, derrota). Ver `02-jogo-roguelike/README.md`.
- [ ] Conta de developer do Google Play já está paga (não é bloqueador).
- [ ] itch.io não requer conta paga nem aprovação — pode publicar quando tiver o primeiro build (blackjack e/ou roguelike).

## O que falta fazer, em ordem

1. Roguelike: mais de 1 andar por corrida, upgrades permanentes de verdade com o ouro acumulado, variedade real de atributos entre inimigos (ver "O que falta" em `02-jogo-roguelike/README.md`).
2. Publicar early builds (blackjack e/ou roguelike) no itch.io — ainda não feito, João decidiu adiar pra seguir com o roguelike primeiro.
3. Depois do roguelike validado, seguir pro Projeto 3 (`03-jogo-platformer/`, dias 66–90 do plano) ou aprofundar o roguelike, dependendo de tração.

## Decisões já tomadas (não reabrir sem motivo)

- Engine: Godot (grátis, sem royalties, bom export web/Android, GDScript acessível pra quem já programa).
- Publicação: itch.io primeiro (grátis, pay-what-you-want) → Google Play depois do jogo validado.
- Arte: pixel art gratuita/CC0 (Kenney.nl) nos primeiros projetos, sem orçamento pra contratar artista por enquanto.
- Ordem dos jogos: blackjack → roguelike → platformer → civilização, cada um introduzindo só 1–2 sistemas novos em cima do framework. O Projeto 1 era puzzle no plano original; João pediu blackjack no lugar (ver `docs/temas-e-evolucao.md`).

## Perguntas em aberto pro João decidir depois

- Se vai programar em GDScript ou C# dentro do Godot.
