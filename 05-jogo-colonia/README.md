# Projeto 5 — Colônia Viva

Evolução do Projeto 4 (`04-jogo-civilizacao`) de idle/clicker pra **colony sim** (estilo RimWorld/Banished): personagens individuais, simulados, que decidem e executam ações visíveis, em vez de produção calculada por fórmula.

Status (2026-08-04): **Fases 0 a 6 implementadas e testadas** (153/153 testes headless, incluindo o spike de performance da Fase 0). A Fase 7 (doenças/eventos/traços/relações) é opcional e fica pra depois — ver "Próximos passos" no fim deste README.

## Por que existe um projeto separado do 04

`04-jogo-civilizacao` está **completo e fechado** como o clicker pixel art que era pra ser (5 eras, 15 construções, 104/104 testes, jogável do início ao fim) — não vamos mexer nele. João decidiu em 2026-08-04 (mesma sessão) que quer aprofundar a simulação de personagens muito além do escopo original de "jogo pequeno e publicável rápido", então em vez de inchar o 04 fora do que ele foi desenhado pra ser, este projeto novo parte de uma **cópia do 04 como ponto de partida** (mesmo framework, mesma economia, mesmos assets) e evolui a partir daí. Segue o padrão dos outros projetos: self-contained, `addons/framework/` e assets copiados pra dentro, sem referência cruzada.

O commit inicial só trocava o nome em `project.godot` (`config/name="Colônia Viva"`), com `Economy`/`Buildings`/`Eras`/`main.tscn` idênticos ao 04 — essa era a base. Desde então (Fases 0-6, ver plano abaixo) `Buildings` ganhou vagas de trabalho (`jobs`), `Economy` ganhou um parâmetro opcional de staffing (retrocompatível — sem ele, se comporta exatamente como o 04) e `scenes/main.gd` ganhou a simulação de moradores por cima. `Eras` e o catálogo de custo/produção em si continuam os mesmos do 04.

## O objetivo (o que "colony sim" significa aqui)

João pediu 4 coisas em linguagem não-técnica; a tradução técnica acordada com ele foi:

1. **Mecânica de jogo** — profundidade além de comprar construção/virar era (tech tree, eventos, decisões). Ainda não escopado em detalhe — decidir isso depois que personagens existirem.
2. **Personagens** — entidades individuais de população (`Villager`), com identidade própria, separadas da abstração numérica do `Economy`.
3. **Simulação dos personagens** — cada `Villager` roda sua própria máquina de estados (necessidades: fome/energia/humor) de forma independente dos outros. Isto é **agent-based simulation**, não uma fórmula global.
4. **Simulação de ações** — produção deixa de ser um número que sobe sozinho: o personagem anda até a construção (pathfinding), toca animação de trabalho, e só então produz.

Escopo confirmado com o João (2026-08-04): simulação **completa** (needs, humor, decisões próprias — não só cosmético), população grande em eras avançadas (**30–100+ personagens simultâneos**), e a ordem de ataque começa por **personagem + movimento**, não pela mecânica econômica.

## Plano de fases (ordem de dependência — não pular)

**Fase 0 — Spike técnico de arquitetura. ✅** Decisão tomada e validada: `Villager` (`scripts/villager.gd`) e `Population` (`scripts/population.gd`) são dado puro (`RefCounted`, sem `Node2D`), testável headless, no mesmo padrão de `Economy`/`Buildings`. A cena (`scenes/main.gd`) só lê `population.villagers` e espelha posição/estado num pool de `Sprite2D` reaproveitados (`_update_villager_sprites`) — nunca instancia/destrói nó por tick. O teste `_test_scale_100_agents_performance` em `tests/run_tests.gd` prova isso na prática: 100 agentes, 300 ticks (~5s de jogo simulado) rodam em ~40ms reais, bem abaixo de qualquer orçamento de frame.

**Fase 1 — Entidade Personagem. ✅** `Villager`: id, nome, posição, `job_id` (construção/vaga atribuída), estado (`idle`/`walking`/`working`/`eating`/`resting`). `to_dict()`/`from_dict()` pra persistência.

**Fase 2 — Movimento. ✅** `Population._move_all()` move cada `Villager` em linha reta até `target_position`, na velocidade própria dele. **Decisão consciente: sem `NavigationAgent2D`.** O README original cogitava pathfinding com `NavigationAgent2D`, mas isso exigiria um `NavigationRegion2D` dependente de cena, quebrando o padrão "lógica testável sem cena" que todo o resto do projeto segue (e o mapa da vila é pequeno e sem obstáculos — linha reta já é suficiente). Se um dia a vila ganhar obstáculos de verdade, revisitar essa decisão.

**Fase 3 — Alocação de trabalho ligada à produção. ✅** Cada construção declara `jobs` (vagas por unidade) em `Buildings.ALL`. `Population.sync_work_sites()` cria **um posto de trabalho por TIPO de construção** (não por unidade individual — o jogo já trata construções como contagem, `Economy.owned[id] = quantidade`, sem identidade por cópia, então a vaga de trabalho segue a mesma simplificação), com `capacity = jobs_of(id) × quantidade`. `Population.staffing_ratios()` calcula, por construção, a fração de vagas realmente ocupadas por alguém no estado `working` **agora** (só estar alocado não basta — tem que estar fisicamente lá). `Economy.production_per_second(staffing)` e `Economy.tick(delta, staffing)` ganharam um parâmetro opcional pra usar essa fração em vez de assumir 100% staffado — com o parâmetro omitido, o comportamento é idêntico ao 04-jogo-civilizacao (retrocompatível, os testes herdados do 04 continuam passando sem alteração).

