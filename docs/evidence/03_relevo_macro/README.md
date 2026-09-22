# Evidências — Etapa 3

Godot 4.6.1, Windows, Forward+/Vulkan, Radeon Vega 3, 1100×760, seed 73129.

- `global-map.png`: mapa de área igual longitude/seno(latitude), campo autoritativo,
  sem câmera/quadtree. Não é fotografia nem render de materiais finais.
- `globe_0..5.png`: seis vistas globais do renderer real.
- Capturas nomeadas por forma: aproximações oblíquas do mesmo terreno.
- `cube_edge.png` e `debug_*.png`: borda +X/+Z e modos técnicos.
- `visual.log`: convergência/2:1 das capturas.
- `debug_4.png` / `debug-final.log`: captura adicional isolada após corrigir
  interpolação categórica (flat); pode ter contagem LOD diferente pela histerese.
- `stage2-visual.log`: regressão gráfica da esfera lisa, `VISUAL_TEST_OK`.
- `sphere-profile.json` / `terrain-profile.json`: telemetria bruta da rota
  prolongada comparável, 2.580 updates; aquecimento orbital separado.
- `terrain-test.log`: validação final, incluindo benchmark indexado versus todos
  os descritores, com igualdade exata. Tempos de benchmark são diagnósticos,
  não asserts dependentes de hardware.
- Logs das suítes anteriores e determinismo entre processos também preservados.

As imagens mostram batimetria, não uma superfície física de água. Aspectos
estéticos, estatísticas e limites de interpretação estão em
`../../stages/03_relevo_macro.md`.

Reproduzir pelos scripts de `tests/planet/README.md`. Não há garantia de
igualdade de timings entre execuções, nem screenshots provam ausência de popping
em qualquer movimento. Usuário confirmou voo sem pausas relevantes nesta versão.
