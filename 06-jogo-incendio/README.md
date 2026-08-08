# Projeto 6 — O Vale em Chamas

Um incêndio atravessa um vale habitado. Você tem três brigadistas, uma pá, uns
baldes d'água e a opção de atear fogo você mesmo.

Godot 4.7, GDScript, arte CC0 (Kenney). 254 asserções headless.

## O sistema novo

Os cinco jogos anteriores deste repositório têm coisas que **decidem**: o
inimigo do roguelike persegue, o morador da colônia escolhe entre comer e
descansar. Um incêndio não decide nada — ele é consequência mecânica do estado
do vale. E é justamente por isso que dá pra jogar contra ele: **se você entende
as regras, você prevê.**

O motor é um autômato celular (`scripts/fire_sim.gd`) com cinco regras:

1. Célula em chamas joga **calor** nos 8 vizinhos.
2. Esse calor é dobrado ou anulado por **vento** e por **relevo** (fogo sobe
   morro muito mais rápido do que desce).
3. O mesmo calor **seca** o vizinho, e terreno seco pega mais fácil — um
   incêndio grande prepara o próprio caminho.
4. Célula acumula calor, perde calor pro ar, e acende quando passa do limiar do
   terreno dela (mais alto se estiver molhada).
5. Queimar consome **combustível**. Sem combustível vira cinza, e cinza não
   queima de novo.

A regra 5 é o jogo inteiro. Aceiro e contra-fogo não são poderes: são as duas
maneiras de gastar o combustível antes de o fogo chegar nele.

### Os números, e por que são esses

| condição | segundos por célula |
| --- | --- |
| capim plano, sem vento | 2,3 |
| a favor do vento | 0,9 |
| contra o vento | 7,5 |
| morro acima / abaixo | 1,5 / 3,5 |
| mato / mata / lavoura | 1,3 / 1,6 / 1,7 |
| capim encharcado | a frente morre |

Nada disso foi chutado — saiu de `tests/calibrate.gd`, que mede cada condição
isoladamente, e virou asserção em `run_tests.gd` com faixa numérica.

Duas descobertas custaram uma calibração inteira cada:

- **O que dá ritmo ao fogo é o calor demorar a se dissipar, não o calor emitido
  ser pequeno.** Com dissipação rápida, a célula só acende se o que ela recebe
  por segundo vencer o que ela perde por segundo — e o sistema inteiro passa a
  viver no fio da navalha, onde mexer 10% em qualquer constante faz o incêndio
  ou morrer sozinho ou varrer o mapa. Com dissipação lenta o calor **acumula**,
  o tempo até acender vira rampa suave, e dá pra ter fogo lento e robusto ao
  mesmo tempo.
- **Uma célula precisa queimar por mais tempo do que leva pra acender a
  vizinha.** Óbvio depois de escrito; invisível antes. Na primeira calibração o
  capim queimava 7,7s e levava 9,8s pra pegar no vizinho: toda frente de fogo se
  apagava sozinha e o jogo não existia, sem uma única exceção no console. Hoje é
  a primeira asserção da suíte.

## O que você faz

Você **não cava**. Você põe uma ordem no mapa e um brigadista caminha até lá.
Entre a decisão e o efeito existe uma travessia — e a travessia pode falhar: o
fogo fecha o caminho, o alvo deixa de fazer sentido, o calor obriga a recuar.
Errar o lugar custa o tempo da ida, e é isso que faz "onde eu clico" ser uma
decisão em vez de um clique.

| ferramenta | tempo | quantidade | o que faz |
| --- | --- | --- | --- |
| **Aceiro** | 2,0s | infinito | tira o combustível pra sempre |
| **Água** | 1,1s | contada | apaga chama acesa e molha o que não pegou |
| **Contra-fogo** | 0,9s | contada | queima de propósito, antes de a frente chegar |

Um triângulo: com só a primeira o jogo seria paciência; com só a segunda, gestão
de recurso; com só a terceira, roleta.

E há **faíscas**. Sem elas o jogo teria uma resposta certa e só uma — uma linha
de aceiro de uma célula, em qualquer lugar, barraria o fogo pra sempre. Com
vento forte a brasa pula duas a quatro células por cima da barreira, e aí é
preciso escolher entre cavar largo, molhar o outro lado, ou aceitar o salto e
conter o foco novo depois.

