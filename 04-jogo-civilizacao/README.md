# Projeto 4 — Eras da Civilização

O clicker de civilização do João virando jogo pixel art de verdade, em cima do framework já testado nos projetos 1–3. Ver `docs/temas-e-evolucao.md` e `docs/plano-90-dias.md`.

Status: jogável do começo (Idade da Pedra) ao fim (Era da Informação).

## O que tem

- **Cinco eras** (`scripts/eras.gd`): Idade da Pedra → Agricultura → Era Antiga → Era Industrial → Era da Informação. Cada era muda paleta, cenário da vila, o que um clique rende e quanto ele rende, e libera três construções novas.
- **Máquina de estados de eras**: uma `EraState` por era dentro do `StateMachine` do framework — entrar num estado é o que reconfigura cenário, botões de coleta e lista de construções.
- **15 construções** (`scripts/buildings.gd`), 3 por era, cada uma com custo crescente (×1,15 por cópia, padrão de jogo idle) e produção por segundo de comida, materiais e/ou conhecimento.
- **Economia inteira sem dependência de cena** (`scripts/economy.gd`): estoque, produção por segundo, custo das construções, requisito e consumo da virada de era, progresso da era e formatação de números grandes (1.5k, 2.5M). Isso é o que deixa o jogo testável headless.
- **Virada de era com custo**: passar de era consome os recursos exigidos — a civilização investe tudo na virada.
- **Progresso offline**: ao abrir o jogo, o tempo desde o último save vira produção (com teto de 8 horas), e o jogo avisa quanto rendeu.
- **Save automático** a cada 10 s e a cada compra/virada, via `SaveSystem` do framework.
- **Vila que cresce na tela**: cada construção comprada vira sprite no cenário (com teto de ícones pra não virar sopa de sprites), junto com a decoração da era.
- **Custos e produção coloridos por recurso**: cada preço/ganho na loja usa a cor do recurso (verde=comida, laranja=materiais, azul=conhecimento), pra ler rápido sem precisar decifrar texto corrido.
- **Painel de recursos "vivo"**: cada recurso tem uma barra de pips que enche em escala logarítmica com o estoque, mais um nome de nível ("vazio" → "início" → ... → "riqueza"), simulando visualmente o mundo crescendo junto com o número.
- **Compra em lote (×1/×10/×25/Máx)**: seletor de multiplicador no topo da loja; "Máx" calcula quantas cópias dá pra comprar de uma vez com o estoque atual (`Economy.max_affordable`).

## Arte

- Kenney **Tiny Town** (CC0) — `assets/town/tilemap_packed.png`: construções, ferramentas e cenário.
- **Reaproveitamento do Projeto 2**: o tileset Kenney Tiny Dungeon (`assets/dungeon/tilemap_packed.png`, o mesmo do roguelike) fornece os ícones das eras primitivas (aldeão coletor, fogueira do clã, escriba).
- Fonte Kenney Pixel e `UITheme`, os mesmos dos projetos 1–3. Créditos em `assets/CREDITOS.md` na raiz.

## Testes

`tests/run_tests.gd` — 104 asserções headless:

- catálogos (5 eras, 15 construções, 3 novas por era, construções cumulativas);
- clique manual (rende conforme a era, recurso bloqueado antes da era certa);
- produção por segundo, `tick()` e acúmulo de tempo;
- custo crescente, compra debitando recursos e construção travada por era;
- compra em lote (`cost_of_n`/`buy_n`/`max_affordable`), inclusive pela UI com o seletor ×10/xMáx;
- virada de era: requisito, progresso, consumo e recusa na última era;
- progresso offline (inclusive o teto de 8 h e tempo negativo);
- salvar/carregar, com id desconhecido ignorado e era fora do intervalo limitada;
- cena: boot, botões de coleta por era, construir pela UI, virada de era com overlay, reabrir o jogo já na era salva e produção offline aplicada ao carregar.

```powershell
& "C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
```

Validação visual: `tests/visual_capture.gd` gera 4 PNGs em `.visual_capture/` (gitignored) — começo na Idade da Pedra, vila crescendo na Agricultura, overlay de virada de era e a Era da Informação com a civilização inteira produzindo.

## O que falta

- Áudio e efeitos de clique (o `AudioManager` do framework está pronto).
- Conquistas/marcos e eventos históricos por era, se o jogo mostrar tração.
- Export web/Android e publicação (itch.io primeiro, Google Play depois).
