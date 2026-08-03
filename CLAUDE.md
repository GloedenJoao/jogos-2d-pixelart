# Contexto do projeto — jogos-2d-pixelart

Este arquivo é pra qualquer sessão do Claude (Code ou Cowork) que abrir este diretório entender o estado atual sem precisar reperguntar tudo.

## Objetivo

João quer gerar renda publicando jogos 2D pixel art, começando simples e evoluindo pra jogos mais complexos, reaproveitando um framework compartilhado em Godot. Plano completo em `docs/plano-90-dias.md` e ideias de tema em `docs/temas-e-evolucao.md`.

## Estado atual (2026-08-03)

- [x] Estrutura de pastas criada (`framework/`, `01-jogo-puzzle/`, `02-jogo-roguelike/`, `03-jogo-platformer/`, `04-jogo-civilizacao/`, `assets/`, `docs/`).
- [x] Plano de 90 dias e documento de temas escritos.
- [x] **Repositório git próprio e independente** (não faz mais parte do monorepo `projetos_claude`), publicado em https://github.com/GloedenJoao/jogos-2d-pixelart (público), branch `main`.
- [x] **Godot 4.7.1 (Standard) instalado via winget** (`GodotEngine.GodotEngine`). Não está no PATH deste shell — usar o caminho completo do exe (`C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe`) até reabrir o terminal.
- [x] **Projeto Godot criado em `framework/`** com os 5 sistemas implementados (`addons/framework/`, estruturado como addon Godot): SceneManager, SaveSystem, StateMachine, AudioManager, UITheme. Ver `framework/README.md` pra detalhes de cada um.
- [x] **Marco dos dias 1–15 atingido**: `framework/scenes/menu.tscn` é uma tela de menu funcional (título, melhor pontuação, sliders de volume, Jogar/Sair) que usa os 4 autoloads do framework. Validado rodando o projeto headless via Godot CLI — sobe sem erros e grava `user://save.json` corretamente. StateMachine ainda não tem uso concreto (é pra entidades de jogo, que só aparecem no Projeto 1).
- [ ] Ninguém abriu o projeto no editor Godot ainda (só validado via linha de comando/headless) — vale abrir visualmente antes de seguir.
- [ ] Nenhum asset baixado ainda em `assets/` — UITheme usa fonte padrão do Godot, trocar por pixel font depois.
- [ ] Conta de developer do Google Play já está paga (não é bloqueador).
- [ ] itch.io não requer conta paga nem aprovação — pode publicar quando tiver o primeiro build.

## O que falta fazer, em ordem

1. Abrir `framework/` no editor Godot pra conferir visualmente o menu (só foi validado headless até agora).
2. Copiar `framework/addons/framework/` pro projeto do `01-jogo-puzzle/` (criar o projeto Godot lá) e ativar o plugin. Começar o jogo puzzle em si (ver `docs/plano-90-dias.md`, dias 16–40).
3. Baixar assets pixel art (Kenney.nl) em `assets/` conforme forem necessários — inclui uma fonte pixel pra plugar no UITheme.

## Decisões já tomadas (não reabrir sem motivo)

- Engine: Godot (grátis, sem royalties, bom export web/Android, GDScript acessível pra quem já programa).
- Publicação: itch.io primeiro (grátis, pay-what-you-want) → Google Play depois do jogo validado.
- Arte: pixel art gratuita/CC0 (Kenney.nl) nos primeiros projetos, sem orçamento pra contratar artista por enquanto.
- Ordem dos jogos: puzzle → roguelike → platformer → civilização, cada um introduzindo só 1–2 sistemas novos em cima do framework.

## Perguntas em aberto pro João decidir depois

- Tema definitivo do Projeto 1 (puzzle) — há sugestões em `docs/temas-e-evolucao.md`, mas não está fechado.
- Se vai programar em GDScript ou C# dentro do Godot.
