# Projeto 2 — Mini Roguelike (Caverna)

Ver `docs/temas-e-evolucao.md` na raiz pra ideias de tema e `docs/plano-90-dias.md` pro cronograma (dias 41–65).

Status: jogável e completo pro escopo do plano — dungeon crawler top-down, grid-based, contra criaturas da caverna, com corrida de vários andares e meta-progressão entre corridas.

## O que tem

- **Corrida de 5 andares** (`FLOORS_PER_RUN`): cada saída leva ao andar seguinte (novo calabouço procedural, +3 HP de brinde), e só a saída do 5º andar encerra a corrida em vitória. HUD mostra `Andar: n/5`.
- **Dificuldade crescente por andar**: mais inimigos por andar (`DungeonGenerator.ENEMIES_PER_FLOOR`) e atributos escalados (`EnemyKinds.scaled` — +2 HP por andar, +1 de ataque a cada 3 andares).
- **Variedade real de inimigos** (`scripts/enemy_kinds.gd`): Limo, Caranguejo, Morcego, Fungo Rastejante e Golem de Pedra, cada um com HP, ataque, raio de agressividade e ouro próprios, liberados conforme a profundidade (`min_floor`). O morcego enxerga longe (aggro 9), o fungo quase não sai do lugar (aggro 2). No último andar aparece o **Guardião da Caverna** (chefe: maior, avermelhado, 34 HP, 7 de ataque), posicionado no spawn mais perto da saída.
- **Meta-progressão / acampamento** (`scripts/meta_progression.gd`): o ouro da corrida vai pro acampamento e compra upgrades permanentes — Vitalidade (+4 HP máx, até Nv5), Força (+1 ataque, até Nv4), Suprimentos (+1 poção inicial, até Nv3) e Sorte (+15% de ouro, até Nv3). O custo sobe a cada nível; tudo persiste via `SaveSystem` (`roguelike_upgrades`, `roguelike_total_gold`, `roguelike_deepest_floor`). Painel acessível pelos botões "Acampamento" nas telas de vitória e derrota.
- Geração procedural de calabouço (salas retangulares + corredores em L) via `DungeonGenerator`, com entrada e saída (a sala mais distante da entrada).
- Movimento em grid (WASD/setas), combate por "bump attack" (andar na direção de um inimigo ataca em vez de mover). Matar inimigo dá ouro na hora.
- Itens espalhados pelo chão: poções (curam HP, usar com `U`) e ouro (afetado pelo upgrade Sorte).
- Fases da corrida (Playing → Victory/GameOver) usam o `StateMachine` do framework.
- Arte: tileset Kenney "Tiny Dungeon" (CC0) reaproveitado como visual de caverna, fonte Kenney Pixel (mesma do blackjack).

## Testes

Headless: `tests/run_tests.gd` (97 asserções — geração de calabouço com conectividade via BFS e densidade por andar, combate, inventário, IA com aggro por tipo, catálogo de inimigos, matemática da meta-progressão, e o fluxo pela `main.tscn`: estado inicial, bump attack, coleta de itens, descida entre andares, vitória só no último andar, derrota, upgrades valendo na corrida seguinte, compra no acampamento e uma corrida completa pelos 5 andares procedurais).

```powershell
& "C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
```

Validação visual: `tests/visual_capture.gd` captura 6 cenários — explorando, combate, andar do chefe, vitória, acampamento e derrota — em `.visual_capture/*.png` (gitignored).

## O que falta

- Publicar early build no itch.io (depende de conta/upload do João).
- Mais tipos de item (equipamentos, armadilhas) e salas especiais, se quiser aprofundar depois da publicação.
