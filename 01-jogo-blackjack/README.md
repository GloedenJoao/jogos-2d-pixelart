# Projeto 1 — Blackjack

Ver `docs/plano-90-dias.md` pro cronograma (dias 16–40, escopo original era puzzle, substituído por blackjack a pedido do João).

Status: jogável. Loop completo de blackjack (21) contra o dealer:

- Apostar fichas (ajustável em incrementos de 10), pedir/parar/dobrar, dealer joga sozinho (para em 17).
- Blackjack natural paga 3:2, vitória simples paga 1:1, empate devolve a aposta.
- Saldo de fichas, última aposta e estatísticas (mãos jogadas/vencidas, melhor saldo) persistem via `SaveSystem` do framework.
- Usa `StateMachine` do framework pras fases da rodada (Betting → PlayerTurn → DealerTurn → Resolve) e `UITheme`/`AudioManager` pro visual e volume.
- Arte do Kenney Playing Cards Pack (`assets/cards/`) e pixel font Kenney Pixel (`assets/fonts/`), ambos CC0. Cartas renderizadas via `TextureRect` (ver `Card.sprite_name()` em `scripts/card.gd` e `_build_card_node()` em `scenes/main.gd`).
- Polimento visual: cartas "caem" na mesa com animação de escala/fade ao serem distribuídas, aposta é representada por uma pilha de fichas coloridas (100/50/10) além do número, mesas do dealer/jogador ganharam painel com borda, e um botão "Estatísticas" abre um overlay com mãos jogadas/vencidas e melhor saldo (lidos do `SaveSystem`).

Testes headless: `tests/run_tests.gd` (28 asserções — Card/Hand/Deck/RoundResolver + fluxo completo de rodadas via `main.tscn`).

```powershell
& "C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
```

Validação visual automatizada: `tests/visual_capture.gd` (força cenários-chave — apostando, meio da rodada, blackjack resolvido, overlay de estatísticas — igual aos testes headless, e salva screenshots em `.visual_capture/*.png`). É o jeito **padrão** de checar layout/UI agora, sem abrir o editor nem usar computer-use — só usar computer-use pra casos genuinamente interativos (testar uma animação em movimento, por exemplo).

```powershell
# Só na primeira vez num checkout/worktree novo (gera o cache de import/classes globais; sem isso "Card"/"Hand"/"Deck" não resolvem em --script):
& "...\Godot_v4.7.1-stable_win64_console.exe" --path . --headless --import

# Captura (roda em segundos, sem clique nenhum, o processo fecha sozinho):
& "...\Godot_v4.7.1-stable_win64_console.exe" --path . --script res://tests/visual_capture.gd
```

Depois é só ler os PNGs de `.visual_capture/` direto com a ferramenta de leitura de arquivo. Pra adicionar um novo cenário, copiar o padrão de uma função `_capture_*()` existente (força o save/deck, chama o método do estado direto tipo `on_deal()`/`on_stand()`, espera os `await` necessários, e chama `_shoot("nome")`).