**Fase 4 — Necessidades (needs). ✅** Fome/energia decaem com `HUNGER_DECAY`/`ENERGY_DECAY_*` (trabalhar cansa mais rápido que ficar ocioso). Humor (`mood`) deriva de fome+energia com um "atraso" (`move_toward`), então reage suave, não instantaneamente. Fome crítica manda o `Villager` andar até a praça e comer (consome comida de `Economy` de verdade — sem estoque, a fome não se resolve); energia crítica manda descansar. **Efeito real, não cosmético (pedido explícito do João):** `staffing_ratios()` pondera pelo humor médio de quem está trabalhando ali — colônia infeliz produz menos, mesmo com todas as vagas "preenchidas no papel".

**Fase 5 — IA de decisão. ✅** `Population._decide_action()` é uma utility AI simples: cada ação candidata (comer/descansar/trabalhar/ficar ocioso) recebe uma pontuação de urgência, a maior vence. Necessidade crítica sempre bate prioridade de trabalho — é assim que "personagem interrompe trabalho pra resolver necessidade" (Fase 4) realmente acontece.

**Fase 6 — Escala (30-100+). ✅** Três otimizações: (1) `DECISION_INTERVAL` — needs/IA só recalculam a cada 0.5s acumulado, não todo frame (movimento continua todo frame, é só soma de vetor, barato); (2) pool de `Sprite2D` reaproveitado por id em `main.gd`, nunca recriado; (3) crescimento populacional tem teto (`POPULATION_CAP = 120`) e um alvo dinâmico (`population_target()` = vagas de trabalho + folga ociosa), então a simulação nunca tenta rodar mais agentes do que o jogo realmente sustenta.

**Fase 7 — Profundidade extra (opcional, só se o jogo estiver divertido nas fases 1-6).** Ainda não feita. Doença, eventos aleatórios, traços de personalidade, relações entre personagens — candidatos naturais pra próxima sessão, mas nenhum é bloqueador: o loop de colony sim já está completo e jogável sem eles.

## Simplificações intencionais (documentadas, não esquecidas)

- **Um posto de trabalho por tipo de construção, não por cópia individual** (Fase 3) — segue o modelo de dados existente (`Economy.owned` é contagem, sem identidade por unidade). Consequência visual: vários trabalhadores da mesma construção convergem pro mesmo ponto — `Population._crowd_offset()` espalha eles um pouco (deslocamento estável por id) só pra não empilhar exatamente no mesmo pixel.
- **Uma "praça" comunitária única** (`Population.PLAZA_POSITION`) em vez de casas individuais — não existe mecânica de moradia no jogo ainda. Todo mundo come/descansa no mesmo lugar (com o mesmo espalhamento visual acima).
- **Sem morte/atrito populacional.** Necessidade crítica reduz humor (e por consequência produtividade) mas não mata ninguém — mantém o tom "colônia crescendo", não "sobrevivência punitiva", e evita ter que decidir uma mecânica de luto/reposição sem pedido explícito do João.
- **Progresso offline não simula movimento.** Reabrir o jogo depois de um tempo fora (`Population.apply_offline_catchup`) deixa a população "descansada" (needs cheias de novo) e permite crescimento proporcional ao tempo fora, mas não tenta re-simular quem andou pra onde — seria caro e invisível mesmo.
- **Sem sprite de personagem dedicado.** O pack de assets do projeto (Kenney Tiny Town) é só cenário, sem sprite de gente. Cada morador é um pontinho colorido por estado (`main.gd::VILLAGER_STATE_COLORS`) — funcional e testável, mas é o candidato mais óbvio pra um upgrade visual futuro se/quando houver arte de personagem CC0 disponível.

## Próximos passos (pra retomar numa sessão nova)

1. **Fase 7 (opcional)** — doenças/eventos/traços/relações, só se fizer sentido depois de jogar as fases 1-6 e sentir falta de profundidade.
2. **Arte de personagem** — trocar os pontinhos coloridos por um sprite de gente de verdade (CC0), se aparecer um pack compatível com o estilo Kenney já usado.
3. **Mecânica de jogo mais funda** (pedido original nº1 do João, ainda não escopado em detalhe) — tech tree, eventos, decisões — decidir só depois de jogar o que já existe.
4. Como sempre neste projeto: publicar no itch.io continua pendente e pausado (ver `CLAUDE.md` da raiz) — só retomar se o João trouxer o assunto.

## Convenções herdadas do projeto (não reabrir)

- Lógica de jogo sem dependência de cena, testável headless (`tests/run_tests.gd`); física/movimento real testado rodando frames de verdade, não simulado à mão.
- Validação visual via script `SceneTree` que tira screenshot (`tests/visual_capture.gd`), não computer-use.
- Self-contained: framework e assets copiados pra dentro do projeto, sem referência cruzada com outros jogos da pasta.

## Arte (herdada do 04, mesmos créditos)

Kenney Tiny Town (construções/cenário) + Kenney Tiny Dungeon (ícones das eras primitivas) + fonte Kenney Pixel. Créditos em `assets/CREDITOS.md` na raiz do repo.
