# Temas de jogos e evolução de complexidade

A ideia é cada jogo novo introduzir 1–2 sistemas novos, sempre em cima do `framework/` compartilhado, pra você ir empilhando capacidade sem reescrever o que já funciona.

## Projeto 1 — Blackjack (mais simples)

**Decisão do João (2026-08-03):** trocou o puzzle de restauração de artefatos original por um jogo de blackjack (21) contra o dealer. Motivo: preferência direta do João, feita pra ser aproveitada/melhorada nos jogos seguintes (mesma lógica do plano — introduzir sistemas reutilizáveis).

**Sistemas novos:** lógica de baralho/mão (`Card`/`Deck`/`Hand`/`RoundResolver`), state machine de fases de rodada usando o `StateMachine` do framework (Betting → PlayerTurn → DealerTurn → Resolve), HUD de fichas/aposta, save de saldo e estatísticas.

As ideias de puzzle abaixo ficam registradas caso um projeto puzzle entre no roadmap mais pra frente: um "restaurador de artefatos" (encaixar peças/cores/símbolos pra reconstruir um item antigo), puzzle de jardim (arrumar plantas por cor/tipo), ou puzzle de constelações (conectar estrelas em ordem).

## Projeto 2 — Mini roguelike

**Tema sugerido:** conecta com o que você já gosta — um roguelike de "sobrevivente pré-histórico": desce numa caverna, cada run gera salas com recursos, perigos e pequenos combates, upgrades permanentes entre runs (linkando com a ideia de progressão de civilização que você já tinha).

Alternativas: roguelike de explorador de ruínas, roguelike de alquimista coletando ingredientes.

**Sistemas novos:** geração procedural de mapas, combate simples, inventário, progressão entre runs (meta-progressão), IA básica de inimigo.

## Projeto 3 — Platformer/metroidvania leve

**Tema escolhido e implementado:** "Andarilho das Eras" — atravessa cenários de períodos diferentes (caverna → vila antiga → cidade industrial), e cada era entrega uma mecânica de movimento nova: pulo simples, depois pulo duplo, depois dash. Os vãos das fases crescem junto com a mecânica, então a habilidade nova é obrigatória, não decorativa.

**Sistemas novos:** física de plataforma (gravidade, coyote time, buffer de pulo, pulo variável), máquina de estados de animação (Idle/Run/Jump/Fall/Dash), câmera que segue o player com limites, checkpoints e respawn.

**Aprendizado que valeu a viagem:** fases escritas como mapa ASCII + um bot que joga a fase inteira nos testes. Se um mapa novo ficar impossível (ou o jogador bater a cabeça numa plataforma no meio de um pulo obrigatório), o teste quebra antes de alguém jogar.

## Projeto 4 — Civilização (o grande projeto)

**Implementado como "Eras da Civilização":** o clicker vira jogo pixel art completo, com cinco eras (Idade da Pedra → Agricultura → Antiga → Industrial → Informação), 15 construções que produzem sozinhas, custo crescente, virada de era que consome os recursos acumulados e progresso enquanto o jogo está fechado.

**Sistemas que reaproveita de tudo antes:** save/load e state machine (agora guardando eras), UITheme e fonte dos projetos 1–3, e o tileset Tiny Dungeon do Projeto 2 nos ícones das eras primitivas — exatamente a ideia de empilhar capacidade em vez de recomeçar.

## Projeto 5 e 5 V2 — Colônia Viva

**Implementado:** colony sim onde o mundo ocupa a tela inteira e cada morador decide sozinho o que fazer. O V2 refez os moradores (arte modular recolorida por pessoa, animação por partes, A* com trilhas de pisoteio, sete ações autônomas).

**Sistemas novos:** IA de utilidade multi-agente, pathfinding com custo emergente, composição de sprite em tempo de execução.

## Projeto 6 — O Vale em Chamas

**Escolhido pelo João em 2026-08-08**, de um cardápio de oito temas (táticas por turnos, tower defense, comércio, simulação sistêmica, puzzle de tempo, deck-building, ritmo, narrativa sistêmica). Ele pediu explicitamente que cada opção descrevesse o *sistema novo*, não o gênero — e escolheu o que mais acrescentava ao repertório: **simulação sistêmica**.

**Implementado:** um incêndio atravessa um vale habitado e você o contém com aceiro, água e contra-fogo. Seis fases, cada uma ensinando uma regra do sistema.

**Sistemas novos:** autômato celular determinístico (calor, vento, relevo, umidade, combustível, faíscas), agentes que reagem a um *campo* em vez de a um script, e previsão por Dijkstra sobre o estado atual — a ferramenta que transforma o jogo de reação em planejamento.

**O que ele quebrou primeiro:** o equilíbrio, não a lógica. Num sistema com regras que se realimentam, ninguém quebra a propagação do fogo por acidente — quebra-se a relação entre "quanto tempo o capim queima" e "quanto tempo ele leva pra acender o vizinho". Daí a lição que virou método: constante de simulação se calibra com medição, e a medição vira asserção.

## Por que essa ordem

Cada projeto é propositalmente mais complexo que o anterior, mas nunca pula um degrau: blackjack não tem física nem IA de verdade (o dealer só segue uma regra fixa), então é o warm-up mais seguro. Roguelike introduz geração procedural e combate, mas ainda em grid/top-down simples. Platformer introduz física real, que é mais imprevisível e trabalhosa. O projeto de civilização é o mais ambicioso porque puxa sistemas de economia, múltiplas eras e produção automática — só vale tentar depois que os fundamentos (save, state machine, UI) já foram validados em jogos menores e reais, publicados e testados por outras pessoas.
