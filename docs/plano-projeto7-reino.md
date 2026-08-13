# Projeto 7 — "Reino em Construção" (nome provisório)

Documento de planejamento. Escrito antes de qualquer implementação — registra as decisões de design tomadas em conversa com o João em 2026-08-10, pra servir de referência quando a sessão de código começar.

## Histórico da ideia

Partiu de "quero sair do gênero clicker" → cardápio de temas → João pediu um jogo de desenvolver cidade estilo Travian/Clash of Clans → decisão de ser single-player contra IA (sem backend/multiplayer) → João pediu que o mapa fosse estilo Factorio (recursos físicos no chão, extração + transporte) → ao detalhar transporte/energia, João pediu explicitamente para pivotar a inspiração principal para **Timberborn** e **deixar combate de lado por enquanto**, focando em ser o melhor city-builder / explorador de mapa / automação de extração possível.

**Combate e exército ficam fora do escopo atual.** Podem voltar depois como uma fase futura, mas não fazem parte do plano de construção do jogo por ora.

## Ideia central

City-builder de sobrevivência e automação: o jogador explora um mapa físico em busca de depósitos de recursos, constrói uma cadeia de extração → transporte → processamento → armazenamento, sustentada por trabalhadores alocáveis e uma rede de energia real. A tensão do jogo vem de:
- **Recursos finitos** (motiva expansão pelo mapa em vez de otimizar um canto só).
- **Energia e população limitadas** (motiva otimização de layout, como em Timberborn/Factorio).
- **Água como sistema de simulação de fluxo**, não depósito estático (motiva engenharia de terreno: cavar canais, represar).

## Loop principal

1. Explorar o mapa (nevoeiro de guerra) e localizar depósitos.
2. Construir extrator sobre ou perto do depósito.
3. Ligar o prédio à energia (cabo direto ou distribuidor por raio) e/ou alocar trabalhador.
4. Recurso extraído é transportado até o armazém/processamento por NPC carregador.
5. Processar recursos brutos em recursos construídos (madeira → tábua, minério → lingote, pedra → bloco).
6. Usar recursos construídos para expandir prédios, desbloquear tecnologia e alcançar novos depósitos.
7. Depósito se esgota → motiva avançar mais no mapa, repetindo o ciclo em terreno mais desafiador.

## Recursos

### Brutos (extraídos do chão)
- **Madeira** — bosques, depósito finito com leve regeneração se árvores maduras forem deixadas.
- **Pedra** — afloramentos, finito, sem regeneração.
- **Minério** — veios em colinas/montanhas, finito, sem regeneração.
- **Água** — não é depósito fixo, é simulação de fluxo (ver seção própria). Extraída via captação + armazenada em barril/cisterna.

### Alimento (mínimo 2 tipos, com características diferentes)
- **Colheita/grão** — terra fértil + irrigação (precisa de água), produção em lote/estação, mais volume por ciclo.
- **Caça/pesca** — depósito natural (animais/cardumes), produção mais rápida mas se esgota como os brutos.
- Possível efeito de variedade alimentar na satisfação da população (a decidir na fase de balanceamento).

### Processados (construídos a partir de brutos)
- Tábua (madeira processada) — insumo da maioria dos prédios.
- Bloco de pedra — infraestrutura e prédios avançados.
- Lingote de metal — prédios avançados e, futuramente, tecnologia.

## Água — simulação de fluxo, não depósito estático

Decisão explícita do João: precisa ser possível **"abrir rios"** — cavar canais, redirecionar fluxo, represar. Isso pede um autômato celular parecido com o do incêndio (Projeto 6, `fire_sim.gd`): água como célula com volume/altura que escoa entre tiles vizinhos conforme diferença de altura e obstáculos.

Isso permite:
- Cavar canais (remove terreno, abre caminho para a água escoar até uma área nova).
- Construir represas/comportas (bloqueiam ou controlam o fluxo — decisão espacial real).
- Extratores de água ficam sensíveis a "tem água aqui agora?" em vez de um depósito fixo que só esvazia.

Água é um recurso **compartilhado entre três usos**: consumo industrial (prédios), consumo da população (beber) e irrigação da fazenda. Isso significa que faltar água tem efeito em cascata sobre os três sistemas — não é um recurso isolado.

Consistente com a lição já registrada no projeto ([[reference_simulation_constants_need_measurement]]): a velocidade de escoamento e os limiares de volume por célula devem ser medidos com script de calibração antes de virar constante travada, não chutados.

## Energia

