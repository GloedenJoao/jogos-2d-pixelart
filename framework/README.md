# Framework compartilhado

Sistemas reutilizáveis entre todos os jogos deste diretório. Estruturar como addon Godot (`res://addons/framework/`) dentro de cada projeto, ou como projeto Godot próprio que os outros importam — decidir isso no dia 1–15 do plano (`docs/plano-90-dias.md`).

Sistemas planejados, em ordem de construção:

1. **SceneManager** — troca de cenas com transição (fade in/out).
2. **SaveSystem** — salvar/carregar progresso em JSON local.
3. **StateMachine** — máquina de estados genérica (reaproveitável pra player, inimigos, fluxo de jogo).
4. **AudioManager** — tocar música/SFX com controle de volume, persistente entre cenas.
5. **UITheme** — tema visual pixel art consistente (fonte, botões, painéis) pra todos os jogos.

Ainda vazio — começa a ser preenchido no dia 1 do plano.
