# Projeto 5 — Colônia Viva

Colony sim 2D pixel art: um vale, um punhado de gente e uma economia que só
anda se **os moradores estiverem lá para tocá-la**. Cada morador é um agente
com fome, energia e humor, que decide sozinho se vai trabalhar, comer ou
descansar — e a produção de cada construção é multiplicada pela fração das
vagas realmente ocupadas por alguém trabalhando naquele instante.

Godot 4.7, GDScript, arte CC0 (Kenney).

## Por que esta é a segunda tentativa

A primeira versão deste projeto foi apagada. A simulação funcionava (moradores,
necessidades, IA de decisão, staffing ligado à produção, 153 testes passando),
mas ela nasceu como **fork da cena do `04-jogo-civilizacao`**: herdou o painel
"Construções" ocupando metade da largura e o painel de recursos dominando o
topo, e os moradores foram encaixados na faixa de ~290px que sobrou embaixo.

O veredito do João foi direto: *"não gostei nem um pouco… é o jogo 4… a nova
funcionalidade tão pequena que eu nem consigo julgar"*.

A lição, e a regra deste projeto:

> Quando a feature nova é o **centro** do jogo, ela não pode herdar o layout de
> tela de um jogo cujo centro era outra coisa. O layout se desenha em função
> dela, e se valida visualmente **antes** de empilhar sistema em cima de sistema.

Por isso, aqui:

- **O mundo ocupa a tela inteira.** Recursos, era e população moram numa tira
  fina de 100px no topo (duas linhas: estado da colônia + ações).
- **A loja é uma gaveta.** O painel de construções fica fora da tela e desliza
  por cima só enquanto está aberto — fechado, o vale tem os 1280px.
- **Nada flutua sobre o mundo.** Botões de coleta e recado do jogo estão na
  tira do topo, não no rodapé: qualquer coisa flutuando embaixo cobre a turma
  que trabalha nos lotes de baixo.
- **Moradores em tamanho de gente:** sprite de 16px em escala 3 (48px de
  altura), com o estado indicado por uma marca colorida acima da cabeça em vez
  de tingir o corpo (tingir arte detalhada transforma todo mundo em borrão).

Essas regras não são só convenção: estão em `tests/run_tests.gd`
(`_test_valley_layout` e `_test_scene_layout_invariants`) como asserções.

## Como jogar

- A colônia começa com 5 moradores na praça e nenhuma construção.
- **+ Comida / + Materiais / + Conhecimento** (topo) é a coleta manual — o
  empurrão inicial de cada era.
- **Construções** (canto superior direito) abre a gaveta: cada construção tem
  custo crescente (×1,15 por cópia), produção por segundo e um número de vagas
  de trabalho. Compra em lote com ×1 / ×10 / ×25 / Máx.
- Cada tipo de construção ocupa **um lote fixo** do vale. Comprar mais cópias
  aumenta a capacidade daquele lote (o contador `×N` embaixo) em vez de espalhar
  ícones repetidos pela tela.
- Os moradores vão sozinhos até a construção onde trabalham e formam uma turma
  na frente da porta. Sem gente presente, aquela construção **não produz**.
- A população cresce até `vagas de trabalho + 3`, consumindo comida a cada
  nascimento, com teto de 120.
- Cinco eras. A virada consome o requisito acumulado e libera 3 construções
  novas, muda o clima do vale e o estilo das casas (acampamento → madeira →
  telha → pedra).
- Salva sozinho a cada 10s e rende produção offline (teto de 8h).

Marcas acima da cabeça: **branco** ocioso · **azul** a caminho ·
**amarelo** trabalhando · **verde** comendo · **roxo** descansando.

## Arquitetura

Nada de lógica dentro da cena — o padrão dos outros projetos da pasta:

| Arquivo | O que faz |
| --- | --- |
| `scripts/economy.gd` | Estoque, produção, custo crescente, eras, offline. `production_per_second(staffing)` recebe a fração de vagas ocupadas. |
| `scripts/buildings.gd` | Catálogo das 15 construções (custo, produção, era, `jobs`). |
| `scripts/eras.gd` | As 5 eras e seus requisitos. |
| `scripts/valley.gd` | **Geometria do vale**: grade, praça, lote de cada construção, onde a turma fica de pé. |
| `scripts/villager.gd` | Um morador: posição, estado, fome/energia/humor. Dado puro. |
| `scripts/population.gd` | Simulação: movimento, vagas, necessidades, IA de decisão por utilidade, crescimento. |
| `scenes/main.gd` | Mundo (tilemap, lotes, sprites), HUD, gaveta, persistência. |

`Valley` existe justamente para que a cena (que **desenha** a construção) e a
`Population` (que decide **para onde o morador anda**) leiam a mesma tabela de
posições. Sem isso dá pra alguém "trabalhar" três tiles longe da própria casa
sem nenhum teste reclamar.

A ordem do frame importa: os moradores decidem e andam primeiro, depois a
economia rende usando `population.staffing_ratios()`.

## Testes

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path 05-jogo-colonia --script res://tests/run_tests.gd
```

172 asserções: catálogos, geometria do vale, economia pura, compra em lote,
eras, offline, save/load, entidade Villager, movimento, vagas/staffing,
necessidades, IA de decisão, crescimento populacional, spike de performance com
100 agentes, e a cena inteira instanciada (boot, coleta, compra, virada de era,
save/reload, invariantes de layout).

Capturas de tela automatizadas (em `.visual_capture/`, fora do git):

```bash
Godot_v4.7.1-stable_win64_console.exe --path 05-jogo-colonia --script res://tests/visual_capture.gd
```

## Créditos de arte

Todos CC0, de [Kenney.nl](https://kenney.nl):

- **Roguelike Characters** — os 12 moradores (`assets/characters/`).
- **Tiny Town** — chão, árvores, casas, tonéis (`assets/town/`).
- **Tiny Dungeon** — ícones das construções primitivas (`assets/dungeon/`).
- **Kenney Fonts** — `Kenney Pixel.ttf` (`assets/fonts/`).
