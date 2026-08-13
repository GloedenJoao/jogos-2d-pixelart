# Projeto 7 — "Reino em Construção" (nome provisório)

City-builder de sobrevivência e automação inspirado em Timberborn: explorar um mapa físico, extrair recursos finitos, transportar com NPCs carregadores, processar e sustentar população e energia. Combate fica fora do escopo por decisão explícita do João. Design completo em [`docs/plano-projeto7-reino.md`](../docs/plano-projeto7-reino.md), incluindo a quebra em fases.

## Estado atual: desbloqueio de prédios por nível

Até aqui todo prédio nascia de uma vez no frame 1 — corte deliberado registrado desde a Fase 7 ("gatear isso por nível pediria reescrever a colocação de prédios pra ser progressiva, mudança de arquitetura maior que o resto desta fase"). Agora `Progression.level` (progression.gd) controla o quê existe: a vila nasce **pequena** (só Armazém + Fazenda + uma Casa) e ganha prédios novos a cada nível, até um teto de 4 tiers.

- [`scenes/main.gd`](scenes/main.gd) — `_unlock_building_tier(level)` planta só os prédios daquele nível (`_place_tier1_buildings` … `_place_tier4_buildings`); `_maybe_unlock_next_tier()`, chamado todo `_process()`, dispara o próximo tier assim que `progression.level` ultrapassa `_unlocked_level`. Nível 1: Armazém, Fazenda, uma Casa (só sobrevivência). Nível 2: Posto de Lenhador, Pedreira, segunda Casa. Nível 3: Mina, Serraria, terceira Casa. Nível 4: Oficina de Pedra, Gerador, Forja — fecha o catálogo. `MAX_BUILDING_TIER = 4`: nível 5 (o teto de `Progression.REVEAL_RADIUS_BY_LEVEL`) só amplia o alcance de exploração, não planta prédio novo.
- **`pathfinder.rebuild()` e os nós da cena (`_sync_new_building_nodes()`) agora rodam a cada desbloqueio, não só no frame 1** — os dois usavam um loop único sobre `buildings.list` assumindo que a lista inteira já existia; viraram versões incrementais (`_jobs_registered_up_to`/`_nodes_built_up_to` marcam até onde cada um já processou) pra não recriar nó nem reenfileirar vaga de prédio que já tinha.
- **A fila de contratação continua priorizando Fazenda + carregador** (ver a nota da Fazenda abaixo) — como agora só a Fazenda existe no nível 1, isso sai de graça: `_register_pending_jobs()` só acha a Fazenda pra enfileirar, e o carregador entra logo atrás.
- [`tests/run_tests.gd`](tests/run_tests.gd) — 272 asserções: as anteriores adaptadas pra esperar o tier certo antes de procurar um prédio por Kind (`_advance_to_tier`, novo helper de teste), mais um teste dedicado ao mecanismo em si (`_test_scene_buildings_unlock_progressively`) confirmando os prédios certos aparecem no nível certo e nenhum prédio novo nasce depois do tier 4.

**Fazenda — necessidade de comida.** Primeira necessidade de população de verdade: cada habitante consome comida por segundo, e a Fazenda é a primeira fonte de produção SEM depósito finito — não existe tile de "terra fértil" no mapa, ela representa lavoura ao redor da vila.

- [`scripts/buildings.gd`](scripts/buildings.gd) — `Kind.FARM` tem entrada em `RESOURCE_OF` ("comida") mas de propósito NÃO tem entrada em `DEPOSIT_KIND_OF`; `_advance_extractor()` usa essa ausência como sinal pra produzir direto pro pátio (fonte renovável, só limitada pelo teto do pátio) em vez de chamar `map.extract()`. Ainda precisa de `Carrier` pra virar estoque jogável — não é atalho.
- [`scripts/population.gd`](scripts/population.gd) — `Population.advance()` agora recebe quanto de comida está disponível e devolve quanto foi consumido; crescimento continua incondicional até `BOOTSTRAP_POPULATION` (2, gente o bastante pra staffar a própria Fazenda + o carregador), mas acima disso só cresce se a comida cobrir o consumo do tick. Faltando comida, a população encolhe na proporção do déficit até (no mínimo) o próprio piso — nunca some de vez, mas recua de verdade enquanto durar a fome.
- **A fila de contratação (`_pending_jobs` em `main.gd`) põe Fazenda e carregador PRIMEIRO**, à frente de Posto de Lenhador/Pedreira/Mina/Serraria/Forja — achado rodando a suíte de testes: com a ordem antiga (extratores primeiro), os dois trabalhadores do piso de arranque iam pra lá, a Fazenda nunca ganhava gente, e a vila travava em população 2 pra sempre. Constantes calibradas por medição (`tests/calibrate_farm.gd`, removido depois de usado): sem Fazenda nenhuma, população trava exatamente no piso; com Fazenda staffada, sustenta a capacidade cheia com folga.
- **Terceira Casa** — a Fazenda é o sexto prédio staffável; junto com o carregador são 7 vagas, e duas Casas (capacidade 6) já não cobririam nem as vagas.

