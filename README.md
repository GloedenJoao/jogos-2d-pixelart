# Jogos 2D Pixel Art — Projeto de evolução incremental

Objetivo: aprender Godot fazendo jogos 2D pixel art cada vez mais complexos, reaproveitando um framework compartilhado, com o fim de publicar no itch.io (e depois Google Play) e gerar renda.

## Estrutura

```
jogos-2d-pixelart/
├── docs/                     Plano, temas e roadmap de evolução
├── framework/                Sistemas reutilizáveis (Godot addon): save/load, state machine, UI, áudio, cenas
├── 01-jogo-blackjack/        Projeto 1 — blackjack (21) contra o dealer
├── 02-jogo-roguelike/        Projeto 2 — roguelike de caverna, 5 andares e meta-progressão
├── 03-jogo-platformer/       Projeto 3 — "Andarilho das Eras", física e animação
├── 04-jogo-civilizacao/      Projeto 4 — "Eras da Civilização", idle/clicker completo
└── assets/                   Assets compartilhados (pixel art CC0, licenças e créditos)
```

Cada projeto é um projeto Godot independente que carrega o `framework/` como addon — assim cada jogo novo começa com save system, UI, gerenciador de áudio e state machine prontos, e só se programa o que é novo daquele jogo.

## Estado dos projetos

| Projeto | Jogo | O que introduziu | Testes headless |
|---|---|---|---|
| — | `framework/` | SceneManager, SaveSystem, StateMachine, AudioManager, UITheme | 16 |
| 1 | Blackjack | Fases de rodada com state machine, HUD, save de saldo | 28 |
| 2 | Roguelike de caverna | Geração procedural, IA de inimigo, meta-progressão entre corridas | 97 |
| 3 | Andarilho das Eras | Física de plataforma, state machine de animação, câmera, checkpoints | 80 |
| 4 | Eras da Civilização | Economia idle, produção automática, eras, progresso offline | 93 |

Todos rodam headless com o mesmo comando (trocando a pasta):

```bash
godot --headless --path 02-jogo-roguelike --script res://tests/run_tests.gd
```

Cada projeto também tem `tests/visual_capture.gd`, que gera screenshots dos cenários-chave em `.visual_capture/` sem precisar clicar em nada.

## Por onde começar

Leia `docs/plano-90-dias.md` pra cronograma e `docs/temas-e-evolucao.md` pra ideias de tema e o motivo de cada projeto vir na ordem que vem. O próximo passo do plano é publicar os builds no itch.io.
