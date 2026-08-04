# Projeto 2 — Mini Roguelike (Caverna)

Ver `docs/temas-e-evolucao.md` na raiz pra ideias de tema e `docs/plano-90-dias.md` pro cronograma (dias 41–65).

Status: jogável. Marco inicial (1 andar completo) atingido — dungeon crawler top-down, grid-based, contra criaturas da caverna:

- Geração procedural de calabouço (salas retangulares + corredores em L conectando-as) via `DungeonGenerator`, com entrada e saída (a sala mais distante da entrada).
- Movimento em grid (WASD/setas), combate por "bump attack" (andar na direção de um inimigo ataca em vez de mover).
- Inimigos com IA simples (`EnemyAI`): atacam se adjacentes, perseguem o jogador dentro de um raio de agressividade, ficam parados fora dele.
- Itens espalhados pelo chão: poções (curam HP, usar com `U`) e ouro (moeda meta, banda entre corridas).
- Fases da corrida (Playing → Victory/GameOver) usam o `StateMachine` do framework; saldo de ouro total e estatísticas de corridas persistem via `SaveSystem`.
- Arte: tileset Kenney "Tiny Dungeon" (CC0) reaproveitado como visual de caverna (piso de terra/pedra, paredes de rocha, criaturas — limo, morcego, caranguejo, golem, fungo), fonte Kenney Pixel (mesma do blackjack).

Testes headless: `tests/run_tests.gd` (39 asserções — geração de calabouço incluindo conectividade via BFS, combate, inventário, IA de inimigo, e o fluxo completo via `main.tscn`: estado inicial, bump attack, coleta de itens, vitória ao alcançar a saída, derrota ao HP zerar).

Validação visual: `tests/visual_capture.gd` (mesmo padrão do blackjack) captura 4 cenários — explorando, combate, vitória, derrota — em `.visual_capture/*.png` (gitignored).

```powershell
& "C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
```

## O que falta pra ir além do marco inicial

- Mais de 1 andar por corrida (progressão de dificuldade dentro da mesma run).
- Upgrades permanentes comprados com o ouro acumulado entre corridas (meta-progressão de verdade — hoje o ouro só é somado e exibido).
- Variedade de inimigos com atributos diferentes (hoje todos usam os mesmos HP/attack, só o sprite muda).
- Publicar early build no itch.io.
