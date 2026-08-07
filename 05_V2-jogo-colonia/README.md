# Projeto 5 V2 — Colônia Viva: os moradores

Mesmo jogo do `05-jogo-colonia`, com um único objetivo: **fazer os moradores
parecerem gente e o vale parecer um lugar onde eles moram.**

Economia, eras, catálogo de construções e layout de tela ficaram **iguais de
propósito**. Este projeto não é sobre jogabilidade nova; é sobre os agentes e
os arredores deles.

Godot 4.7, GDScript, arte CC0 (Kenney).

## O problema que este projeto resolve

O V1 acertou o layout (mundo em tela cheia, loja em gaveta) e a simulação (cada
morador decide sozinho; construção sem gente não produz). Mas os moradores em
si eram o ponto fraco:

| No V1 | No V2 |
| --- | --- |
| Sprite parado de 16px, escolhido de um elenco de 12 | Corpo montado camada a camada e recolorido por pessoa |
| Todo mundo de frente, inclusive andando pra trás | Quatro direções, com pose de costas e de perfil |
| Deslizava até o destino sem mover nada | Ciclo de passos: pernas alternadas, braços balançando, corpo repicando |
| Uma postura genérica pra "trabalhando" | Machado, picareta, enxada, martelo ou livro, conforme o ofício — e a ferramenta gira na mão |
| Linha reta atravessando as casas | A* sobre o vale, contornando lotes, com corte de esquina |
| Trabalhar, comer, descansar | + conversar, passear, carregar a produção, levantar obra, comemorar |
| Estado = bolinha colorida | Rosto com expressão (fome/cansaço/humor), balão só quando o corpo não conta sozinho |
| Vale estático | Trilhas que se abrem no chão, fumaça de chaminé, lavoura, fogueira tremendo, pássaros |

## Como o morador é feito

O sheet "Roguelike Characters" da Kenney **não** é um catálogo de personagens
prontos — é um paper doll modular: corpos nus, camisas, cabelos, barbas e
chapéus desenhados na mesma grade de 16×16, alinhados pixel a pixel. O V1 usou
só as duas colunas de personagens já montados e por isso tinha 12 pessoas.

`scripts/villager_art.gd` monta cada morador a partir das peças e **recoloriza**
cada camada trocando a paleta por uma rampa da cor alvo, preservando a ordem de
luminância. É isso que permite qualquer cor de roupa e de cabelo mantendo o
sombreado do pixel art (tingir com `modulate` só escurece e vira borrão — foi o
que o V1 evitou fazendo nada).

Cada morador nasce com pele, camisa, cor da camisa, cabelo, cor do cabelo,
barba e chapéu próprios — e isso é **salvo junto com ele**, então reabrir o
jogo não troca a colônia por estranhos.

## Como a animação funciona

Assar spritesheet por morador não fecha: 5 estados × 4 direções × 4 quadros,
vezes 120 moradores de aparência única, é textura demais. Então:

- **Assado (uma vez por morador):** o corpo de 16×16 em duas poses — de frente
  e de costas — numa tira de 32×16. Mais um atlas minúsculo de rostos.
- **Não assado:** a animação. A cena recorta essa textura em seis pedaços
  (cabeça, tronco, dois braços, duas pernas) e **move os pedaços**.

Mover seis retângulos custa quase nada, dá pose contínua (a caminhada acelera
junto com quem anda rápido) e deixa a ferramenta girar de verdade na mão. As
faixas dos pedaços se sobrepõem de propósito — o tronco começa uma linha antes
de a cabeça acabar — então deslocar uma parte 1px nunca abre buraco na
silhueta.

O rosto **não** é assado no corpo: fica num sprite por cima, porque a expressão
muda em tempo real com fome, cansaço, humor e piscada.

## O que os moradores fazem agora

A IA de utilidade do V1 pontuava três ações. Agora são sete, e cada uma tem um
**lugar** no vale em vez de "algum ponto da praça":

| Ação | Onde | O que se vê |
| --- | --- | --- |
| Trabalhar | na porta da própria construção | gesto e ferramenta do ofício |
| Comer | em roda na fogueira comunal | mão levando comida à boca |
| Descansar | na sombra das bordas do vale | sentado, olhos fechados, balão de sono |
| Conversar | no meio do caminho entre os dois | de frente um pro outro, gesticulando |
| Passear | qualquer canto livre do vale | caminhada normal |
| Carregar | do posto até o celeiro | caixa na cabeça, "+recurso" ao entregar |
| Levantar obra | no lote recém-comprado | turma martelando |
| Comemorar | onde estiver | pulinho de braços pra cima |

Necessidade nova: **convívio**. Decai devagar, entra no cálculo do humor, e é
por isso que as pessoas param pra conversar.

### Nota de equilíbrio

Carregar, levantar obra e comemorar **continuam contando como vaga ocupada**
em `staffing_ratios()`. É trabalho da colônia, e o V2 é sobre comportamento,
não sobre rebalancear a economia do V1. Isso inclui a **volta** do celeiro (o
campo `errand` do `Villager`): contar só a ida faria a produção cair só porque
o trabalhador passou a andar. A única ação que de fato tira alguém do posto é
conversar — curta, rara, e devolve humor, que já multiplica a produção.

## As trilhas

