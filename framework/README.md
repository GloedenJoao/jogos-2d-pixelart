# Framework compartilhado

Sistemas reutilizáveis entre todos os jogos deste diretório. Estruturado como addon Godot em `addons/framework/` — cada jogo novo copia (ou symlinka) essa pasta pro seu próprio projeto e ativa o plugin em Project Settings → Plugins, o que já registra os 4 autoloads automaticamente.

Este diretório também é, em si, um projeto Godot 4.7 completo e executável — serve de sandbox pra testar o framework isoladamente antes de usá-lo nos jogos.

## Sistemas implementados

1. **SceneManager** (`addons/framework/scene_manager.gd`) — autoload. Troca de cenas com fade in/out via `SceneManager.change_scene("res://caminho/cena.tscn")`.
2. **SaveSystem** (`addons/framework/save_system.gd`) — autoload. Save/load em JSON local (`user://save.json`) via `SaveSystem.set_value()` / `get_value()` / `save_data()`.
3. **StateMachine** (`addons/framework/state_machine.gd` + `state.gd`) — classes globais (`StateMachine`, `State`), não autoload. Reaproveitável pra player, inimigos, fluxo de jogo — ainda sem uso concreto porque não existe entidade de jogo até o Projeto 1.
4. **AudioManager** (`addons/framework/audio_manager.gd`) — autoload. Música/SFX com buses de volume dedicados via `AudioManager.play_music()` / `play_sfx()` / `set_music_volume()` / `set_sfx_volume()`.
5. **UITheme** (`addons/framework/ui_theme.gd`) — autoload. Gera um `Theme` pixel-art (bordas retas, cantos sem arredondamento) programaticamente em `UITheme.theme` — ainda usando fonte padrão do Godot, trocar por fonte pixel quando tiver assets baixados em `assets/`.

## Cena de demonstração

`scenes/menu.tscn` é a cena principal do projeto (`run/main_scene`) e prova que o framework carrega e funciona: título, melhor pontuação (via SaveSystem), sliders de volume (via AudioManager, persistidos via SaveSystem), botão Jogar (transição via SceneManager pra `scenes/em_breve.tscn`) e botão Sair. Tudo estilizado pelo UITheme. Testado headless com o Godot 4.7.1 — sobe sem erros e grava o save corretamente.

Isso cumpre a meta do marco dos dias 1–15 do plano: "um projeto Godot vazio que já carrega o framework e mostra uma tela de menu funcional".

## Próximo passo

Abrir este projeto no editor Godot pra conferir visualmente, trocar a fonte padrão por uma pixel (quando houver assets), e depois copiar `addons/framework/` pro projeto do `01-jogo-puzzle/`.
