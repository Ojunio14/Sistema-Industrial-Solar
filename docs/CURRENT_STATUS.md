# Estado atual — Planet v0.1

## Etapa atual

Etapa 6: fundação substituída pelo pipeline runtime de Sistema_Industrial_v1.
Planet Lab usa exclusivamente PlanetShape/LOD/chunks/normais/workers do doador.
Detalhes: [06_substituicao_planeta.md](stages/06_substituicao_planeta.md).

## Implementado e validado

- Preset 100 km, raio 50.000 m, seed 12051965, escala 1 m/unidade.
- Seis quadtrees, chunks 17×17, LOD8, saias, SSE/histerese/cache do doador.
- Normais físicas 2 m; dois workers, uploads na main thread, revisão/alive.
- Planet Lab, três câmeras, overlay/F4; luz técnica sem efeitos planetários.
- Pipeline antigo arquivado em archive/stages_02_05, ignorado pela engine.
- Regressão completa: import/cena/câmeras/matemática/terrain/LOD aprovados;
  85.196 contratos em dois processos, hashes iguais aos doador.
- Comparação Vulkan de nove poses: globo, centenas, solo e borda de face
  idênticos pixel a pixel com material técnico; sem piora clara nas demais.
- Frame p95 repetição isolada 31,117 ms versus 31,106 ms do doador;
  máximo 33,409 versus 32,044 ms. Budgets de produção respeitados.

## Preservado para depois

Geologia, clima e dez biomas estão preservados e **desconectados**.
Mineração continua planejada: base_height + edit_delta; zonas/chunks ~256 m,
células ~2 m. Edição/colisão/mineração/materiais finais não implementados.

## Problemas

- **CONFIRMADO:** malha/cores técnicas revelam polígonos próximos como no doador.
- **CONFIRMADO:** primeira medição teve dois frames >50 ms, máximo 94,446 ms;
  repetição isolada sem frames >50 ms, causa original não confirmada.
- **RISCO:** saias/troca discreta/LOD8/budget cheio podem causar popping/latência.
- **DÍVIDA TÉCNICA:** reintegração e invalidação regional futuras; navegação RTS
  esférica/colisão ainda não validadas integralmente. FreeFly atravessa terreno.

Evidências: docs/evidence/06_substituicao_planeta. Runner:
tests/planet/run_validation.ps1; capturas: surface_visual_test.gd.
Percentuais/contagens das Etapas 2–5 são históricos, não estado atual.
Próximo trabalho: aguardar instrução; nenhuma reintegração iniciada.
