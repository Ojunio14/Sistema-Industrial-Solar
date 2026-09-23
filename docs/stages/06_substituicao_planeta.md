# Etapa 6 — Substituição do planeta

23/09/2026. Substituição integral da fundação por Sistema_Industrial_v1.
Geologia, clima e biomas não reintegrados. Nenhuma operação Git.

## Pipeline substituído

PlanetTerrain (âncoras/calibração), PlanetQuadtreeView, PlanetPatchMesh, morph,
stitching 2:1 e material por derivadas de triângulo deixaram o runtime.
Não há gerador doador combinado com mesh/quadtree antigo.

O conteúdo anterior de systems/planet e tests/planet foi preservado integralmente
em archive/stages_02_05, excluído da engine por .gdignore. Inclui geologia, clima,
biomas, testes e experimentos de materiais existentes. Referências externas
conferidas: PlanetLab e seu overlay eram os consumidores a adaptar. As três
câmeras e CameraManager permanecem. Os caminhos res:// do snapshot são históricos;
o arquivo preservado não é uma segunda implementação executável simultaneamente.

## Componentes reais do doador

Migrados para systems/planet/surface:

| Componente | Adaptação |
|---|---|
| PlanetDefinition / test_planet_100km.tres | Configuração natural real; campos climáticos removidos |
| PlanetShape | Algoritmo natural preservado; consulta/ruído climático removidos |
| CubeSphereMapping | Conversões originais sem mudança |
| QuadtreeNode | Identidade face/depth/cell e árvore do doador |
| PlanetChunkBuilder | Mesmos vértices/normais/índices/cores/saias; sem UV2 climático |
| PlanetLODManager | Mesmo SSE/LOD/cache/workers/budgets; referências a efeitos removidas |
| planet_lod_debug.gdshader | Material técnico original, sem texturas/clima |

PlanetRoot agora é apenas adaptador: instancia um PlanetLODManager, expõe altura
natural e overlay. systems/planet/planet.tscn usa somente o preset de 100 km.
F4 alterna LOD; antigos F5/F6/F7 de geologia/clima/materiais estão desconectados.
Camada de render 2→1 integra as câmeras do Lab; near FreeFly 10→0,5 m permite
inspeção próxima. Luz direcional da demo doadora e ambiente constante 0,25,
fundo sólido, sem Sky/atmosfera/pós-processamento. Nenhum shader PBR final migrado.

Única correção geométrica de integração: AABB inclui saias e margem float32
de 0,05 m, aplicada ao MeshInstance3D. Pode alterar seleção/culling discretamente;
nenhuma posição/normal/índice foi alterado. Hashes comprovam isso abaixo.

## PlanetShape e fonte de verdade

Raio 50.000 m, diâmetro 100 km, 1 unidade = 1 metro, seed **12051965**.
Preset real: escala continental 1,3; threshold −0,06; coast_blend 0,15;
montanhas 620 m. Defaults preservados: warp 2,3/0,13; oceano 350 m; teto 900 m;
planície 150 m; colinas 130 m/escala 7; planalto 190 m/escala 4,2; terrace
45 m/força 0,3; montanhas escala 5,5/cinturão 2,1/potência 2,2; vales
95 m/escala 11; detalhe 22 m/escala 28.

PlanetShape.sample_base_height(direction) é alias de sample_height_m. A mesma
direção/seed/configuração produz a mesma altura, sem câmera, face, LOD, mesh
ou ordem de consulta. sample_components retorna altura/terra/montanha/planalto.
FastNoiseLite simplex/fBM e warp formam continentes; plataforma oceânica,
colinas/terraces, cristas moduladas por cinturões, vales e detalhe completam
a forma. configure() duplica a configuração por revisão; hot reload do Inspector
não foi implementado. Mesh/caches/futura colisão são derivados reconstruíveis.

Cinco âncoras e quota antiga de terra foram removidas do runtime. Em 4.096
amostras aproximadamente uniformes: **45,3% oceano / 54,7% terra**, alturas
−350..874,7 m. São resultados do doador, não metas impostas ao gerador.

## Chunks, normais, LOD e workers

17×17 vértices de superfície; 16×16 quads; 512 triângulos de terreno e 128 de
saia, 357 vértices totais. Cube-sphere normalizado com quadro UV do doador.
IDs face/depth/cell e chave face/depth/x/y, independentes de Node/XYZ.
A orientação UV difere da antiga: não reinterpretar IDs históricos diretamente.