## Fases anteriores

**Mina + Forja — terceira cadeia de recurso.** Minério vira lingote, fechando a lacuna que a Fase 4 deixou explicitamente em aberto (não existia extrator de minério ainda). A Mina senta sobre o depósito de colina (`MapGen.Kind.HILLS`) que o mapa gera desde a Fase 1 sem nenhum prédio explorando ele, e a Forja processa minério em lingote — mesma arquitetura de sempre, sem sistema novo. Cor do marcador da Mina escolhida fria de propósito (slate azul-arroxeado, `4a4a5c`) — o chão de colina onde ela nasce já é tingido de laranja pelo próprio depósito de minério (mesma paleta quente da Pedreira que causou a camuflagem da Fase 2).

**Fase 7 — progressão.** A vila sobe de nível conforme acumula recurso entregue no Armazém, e cada nível aumenta o **alcance de exploração** — o raio que a névoa revela ao redor da vila cresce de verdade, não é só um número guardado.

- [`scripts/progression.gd`](scripts/progression.gd) — `Progression.xp` cresce com todo recurso entregue (qualquer tipo — madeira, pedra, tábua, bloco — é XP puro por volume); ao cruzar `XP_PER_LEVEL`, sobe de nível e carrega o excedente pro próximo. `reveal_radius()` cresce por nível até um teto definido (`REVEAL_RADIUS_BY_LEVEL`).
- **XP não é reconstruível a partir da soma do estoque** — achado depurando esta fase, registrado em `main.gd _advance_progression()`: o Gerador (Fase 5) baixa a soma do estoque de verdade ao queimar madeira como combustível, mas XP só soma ganhos, nunca desconta consumo. Progresso é permanente de propósito — não faria sentido perder nível porque o Gerador gastou madeira depois.
- **"Desbloqueio de prédios" por nível, que o plano do projeto também pede pra esta fase, ficou de fora de propósito na época** — todo prédio nascia de uma vez em `_place_starting_buildings`; a mudança de arquitetura pra colocação progressiva veio depois (ver "Estado atual" acima).

**Fase 6 — população.** Mão de obra deixa de ser infinita e instantânea: até a Fase 5, todo trabalhador e o carregador nasciam prontos no primeiro frame. Agora existe uma população (`population.gd`) que cresce devagar até a capacidade habitacional (soma das Casas construídas — `Kind.HOUSE`), e prédios que precisam de trabalhador entram numa fila preenchida conforme `population.available()` permite — a vila nasce **vazia** e se povoa aos poucos. Necessidade de comida entrou depois (ver "Estado atual" acima); água potável e descanso continuam de fora — cada uma pediria sua própria fonte (poço ligado ao `WaterSim`, um lugar de descanso) que nenhuma fase construiu ainda.

**Fase 5 — energia.** Todo prédio de produção pode funcionar de duas formas: energia OU trabalhador. O Gerador a Lenha (`Kind.GENERATOR`) queima madeira do Armazém e cobre um raio em células (`GENERATOR_RADIUS`) — qualquer extrator/processador dentro do raio produz mesmo sem trabalhador, contanto que haja combustível; o gerador só acende quando alguém no raio de fato precisa dele. A Oficina de Pedra nasce de propósito sem trabalhador nesta fase — prova direta da regra "OU". Uma bolinha amarela acima do prédio marca o frame em que `Building.powered` é verdadeiro.

**Fase 4 — processamento.** Serraria e Oficina de Pedra transformam o bruto que já chegou no Armazém (madeira/pedra) em processado (tábua/bloco), 1:1, throttladas pelo estoque de insumo disponível. Diferença deliberada de arquitetura em relação ao extrator: processamento lê e escreve DIRETO em `stock`, sem pátio próprio nem depender do `Carrier` — o insumo já passou pelo carregador pra virar estoque jogável, e reexigir uma segunda perna de transporte só pra levar o resultado de volta pro mesmo Armazém não ensinaria nada de novo sobre logística.

**Fase 3 — transporte.** A produção deixou de virar estoque jogável na hora: cada extrator produz pro próprio PÁTIO (`Building.buffer`, com teto — `EXTRACTOR_BUFFER_CAP`), e um NPC carregador (`carrier.gd`/`carriers.gd`) precisa fisicamente levar aquilo até o Armazém (`Kind.WAREHOUSE`, nasce na própria vila) pra virar recurso de verdade. O carregador escolhe sempre o pátio **mais cheio**, não o mais próximo — com um só servindo dois extratores, quem está prestes a travar é atendido primeiro. Um quadradinho da cor do recurso aparece acima do carregador só enquanto ele carrega algo.

