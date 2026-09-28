# Estado atual — Planet Mining Prototype

## Etapa atual

Etapa 15: **Current Level separado de Target Level**, grid 3D sobre a superfície
publicada e contorno de Target independente. F10 tem snap/histerese, início de
arraste fixo, ownership de input e cache incremental. Avaliações grandes e
preparação de deltas usam workers destacados. DEV APPLY enfileira uma transação
por chunks; mesh e colisão continuam publicadas juntas pela Etapa 13.

F9 agora é alternância de visibilidade de um diagnóstico persistente; não ativa
nem descarrega zonas. Rótulos próximos mostram Current, com densidade limitada.
Os contratos antigos de datum, plataforma e rampa contínua são preservados.
Veja [Etapa 15](stages/15_ux_performance_designacao.md),
[testes e métricas](evidence/15_ux_performance_designacao/results.md) e o roteiro
manual A–D no documento da etapa. A cena PBR ainda pode ser limitada pela GPU;
Apply assíncrono não implica publicação instantânea. Sem máquinas ou gameplay.

## Base de designação — Etapa 14

Etapa 14: designação técnica por **GRID + LEVELS**, com datum planetário único,
plataformas, rampas entre dois níveis e targets contínuos. F10 oferece seleção
por arrasto, preview, confirmação e DEV APPLY separado. Estados de corte,
aterro, alvo e execução são calculados por célula; grid e números são batch.
Planos não modificam terreno até aplicação. O caminho continua sendo targets
→ deltas → FinalTerrain → mesh/colisão assíncronas da Etapa 13.

Não existem máquinas, inventário, conservação de massa ou transporte.
Origem padrão 0 m / passo 1 m, configuráveis antes dos planos; limites de grade,
tolerância, seleção e apresentação são técnicos. Não há salvamento de planos.
Veja [Etapa 14](stages/14_grid_levels.md) e
[evidências](evidence/14_grid_levels/results.md).

## Base integrada preservada — Etapa 13

Etapa 13: superfície editável integrada ao planeta real. Recorte geométrico
retira a cobertura global, uma faixa de transição une tesselações e a Mining
Zone assume altura natural + delta. Resolução 256 m / 128² cells / 129² vértices
preservada; material PBR da Etapa 11 e serviços naturais compartilhados.

Geração em WorkerThreadPool, snapshots destacados, rejeição de revisão antiga,
fila limitada, uploads progressivos e publicação conjunta de vizinhos dirty.
Colisão técnica por chunk usa exatamente os triângulos finais, divididos em
16 shapes com commits distribuídos entre frames. Desativar restaura o terreno
global e preserva deltas; reativar recupera a edição. F9 agora mostra diagnóstico
no World3D principal, sem visor/câmera local separados e sem ferramenta jogável.

Limites explícitos: publicação inicial por zona; faixa externa protegida de 4 m;
collar de 16 m e pins locais de LOD; zonas visuais conservadoramente separadas;
64 chunks visuais totais; budget temporal flexível. A geração deixa o frame
principal, mas a latência de preparo e o custo gráfico/da física continuam
mensuráveis. Sem promessa de tempo máximo universal por frame.

Detalhes, testes, comparação com 2,44 s síncronos e evidências visuais:
[Etapa 13](stages/13_integracao_terreno_editavel.md) e
[resultados](evidence/13_integracao_terreno_editavel/results.md).
Não foram iniciados escavadeira, mouse brush jogável, inventário ou mineração.

## Fundação visual preservada — Etapa 11

Etapa 11: material PBR triplanar de terreno, oito famílias 2K, pesos contínuos
de aparência implementados; a tecla 1 alterna o debug de materiais. Detalhes em
[11_materiais_aparencia.md](stages/11_materiais_aparencia.md). A geometria da
Etapa 10 continua: ContinentalShape → geologia estrutural → TerrainRelief →
PlanetShape. Clima e biomas continuam dados derivados.

## Arquitetura implementada

- PlanetShape compõe a única altura natural. Cube-sphere/quadtree/budgets
  permanecem em 17×17/LOD9, 510 residentes, 96 cache, dois workers/uploads;
  raio 50 km.
