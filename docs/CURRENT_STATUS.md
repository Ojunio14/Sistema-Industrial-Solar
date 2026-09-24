# Estado atual — Planet v0.1

## Etapa atual

Etapa 10: continentes separados do relevo, geologia estrutural e resolução
próxima 17×17/LOD9 implementada e validada. Detalhes em
[10_refinamento_relevo.md](stages/10_refinamento_relevo.md).

## Arquitetura implementada

- ContinentalShape preserva máscara e contorno terra/água do doador. A faixa
  costeira compatível é separada do relevo interior, substituído por completo.
- PlanetShape compõe a única altura natural com TerrainRelief. Geologia v3
  orienta cadeias, maturidade, planaltos, bacias e formas ígneas. Não há ciclo:
  continentes → geologia estrutural → relevo → clima → biomas.
- Clima/biomas são reconstruídos da nova altura, sem recalibração de percentuais.
- Cube-sphere, quadtree, chunks e budgets preservados: 17×17/LOD9, 510 residentes,
  96 cache, dois workers/uploads. ~12,2 m no centro da face, menor nas bordas.
- Normais físicas a 2 m; bounds, SSE e culling consideram relevo final.
  Troca conjunta dos filhos e saias; busca ordenada de vítimas de LOD corrigida.
- Planet Lab mantém FreeFly/RTS/Orbital e F4/F5/F6/F7. Material técnico preservado.

## Resultados desta execução

- 8.192 direções: máscara e sinal terra/água iguais à Etapa 9; 4.436 terrestres.
- Curvatura regional nas novas cadeias ~49,8% maior; planícies selecionadas
  variam no máximo 1,75 m em 20 m. Relevo máximo amostrado 644,83 m.
- Espaçamento sob a câmera próxima: 21,13→10,56 m; planície ~12,20 m.
  Alternativa 33×33 requer ~469 mil vértices contra ~137 mil com 17×17.
- Clima médio terrestre 4,20 °C; umidade 0,51784. Biomas: tropical 12,15%,
  savana 1,13%, deserto 15,40%, temperado 25,68%, pântano 3,67%, taiga 20,47%,
  tundra 15,92%, polar 5,59%. Salar/alpino: nenhuma dominância nas amostras;
  as dez famílias continuam cobertas por casos controlados, sem quotas.
- Suíte principal: zero falhas. Por processo: 93.388 contratos de superfície,
  52.416 geologia, 34.883 clima, 75.497 biomas e 65.331 relevo; fingerprints
  iguais em dois processos. Câmeras/fundação/terreno/LOD também passaram.
- Planet Lab abriu graficamente no projeto principal. Comparação em dez poses,
  mais solo a 30 m e sequência de transições. Performance e condições de
  medição detalhadas na etapa. Repetição comparável: p95 23,43→16,97 ms;
  custo por chunk ~23,70→51,75 ms (mediana observada). Houve variação de
  apresentação em outra rodada; não se promete FPS constante entre execuções.

## Histórico e testes

Etapas 6–9 são histórico; sua geometria/hash não é exigência do terreno atual.
A fixture da Etapa 9 fica somente nos testes, conferida contra o oráculo original.
`relief_enabled=false` retorna substrato continental, não o relevo da Etapa 9.
`tests/planet/run_validation.ps1` cobre regressões e determinismo entre processos.
Evidências comparáveis: `docs/evidence/10_refinamento_relevo`.

## Limites e próximo escopo

- **CONFIRMADO:** algumas escarpas costeiras e depressões rasas pertencem ao
  contorno preservado. Material técnico/seabed opaco não representa água/PBR.
- **RISCO:** orçamento cheio ou viagens rápidas podem atrasar LOD9; saias e
  troca discreta não equivalem a morph. Construção geológica/climática síncrona.
- **DÍVIDA TÉCNICA:** modelo geomorfológico aproximado, sem erosão física;
  grade climática regional, colisão/navegação RTS esférica e edição regional futuras.
- Nenhum material final, vegetação, recurso ou mineração iniciados. Aguardar
  instrução. Natural height + terrain edit delta = final height; células ~2 m
  somente nas futuras Mining Zones, com chunks ~256×256 m.