**Fase 2 — extração básica + um trabalhador por prédio.** Um Posto de Lenhador e uma Pedreira nascem na célula de depósito mais próxima da vila; um trabalhador por prédio anda até lá pelo Pathfinder e só produz quando chega e fica `WORKING` de verdade — "alocado" não é "produzindo". A primeira versão desta fase nascia com um único trabalhador no total (o suficiente pra provar o sistema, mas deixava a Pedreira sempre parada — João achou que ela nem existia, e um extrator parado é indistinguível de um extrator inexistente pra quem só está jogando). Trabalhador é um sprite do pack Kenney "Roguelike Characters" — um rosto por trabalhador, não clone — com uma bolinha de estado colorida acima da cabeça; prédio é um retângulo com "telhado" e borda escura gerados por código (a borda existe porque a primeira versão da Pedreira usava cinza, quase a mesma cor do depósito de pedra por baixo dela, virando camuflagem).

**Fase 1 — mapa e exploração.** O objetivo era provar que dava pra OLHAR o mapa que as fases seguintes construiriam em cima.

- [`scripts/map_gen.gd`](scripts/map_gen.gd) — gera o mapa: relevo por ruído fractal (`FastNoiseLite`, alimenta o `WaterSim` da Fase 0 sem adaptação nenhuma) e depósitos finitos de madeira/pedra/minério, cada um numa faixa de altura + um segundo ruído independente de "cobertura" (senão floresta nasce sempre na mesma altura, mapa previsível). Limiares calibrados por medição — a primeira versão dava mapas com 90%+ de floresta. `extract()` decrementa e reverte a célula pra grama quando esgota; floresta cortada pela metade se regenera devagar se for deixada em pé, pedra/minério não.
- [`scripts/fog.gd`](scripts/fog.gd) — nevoeiro de guerra com dois estados por célula: `explored` (permanente, memória do terreno) e `visible` (recalculado por fontes de visão, círculo de verdade via distância euclidiana). A separação importa assim que uma fonte de visão se mover — não existe isso ainda na Fase 1 (sem unidades), mas o mecanismo já está testado pra quando existir.
- [`scenes/main.gd`](scenes/main.gd) — a cena: `TileMapLayer` de chão (Kenney Tiny Town) + `TileMapLayer` de depósitos (árvore pra floresta, pedra do Kenney Tiny Dungeon pra afloramento/colina, minério é a mesma pedra com uma variante de tile tingida de laranja), `Camera2D` real com `limit_*` e pan por WASD/setas + zoom por roda do mouse, névoa desenhada por cima num `Node2D._draw()`. Clique no mapa simula um posto de observação (soma uma fonte de visão permanente) — não é mecânica final, é o jeito mais simples de mostrar a névoa recuando de verdade nesta fase sem inventar um sistema que a Fase 2 for jogar fora.
- **Lagos de verdade, não pintados**: `_seed_lakes()` semeia água nas células mais baixas do relevo (limiar e volume calibrados rodando o autômato de verdade, não chutados — a primeira tentativa inundava 29% do mapa) e deixa o `WaterSim` da Fase 0 acomodar antes do primeiro desenho. O que aparece na tela é `water_sim.water_at()` de verdade, não uma cor decorativa — cavar canal/represar (Fase 2+) vai mexer nesse mesmo estado.
- **Bug real pego pela integração, não por um teste isolado:** o `water_sim.gd` da Fase 0 conservava água em qualquer teste em linha (no máximo 2 vizinhos por célula), mas rodar `WaterSim` sobre um mapa 2D de verdade (células com até 4 vizinhos mais baixos ao mesmo tempo) expôs um cálculo de fluxo que criava água do nada quando uma célula tentava mandar mais do que tinha. Corrigido com um passo de normalização por célula antes de aplicar qualquer fluxo (ver o comentário em `water_sim.gd::_tick`). Isso é a razão de existir `_test_map_height_feeds_water_sim` e `_test_conservation_holds_with_a_peak_surrounded_on_four_sides`.

[`tests/visual_capture.gd`](tests/visual_capture.gd) captura a vila **pequena** no primeiro frame (só tier 1: Armazém, Fazenda, uma Casa — população 0/3), depois **todos os tiers desbloqueados** (o catálogo inteiro de prédios), **povoada**, o carregador entregando no Armazém, a cadeia de processamento madeira/pedra, a cadeia minério/lingote, a população crescendo **além do piso de arranque** graças à Fazenda, a vila com alcance de exploração já bem maior, mapa depois de explorar e vista afastada, em `.visual_capture/` (gitignored).

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
