# Projeto 7 — "Reino em Construção" (nome provisório)

City-builder de sobrevivência e automação inspirado em Timberborn: explorar um mapa físico, extrair recursos finitos, transportar com NPCs carregadores, processar e sustentar população e energia. Combate fica fora do escopo por decisão explícita do João. Design completo em [`docs/plano-projeto7-reino.md`](../docs/plano-projeto7-reino.md), incluindo a quebra em fases.

## Estado atual: Fase 4 — processamento

A cadeia agora vai até o fim: extrair → transportar → processar. Serraria e Oficina de Pedra transformam o bruto que já chegou no Armazém (madeira/pedra) em processado (tábua/bloco), 1:1, throttladas pelo estoque de insumo disponível — sem madeira, a Serraria fica com trabalhador `WORKING` mas não produz nada, mesma lógica de "só rende o que existe" do extrator, só que o limite agora é estoque em vez de depósito ou pátio.

- [`scripts/buildings.gd`](scripts/buildings.gd) ganhou `Kind.SAWMILL`/`Kind.STONE_WORKSHOP` e `PROCESS_RECIPES`. Diferença deliberada de arquitetura em relação ao extrator: processamento lê e escreve DIRETO em `stock`, sem pátio próprio nem depender do `Carrier` — o insumo já passou pelo carregador pra virar estoque jogável, e reexigir uma segunda perna de transporte só pra levar o resultado de volta pro mesmo Armazém não ensinaria nada de novo sobre logística. Fica registrado como simplificação consciente no código, não descuido.
- `scenes/main.gd` coloca Serraria e Oficina de Pedra perto da vila (não dependem de depósito, só de uma célula livre) e ganham trabalhador pelo mesmo loop genérico que já staffava os extratores (agora só pula o Armazém). Cores distintas: dourado pra Serraria, cinza-ardósia pra Oficina de Pedra (nem a cor da Pedreira — terracota — nem a do depósito de pedra — azul-acinzentado — pra não repetir a confusão de camuflagem da Fase 2).
- [`tests/run_tests.gd`](tests/run_tests.gd) — 192 asserções (Fase 0 + 1 + 2 + 3 + 4): as anteriores, mais processamento só com trabalhador `WORKING`, conversão 1:1 verificada, produção throttlada pelo insumo disponível (não pela taxa da receita), e a cadeia inteira (extrair → transportar → processar) rendendo tábua e bloco de verdade numa cena real.

## Fases anteriores

**Fase 3 — transporte.** A produção deixou de virar estoque jogável na hora: cada extrator produz pro próprio PÁTIO (`Building.buffer`, com teto — `EXTRACTOR_BUFFER_CAP`), e um NPC carregador (`carrier.gd`/`carriers.gd`) precisa fisicamente levar aquilo até o Armazém (`Kind.WAREHOUSE`, nasce na própria vila) pra virar recurso de verdade. O carregador escolhe sempre o pátio **mais cheio**, não o mais próximo — com um só servindo dois extratores, quem está prestes a travar é atendido primeiro. Um quadradinho da cor do recurso aparece acima do carregador só enquanto ele carrega algo.

**Fase 2 — extração básica + um trabalhador por prédio.** Um Posto de Lenhador e uma Pedreira nascem na célula de depósito mais próxima da vila; um trabalhador por prédio anda até lá pelo Pathfinder e só produz quando chega e fica `WORKING` de verdade — "alocado" não é "produzindo". A primeira versão desta fase nascia com um único trabalhador no total (o suficiente pra provar o sistema, mas deixava a Pedreira sempre parada — João achou que ela nem existia, e um extrator parado é indistinguível de um extrator inexistente pra quem só está jogando). Trabalhador é um sprite do pack Kenney "Roguelike Characters" — um rosto por trabalhador, não clone — com uma bolinha de estado colorida acima da cabeça; prédio é um retângulo com "telhado" e borda escura gerados por código (a borda existe porque a primeira versão da Pedreira usava cinza, quase a mesma cor do depósito de pedra por baixo dela, virando camuflagem).

**Fase 1 — mapa e exploração.** O objetivo era provar que dava pra OLHAR o mapa que as fases seguintes construiriam em cima.

- [`scripts/map_gen.gd`](scripts/map_gen.gd) — gera o mapa: relevo por ruído fractal (`FastNoiseLite`, alimenta o `WaterSim` da Fase 0 sem adaptação nenhuma) e depósitos finitos de madeira/pedra/minério, cada um numa faixa de altura + um segundo ruído independente de "cobertura" (senão floresta nasce sempre na mesma altura, mapa previsível). Limiares calibrados por medição — a primeira versão dava mapas com 90%+ de floresta. `extract()` decrementa e reverte a célula pra grama quando esgota; floresta cortada pela metade se regenera devagar se for deixada em pé, pedra/minério não.
- [`scripts/fog.gd`](scripts/fog.gd) — nevoeiro de guerra com dois estados por célula: `explored` (permanente, memória do terreno) e `visible` (recalculado por fontes de visão, círculo de verdade via distância euclidiana). A separação importa assim que uma fonte de visão se mover — não existe isso ainda na Fase 1 (sem unidades), mas o mecanismo já está testado pra quando existir.
- [`scenes/main.gd`](scenes/main.gd) — a cena: `TileMapLayer` de chão (Kenney Tiny Town) + `TileMapLayer` de depósitos (árvore pra floresta, pedra do Kenney Tiny Dungeon pra afloramento/colina, minério é a mesma pedra com uma variante de tile tingida de laranja), `Camera2D` real com `limit_*` e pan por WASD/setas + zoom por roda do mouse, névoa desenhada por cima num `Node2D._draw()`. Clique no mapa simula um posto de observação (soma uma fonte de visão permanente) — não é mecânica final, é o jeito mais simples de mostrar a névoa recuando de verdade nesta fase sem inventar um sistema que a Fase 2 for jogar fora.
- **Lagos de verdade, não pintados**: `_seed_lakes()` semeia água nas células mais baixas do relevo (limiar e volume calibrados rodando o autômato de verdade, não chutados — a primeira tentativa inundava 29% do mapa) e deixa o `WaterSim` da Fase 0 acomodar antes do primeiro desenho. O que aparece na tela é `water_sim.water_at()` de verdade, não uma cor decorativa — cavar canal/represar (Fase 2+) vai mexer nesse mesmo estado.
- **Bug real pego pela integração, não por um teste isolado:** o `water_sim.gd` da Fase 0 conservava água em qualquer teste em linha (no máximo 2 vizinhos por célula), mas rodar `WaterSim` sobre um mapa 2D de verdade (células com até 4 vizinhos mais baixos ao mesmo tempo) expôs um cálculo de fluxo que criava água do nada quando uma célula tentava mandar mais do que tinha. Corrigido com um passo de normalização por célula antes de aplicar qualquer fluxo (ver o comentário em `water_sim.gd::_tick`). Isso é a razão de existir `_test_map_height_feeds_water_sim` e `_test_conservation_holds_with_a_peak_surrounded_on_four_sides`.

[`tests/visual_capture.gd`](tests/visual_capture.gd) captura vila inicial, os trabalhadores nos postos, o carregador entregando no Armazém, a cadeia de processamento rendendo tábua/bloco, mapa depois de explorar e vista afastada, em `.visual_capture/` (gitignored).

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
