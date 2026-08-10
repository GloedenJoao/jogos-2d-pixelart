# Projeto 7 — "Reino em Construção" (nome provisório)

City-builder de sobrevivência e automação inspirado em Timberborn: explorar um mapa físico, extrair recursos finitos, transportar com NPCs carregadores, processar e sustentar população e energia. Combate fica fora do escopo por decisão explícita do João. Design completo em [`docs/plano-projeto7-reino.md`](../docs/plano-projeto7-reino.md), incluindo a quebra em fases.

## Estado atual: Fase 0 — fundação técnica

Sem jogo pra jogar ainda. A Fase 0 existe pra provar, antes de desenhar qualquer tela, que a mecânica mais nova e mais arriscada do design — **água como simulação de fluxo, não depósito estático** — funciona de verdade.

- [`scripts/water_sim.gd`](scripts/water_sim.gd) — autômato de água em grade: cada célula tem altura de terreno (fixa) e volume de água; a água escoa entre vizinhos ortogonais até equalizar a *superfície* (altura + água), não o volume — como vasos comunicantes de verdade. Cavar canal é só baixar a altura de uma célula (`set_height`); represar/abrir comporta é `set_blocked`. Conservação de volume é uma garantia do modelo, testada explicitamente.
- Arquitetura sem dependência de cena (`RefCounted`, como `FireSim` do Projeto 6), pra caber inteira em testes headless.
- [`tests/run_tests.gd`](tests/run_tests.gd) — 30 asserções: escoamento até equalizar, água represando atrás de muro alto e atravessando depois de cavar canal, represa/comporta, conservação de volume em terreno plano/irregular/com represa, ausência de água negativa ou dentro de parede, independência do tamanho do frame, delta gigante não trava a simulação.
- [`tests/calibrate.gd`](tests/calibrate.gd) — mede (não chuta) o tempo de acomodação: duas células planas com desnível de 10 chegam a menos de 0.01 de diferença em 1 segundo (10 passos); um corredor de 20 células leva ~7.5s pra água perceptível alcançar a ponta oposta. `FLOW_RATE = 0.5` foi escolhido a partir dessa medição — rápido o bastante pra "abrir um canal" parecer responsivo, devagar o bastante pra dar pra VER a água escoando em vez de piscar de um estado pro outro.

Sem visual ainda — a Fase 1 (mapa, relevo, exploração) é onde este autômato ganha uma tela em cima.

## Rodar os testes

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/run_tests.gd
```

(No Windows deste projeto, o caminho completo do executável está registrado no `CLAUDE.md` da raiz do repositório.)

Para medir os tempos de acomodação em vez de rodar a suíte:

```bash
Godot_v4.7.1-stable_win64_console.exe --headless --path . --script tests/calibrate.gd
```
