# Arquitetura atual — Planet v0.1

A Etapa 6 substituiu integralmente a superfície/renderer pela implementação
runtime de Sistema_Industrial_v1. A Etapa 7 acrescentou geologia consultável;
a Etapa 8 acrescentou clima consultável, e a Etapa 9 acrescentou biomas derivados.
A Etapa 10 separa continentes e relevo, usa geologia estrutural para orientar
o terreno e acrescenta LOD9 próximo. Clima/biomas consomem a nova altura. Detalhes:
[06_substituicao_planeta.md](stages/06_substituicao_planeta.md) e
[07_reintegracao_geologia.md](stages/07_reintegracao_geologia.md) e
[08_reintegracao_clima.md](stages/08_reintegracao_clima.md) e
[09_reintegracao_biomas.md](stages/09_reintegracao_biomas.md) e
[10_refinamento_relevo.md](stages/10_refinamento_relevo.md).

## Autoridade e escala

Uma superfície radial, 1 unidade = 1 metro, raio 50.000 m e seed 12051965.
PlanetShape.sample_base_height / sample_height_m é a autoridade natural.
`ContinentalShape.sample` preserva ruído continental, warp, seed e máscara
terra/oceano do doador. Preserva também o contorno zero efetivo, pois relevo antigo cruzava o mar.
O substrato descarta altura terrestre antiga acima da transição 0–45 m; o
contexto costeiro sem quantização modera o novo relevo, sem somar altura antiga.
`PlanetGeology` constrói descritores estruturais usando apenas continentes e
potenciais amplos de implantação. `TerrainRelief` transforma descritores
orientados em cadeias, planaltos, bacias e formas ígneas dentro da terra.
`PlanetShape.sample_components` compõe os dois: única altura natural final.
Geologia estrutural → relevo → clima → biomas; nenhum feedback de bioma/clima
para geometria. Classificação geológica superficial é posterior ao relevo e
não é consultada por TerrainRelief. Não existe ciclo de altura nem de RefCounted.
`natural_max_height_m()` limita conservadoramente a função final para culling.
Direção/seed/configuração determinam a altura independentemente de câmera,
face, chunk, LOD e ordem. Mesh/futura colisão/caches são dados derivados.
Preset único: systems/planet/surface/data/test_planet_100km.tres.
Sem quotas continentais ou anchors da antiga Etapa 3.

## Runtime

PlanetLab → PlanetRoot → PlanetLODManager → QuadtreeNode → PlanetChunkBuilder.
PlanetRoot adapta câmeras/overlay. CubeSphereMapping é a conversão canônica.
IDs face/depth/cell, chave face/depth/x/y; não dependem de Node/XYZ da mesh.
O quadro UV mudou para o doador: IDs antigos não são diretamente intercambiáveis.

Seis quadtrees; 17×17 amostras; LOD9; erro projetado/tamanho aparente de quad,
histerese, troca pai/quatro filhos e saias. Não há antigo stitching 2:1/morph.
Até 510 residentes, 96 em cache, dois workers/uploads e budget flexível de 2 ms.
Workers produzem arrays locais. ArrayMesh/Nodes/SceneTree permanecem na main
thread; revisão/alive invalidam jobs; shutdown recolhe tarefas pendentes.
Normais usam stencil físico de 2 m, sem dependência de LOD/face.
Agora amostram a função refinada. Erro/AABB incluem envelope do detalhe ainda
não resolvido. A seleção interrompe a busca ordenada quando nenhuma vítima
restante pode ceder orçamento ao split. Não há sampler diferente por LOD,
nem aumento global de densidade para 33×33. Configure reconstrói todos os
consumidores e descarta caches/jobs da revisão anterior.

## Geologia superficial