Três fontes:
- **Lenha** — queima madeira/tábua, gerador simples, sempre disponível mas consome recurso.
- **Roda d'água** — precisa estar posicionada no rio/fluxo de água, grátis para operar depois de construída, limitada por localização.
- **Vento** — precisa de posição aberta/elevada, grátis, possivelmente com variação de intensidade.

Duas formas de distribuição:
- **Cabo direto** — conecta prédio a prédio manualmente, mais barato, exige planejamento de layout (o jogador desenha a rede).
- **Distribuidor por raio** — mais caro de construir, cobre uma área sem exigir cabos individuais, melhor para clusters densos de prédios.

Regra geral: todo prédio de produção precisa de **energia OU trabalhador alocado** para funcionar (alguns prédios avançados podem exigir os dois).

## Trabalhadores (estilo Timberborn)

- População é um recurso central: cada trabalhador é alocado a UM prédio por vez.
- Trabalhadores se deslocam fisicamente até o prédio (reaproveita o modelo de agente + pathfinder da Colônia V2 — ver `05_V2-jogo-colonia/scripts/pathfinder.gd`). Prédio longe do núcleo populacional custa tempo de trajeto.
- Necessidades dos trabalhadores (comida, água, descanso) consomem parte da produção — mesmo ciclo de sustentar quem sustenta a produção que já existe na Colônia, agora aplicado a um jogo de automação.

## Transporte de recursos

Decisão: **NPC carregador**, não esteira. Motivo (registrado em conversa): esteira exigiria um sistema de tiles direcionais + item físico se movendo tile a tile — o tipo de sistema que vira o centro do jogo se bem feito, mas o mais caro de construir e testar. NPC carregador reaproveita quase inteiramente o agente + pathfinder já validado na Colônia V2, entrega mais rápido e ainda dá a sensação de logística física. Esteira fica como possível desbloqueio tardio, não como base do jogo.

## Pathfinding — estratégia recomendada

O A* por agente (`AStarGrid2D`, já validado na Colônia V2) continua sendo a base, mas esse jogo tem um padrão de tráfego diferente: **muitos NPCs convergindo para o mesmo destino** (armazém central, poço). Rodar A* individual para cada um é redundante e caro em escala.

Estratégia: **flow field** para os destinos fixos mais visitados (calcula o campo de direção uma vez; todo NPC indo para lá segue o campo — muito mais barato com dezenas de agentes simultâneos) combinado com A* pontual para trajetos incomuns/um-off. As trilhas de pisoteio que já existem na Colônia V2 continuam válidas, realimentando o custo de ambos os sistemas.

## Construções previstas (primeira leva, sem combate)

**Extração**
- Posto de Lenhador (madeira, NPC)
- Pedreira (pedra, energia ou NPC)
- Mina (minério, energia ou NPC)
- Captação de Água (água, energia ou NPC) + Barril/Cisterna (armazenamento)
- Fazenda (colheita, NPC, precisa de irrigação)
- Posto de Caça/Pesca (segundo tipo de comida, NPC)

**Energia**
- Gerador a Lenha
- Roda D'água (exige posição no rio)
- Moinho de Vento
- Distribuidor de Energia (raio)

**Processamento**
- Serraria (madeira → tábua)
- Forja (minério → lingote)
- Oficina de Pedra (pedra → bloco)

**Infraestrutura/logística**
- Armazém (estoque central de brutos)
- Depósito especializado por tipo de recurso (se o volume pedir)
- Estrada/trilha (acelera trajeto de NPC, reaproveitando trilhas de pisoteio)
- Canal/represa/comporta (engenharia de água)

**Habitação e vida**
- Casa (abriga população, define teto de trabalhadores)
- Poço/fonte de água potável (consumo da população)
- Espaço de convívio (reaproveita ideia da fogueira/praça da Colônia)

**Progressão**
- Centro/Prefeitura por níveis, desbloqueando prédios e alcance de exploração.

## Fora de escopo (por enquanto)

- Exército, tropas, combate contra vilas de IA — descartado explicitamente pelo João em 2026-08-10 em favor de aprofundar city-building/automação. Pode ser retomado como fase futura, mas não faz parte do plano de construção atual.
- Multiplayer/backend — descartado desde o início da conversa; jogo é single-player, self-contained como os demais projetos do repositório.

## Próximos passos

1. Quebrar este design em fases pequenas e testáveis (padrão de todos os projetos anteriores: cada fase jogável e coberta por testes headless antes de avançar).
2. Validar visualmente cada fase antes de seguir para a próxima (screenshots automáticos + revisão do João).
3. Calibrar constantes de simulação (fluxo de água, tempos de trajeto, produção) com script de medição, não chute — lição já registrada de erros anteriores do projeto.