Cada célula do vale conta quantas vezes foi pisada. As mais pisadas viram
caminho de terra: mais baratas pro A*, então o próximo morador tende a usá-las.
As estradas da colônia se desenham sozinhas.

O detalhe que faz funcionar é o **teto** (`Pathfinder.TRAIL_LIMIT`). Sem ele,
uma colônia grande pisa em tudo e o vale inteiro vira terra batida — o que não
lê como "caminho", lê como "alguém arou o mapa". Foi exatamente o que a
primeira tentativa fez, e agora é asserção em `_test_trails`.

## Como jogar

Igual ao V1, com um acréscimo: **clique num morador**. A ficha dele aparece na
tira do topo — nome, ofício, o que está fazendo agora e as barras de fome,
energia e convívio. É a porta de entrada pra toda a vida interior que o V2
acrescentou; sem ela, a simulação só existiria pro código.

O balão acima da cabeça aparece só pro que o corpo não conta sozinho (comer,
descansar, conversar, comemorar, construir). Trabalhar e andar se leem pela
ferramenta, pelo lugar e pelo movimento — encher tudo de balão cobre a colônia
de caixinhas e o olho para de distinguir o que importa.

## Arquitetura

| Arquivo | O que faz |
| --- | --- |
| `scripts/economy.gd` | Estoque, produção, custo crescente, eras, offline. *(igual ao V1)* |
| `scripts/buildings.gd` | Catálogo das 15 construções. **Novo:** `work`, o jeito de trabalhar de cada uma. |
| `scripts/eras.gd` | As 5 eras e seus requisitos. *(igual ao V1)* |
| `scripts/valley.gd` | Geometria do vale. **Novo:** fogueira, poço, celeiro, sombras, ponto de encontro. |
| `scripts/villager_art.gd` | **Novo.** Monta e recoloriza o morador; assa corpo e rostos. |
| `scripts/pathfinder.gd` | **Novo.** A* sobre o vale, corte de esquina, trilhas de pisoteio. |
| `scripts/villager.gd` | Um morador. **Novo:** aparência, direção, rota, convívio, carga. |
| `scripts/population.gd` | Simulação. **Novo:** rota, ações autônomas, separação local, fila de acontecimentos. |
| `scenes/villager_view.gd` | **Novo.** O boneco articulado: seis pedaços, rosto, ferramenta, carga, balão. |
| `scenes/main.gd` | Mundo, arredores animados, HUD, ficha do morador, gaveta, persistência. |

A regra do projeto continua valendo: **nada de lógica dentro da cena.**
`VillagerArt` e `Pathfinder` também não dependem de cena (usam `Image` e
`AStarGrid2D`, que são núcleo do Godot), então tudo continua testável headless.

## Testes

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path 05_V2-jogo-colonia --script res://tests/run_tests.gd
```

271 asserções. Além de tudo que o V1 já cobria, o V2 acrescentou regressão para
cada promessa deste README:

- **Arte:** 30 sorteios dão ≥25 aparências distintas; a recolorização preserva
  a ordem de luminância; o corpo assado não traz rosto pintado; a expressão
  segue a necessidade mais gritante.
- **Navegação:** o lote vira obstáculo; nenhum trecho do caminho atravessa uma
  construção; o desvio nunca é mais curto que a reta; com as 15 construções de
  pé, todo posto continua alcançável; o corte de esquina reduz os pontos.
- **Trilhas:** aparecem com o uso, somem sem uso, ficam mais baratas pro A*,
  são salvas — e nunca passam do teto de células.
- **Comportamento:** dois carentes de convívio viram dupla e conversam de fato;
  o carregador entrega no celeiro; quem carrega e quem constrói continuam
  contando como vaga ocupada; a festa termina sozinha; sobrepostos se afastam
  mas a turma no posto não é empurrada.
- **Boneco:** a perna muda de lugar entre quadros; parado ele respira; de
  costas não tem rosto; de perfil some o braço de trás; a ferramenta gira ao
  longo do golpe e é diferente por ofício; a cara muda com fome e cansaço;
  cada morador tem a própria textura assada.

Capturas de tela automatizadas (em `.visual_capture/`, fora do git):

```bash
Godot_v4.7.1-stable_win64_console.exe --path 05_V2-jogo-colonia --script res://tests/visual_capture.gd
```

Inclui duas capturas que o V1 não tinha: `00_elenco` (os bonecos fora do jogo,
em todos os estados, direções, ofícios e humores) e `04_close` (zoom no vale).
Arte de 16px em escala 3 não dá pra revisar numa foto de tela inteira.

## Créditos de arte

Todos CC0, de [Kenney.nl](https://kenney.nl):

- **Roguelike Characters** — corpos, roupas, cabelos, barbas, chapéus e
  ferramentas dos moradores (`assets/characters/`).
- **Tiny Town** — chão, árvores, casas, tonéis, lavoura (`assets/town/`).
- **Tiny Dungeon** — ícones das construções primitivas (`assets/dungeon/`).
- **Kenney Fonts** — `Kenney Pixel.ttf` (`assets/fonts/`).

Fogueira, pássaro, sombra, balão, ícones de balão, comida, livro e caixote são
desenhados por código (`scenes/main.gd` e `scenes/villager_view.gd`): nenhum
tile dos packs servia nesses tamanhos.
