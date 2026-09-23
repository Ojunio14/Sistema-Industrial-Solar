# Evidências — Etapa 4

Godot 4.6.1 stable, Windows, Vulkan Forward+, AMD Radeon Vega 3, seed 73129.
Os artefatos foram produzidos pelos runners em tests/planet, sem operações Git.

- `validation/`: execução completa (import, main, câmeras, fundação, quadtree,
  terreno base/integrado, geologia e determinismo entre processos).
- `geology-final/`: suíte geológica ampliada com oito seeds e comparação explícita
  de perfil jovem/antigo. 158.752 verificações, zero falhas.
- `macro-profile.json` / `geology-profile.json`: captura comparável sequencial,
  2.580 updates, warmup orbital separado, 1100×760, mesma rota/seed/budgets/SSE.
  Apenas a integração geológica difere. Dados brutos e resumos incluídos.
- `visual/`: 73 capturas reais do renderer; seis hemisférios, macroformas da base,
  exemplos dos sete tipos estruturais, cinturões jovem/antigo, cube edge,
  afastamento e debug. Log confirma convergência e 2:1 em cada pose.

Comandos:

```powershell
./tests/planet/run_validation.ps1
./tests/planet/run_validation.ps1 -Only geology
./tests/planet/run_profile.ps1 -Label stage4-macro-baseline -Graphics -MacroRoute -SettledRoute -NoGeology
./tests/planet/run_profile.ps1 -Label stage4-geology -Graphics -MacroRoute -SettledRoute
./tests/planet/run_terrain_visual.ps1 -Geology
```

`globe_*_mode7` = IDs; `mode8` = maturidade. `geology_1` = interior antigo;
`geology_2_young/old` = cinturões; 3 = sedimentar; 4 = ígneo; 5 = planalto;
6 = bacia fechada; 7 = antiga área marinha. Arquivos sem sufixo mode mostram altitude.
Os filtros de tipo mostram dominância, não todos os pesos sobrepostos.

Inspeção direta: seis hemisférios de IDs; maturidade global; cadeia/serra antiga,
planalto, sedimentar, ígneo e bacia fechada; borda em altitude/ID/maturidade.
A captura chain foi comparada com docs/evidence/03_relevo_macro/chain.png:
mudança controlada, não substituição da macroforma. Não há fissura visível nas
poses inspecionadas. Persistem formas arredondadas/regularidade e contornos
categóricos facetados; as capturas não são materiais finais nem prova universal
de continuidade durante qualquer voo.

Profile não equivale a um teste de convergência: rota limitada termina com
trabalho pendente nos dois casos. Geologia aumenta custo por vértice e demanda
SSE; budgets espalham o trabalho, podendo atrasar refinamento. Frames p95
16,645 → 16,717 ms; máximos 28,741 → 21,929 ms. Não interpretar o máximo menor
como aceleração: foram gerados 470.448 → 392.040 vértices nessa janela fixa.
Validação visual separada aguardou idle/balanceamento em todas as poses.

Detalhes, distribuição, contratos, limites e performance em
docs/stages/04_geologia_estrutural.md. Logs de câmeras incluem dois warnings
esperados de casos negativos; não houve erros na validação final.
