# Projeto 3 — Andarilho das Eras (platformer)

Platformer 2D pixel art em Godot 4, terceiro projeto do plano (`docs/plano-90-dias.md`, dias 66–90). Tema conforme `docs/temas-e-evolucao.md`: um andarilho atravessa três eras, e cada era entrega uma mecânica de movimento nova.

Status: jogável de ponta a ponta (3 fases, começo → fim).

## O que tem

- **Física de plataforma** (`scripts/player.gd`): gravidade, aceleração/atrito separados para chão e ar, pulo variável (soltar o botão corta a subida), *coyote time* (0,12 s pra pular depois de sair da borda) e *buffer* de pulo (0,12 s pra apertar antes de pousar).
- **Máquina de estados de animação** usando o `StateMachine` do framework: `Idle`, `Run`, `Jump`, `Fall`, `Dash` (`scripts/states/player_*.gd`), cada um decidindo transições e sprite.
- **Três eras com mecânica cumulativa** (`scripts/levels.gd`):
  1. *Era da Caverna* — andar e pular; vãos de até 3 tiles.
  2. *Era da Vila Antiga* — **pulo duplo**; vãos de até 5 tiles.
  3. *Era da Indústria* — **dash**; vãos de até 7 tiles.
  Cada era troca paleta, tileset e tipo de inimigo.
- **Fases em mapa ASCII** (`scripts/level_data.gd`): `#` sólido, `P` spawn, `E` porta, `G` gema, `^` espinho, `F` checkpoint, `M` inimigo. Fáceis de editar e de testar sem abrir o editor.
- **Câmera** que segue o andarilho com suavização e limites do mapa (zoom 3 sobre tiles de 18 px).
- **Checkpoints, corações e respawn**: 3 corações por era; espinho, inimigo ou queda no vazio custam um coração e devolvem o jogador ao último checkpoint; sem corações, a era recomeça.
- **Inimigos de patrulha** (`scripts/enemy.gd`): andam num posto de ±3 tiles, viram na parede/beirada, e podem ser derrotados com pisão (o jogador quica).
- **Progresso salvo** via `SaveSystem`: era alcançada, quedas, conclusão do jogo e melhor total de gemas.
- **Modo demo** (tecla `B`): o `DemoBot` assume o controle e joga sozinho — o mesmo bot usado nos testes.

Controles: `A`/`D` ou setas para andar, `Espaço`/`W` para pular, `Shift`/`J` para dash, `R` reinicia a era, `B` liga/desliga o modo demo.

## Testes

`tests/run_tests.gd` — 80 asserções headless, incluindo física de verdade (o teste roda frames de física e controla o jogador como um humano faria):

- parser de mapa, sanidade dos três mapas, habilidades por era;
- gravidade/pouso, caminhada, direção do sprite e estados de animação;
- altura do pulo, pulo duplo só a partir da era 2, dash só na era 3;
- coleta de gema, dano de espinho com respawn no checkpoint, pisão em inimigo, queda pra fora do mapa;
- conclusão de era, conclusão do jogo e persistência no `SaveSystem`;
- **cada era é terminável**: o `DemoBot` precisa chegar na porta das três fases sem perder todos os corações (regressão de level design — se um mapa novo ficar impossível, o teste quebra).

```powershell
& "C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/run_tests.gd
```

Diagnóstico de level design: `tests/bot_debug.gd` imprime o trajeto do bot e em que coluna ele empaca.

Validação visual: `tests/visual_capture.gd` gera 6 PNGs em `.visual_capture/` (gitignored) — as três eras em gameplay real (dirigidas pelo bot), plataformas de gema, era concluída e fim da jornada.

## Arte

Kenney "Pixel Platformer" (CC0): `assets/platformer/tilemap_packed.png` (tiles 18×18) e `tilemap-characters_packed.png` (personagens 24×24). Fonte Kenney Pixel, a mesma dos projetos 1 e 2. Créditos em `assets/CREDITOS.md` na raiz.

## O que falta

- Áudio (o `AudioManager` do framework está pronto, faltam os sons).
- Mais fases por era e chefes, se o jogo mostrar tração.
- Publicar no itch.io junto com os projetos 1 e 2.
