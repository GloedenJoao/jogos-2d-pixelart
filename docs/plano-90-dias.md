# Plano de 90 dias — jogos 2D pixel art em Godot

Perfil: programador sem experiência em engine, foco sério, sem orçamento, conta de dev do Google Play já paga.

## Stack

- **Engine:** Godot 4 (grátis, sem royalties, GDScript parecido com Python, export leve pra web e Android).
- **Arte:** pixel art gratuita (Kenney.nl, licença CC0) até você (ou alguém contratado depois) produzir arte própria.
- **Publicação:** itch.io primeiro (grátis, zero aprovação, pay-what-you-want) → Google Play depois, só com jogo validado.

## Dias 1–15 — Fundamentos + framework base

- Tutorial oficial "Your First 2D Game" do Godot.
- Criar o `framework/` deste diretório com os sistemas que todo jogo vai reaproveitar:
  - Gerenciador de cenas/transições
  - Sistema de save/load (JSON local)
  - State machine genérica (pra player, inimigos, jogo)
  - Gerenciador de áudio (música + SFX com volume configurável)
  - Tema de UI consistente (fonte pixel, botões, painéis)
- Meta do marco: um projeto Godot vazio que já carrega o framework e mostra uma tela de menu funcional.

## Dias 16–40 — Projeto 1: blackjack (`01-jogo-blackjack`)

- Escopo mínimo: loop completo de blackjack (21) contra o dealer — apostar, pedir/parar/dobrar, dealer joga sozinho, resolução (blackjack 3:2, vitória 1:1, empate). Substituiu o puzzle original de restauração de artefatos (decisão do João, ver `docs/temas-e-evolucao.md`).
- Objetivo de aprendizado: input handling, HUD, state machine de fases de jogo, salvar saldo/estatísticas usando o framework.
- Publicar early build no itch.io como devlog assim que a arte de cartas estiver pronta (hoje as cartas são placeholder de código, sem assets).

## Dias 41–65 — Projeto 2: mini roguelike (`02-jogo-roguelike`)

- Escopo: dungeon crawler top-down curto, geração procedural simples, combate básico, inventário pequeno.
- Objetivo de aprendizado: geração procedural, IA simples de inimigo, sistemas de progressão (upgrades entre runs), reaproveitar state machine e save do framework.
- Esse é o projeto que deve ir a lançamento completo no itch.io (pay-what-you-want) até o dia 65.

## Dias 66–90 — Decisão: aprofundar ou avançar

- Medir o roguelike: downloads, % que pagou, feedback qualitativo.
- Se teve tração: investir mais conteúdo nele (novas áreas, chefes, versão Android via conta já paga do Google Play).
- Se não teve tração relevante: seguir pro Projeto 3 (`03-jogo-platformer`), que introduz física e animação — mais complexo, mais caro em tempo, então só vale investir depois de já ter 1-2 jogos publicados e algum aprendizado de mercado.

## Depois dos 90 dias

- `04-jogo-civilizacao`: reconstrução do seu clicker de civilização original, agora como jogo pixel art completo, usando o framework maduro (state machine pra eras, save system, UI). Esse é o projeto mais ambicioso da lista — só faz sentido depois que o framework já foi testado em 2-3 jogos menores.

## Métrica de sucesso realista

Jogo indie mediano na Steam faturou $249 em 2025. Os primeiros projetos são sobre aprendizado, portfólio e testar o framework — não espere renda significativa antes do 3º ou 4º jogo publicado.