Normais: base tangente determinística e duas amostras a 2/radius; produto
vetorial com passo físico de 2 m independente de face/LOD. Shader interpola
normais de vértice, sem derivadas de triângulo do renderer anterior.

Padrões do doador: nível máximo 8; split 8 px; merge 0,55 do split; quads alvo
10 px; seleção a cada 0,12 s; horizon culling; 510 residentes incluindo pais;
cache limitado a 96; dois workers; dois uploads/frame e budget flexível de 2 ms.
Erro amostrado em pontos médios de diagonais/arestas ×1,5. Pai permanece visível
até quatro filhos prontos; troca conjunta, sem geomorphing. Saias cobrem
T-junctions: max(2 m, erro×1,5, espaçamento×0,04). Não há antigo stitching 2:1.
LOD8 equivale a ~24,4 m no centro de uma face; varia pela projeção. Orçamento
cheio pode impedir o alvo de pixels e atrasar refinamento.

Main thread duplica configuração, agenda WorkerThreadPool, recolhe resultados,
cria ArrayMesh/MeshInstance3D e altera SceneTree/visibilidade. Cada builder tem
configuração e FastNoiseLite próprios; workers calculam arrays/bounds locais.
Revisão e flag alive invalidam jobs por configure/merge. Cada task é aguardada
uma vez, após completar ou no shutdown. Não se espera um job em execução durante
um frame normal. Configure limpa o cache. Não há manipulação de Nodes em workers.

## Comparação visual

Godot 4.6.1, Vulkan Forward+, AMD Radeon Vega 3, 1100×760. Referência isolada
executou os arquivos originais do doador, mesmo preset, material técnico,
luz e câmeras. Compara terreno sólido, não a aparência com PBR/efeitos do doador.
18 PNGs por execução: globo, órbita baixa, quilômetros, centenas de metros,
solo, montanhas, horizonte, borda de face, afastamento e seus diagnósticos LOD.

Globo/centenas/solo/borda de face foram idênticos pixel a pixel. Nas demais poses,
diferença média RGB por canal 0,0013..0,3155 em escala 0–255, com pequenas diferenças
de árvore/histórico/bounds sob budget. Pares inspecionados em
docs/evidence/06_substituicao_planeta/comparison_1.png até comparison_3.png.

O renderer low-poly antigo saiu por completo. A nova fundação não ficou mais
facetada que o doador nas poses. **Persistem polígonos na silhueta muito próxima
e serrilhado da coloração técnica nas montanhas, também presentes no doador.**
Não se promete terreno infinitamente suave/material final. Nenhuma fissura
aberta foi identificada nas poses; imagens não provam ausência de popping/saia
visível em qualquer trajeto. Troca de LOD discreta é uma limitação herdada.

## Performance

Rota idêntica de 720 frames por execução, separada das capturas estabilizadas:
aproximação, voo lateral a 80 m e afastamento. Execuções gráficas sequenciais.

| Medida | Doador | Destino inicial | Destino repetição isolada |
|---|---:|---:|---:|
| Frame mediana/p95 ms | 30,180/31,106 | 30,188/31,483 | 30,089/31,117 |
| Frame máximo ms | 32,044 | 94,446 | 33,409 |
| Update CPU p95/máximo ms | 9,247/18,977 | 7,742/14,570 | 8,700/15,580 |
| Poll/uploads p95/máximo ms | 0,476/0,978 | 0,470/0,782 | 0,469/1,104 |
| Chunk observado mediana/p95 ms | 22,860/34,020 | 24,323/35,283 | 23,399/31,613 |
| Pico fila | 318 | 328 | 325 |
| Frames >50 ms | 0 | 2 | 0 |
| Frames >100 ms | 0 | 0 | 0 |

Dois workers, dois uploads/frame e 510 residentes respeitados. Até 245.760
triângulos. Repetição: máximo de frame 33,409 ms aproximação; 32,650 lateral;
31,729 afastamento. Sem regressão grande sustentada na rota comparada.
Primeira captura teve chunk observado de 210,049 ms e dois frames lentos;
repetição isolada, chunk máximo 45,655 ms e nenhum frame >50 ms. Causa original
**não confirmada**. Tempo de worker inclui escalonamento do SO; last_build_ms
registra o último job recolhido, não todos os jobs do frame. Budget é flexível
e não interrompe chamadas da engine. Não se afirma ausência universal de stutter.