PlanetGeology recebe PlanetDefinition e deriva a subseed GEO2; a versão do
gerador/IDs é **3** (posições antigas não são identidade persistente compatível).
Antes do relevo, seleciona descritores em 3.072 candidatos continentais com
potenciais estruturais. Cada descritor possui centro, extensão, orientação
tangente, maturidade, força e tipo. Índice cartesiano 8³ e descritores são
somente leitura depois da construção e compartilhados pelos workers.
`relief_candidates` empresta o bucket para formas contínuas, sem seleção por
ID dominante e sem allocation por consulta. `sample(direction)` calcula a
mesma altura e retorna Vector4(ID, maturidade, influência, tipo);
`sample_with_surface` reutiliza componentes já obtidos pelo builder. Não
existe delta geológico separado: TerrainRelief é a única aplicação das formas.
Configure constrói geologia primeiro e compartilha contexto com PlanetShape,
PlanetClimate e PlanetBiomes. O sampler direto não exige renderer ou SceneTree.

Uma cópia efêmera da classificação por vértice alimenta apenas o shader técnico
de F5; a autoridade permanece no serviço consultável por direção/posição. Com
F5 desligado, o material natural do doador permanece ativo. F4 mantém LOD.

## Clima superficial

PlanetClimate recebe PlanetDefinition, deriva a subseed CLI8 e precomputa uma
grade global 192×96 do relevo real de PlanetShape: altitude, terra/água,
montanhas, oceanicidade propagada e barlavento/sotavento conforme ventos que
variam com latitude. `sample(direction)` retorna PlanetClimateSample com
temperatura, umidade, precipitação, influência oceânica, sombra de chuva,
exposição e altitude; não retorna bioma ou delta de altura. Latitude e altitude
da superfície atual determinam a temperatura. A consulta de worker
`sample_with_surface_into` recebe componentes do terreno já amostrados e lê
somente arrays imutáveis, sem Node/SceneTree ou RNG. Geologia não alimenta o
clima. A construção global é síncrona uma vez por configuração, não por chunk.

F6 alterna cinco visualizações climáticas com texturas globais criadas sob
demanda. F5/F6 selecionam materiais técnicos mutuamente exclusivos. Nenhum
campo climático é anexado aos vértices da mesh natural, e F6 desligado conserva
exatamente seu material. Materiais/biomas futuros poderão consultar o serviço
ou receber somente os campos de que precisarem.

## Biomas superficiais

PlanetBiomes consome componentes atuais de PlanetShape, PlanetClimateSample,
inclinação regional aproximada do relevo e descritores geológicos de bacia
fechada somente para salar, com influência radial contínua. Dez famílias terrestres têm scores suaves
normalizados; água retorna IDs −1 e pesos zerados. `sample_with_context_into`
reutiliza clima/superfície fornecidos pelo consumidor e escreve em output
próprio, sem refazer amostras caras ou alocar objeto por consulta.
Não há bioma vulcânico. A geologia ígnea não altera os pesos de bioma.

F7 alterna dominante, blend de todos os pesos e intensidade do dominante.
Texturas globais de debug são criadas sob demanda; a mesh natural não recebe
atributos de bioma. Materiais finais poderão misturar bioma, geologia,
inclinação, altitude e costa, sem tratar bioma como textura. Mining Zones
futuras poderão consultar os dados, sem torná-los autoridade geométrica.

## Sistemas suspensos

archive/stages_02_05/.gdignore exclui gerador, renderer e testes antigos,
preservando a implementação histórica de geologia, clima, dez biomas e materiais.
O código antigo não roda; Etapas 7–9 reimplementaram suas camadas de dados
sobre PlanetShape. Materiais finais/recursos seguem desconectados.

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

FreeFly, RTS, Orbital e CameraManager preservados. F4: LOD; F5: geologia;
F6: temperatura, umidade, oceanicidade, precipitação e sombra de chuva;
F7: biomas. Luz/ambiente
constantes, fundo sólido e material técnico do doador. Sem nuvens, atmosfera,
sky artístico, pós-processamento, oceano avançado ou colisão planetária.