## Os moradores

Brigadistas obedecem; moradores **não**. Eles ficam em casa até perceberem o
fogo, correm para o abrigo alcançável mais perto, e entram em pânico quando não
há nenhum. Você não os comanda — você muda o mapa em que eles decidem. Abrir um
caminho seguro é uma ordem indireta, e é a forma mais bonita de controle que
este jogo tem.

É a IA de utilidade do Projeto 5 com a entrada trocada: lá o morador olhava pra
dentro (fome, sono, convívio); aqui ele olha pro campo de perigo. O
comportamento que sai é irreconhecível.

O detalhe que decidiu vidas: o morador escolhe o abrigo pelo **preço** do
caminho, não pelo número de passos. Contando passos, ele escolhia o abrigo mais
perto — que numa fase ficava a quatro células do foco do incêndio — e corria
alegremente pra dentro do fogo.

## A previsão

TAB pinta o vale com o tempo estimado até o fogo chegar em cada lugar. Não é a
simulação rodada adiante: é um Dijkstra sobre o vale onde o custo de entrar numa
célula é o tempo estimado até ela acender, dadas as condições de agora.
Aproximado de propósito — um jogo que entrega o futuro exato não tem decisão
nenhuma.

A cor mais importante é o **azul-claro**: célula que o fogo *não* alcança. É
assim que um aceiro se anuncia como pronto — o outro lado muda de cor inteiro,
antes de a chama chegar, e você vê o próprio plano funcionando em vez de torcer.

## As fases

Seis, cada uma existindo pra ensinar uma regra, e a seguinte cobrando que a
anterior tenha sido entendida:

| # | fase | ensina |
| --- | --- | --- |
| 1 | A garganta | cavar aceiro fecha uma passagem |
| 2 | O vento manda | o vento decide qual lado queima primeiro |
| 3 | A encosta | fogo sobe morro muito mais rápido do que desce |
| 4 | Sede | água apaga e protege — mas acaba |
| 5 | Brasas | com vento forte a brasa **pula** o aceiro |
| 6 | Contra-fogo | contra o fogo grande, gaste o combustível antes |

São mapas ASCII em `scripts/levels.gd` — mesma ideia que salvou o Projeto 3.
Uma fase é dado, não código: dá pra ler o vale inteiro de bater o olho, editar
sem abrir o editor, e pôr um bot pra jogar nos testes.

## A tela

Desenhada pro fogo, não herdada de ninguém. O Projeto 5 pôs o HUD numa tira no
topo porque o assunto lá eram pessoas andando pelo chão. Aqui o assunto é uma
frente que avança, e isso muda tudo:

- **O mapa é maior que a tela.** Um incêndio precisa de espaço pra ter forma —
  frente, flanco, retaguarda. Daí a câmera.
- **Daí também o minimapa.** Um jogo em que se descobre por acaso que uma casa
  queimou do outro lado seria um jogo sobre arrastar a tela.
- **Barra vertical à esquerda**, com as três ferramentas e o custo sempre à
  vista: ferramenta é escolha constante, não menu.
- **Bússola grande.** O vento é a informação mais cara do jogo. Num canto
  discreto ninguém olha, e quem não olha o vento não entende por que perdeu.

## Como jogar

```bash
Godot_v4.7.1-stable_win64_console.exe --path 06-jogo-incendio
```

Clique numa célula com a ferramenta escolhida pra dar uma ordem; botão direito
cancela (e devolve o recurso). `1`/`2`/`3` trocam de ferramenta, `TAB` liga a
previsão, `F` acelera o tempo, `WASD` movem a câmera, `B` liga a demonstração,
`R` recomeça.

## Arquitetura

Nada que decide alguma coisa mora na cena.

