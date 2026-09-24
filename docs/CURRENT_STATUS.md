# Estado atual — Planet v0.1

## Etapa atual

Etapa 8: clima estático como dados reintegrado sobre a fundação da Etapa 6.
PlanetShape segue sendo a única autoridade de altura; geologia e clima não
alteram relevo. Detalhes: [08_reintegracao_clima.md](stages/08_reintegracao_clima.md).

## Implementado e validado

- Preset 100 km, raio 50.000 m, seed 12051965, escala 1 m/unidade.
- Seis quadtrees, chunks 17×17, LOD8, saias, SSE/histerese/cache do doador.
- Normais físicas 2 m; dois workers, uploads na main thread, revisão/alive.
- Planet Lab, três câmeras, overlay/F4; luz técnica sem efeitos planetários.
- Pipeline antigo arquivado em archive/stages_02_05, ignorado pela engine.
- PlanetGeology separado, 40 descritores derivados do relevo atual, nove tipos
  incluindo fundos, ID/idade/influência, consulta independente de face/LOD.
- F5: nove vistas técnicas de geologia; F4: LOD. Material natural intacto.
- PlanetClimate independente da geologia: grade global 192×96 de altitude,
  oceanicidade e relevo a montante do vento; temperatura, umidade, precipitação
  e sombra de chuva consultáveis sem biomas nem dados climáticos na mesh.
- F6: cinco vistas técnicas climáticas, desligado preserva o material natural.
  Consultas de worker com saída local e arrays imutáveis; seed CLI8 estável.
- Clima: 34.865 verificações sem falhas no teste isolado, 12 arestas/8 cantos,
  cinco profundidades de LOD e par real barlavento/sotavento. Em 4.436 amostras
  terrestres, temperatura média 3,53 °C, umidade 0,481, precipitação 0,355 e
  continentalidade 0,483. Construção ~1,0 s; 8.192 consultas quentes ~85 ms
  e 8.192 chamadas diretas a `climate.sample()` ~188 ms.
- Regressão da Etapa 6 mantida; geologia 52.400 checagens em cada um de dois
  processos, fingerprints iguais, zero falhas. 12 arestas/8 cantos e 106
  fronteiras testadas; workers concorrentes e altura/mesh inalteradas.
- Nove capturas naturais idênticas por hash à Etapa 6; captura Vulkan geológica
  e rota de 720 frames aprovadas.
- Nove capturas naturais, F4 e F5 novamente idênticas por hash à Etapa 7 após
  adicionar clima (43 PNGs idênticos); F6 capturado em nove poses e oito alvos
  climáticos. Rota gráfica final de 720 frames no projeto principal aprovada,
  p95 17,00 ms, máximo 18,13 ms, com filas/workers drenados nas capturas.
- Regressão completa: import/cena/câmeras/matemática/terrain/LOD aprovados;
  85.196 contratos em dois processos, hashes iguais aos doador.
- Comparação Vulkan de nove poses: globo, centenas, solo e borda de face
  idênticos pixel a pixel com material técnico; sem piora clara nas demais.
- Frame p95 repetição isolada 31,117 ms versus 31,106 ms do doador;
  máximo 33,409 versus 32,044 ms. Budgets de produção respeitados.

## Preservado para depois

Geologia histórica, clima e dez biomas estão preservados em arquivo. As
implementações atuais de geologia e clima são somente dados; biomas desconectados.
Mineração continua planejada: base_height + edit_delta; zonas/chunks ~256 m,
células ~2 m. Edição/colisão/mineração/materiais finais não implementados.

## Problemas

- **CONFIRMADO:** malha/cores técnicas revelam polígonos próximos como no doador.
- **CONFIRMADO:** primeira medição teve dois frames >50 ms, máximo 94,446 ms;
  repetição isolada sem frames >50 ms, causa original não confirmada.
- **RISCO:** saias/troca discreta/LOD8/budget cheio podem causar popping/latência.
- **DÍVIDA TÉCNICA:** reintegração e invalidação regional futuras; navegação RTS
  esférica/colisão ainda não validadas integralmente. FreeFly atravessa terreno.
- **RISCO:** construção geológica síncrona mediu 0,69–1,25 s neste hardware;
  eventual múltiplos planetas ou reconfiguração em tempo real exigirão trabalho
  assíncrono ou cache de descritores.
- **RISCO:** payload de debug adiciona ~16 bytes/vértice e alguns ms por chunk,
  com variação relevante entre execuções; pode ser criado sob demanda no futuro.
- **RISCO:** clima soma cerca de 1 s de construção síncrona por configuração;
  múltiplos planetas ou reconfiguração frequente podem pedir cache ou construção
  assíncrona. A grade 192×96 aproxima vales e costas pequenas.

Evidências: docs/evidence/06_substituicao_planeta,
docs/evidence/07_reintegracao_geologia e docs/evidence/08_reintegracao_clima. Runner:
tests/planet/run_validation.ps1; capturas: surface_visual_test.gd.
Percentuais/contagens das Etapas 2–5 são históricos, não estado atual.
Próximo trabalho: aguardar instrução; biomas e mineração não iniciados.
