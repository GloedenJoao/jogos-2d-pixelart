# Testes headless

`run_tests.gd` é um test runner simples (sem addon externo) que instancia as cenas, simula interações e valida o framework via linha de comando, sem precisar abrir o editor.

Rodar:

```powershell
& "C:\Users\joaog\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.1-stable_win64_console.exe" --headless --path "caminho\para\framework" --script res://tests/run_tests.gd
```

Sai com código 0 se tudo passou, 1 se algo falhou — dá pra usar em CI depois.

## Detalhe técnico

Scripts customizados de main loop (`extends SceneTree`) só têm os autoloads (SceneManager, SaveSystem, AudioManager, UITheme) disponíveis **depois do primeiro `await process_frame`** — antes disso o compilador nem reconhece os nomes. Por isso `_initialize()` sempre começa com `await process_frame` antes de qualquer coisa que toque nos autoloads.

Sliders com `step` definido arredondam o valor pro múltiplo mais próximo — testes que setam `.value` direto precisam usar um valor já alinhado ao step, senão a asserção de igualdade falha por um motivo que não é bug.
