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