## Fases planejadas

Quebra do design acima em fases pequenas e testáveis, escrita em 2026-08-10 antes de começar a codar (item 1 dos próximos passos). Cada fase é headless-testável antes de ganhar visual, e cada fase ganha uma validação visual antes de a próxima começar.

- **Fase 0 — Fundação técnica. [concluída 2026-08-10]** Scaffold do projeto Godot self-contained (`addons/framework/` copiado, projeto mínimo abrindo). Spike do sistema mais arriscado e mais novo do design — o autômato de água (escoamento, cavar canal, represar) — como classe sem dependência de cena, com testes headless e calibração da velocidade de escoamento por medição (ver [[reference_simulation_constants_need_measurement]]). Sem visual ainda: o objetivo é provar que a mecânica central de terraplanagem funciona antes de desenhar qualquer tela em cima dela.
- **Fase 1 — Mapa e exploração. [concluída 2026-08-10]** Terreno com relevo (a altura que o `water_sim` já consome), depósitos de recursos visíveis no chão, câmera navegável, nevoeiro de guerra, e lagos de verdade (água semeada nos pontos baixos do relevo e acomodada pelo autômato antes do primeiro desenho — pedido explícito do João depois de ver a fase sem nenhuma água visível). Primeira validação visual do projeto. A integração do mapa 2D com o `water_sim` pegou um bug real de conservação que os testes em linha da Fase 0 não expunham (célula com mais de 2 vizinhos simultâneos mandava mais água do que tinha) — corrigido, ver `07-jogo-reino/README.md`.
- **Fase 2 — Extração + trabalhador por prédio. [concluída 2026-08-10]** Posto de Lenhador e Pedreira, produção headless testável. Trabalhador anda de verdade até o prédio (A* portado da Colônia V2, `07-jogo-reino/scripts/pathfinder.gd`) e só produz depois de chegar (`WORKING`, não só "alocado") — trajeto custa tempo de produção, como o design original pedia. A primeira versão nasceu com "trabalhador único" no escopo (um NPC só, o outro prédio ficava parado); João viu o jogo, achou que a Pedreira nem existia (prédio parado e prédio inexistente se confundem pra quem só está jogando) e pediu um segundo trabalhador — ajustado no mesmo dia pra "um trabalhador por prédio". Captação de Água ficou de fora desta fase (interface com o `WaterSim` compartilhado é mecânica diferente de puxar um depósito finito do `MapGen`; entra quando fizer sentido, não precisou pra provar o sistema).
- **Fase 3 — Transporte. [concluída 2026-08-10]** NPC carregador levando recursos do extrator ao armazém, reaproveitando agente + pathfinder da Colônia V2. Mudança de fundo: produção deixou de virar estoque jogável direto — vira `Building.buffer` (pátio local, com teto) até o carregador entregar no Armazém. Sem o teto do pátio, o transporte seria decoração (o jogo funcionaria igual sem ele); com ele, um extrator longe demais ou mal servido de fato trava. Carregador escolhe sempre o pátio mais cheio, não o mais próximo — evita que "não era a vez dele" esconda um gargalo real.
- **Fase 4 — Processamento. [concluída 2026-08-12]** Cadeia bruto → processado: Serraria (madeira → tábua) e Oficina de Pedra (pedra → bloco), 1:1, throttladas pelo estoque bruto disponível. Forja (minério → lingote) ficou de fora — não existe extrator de minério ainda (a Mina não entrou nas fases anteriores), então não haveria insumo pra ela produzir. Decisão de arquitetura registrada em `buildings.gd`: processamento lê/escreve direto no Armazém, sem pátio próprio nem `Carrier` — o insumo já passou pelo transporte da Fase 3, e uma segunda perna só pra levar o processado de volta pro mesmo Armazém não ensinaria nada novo sobre logística.
- **Fase 5 — Energia. [concluída 2026-08-12, parcial]** Regra "energia OU trabalhador" implementada e provada: o Gerador a Lenha (queima madeira) cobre um raio fixo em células, e todo prédio de produção dentro do raio funciona mesmo sem trabalhador, contanto que haja combustível. A Oficina de Pedra nasce de propósito sem trabalhador nesta fase, só pra provar que o raio sozinho basta. Ficou de fora (fase futura, se fizer sentido): Roda D'água e Moinho de Vento (as outras duas fontes do plano original — exigiriam posição condicionada a rio/relevo, que este raio genérico não modela) e a distinção cabo-direto vs distribuidor-por-raio como duas mecânicas separadas (por ora só existe o "raio", sem custo/trade-off entre as duas formas de distribuição).
- **Fase 6 — População e habitação. [concluída 2026-08-12, parcial]** Casa e teto de trabalhadores implementados: população cresce devagar até a capacidade habitacional, e mão de obra (trabalhadores + carregador) deixa de ser instantânea — nasce numa fila, preenchida conforme população disponível. A vila agora começa vazia e se povoa aos poucos. Ficou de fora (fase futura, se fizer sentido): necessidades (comida, água potável, descanso) consumindo produção — exigiria uma fonte de comida (Fazenda/Posto de Caça) que nenhuma fase anterior construiu; sem isso, "comida" não teria de onde vir.
- **Fase 7 — Progressão. [concluída 2026-08-12, parcial]** A vila (sem prédio de Prefeitura separado — o Armazém já é o centro) sobe de nível acumulando XP de todo recurso entregue, e cada nível aumenta de verdade o alcance de exploração (raio da névoa). Ficou de fora: desbloqueio de prédios por nível — hoje todo prédio nasce de uma vez no início do jogo, antes de existir qualquer conceito de nível; gatear isso pediria reescrever a colocação de prédios pra ser progressiva, e essa mudança de arquitetura é maior que o resto desta fase.
- **Mina + Forja. [concluída 2026-08-12]** Terceira cadeia de recurso (minério → lingote), fechando a lacuna deixada em aberto na Fase 4: a Mina (extrator) senta sobre o depósito de colina (`MapGen.Kind.HILLS`) que existe desde a Fase 1 sem nenhum prédio explorando ele, e a Forja (processador) converte minério em lingote 1:1, mesmo padrão da Serraria/Oficina de Pedra. Reaproveita 100% da arquitetura genérica de `buildings.gd` (extração via pátio+Carrier, processamento direto no estoque) — zero mudança de sistema, só entradas novas nos dicts dirigidos por `Kind`. Cor do marcador da Mina escolhida de propósito fria (slate azul-arroxeado) pra não repetir a camuflagem da Pedreira na Fase 2 (o chão de colina já é tingido de laranja pelo próprio depósito de minério).
- **Fazenda + necessidade de comida. [concluída 2026-08-13]** Primeira necessidade real de população: `Kind.FARM` produz comida sem depósito finito (não existe tile de "terra fértil" — representa lavoura ao redor da vila, mesma arquitetura de extração de sempre, só sem `DEPOSIT_KIND_OF`), e `Population.advance()` agora consome comida por habitante, encolhendo a população em déficit até um piso de arranque (`BOOTSTRAP_POPULATION`) que nunca depende de comida — sem esse piso a vila trava (ninguém pra construir a Fazenda sem população, nenhuma comida sem Fazenda). Achado rodando a suíte: a fila de contratação precisou passar a priorizar Fazenda e carregador ANTES dos extratores de matéria-prima, senão os dois trabalhadores do piso iam pra Lenhador/Pedreira e a Fazenda nunca era staffada — deadlock permanente em população 2. Constantes calibradas por medição (`tests/calibrate_farm.gd`, removido depois de usado). Água potável e descanso continuam de fora — cada um pediria sua própria fonte que nenhuma fase construiu ainda.
- **Nota de 2026-08-12:** com as 8 fases (0–7) do plano original implementadas (algumas parciais, listadas acima), o João perguntou diretamente "já dá pra jogar?". A resposta honesta foi não: o jogo inteiro roda sozinho — mapa, extração, transporte, processamento, energia, população e progressão são todos automáticos, sem nenhuma decisão do jogador (fora mover câmera, zoom e clicar pra revelar névoa). Perguntado se preferia pausar as fases do plano pra dar agência real ao jogador (uma ferramenta de construção, por exemplo) ou continuar como estava, o João escolheu continuar o plano. Registrado aqui pra próxima sessão não reabrir a pergunta sem necessidade — mas também não esquecer que ela existe.
- **Fase 8+ — Escala e polimento.** Flow field para destinos fixos de tráfego denso (armazém, poço), engenharia de água mais rica (comportas), balanceamento de recursos/alimentação, áudio.

Fases 1+ podem ser reordenadas ou fundidas conforme a implementação mostrar o que faz sentido jogar primeiro; a ordem acima é a leitura mais direta do loop principal, não um contrato fechado.
