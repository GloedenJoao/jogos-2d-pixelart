# Contexto do projeto — jogos-2d-pixelart

Este arquivo é pra qualquer sessão do Claude (Code ou Cowork) que abrir este diretório entender o estado atual sem precisar reperguntar tudo.

## Objetivo

João quer gerar renda publicando jogos 2D pixel art, começando simples e evoluindo pra jogos mais complexos, reaproveitando um framework compartilhado em Godot. Plano completo em `docs/plano-90-dias.md` e ideias de tema em `docs/temas-e-evolucao.md`.

## Estado atual (2026-08-04)

- [x] Estrutura de pastas criada (`framework/`, `01-jogo-blackjack/` — antes `01-jogo-puzzle/`, `02-jogo-roguelike/`, `03-jogo-platformer/`, `04-jogo-civilizacao/`, `assets/`, `docs/`).
- [x] Plano de 90 dias e documento de temas escritos.
- [x] **Repositório git próprio e independente** (não faz mais parte do monorepo `projetos_claude`), publicado em https://github.com/GloedenJoao/jogos-2d-pixelart (público), branch `main`.
- [x] **Godot 4.7.1 (Standard) instalado via winget** (`GodotEngine.GodotEngine`). Não está no PATH deste shell — usar o caminho completo do exe (`C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe`) até reabrir o terminal.
- [x] **Projeto Godot em `framework/`** com os 5 sistemas implementados (`addons/framework/`, estruturado como addon Godot): SceneManager, SaveSystem, StateMachine, AudioManager, UITheme. Ver `framework/README.md`. Marco dos dias 1–15 atingido e validado (headless + visual no editor).
- [x] **Projeto 1 virou blackjack (21), não puzzle** — decisão do João em 2026-08-03 (pediu explicitamente pra trocar o tema). `01-jogo-blackjack/` é um projeto Godot jogável: apostar, pedir/parar/dobrar, dealer joga sozinho, blackjack paga 3:2, saldo/estatísticas persistem via SaveSystem, fases da rodada usam o StateMachine do framework. 28/28 testes headless passando (`01-jogo-blackjack/tests/`) e validado visualmente no editor (blackjack natural, hit/stand, dealer estourando/parando, empate). Ver `01-jogo-blackjack/README.md`.
- [x] Assets do Kenney.nl (CC0) baixados em `assets/` (fontes em `ui/kenney-fonts/`, cartas em `sprites/kenney-playing-cards/`, créditos em `assets/CREDITOS.md`) **e já aplicados** no blackjack: `UITheme` usa `Kenney Pixel.ttf`, e as cartas (`01-jogo-blackjack/scenes/main.gd` + `scripts/card.gd`) renderizam sprites reais em vez de desenho por código. Validado visualmente no editor (rodada completa: aposta, hit, dealer estourando, carta virada revelada) e os 28 testes headless continuam passando.
- [x] Polimento visual do blackjack: animação de "distribuir" cartas (escala/fade), aposta representada por pilha de fichas coloridas, mesas com painel/borda, e painel de "Estatísticas" (mãos jogadas/vencidas, melhor saldo) acessível por botão. Validado visualmente. Ver `01-jogo-blackjack/README.md`.
- [x] **Os quatro projetos do plano estão jogáveis e testados** (2026-08-04). Total de 325 asserções headless: framework 16, blackjack 28, roguelike 97, platformer 80, civilização 104. Cada projeto tem `tests/run_tests.gd` (headless) e `tests/visual_capture.gd` (screenshots automáticos em `.visual_capture/`, gitignored).
- [x] **Projeto 2 (roguelike) — completo:** além do marco inicial, ganhou corrida de **5 andares** com dificuldade crescente (mais inimigos e atributos escalados por andar), **variedade real de criaturas** (`scripts/enemy_kinds.gd`: HP/ataque/aggro/ouro próprios, liberadas por profundidade, mais o chefe "Guardião da Caverna" no último andar) e **meta-progressão** (`scripts/meta_progression.gd`: acampamento com Vitalidade/Força/Suprimentos/Sorte, custo crescente, comprados com o ouro acumulado e persistidos no SaveSystem). 97/97 testes.
- [x] **Projeto 3 (`03-jogo-platformer`) — "Andarilho das Eras":** três eras, cada uma com uma mecânica de movimento nova e cumulativa (pulo → pulo duplo → dash), física completa (coyote time, buffer, pulo variável), state machine de animação (Idle/Run/Jump/Fall/Dash), câmera com limites, checkpoints, corações, inimigos de patrulha com pisão e gemas. Fases são mapas ASCII (`scripts/levels.gd`) e o `DemoBot` (tecla `B` no jogo) precisa terminar as três nos testes — é a regressão de level design. Arte: Kenney Pixel Platformer (CC0). 80/80 testes.
- [x] **Projeto 4 (`04-jogo-civilizacao`) — "Eras da Civilização":** o clicker do João como jogo completo — 5 eras via StateMachine (uma `EraState` por era), 15 construções (3 por era) com custo crescente ×1,15 e produção por segundo, virada de era que consome o requisito, progresso offline com teto de 8h e autosave. Toda a matemática fica em `scripts/economy.gd`, sem dependência de cena, por isso dá pra testar tudo headless. Arte: Kenney Tiny Town (CC0) + tileset Tiny Dungeon do Projeto 2 reaproveitado nos ícones primitivos. 104/104 testes.
- [x] **Projeto 4 — polimento visual e de jogabilidade (2026-08-04):** custos/produção da loja coloridos por recurso (verde/laranja/azul, igual ao nome do recurso) pra parar de ler texto corrido; painel de recursos virou uma leitura "de mundo" — pips que enchem em escala log com o estoque mais um nome de nível ("vazio" → "riqueza"), em vez de só o número cru; e compra em lote via seletor ×1/×10/×25/Máx (`Economy.cost_of_n`/`buy_n`/`max_affordable`), pedido do João pra melhorar a jogabilidade do clicker sem inventar sistema novo.
- [x] **Projeto 2 (roguelike) — marco inicial (histórico):** João pediu pra pular a publicação do blackjack no itch.io por ora e seguir direto pro Projeto 2. `02-jogo-roguelike/` é um dungeon crawler top-down grid-based jogável: geração procedural de calabouço (`DungeonGenerator`, salas + corredores em L), combate por bump-attack, IA simples de inimigo (`EnemyAI`: ataca se adjacente, persegue dentro de um raio, senão parado), poções/ouro coletáveis, fases Playing/Victory/GameOver via StateMachine do framework, ouro total e corridas persistem via SaveSystem. Arte: tileset Kenney "Tiny Dungeon" (CC0) reaproveitado como visual de caverna. 39/39 testes headless passando (`02-jogo-roguelike/tests/run_tests.gd`, inclui BFS de conectividade do calabouço) e validado visualmente via `tests/visual_capture.gd` (explorando, combate, vitória, derrota). Ver `02-jogo-roguelike/README.md`.
- [ ] Conta de developer do Google Play já está paga (não é bloqueador).
- [ ] itch.io não requer conta paga nem aprovação — pode publicar quando tiver o primeiro build (blackjack e/ou roguelike).