| arquivo | o que faz |
| --- | --- |
| `scripts/terrain.gd` | a tabela do que queima e como |
| `scripts/fire_sim.gd` | o autômato celular, o vento, as faíscas e a previsão |
| `scripts/levels.gd` | as seis fases em ASCII, e o parser |
| `scripts/tools.gd` | as três ferramentas, com custo e validação |
| `scripts/nav.gd` | A* sobre um mapa de custo que é o próprio incêndio |
| `scripts/agents.gd` | brigadistas (obedecem) e moradores (reagem) |
| `scripts/mission.gd` | uma partida: orçamento, vitória, derrota, estrelas |
| `scripts/containment_bot.gd` | o bombeiro automático dos testes |
| `scripts/layout.gd` | a geometria da tela, num lugar só |
| `scripts/person_art.gd` | o paper doll do Projeto 5 V2, com paletas por papel |
| `scenes/main.gd` | desenha e escuta o mouse |

O `StateMachine` do framework cuida do fluxo de telas (briefing → jogo →
resultado). A regra da partida fica fora dele de propósito: `Mission` é
`RefCounted` e roda sem cena, que é o que permite o bot jogar as seis fases
milhares de vezes mais rápido que tempo real.

## Testes

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path 06-jogo-incendio --script res://tests/run_tests.gd
```

254 asserções, em três camadas:

1. **Unidade** — cada regra do autômato isolada, com número: não "o vento
   espalha mais", e sim "a favor do vento a frente anda pelo menos 1,8× mais
   rápido".
2. **Comportamento** — o brigadista recua do calor; a ordem inalcançável expira;
   o morador só foge do que percebe; quem foge escolhe o abrigo frio.
3. **Level design** — o bot vence as seis fases, **e** quem não faz nada perde
   as seis. A segunda metade é a que se esquece: uma fase que se resolve sozinha
   passa despercebida porque o bot também "vence" nela. Foi um bug real — a
   "encosta" nasceu com o povoado já cercado de terra batida no ASCII.

Num sistema com regras que se realimentam, a regressão perigosa não é a exceção,
é o **equilíbrio**: ninguém quebra a propagação do fogo por acidente; o que se
quebra por acidente é a relação entre quanto tempo o capim queima e quanto tempo
ele leva pra acender o vizinho.

Ferramentas de balanceamento, fora da suíte:

```bash
# mede a velocidade da frente em cada condição
... --headless --path 06-jogo-incendio --script res://tests/calibrate.gd
# põe o bot pra jogar as seis fases e reporta o placar
... --headless --path 06-jogo-incendio --script res://tests/playtest.gd
# acompanha uma fase segundo a segundo, desenhando o vale em ASCII
... --headless --path 06-jogo-incendio --script res://tests/diagnose.gd
```

Capturas de tela automatizadas (em `.visual_capture/`, fora do git):

```bash
Godot_v4.7.1-stable_win64_console.exe --path 06-jogo-incendio --script res://tests/visual_capture.gd
```

## Três bugs que valeram o preço

- **O aceiro demolia a casa.** `can_dig` só perguntava "isso queima?", e casa
  queima. O brigadista derrubava a casa pra impedir que ela pegasse fogo, o
  total de casas caía, e a fase virava impossível por um motivo que não aparecia
  em lugar nenhum na tela.
- **A previsão morria em dois níveis.** Os custos eram calculados em float64 e
  guardados num `PackedFloat32Array`; o arredondamento fazia a comparação
  `custo > registrado` disparar por um milionésimo de segundo, e o Dijkstra
  descartava a célula como já visitada. O overlay dizia "o fogo nunca chega"
  para o vale quase inteiro — a mentira mais perigosa que este jogo pode contar.
- **O clique saiu do lugar.** Centralizar mapas menores que a tela mexeu no
  offset de desenho e não no de clique. O jogador cavava algumas células ao lado
  de onde tinha clicado, e nada explicava por quê. Hoje os dois usam a mesma
  função, e um teste compara clique com desenho.

## Créditos de arte

Todos CC0, de [Kenney.nl](https://kenney.nl):

- **Tiny Town** — chão, terra, mato, lavoura, árvores e casas.
- **Roguelike Characters** — o paper doll dos brigadistas e moradores.
- **Kenney Fonts** — `Kenney Pixel.ttf`.

Fogo, fumaça, brasa, água, rocha, bússola e minimapa são desenhados por código:
nenhum pack trazia fogo em pixel art que casasse com o Tiny Town, e fogo parado
seria a pior coisa possível num jogo cujo assunto é o fogo se mexendo.
