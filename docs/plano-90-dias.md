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
- **Feito** (2026-08-04): corrida de 5 andares com dificuldade crescente, 5 tipos de criatura com atributos próprios + chefe no último andar, e meta-progressão de verdade (acampamento com 4 upgrades permanentes comprados com o ouro acumulado). 97 testes headless.
- Falta só o lançamento no itch.io (pay-what-you-want) — depende de conta/upload do João.

## Dias 66–90 — Projeto 3: platformer (`03-jogo-platformer`)

- **Feito** (2026-08-04): "Andarilho das Eras" — três fases/eras, cada uma introduzindo uma mecânica de movimento (pulo → pulo duplo → dash), com física de plataforma completa (coyote time, buffer de pulo, pulo variável), state machine de animação, câmera com limites, checkpoints, corações, inimigos de patrulha e gemas. 80 testes headless, incluindo um bot que precisa terminar as três fases (regressão de level design).
- A decisão original era "aprofundar o roguelike ou avançar": os dois foram feitos, o roguelike ganhou o conteúdo que faltava e o platformer saiu.

## Depois dos 90 dias — Projeto 4: civilização (`04-jogo-civilizacao`)

- **Feito** (2026-08-04): "Eras da Civilização" — o clicker original como jogo pixel art completo, com 5 eras (state machine de eras), 15 construções com custo crescente e produção automática, virada de era que consome recursos, progresso offline e save automático. 93 testes headless.

## Próximos passos

1. Publicar os builds no itch.io (blackjack, roguelike, platformer, civilização) — é o gargalo do plano hoje, e depende do João criar/usar a conta.
2. Áudio nos quatro jogos (o `AudioManager` do framework está pronto, faltam os sons).
3. Medir tração no itch.io e escolher onde investir conteúdo; Google Play depois, com a conta de dev já paga.

## Métrica de sucesso realista

Jogo indie mediano na Steam faturou $249 em 2025. Os primeiros projetos são sobre aprendizado, portfólio e testar o framework — não espere renda significativa antes do 3º ou 4º jogo publicado.
