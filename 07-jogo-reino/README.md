# Projeto 7 — "Reino em Construção" (nome provisório)

City-builder de sobrevivência e automação inspirado em Timberborn: explorar um mapa físico, extrair recursos finitos, transportar com NPCs carregadores, processar e sustentar população e energia. Combate fica fora do escopo por decisão explícita do João. Design completo em [`docs/plano-projeto7-reino.md`](../docs/plano-projeto7-reino.md), incluindo a quebra em fases.

## Estado atual: Fase 2 — extração básica + trabalhador

Primeiro ciclo econômico de verdade: um prédio produz, um trabalhador precisa estar lá pra isso acontecer, e o depósito que ele explora é o mesmo da Fase 1 — sem contabilidade duplicada.

- [`scripts/pathfinder.gd`](scripts/pathfinder.gd) — A* (`AStarGrid2D`) com corte de esquina e trilha de pisoteio, portado de `05_V2-jogo-colonia/scripts/pathfinder.gd` e generalizado (`setup(cols, rows, cell_size)` + `rebuild(solid_cells)` em vez de depender de uma classe `Valley` fixa — o Reino não tem lote 2×2 por construção, cada prédio ocupa a própria célula).
- [`scripts/worker.gd`](scripts/worker.gd) + [`scripts/workers.gd`](scripts/workers.gd) — dado do trabalhador (posição, caminho, estado `IDLE/WALKING/WORKING`) separado de quem move (mesma separação `Villager`/`Population` da Colônia V2). Avanço por posição contínua ao longo da polilinha do caminho, não célula a célula.
- [`scripts/buildings.gd`](scripts/buildings.gd) — prédio extrator senta EM CIMA de uma célula de depósito do `MapGen` e puxa direto dali (`map.extract()`) — sem estoque próprio de matéria-prima duplicado. Só produz com o trabalhador de fato `WORKING` (chegou e está lá), não só "alocado": o trajeto até o posto custa tempo de produção de propósito, é o que o plano do projeto pede ("prédio longe do núcleo populacional custa tempo de trajeto"). Com um trabalhador só, staffing é ligado/desligado — o mecanismo de fração de vaga ocupada da Colônia V2 (`staffing_ratios()`) só vale a pena quando houver múltiplas vagas por prédio.
- `scenes/main.gd` agora coloca um Posto de Lenhador e uma Pedreira na célula de depósito mais próxima da vila (busca em anéis crescentes — mapa sem aquele recurso por perto simplesmente não ganha aquele prédio agora, não é erro), spawna um trabalhador que anda até o primeiro prédio e começa a produzir ao chegar. Trabalhador é um sprite único do pack Kenney "Roguelike Characters" (mesma técnica simples do `05-jogo-colonia`, não o paper doll modular da V2) com uma bolinha de estado colorida acima da cabeça; prédio é um retângulo com "telhado" gerado por código (sem sprite de construção isolada nos acervos disponíveis — melhor um placeholder legível do que adivinhar coordenada de tileset errada de novo).
- [`tests/run_tests.gd`](tests/run_tests.gd) — 142 asserções (Fase 0 + 1 + 2): as anteriores, mais pathfinder (rota em grade aberta, desvio de sólido, trilha se formando e decaindo), trabalhadores (chegada exata no alvo, trabalhadores independentes) e prédios (só produz com trabalhador `WORKING`, produção para sozinha quando o depósito esgota, busca do depósito mais próximo).

## Fases anteriores

**Fase 1 — mapa e exploração.** O objetivo era provar que dava pra OLHAR o mapa que as fases seguintes construiriam em cima.

- [`scripts/map_gen.gd`](scripts/map_gen.gd) — gera o mapa: relevo por ruído fractal (`FastNoiseLite`, alimenta o `WaterSim` da Fase 0 sem adaptação nenhuma) e depósitos finitos de madeira/pedra/minério, cada um numa faixa de altura + um segundo ruído independente de "cobertura" (senão floresta nasce sempre na mesma altura, mapa previsível). Limiares calibrados por medição — a primeira versão dava mapas com 90%+ de floresta. `extract()` decrementa e reverte a célula pra grama quando esgota; floresta cortada pela metade se regenera devagar se for deixada em pé, pedra/minério não.
- [`scripts/fog.gd`](scripts/fog.gd) — nevoeiro de guerra com dois estados por célula: `explored` (permanente, memória do terreno) e `visible` (recalculado por fontes de visão, círculo de verdade via distância euclidiana). A separação importa assim que uma fonte de visão se mover — não existe isso ainda na Fase 1 (sem unidades), mas o mecanismo já está testado pra quando existir.
- [`scenes/main.gd`](scenes/main.gd) — a cena: `TileMapLayer` de chão (Kenney Tiny Town) + `TileMapLayer` de depósitos (árvore pra floresta, pedra do Kenney Tiny Dungeon pra afloramento/colina, minério é a mesma pedra com uma variante de tile tingida de laranja), `Camera2D` real com `limit_*` e pan por WASD/setas + zoom por roda do mouse, névoa desenhada por cima num `Node2D._draw()`. Clique no mapa simula um posto de observação (soma uma fonte de visão permanente) — não é mecânica final, é o jeito mais simples de mostrar a névoa recuando de verdade nesta fase sem inventar um sistema que a Fase 2 for jogar fora.
- **Lagos de verdade, não pintados**: `_seed_lakes()` semeia água nas células mais baixas do relevo (limiar e volume calibrados rodando o autômato de verdade, não chutados — a primeira tentativa inundava 29% do mapa) e deixa o `WaterSim` da Fase 0 acomodar antes do primeiro desenho. O que aparece na tela é `water_sim.water_at()` de verdade, não uma cor decorativa — cavar canal/represar (Fase 2+) vai mexer nesse mesmo estado.
- **Bug real pego pela integração, não por um teste isolado:** o `water_sim.gd` da Fase 0 conservava água em qualquer teste em linha (no máximo 2 vizinhos por célula), mas rodar `WaterSim` sobre um mapa 2D de verdade (células com até 4 vizinhos mais baixos ao mesmo tempo) expôs um cálculo de fluxo que criava água do nada quando uma célula tentava mandar mais do que tinha. Corrigido com um passo de normalização por célula antes de aplicar qualquer fluxo (ver o comentário em `water_sim.gd::_tick`). Isso é a razão de existir `_test_map_height_feeds_water_sim` e `_test_conservation_holds_with_a_peak_surrounded_on_four_sides`.

[`tests/visual_capture.gd`](tests/visual_capture.gd) captura vila inicial, trabalhador no posto, mapa depois de explorar e vista afastada, em `.visual_capture/` (gitignored).

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
