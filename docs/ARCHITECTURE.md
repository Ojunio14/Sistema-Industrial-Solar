# Arquitetura atual — Planet v0.1

A Etapa 6 substituiu integralmente a superfície/renderer pela implementação
runtime de Sistema_Industrial_v1. A Etapa 7 acrescentou geologia consultável,
sem mudar a autoridade natural. Detalhes:
[06_substituicao_planeta.md](stages/06_substituicao_planeta.md) e
[07_reintegracao_geologia.md](stages/07_reintegracao_geologia.md).

## Autoridade e escala

Uma superfície radial, 1 unidade = 1 metro, raio 50.000 m e seed 12051965.
PlanetShape.sample_base_height / sample_height_m é a autoridade natural.
Direção/seed/configuração determinam a altura independentemente de câmera,
face, chunk, LOD e ordem. Mesh/futura colisão/caches são dados derivados.
Preset único: systems/planet/surface/data/test_planet_100km.tres.
Sem quotas continentais ou anchors da antiga Etapa 3.

## Runtime

PlanetLab → PlanetRoot → PlanetLODManager → QuadtreeNode → PlanetChunkBuilder.
PlanetRoot adapta câmeras/overlay. CubeSphereMapping é a conversão canônica.
IDs face/depth/cell, chave face/depth/x/y; não dependem de Node/XYZ da mesh.
O quadro UV mudou para o doador: IDs antigos não são diretamente intercambiáveis.

Seis quadtrees; 17×17 amostras; LOD8; erro projetado/tamanho aparente de quad,
histerese, troca pai/quatro filhos e saias. Não há antigo stitching 2:1/morph.
Até 510 residentes, 96 em cache, dois workers/uploads e budget flexível de 2 ms.
Workers produzem arrays locais. ArrayMesh/Nodes/SceneTree permanecem na main
thread; revisão/alive invalidam jobs; shutdown recolhe tarefas pendentes.
Normais usam stencil físico de 2 m, sem dependência de LOD/face.

## Geologia superficial

PlanetGeology recebe PlanetDefinition e deriva a subseed GEO2. Na construção,
amostra PlanetShape e seleciona descritores a partir de altura, máscaras de
montanha/planalto e relevo regional. Descritores e índice cartesiano 8³ ficam
imutáveis durante consultas. `sample(direction)` retorna `Vector4(ID,
maturidade, influência, tipo)`; `sample_with_surface` reutiliza componentes
já obtidos pelo builder. Workers só leem a estrutura, sem Node/SceneTree ou
Resource mutável. IDs são versionados e independentes de face, chunk e LOD.
Geologia nunca retorna delta de altura.

Uma cópia efêmera da classificação por vértice alimenta apenas o shader técnico
de F5; a autoridade permanece no serviço consultável por direção/posição. Com
F5 desligado, o material natural do doador permanece ativo. F4 mantém LOD.

## Sistemas suspensos

archive/stages_02_05/.gdignore exclui gerador, renderer e testes antigos,
preservando a implementação histórica de geologia, clima, dez biomas e materiais.
O código geológico antigo não roda; a Etapa 7 reimplementou sua camada de
classificação sobre PlanetShape. Clima/biomas/recursos seguem desconectados.

## Mineração e deformação futuras

Planet → Cube Face → Quadtree Patch/Chunk → Mining Zone → Mining Chunk → Cell.
base_height(direction) + terrain_edit_delta(position_m) = final_height.
Mining Zones ativarão dados detalhados sem segunda superfície; chunks ~256×256 m
e células ~2 m. A mesh global não precisa dessa resolução. Deltas serão aplicados
antes de gerar vértices/normais/colisão; snapshots/revisões invalidarão chunks
afetados e seus caches/jobs. Persistir somente alterações não reconstruíveis.
Configure hoje reconstrói globalmente; edição, volume, invalidação regional,
colisão e persistência são futuros. Heightfield radial sem voxel global;
overhangs/cavernas continuam fora do escopo inicial.

## Planet Lab

FreeFly, RTS, Orbital e CameraManager preservados. F4: LOD; F5: geologia. Luz/ambiente
constantes, fundo sólido e material técnico do doador. Sem nuvens, atmosfera,
sky artístico, pós-processamento, oceano avançado ou colisão planetária.
