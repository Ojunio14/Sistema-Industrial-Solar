# Evidências — Etapa 5

Godot 4.6.1 stable, Windows, Vulkan Forward+, AMD Radeon Vega 3, seed 73129.
Artefatos produzidos pelos runners em `tests/planet`, sem operações Git.

- `validation/`: importação, cena principal, câmeras, fundação, quadtree,
  terreno base/integrado, geologia, clima e fingerprints entre processos.
- `visual/`: capturas reais do renderer para seis hemisférios, macroformas,
  geologia, dez biomas representativos, sombras/áreas secas e úmidas, borda
  entre faces, afastamento e modos F6. `out.log` confirma convergência por pose.
- `baseline-profile.json` e `climate-profile.json`: mesma rota gráfica,
  2.580 updates, warmup orbital separado, 1100×760, geologia ligada,
  SSE/budgets idênticos; apenas o clima difere.
- `climate-peak-detail.json`: repetição climática instrumentada para localizar
  o maior update inicial. Picos de frame variam entre execuções; houve um
  frame isolado de 123 ms sem causa confirmada no profiler de update.

Comandos:

```powershell
./tests/planet/run_validation.ps1
./tests/planet/run_terrain_visual.ps1 -Climate
./tests/planet/run_profile.ps1 -Graphics -SettledRoute -DebugOff -NoClimate
./tests/planet/run_profile.ps1 -Graphics -SettledRoute -DebugOff
```

`mode16..22` mostram temperatura, umidade, influência oceânica, precipitação,
sombra de chuva, bioma dominante e blend dos dois principais. `mode7..15`
preservam os diagnósticos anteriores. As cores são técnicas, não materiais
finais. As capturas verificam poses escolhidas, não todos os trajetos possíveis.
O usuário confirmou voo sem pausas relevantes e visual coerente nessa etapa.
Métricas, estatísticas e limitações em `docs/stages/05_clima_biomas.md`.
