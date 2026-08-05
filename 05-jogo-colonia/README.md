# Projeto 5 — Colônia Viva

Evolução do Projeto 4 (`04-jogo-civilizacao`) de idle/clicker pra **colony sim** (estilo RimWorld/Banished): personagens individuais, simulados, que decidem e executam ações visíveis, em vez de produção calculada por fórmula.

Status: **não iniciado — só o setup deste README/plano.** Ver seção "Próximos passos" abaixo antes de codar qualquer coisa.

## Por que existe um projeto separado do 04

`04-jogo-civilizacao` está **completo e fechado** como o clicker pixel art que era pra ser (5 eras, 15 construções, 104/104 testes, jogável do início ao fim) — não vamos mexer nele. João decidiu em 2026-08-04 (mesma sessão) que quer aprofundar a simulação de personagens muito além do escopo original de "jogo pequeno e publicável rápido", então em vez de inchar o 04 fora do que ele foi desenhado pra ser, este projeto novo parte de uma **cópia do 04 como ponto de partida** (mesmo framework, mesma economia, mesmos assets) e evolui a partir daí. Segue o padrão dos outros projetos: self-contained, `addons/framework/` e assets copiados pra dentro, sem referência cruzada.

Nada no código foi alterado ainda além do nome em `project.godot` (`config/name="Colônia Viva"`). `Economy`, `Buildings`, `Eras`, a cena `main.tscn` etc. são idênticos ao 04 nesse commit inicial — é a base sobre a qual a simulação de personagens vai ser construída.

## O objetivo (o que "colony sim" significa aqui)

João pediu 4 coisas em linguagem não-técnica; a tradução técnica acordada com ele foi:

1. **Mecânica de jogo** — profundidade além de comprar construção/virar era (tech tree, eventos, decisões). Ainda não escopado em detalhe — decidir isso depois que personagens existirem.
2. **Personagens** — entidades individuais de população (`Villager`), com identidade própria, separadas da abstração numérica do `Economy`.
3. **Simulação dos personagens** — cada `Villager` roda sua própria máquina de estados (necessidades: fome/energia/humor) de forma independente dos outros. Isto é **agent-based simulation**, não uma fórmula global.
4. **Simulação de ações** — produção deixa de ser um número que sobe sozinho: o personagem anda até a construção (pathfinding), toca animação de trabalho, e só então produz.

Escopo confirmado com o João (2026-08-04): simulação **completa** (needs, humor, decisões próprias — não só cosmético), população grande em eras avançadas (**30–100+ personagens simultâneos**), e a ordem de ataque começa por **personagem + movimento**, não pela mecânica econômica.

## Plano de fases (ordem de dependência — não pular)

**Fase 0 — Spike técnico de arquitetura.** Com 30-100+ agentes cada um com sua própria máquina de estados, GDScript pode não aguentar se cada um for um `Node2D` pesado atualizado todo frame. Decidir e prototipar a separação **simulação (dados puros, sem cena, testável headless — mesmo padrão do `Economy` de hoje) vs. renderização (sprites que só refletem estado)** antes de construir qualquer feature em cima. Prototipar 100 agentes "burros" só pra medir custo de frame.

**Fase 1 — Entidade Personagem.** Classe `Villager`: id, nome, posição, construção/casa atribuída, estado atual (ocioso/andando/trabalhando). Sem necessidades, sem IA ainda — só existir e ter identidade. Testável headless, seguindo o padrão de `Economy`/`Buildings`.

**Fase 2 — Movimento.** Pathfinding (`NavigationAgent2D`) entre casa e trabalho, com animação sincronizada via `StateMachine` do framework (reaproveitar o padrão já usado nas eras).

**Fase 3 — Alocação de trabalho ligada à produção.** Construções ganham vagas de trabalho (job slots); produção real passa a depender de quantos `Villager` estão de fato alocados e trabalhando ali, não só de quantas construções foram compradas. É aqui que a simulação passa a importar pro jogo de verdade.

**Fase 4 — Necessidades (needs).** Fome/energia/humor decaem com o tempo; personagem interrompe trabalho pra resolver (comer do estoque, descansar em casa). Liga ao `Economy`: comida do estoque passa a ter duplo uso (virada de era *e* alimentar população).

**Fase 5 — IA de decisão.** Com necessidades competindo, cada personagem precisa escolher "o que fazer agora" — utility AI (pontuar cada ação candidata por urgência) ou FSM com prioridades.

**Fase 6 — Escala (30-100+).** Otimizações: pooling de sprites, atualizar needs em lote/intervalo (não todo frame), simplificar quem está fora da tela. Trabalho técnico puro, sem feature nova visível.

**Fase 7 — Profundidade extra (opcional, só se o jogo estiver divertido nas fases 1-6).** Doença, eventos aleatórios, traços de personalidade, relações entre personagens.

## Próximos passos (pra retomar numa sessão nova)

Nada implementado ainda além da cópia/rename. O próximo passo é a **Fase 0**: prototipar 100 agentes simples e medir custo por frame antes de decidir a arquitetura de simulação vs. renderização.

## Convenções herdadas do projeto (não reabrir)

- Lógica de jogo sem dependência de cena, testável headless (`tests/run_tests.gd`); física/movimento real testado rodando frames de verdade, não simulado à mão.
- Validação visual via script `SceneTree` que tira screenshot (`tests/visual_capture.gd`), não computer-use.
- Self-contained: framework e assets copiados pra dentro do projeto, sem referência cruzada com outros jogos da pasta.

## Arte (herdada do 04, mesmos créditos)

Kenney Tiny Town (construções/cenário) + Kenney Tiny Dungeon (ícones das eras primitivas) + fonte Kenney Pixel. Créditos em `assets/CREDITOS.md` na raiz do repo.