Pipeline antigo medido antes: rota histórica de 2.580 updates até raio 53 km,
frame p95/máximo 17,313/29,178 ms; update 6,528/23,103 ms; warmup 1.433 updates.
Rota e carga diferentes: não usar para alegar aceleração/regressão causal.
JSON bruto preservado em old_stage5_profile.json.

## Testes

Runner tests/planet/run_validation.ps1: import, cena principal, câmeras,
fundação, PlanetShape, contratos em dois processos e LOD, todos saída 0.
Somente dois warnings intencionais dos casos negativos de câmera.

- PlanetShape: 4.096 direções, finitude, seed/configuração, limites.
- **85.196 verificações de contrato**, zero falhas, repetidas em dois processos.
- 8.192 samples/alturas: hash exato do doador; 24 chunks (seis faces × níveis
  0/1/4/8): hashes exatos de posições, normais e índices do doador.
- Winding/índices, normais externas/unitárias, AABB com saias, raio+altura,
  faces/cantos e pontos/normais compartilhados entre LODs.
- LOD/cache: aproximação, afastamento, movimento entre faces/cantos, cobertura,
  histerese, budgets, descarte de revisão antiga e shutdown com jobs ativos.
  Contagem varia com polls assíncronos; cópia validada 4.446 verificações; destino instalado 4.386, ambos sem falhas.
- Três execuções Vulkan com SURFACE_VISUAL_OK; teste de somente um renderer e
  ausência das classes antigas no registro da engine. Câmeras preservadas.

Oráculo independente tests/planet/donor_contracts.json; hashes dos arquivos
originais em docs/evidence/06_substituicao_planeta/donor_sources.json.

## Geologia/clima/biomas e mineração futura

Ideias, código e testes de geologia, clima e dez biomas permanecem no snapshot,
sem consulta/instância no novo builder. Não foram adaptados ou recalculados.
A próxima etapa deverá consumir PlanetShape, sem restaurar a geração continental
antiga. Classificação geológica, clima e recursos continuam sistemas separados.

```text
Planet → Cube Face → Quadtree Patch/Chunk → Mining Zone → Mining Chunk → Cell
final_height = sample_base_height(direction) + terrain_edit_delta(position_m)
```

Mining Chunks ~256×256 m; células ~2 m apenas em zonas detalhadas, sem impor
2 m à mesh global. Delta deverá compor altura antes de vértices/normais/colisão,
com snapshot/revisão e invalidação espacial de jobs/cache/chunks afetados.
Persistir operações/deltas, não meshes. A autoridade independente permite essa
composição; hoje configure reconstrói globalmente. Invalidação local, edição,
colisão, volume e persistência não foram implementados. Heightfield radial
permite escavação/aterro/nivelamento superficiais; overhangs/cavernas continuam
fora da arquitetura inicial. Nenhum gameplay de mineração foi adicionado.

## Problemas e limites

- **CONFIRMADO:** resolução finita e cores técnicas mostram polígonos próximos
  como no doador. Não é o renderer anterior.
- **CONFIRMADO:** dois picos >50 ms na primeira medição; não repetidos na isolada.
- **SUSPEITO:** escalonamento/carga externa contribuiu para esses picos; causa
  não demonstrada, nenhuma correção especulativa aplicada.
- **RISCO:** saias/transições discretas/LOD8/budget cheio podem produzir popping
  e atraso; as poses não cobrem todos os percursos.
- **DÍVIDA TÉCNICA:** reintegração futura; invalidação regional para edição;
  navegação RTS esférica/colisão ainda sem implementação/validação completa.
- FreeFly continua podendo atravessar terreno.

## Não migrado

PlanetData, PlanetHeightMap, PlanetBiomeMap, imagens de continente/bioma,
preview legado, nuvens/seu bug, atmosfera/scattering, sky artístico, sunset,
pós-processamento, oceano avançado, texturas/materiais finais PBR.
Azul representa o terreno submarino opaco, sem segunda superfície de água.
Nenhuma reintegração ou etapa posterior foi iniciada.
