# Projeto 7 — "Reino em Construção" (nome provisório)

City-builder de sobrevivência e automação inspirado em Timberborn: explorar um mapa físico, extrair recursos finitos, transportar com NPCs carregadores, processar e sustentar população e energia. Combate fica fora do escopo por decisão explícita do João. Design completo em [`docs/plano-projeto7-reino.md`](../docs/plano-projeto7-reino.md), incluindo a quebra em fases.

## Estado atual: Fase 1 — mapa e exploração

Primeira tela jogável de verdade (sem economia/trabalhadores ainda — isso é Fase 2+). O objetivo desta fase era provar que dava pra OLHAR o mapa que as fases seguintes vão construir em cima.

- [`scripts/map_gen.gd`](scripts/map_gen.gd) — gera o mapa: relevo por ruído fractal (`FastNoiseLite`, alimenta o `WaterSim` da Fase 0 sem adaptação nenhuma) e depósitos finitos de madeira/pedra/minério, cada um numa faixa de altura + um segundo ruído independente de "cobertura" (senão floresta nasce sempre na mesma altura, mapa previsível). Limiares calibrados por medição — a primeira versão dava mapas com 90%+ de floresta. `extract()` decrementa e reverte a célula pra grama quando esgota; floresta cortada pela metade se regenera devagar se for deixada em pé, pedra/minério não.
- [`scripts/fog.gd`](scripts/fog.gd) — nevoeiro de guerra com dois estados por célula: `explored` (permanente, memória do terreno) e `visible` (recalculado por fontes de visão, círculo de verdade via distância euclidiana). A separação importa assim que uma fonte de visão se mover — não existe isso ainda na Fase 1 (sem unidades), mas o mecanismo já está testado pra quando existir.
- [`scenes/main.gd`](scenes/main.gd) — a cena: `TileMapLayer` de chão (Kenney Tiny Town) + `TileMapLayer` de depósitos (árvore pra floresta, pedra do Kenney Tiny Dungeon pra afloramento/colina, minério é a mesma pedra com uma variante de tile tingida de laranja), `Camera2D` real com `limit_*` e pan por WASD/setas + zoom por roda do mouse, névoa desenhada por cima num `Node2D._draw()`. Clique no mapa simula um posto de observação (soma uma fonte de visão permanente) — não é mecânica final, é o jeito mais simples de mostrar a névoa recuando de verdade nesta fase sem inventar um sistema que a Fase 2 for jogar fora.
- **Bug real pego pela integração, não por um teste isolado:** o `water_sim.gd` da Fase 0 conservava água em qualquer teste em linha (no máximo 2 vizinhos por célula), mas rodar `WaterSim` sobre um mapa 2D de verdade (células com até 4 vizinhos mais baixos ao mesmo tempo) expôs um cálculo de fluxo que criava água do nada quando uma célula tentava mandar mais do que tinha. Corrigido com um passo de normalização por célula antes de aplicar qualquer fluxo (ver o comentário em `water_sim.gd::_tick`). Isso é a razão de existir `_test_map_height_feeds_water_sim` e `_test_conservation_holds_with_a_peak_surrounded_on_four_sides`.
- [`tests/run_tests.gd`](tests/run_tests.gd) — 96 asserções (Fase 0 + Fase 1): determinismo do mapa, cobertura de cada tipo de depósito numa faixa plausível pra várias sementes, extração/esgotamento/regeneração, segurança fora dos limites, integração com `WaterSim`, névoa revelando em círculo e mantendo memória quando a fonte se move, e testes de cena de verdade (câmera limitada ao mapa, clique revela névoa, segurar tecla move e trava na borda).
- [`tests/visual_capture.gd`](tests/visual_capture.gd) — captura automática de tela (vila inicial, depois de explorar dois pontos distantes, vista afastada) em `.visual_capture/` (gitignored).

## Rodar os testes

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/run_tests.gd
```

(No Windows deste projeto, o caminho completo do executável está registrado no `CLAUDE.md` da raiz do repositório.)

Para medir os tempos de acomodação da água em vez de rodar a suíte:

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/calibrate.gd
```

Para capturar screenshots (precisa de renderização de verdade — sem `--headless`):

```bash
Godot_v4.7.1-stable_win64_console.exe --path . --script tests/visual_capture.gd
```

Pra jogar de verdade: abrir o projeto no editor e rodar a cena principal. WASD/setas movem a câmera, a roda do mouse dá zoom, clique no mapa revela uma área nova.