## O que falta fazer, em ordem

1. **Publicar no itch.io** — é o único item do plano que ninguém tocou, e é o gargalo agora: os quatro jogos estão jogáveis e testados, falta exportar (web/HTML5) e subir. Depende do João criar/usar a conta; o Claude não publica nem cria conta por conta própria.
2. Áudio nos quatro jogos: o `AudioManager` do framework está pronto e sem uso — faltam trilha e efeitos (CC0, mesma linha dos outros assets).
3. Depois de medir tração no itch.io, escolher onde investir conteúdo (mais fases/eras/inimigos) e só então pensar em Google Play.

## Decisões já tomadas (não reabrir sem motivo)

- Engine: Godot (grátis, sem royalties, bom export web/Android, GDScript acessível pra quem já programa).
- Publicação: itch.io primeiro (grátis, pay-what-you-want) → Google Play depois do jogo validado.
- Arte: pixel art gratuita/CC0 (Kenney.nl) nos primeiros projetos, sem orçamento pra contratar artista por enquanto.
- Ordem dos jogos: blackjack → roguelike → platformer → civilização, cada um introduzindo só 1–2 sistemas novos em cima do framework. O Projeto 1 era puzzle no plano original; João pediu blackjack no lugar (ver `docs/temas-e-evolucao.md`).
- Cada projeto Godot é self-contained: o `addons/framework/` e os assets usados são copiados pra dentro dele, sem referência cross-project. Duplicação é intencional (facilita export e abrir um projeto isolado).
- Testes: toda a lógica de jogo fica em classes sem dependência de cena (`Economy`, `MetaProgression`, `LevelData`…), e a cena é testada instanciando `main.tscn` headless. Física de plataforma é testada rodando frames de física de verdade, não simulando à mão.

## Perguntas em aberto pro João decidir depois

- Se vai programar em GDScript ou C# dentro do Godot.
