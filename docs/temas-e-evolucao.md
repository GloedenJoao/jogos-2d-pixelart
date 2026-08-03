# Temas de jogos e evolução de complexidade

A ideia é cada jogo novo introduzir 1–2 sistemas novos, sempre em cima do `framework/` compartilhado, pra você ir empilhando capacidade sem reescrever o que já funciona.

## Projeto 1 — Puzzle (mais simples)

**Tema sugerido:** um "restaurador de artefatos" — cada fase é um puzzle de encaixar peças/cores/símbolos pra reconstruir um item antigo (vaso, mosaico, pergaminho). Combina bem com pixel art e é fácil de gerar dezenas de fases só variando o layout.

Alternativas de tema: puzzle de jardim (arrumar plantas por cor/tipo), puzzle de constelações (conectar estrelas em ordem).

**Sistemas novos:** grid lógico, detecção de vitória por padrão, HUD de progresso, save de recorde/fases completadas.

## Projeto 2 — Mini roguelike

**Tema sugerido:** conecta com o que você já gosta — um roguelike de "sobrevivente pré-histórico": desce numa caverna, cada run gera salas com recursos, perigos e pequenos combates, upgrades permanentes entre runs (linkando com a ideia de progressão de civilização que você já tinha).

Alternativas: roguelike de explorador de ruínas, roguelike de alquimista coletando ingredientes.

**Sistemas novos:** geração procedural de mapas, combate simples, inventário, progressão entre runs (meta-progressão), IA básica de inimigo.

## Projeto 3 — Platformer/metroidvania leve

**Tema sugerido:** um "andarilho das eras" — atravessa cenários que representam diferentes períodos históricos (caverna → vila antiga → cidade industrial), cada era com mecânica de movimento nova (pulo duplo, dash, etc.) — ótimo gancho temático com seu clicker de civilização.

**Sistemas novos:** física de plataforma, máquina de estados de animação (idle/correr/pular/atacar), câmera que segue o player, transição de cenas/checkpoints.

## Projeto 4 — Civilização (o grande projeto)

Aqui o clicker de civilização vira um jogo pixel art completo: personagens por era (como você já vinha planejando), produção automática temática por era (mineração, agricultura, fábricas), e agora com tudo isso rodando em cima de um framework já testado em 3 jogos anteriores — save system robusto, UI polida, state machine madura pra transições de era.

**Sistemas que reaproveita de tudo antes:** save/load, state machine, UI, e potencialmente elementos visuais dos projetos anteriores (sprites, efeitos).

## Por que essa ordem

Cada projeto é propositalmente mais complexo que o anterior, mas nunca pula um degrau: puzzle não tem física nem IA, então é o warm-up mais seguro. Roguelike introduz geração procedural e combate, mas ainda em grid/top-down simples. Platformer introduz física real, que é mais imprevisível e trabalhosa. O projeto de civilização é o mais ambicioso porque puxa sistemas de economia, múltiplas eras e produção automática — só vale tentar depois que os fundamentos (save, state machine, UI) já foram validados em jogos menores e reais, publicados e testados por outras pessoas.
