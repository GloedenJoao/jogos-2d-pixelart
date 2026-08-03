# Contexto do projeto — jogos-2d-pixelart

Este arquivo é pra qualquer sessão do Claude (Code ou Cowork) que abrir este diretório entender o estado atual sem precisar reperguntar tudo.

## Objetivo

João quer gerar renda publicando jogos 2D pixel art, começando simples e evoluindo pra jogos mais complexos, reaproveitando um framework compartilhado em Godot. Plano completo em `docs/plano-90-dias.md` e ideias de tema em `docs/temas-e-evolucao.md`.

## Estado atual (2026-08-03)

- [x] Estrutura de pastas criada (`framework/`, `01-jogo-puzzle/`, `02-jogo-roguelike/`, `03-jogo-platformer/`, `04-jogo-civilizacao/`, `assets/`, `docs/`).
- [x] Plano de 90 dias e documento de temas escritos.
- [x] Diretório versionado no git (repo em `A:\Users\joaog\Projetos_Claude`, commit inicial na branch `main`).
- [x] **Godot 4.7.1 (Standard) instalado via winget** (`GodotEngine.GodotEngine`). Alias `godot` no PATH — pode precisar reabrir o terminal para reconhecer.
- [ ] Nenhum projeto Godot foi criado ainda dentro das pastas — só READMEs placeholder.
- [ ] `framework/` está vazio, só tem o README com a lista do que precisa ser construído.
- [ ] Nenhum asset baixado ainda em `assets/`.
- [ ] Conta de developer do Google Play já está paga (não é bloqueador).
- [ ] itch.io não requer conta paga nem aprovação — pode publicar quando tiver o primeiro build.

## O que falta fazer, em ordem

1. Rodar o tutorial oficial "Your First 2D Game" do Godot pra se familiarizar com o editor.
2. Criar o projeto Godot dentro de `framework/` e começar pelos sistemas na ordem listada em `framework/README.md`: SceneManager → SaveSystem → StateMachine → AudioManager → UITheme.
3. Só depois disso, começar `01-jogo-puzzle/` (ver `docs/plano-90-dias.md`, dias 16–40).

## Decisões já tomadas (não reabrir sem motivo)

- Engine: Godot (grátis, sem royalties, bom export web/Android, GDScript acessível pra quem já programa).
- Publicação: itch.io primeiro (grátis, pay-what-you-want) → Google Play depois do jogo validado.
- Arte: pixel art gratuita/CC0 (Kenney.nl) nos primeiros projetos, sem orçamento pra contratar artista por enquanto.
- Ordem dos jogos: puzzle → roguelike → platformer → civilização, cada um introduzindo só 1–2 sistemas novos em cima do framework.

## Perguntas em aberto pro João decidir depois

- Tema definitivo do Projeto 1 (puzzle) — há sugestões em `docs/temas-e-evolucao.md`, mas não está fechado.
- Se vai programar em GDScript ou C# dentro do Godot.
