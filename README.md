# Jogos 2D Pixel Art — Projeto de evolução incremental

Objetivo: aprender Godot fazendo jogos 2D pixel art cada vez mais complexos, reaproveitando um framework compartilhado, com o fim de publicar no itch.io (e depois Google Play) e gerar renda.

## Estrutura

```
jogos-2d-pixelart/
├── docs/                     Plano, temas e roadmap de evolução
├── framework/                Sistemas reutilizáveis (Godot addon): save/load, state machine, UI, áudio, input
├── 01-jogo-puzzle/           Primeiro jogo — escopo mínimo
├── 02-jogo-roguelike/        Segundo jogo — mais complexo
├── 03-jogo-platformer/       Terceiro jogo — física e animação
├── 04-jogo-civilizacao/      Evolução do clicker de civilização em pixel art completo
└── assets/                   Assets compartilhados (pixel art gratuito, licenças)
```

Cada projeto é um projeto Godot independente, mas importa o `framework/` como addon — assim cada jogo novo começa com save system, UI, gerenciador de áudio e state machine já prontos, e você só programa o que é novo daquele jogo.

## Por onde começar

Leia `docs/plano-90-dias.md` pra cronograma e `docs/temas-e-evolucao.md` pra ideias de tema e o motivo de cada projeto vir na ordem que vem.