- Geologia, clima e biomas são consultados uma vez por vértice, reutilizando a
  mesma amostra de superfície. PlanetMaterialWeights gera oito pesos contínuos
  em CUSTOM1/2, sem devolver material ao terreno. CUSTOM0 geológico permanece.
- Um ShaderMaterial PBR compartilhado por todos os chunks escolhe top-2 por
  fragment e amostra albedo, Normal GL e roughness em triplanar local métrico.
  Escalas finais por família: rocha genérica/vulcânica 6 m, sedimentar 8 m,
  solo 4,5 m, cascalho 3 m, areia/árido 6 m e neve/gelo 8 m. Uma segunda escala
  rotacionada do material dominante, warp planetário contínuo e macro/meso
  reduzem a repetição; a base cromática das oito famílias suaviza trocas top-2.
  Micro normal map desvanece à distância. Metalness 0.
- F4–F7 permanecem; a tecla 1 mostra família, blend, slope, rocha, neve e índices.
  O fundo submarino continua opaco e técnico, sem oceano avançado.

## Resultados e evidência

- Inventário: oito diretórios oficiais, cada um com albedo/normal/roughness
  2048×2048; importação VRAM com mipmaps. Arquivos AO/displacement preservados.
  Não foi encontrado documento de licença/atribuição em assets.
- Contratos de superfície/geologia/clima/biomas/relevo mantêm os fingerprints
  da Etapa 10. materials_test.gd verifica assets, normalização, oceano, top-3,
  slope, costa, frio, província ígnea, borda e vértices/normais geométricas.
- Rota idêntica de 840 frames em 1100×760, Godot 4.6.1/Vulkan Forward+/Vega 3,
  par sem VSync: técnico vs PBR frame p95 **5,59 → 10,95 ms**; render GPU p95
  **3,12 → 8,75 ms**; zero frames >50 ms. Update CPU p95 **3,36 → 4,38 ms**.
  Ambos compartilham a mesma seleção CPU, isolando o shader. Com VSync normal,
  nas medições pré-correção houve variabilidade de apresentação: p95
  **19,08 → 31,08 ms** em outra dupla,
  inclusive ~31 ms na órbita PBR com GPU ~1,5 ms. Não atribuir todo o intervalo
  ao shader; manter os dois registros brutos.
- O último chunk observado passou de ~51,75 ms na Etapa 10 a 83,48/83,24 ms
  p50 no par técnico/PBR recente; essa métrica varia entre execuções e pode
  refletir contenção da GPU integrada. O payload de
  malha/cache alcançou 24,25 MiB contra 17,64 MiB na Etapa 10; memória de
  vídeo ~175,71 MiB com os mapas carregados, contra ~43,71 MiB na Etapa 10.
  last_build_ms não é amostragem independente de todos os jobs. A apresentação
  com VSync é variável entre execuções; os dados brutos ficam em
  docs/evidence/11_materiais_aparencia.
- Frente ao PBR anterior com tiles de 12–18 m, o anti-tiling elevou o frame
  p95 sem VSync de 9,00 a 10,95 ms e o GPU p95 de 6,59 a 8,75 ms; VRAM e
  quantidade de vértices permaneceram iguais.

## Histórico e próximos limites

Etapas 6–10 continuam documentadas em docs/stages; seus contratos naturais
seguem validados. A fixture da Etapa 9 é apenas teste. O material técnico
anterior fica disponível para comparação; não é o visual padrão.

- **CONFIRMADO:** algumas escarpas costeiras e depressões rasas pertencem ao
  contorno preservado. Fundo do mar ainda é chão opaco, não água.
- **CONFIRMADO:** VRAM e custo de geração cresceram com os 24 mapas e oito pesos
  por vértice; não houve redução de LOD ou resolução para compensar.
- **RISCO:** a troca top-2 pode revelar uma transição onde três famílias têm
  pesos semelhantes. A procedência/licença dos assets carece de documentação.
- **DÍVIDA TÉCNICA:** ausência de oceano, vegetação, objetos rochosos,
  morph de LOD e erosão física. Mining Zones agora têm fundação técnica descrita acima.

Contrato de edição implementado: natural_height + terrain_edit_delta = final_height;
células de 2 m apenas em Mining Chunks de 256×256 m, sem mudar o grid global.
