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
[10_refinamento_relevo.md](stages/10_refinamento_relevo.md). A Etapa 11 deriva
pesos de aparência desses serviços e usa um material PBR triplanar compartilhado:
[11_materiais_aparencia.md](stages/11_materiais_aparencia.md).

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
Até 510 residentes, 96 em cache, dois workers/uploads e budget flexível de 2 ms
sem zona local ativa. A Etapa 13 reserva um slot global durante geração local.
Workers produzem arrays locais. ArrayMesh/Nodes/SceneTree permanecem na main
thread; revisão/alive invalidam jobs; shutdown recolhe tarefas pendentes.
Normais geométricas usam stencil físico de 2 m, sem dependência de LOD/face.
Agora amostram a função refinada. O normal map da Etapa 11 altera apenas a
iluminação do material, não a geometria. Erro/AABB incluem envelope do detalhe ainda
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
F5 desligado, o material PBR derivado fica ativo. F4 mantém LOD.

## Aparência derivada (Etapa 11)

`PlanetMaterialWeights` recebe superfície, normal física, clima e bioma da
mesma amostra do builder e consulta falloffs geológicos contínuos. Produz oito
pesos normalizados, zero na água, sem alterar os serviços ou a altura. A mesh
guarda os pesos em CUSTOM1/2; CUSTOM0 geológico permanece para F5. O shader
seleciona as duas famílias mais fortes por fragment, interpola seus pesos e
amostra mapas albedo/normal/roughness 2K em triplanar no referencial local
planetário (1 unidade = 1 m), independente da UV de face. A cor-base contínua
considera as oito famílias; o detalhe principal usa tiles de 3–8 m, uma
segunda escala rotacionada e offsets suavemente interpolados em células de 16 m quebram
repetições, e a macrovariação modula as transições costeiras no fragment sem
recalcular clima ou geologia. Uma única instância
`ShaderMaterial` é usada por todos os chunks. A tecla 1 expõe a seleção e os campos
materiais. F5/F6/F7 continuam sendo diagnósticos dos serviços, sem transferir
autoridade à mesh. O chão submarino é opaco e técnico até a etapa de oceano.

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
podem consultar os dados, sem torná-los autoridade geométrica.

## Sistemas suspensos

archive/stages_02_05/.gdignore exclui gerador, renderer e testes antigos,
preservando a implementação histórica de geologia, clima, dez biomas e materiais.
O código antigo não roda; Etapas 7–9 reimplementaram suas camadas de dados
sobre PlanetShape. Materiais finais/recursos seguem desconectados.

## Mining Zones e superfície integrada — Etapas 12–13

PlanetEditableTerrain compõe `natural_height + terrain_edit_delta`, sem alterar
PlanetShape. Charts gnomônicos independem das cube faces; chunks de 256 m,
cells de 2 m e 129×129 vértices. Dados vivos pertencem à main thread; buffers
float32 são alocados somente ao editar. Nós compartilhados têm um proprietário.

MiningSurfaceManager agenda jobs destacados, prioriza a câmera e edições,
limita filas/commits e rejeita resultados por revisão/epoch/sessão/atividade.
MiningBuildJob prepara a superfície final, normais centrais com halo, índices,
atributos PBR e faces de colisão. Geologia/clima/biomas continuam serviços.
O padrão usa um worker local e reserva um global; limites globais são restaurados
ao desativar a última zona. Upload/Nodes/PhysicsServer ficam na main thread.

Ownership no World3D principal: recorte geométrico retira os triângulos globais
sob a zona e sua faixa externa de 16 m. MiningTransitionJob reconstrói as folhas
capturadas usando PlanetChunkBuilder determinístico e recorta em worker, sem
readback da GPU. A borda local é a superfície natural de 2 m; a borda externa
coincide com os triângulos globais reais. Zipper costura ambas. Patches envolvidos
são refinados até pelo menos LOD8 e fixados enquanto a zona estiver ativa.
Fora dessa vizinhança o LOD continua operando. Não há overlay nem offset de altura.

Dados históricos na faixa externa de 4 m impedem ativação visual; não são
apagados. A faixa passa a ser protegida, incluindo o stencil das normais.
Bordas internas permitem edição normal. Geração e uploads progridem por chunk,
mas publicação inicial ocorre por zona; atualizações dirty mantêm o conjunto
anterior coerente até seus vizinhos estarem prontos. O chão global permanece
cobrindo a zona durante o preparo inicial. Revisões publicadas de render e
colisão mudam juntas, sem esperar workers no frame principal.

Colisão técnica usa os mesmos triângulos finais, divididos em 16 shapes por
chunk para distribuir criação/inserção física entre frames. Recursos/corpos
novos ficam ocultos e sem collision_layer até a troca. Desativar libera meshes,
collision e pins, restaura as malhas globais originais e preserva edit data.
API suporta múltiplas zonas separadas, até 64 chunks visuais no total. Nesta
versão há margem conservadora de 1.024 m entre calotas, evitando compartilhar
um patch entre collars independentes. Não há streaming parcial dentro da zona.

F9 é diagnóstico no mundo: limites, status das filas, revisions e deltas.
Não existe mais visor isolado nem controles de escavação. O teste programático
gera depressões/aterro suaves na cena real, cruza quatro chunks e cube face,
testa duas zonas, física e órbita. Contratos, custo e limitações:
[Etapa 12](stages/12_mining_zones.md),
[Etapa 13](stages/13_integracao_terreno_editavel.md).

## Planet Lab

FreeFly, RTS, Orbital e CameraManager preservados. F4: LOD; F5: geologia;
F6: temperatura, umidade, oceanicidade, precipitação e sombra de chuva;
F7: biomas; 1: materiais; F9: Mining Zone integrada e diagnóstico no mundo. Luz/ambiente
constantes, fundo sólido e material técnico do doador. Sem nuvens, atmosfera,
sky artístico, pós-processamento, oceano avançado ou colisão planetária global; a colisão local de Mining Zones é técnica.


## Designação técnica — Etapa 14

TerrainLevelDatum é compartilhado por TerrainDesignationStore para todas as
zonas. TerrainDesignation descreve células, níveis de extremidade e operação.
Plataformas usam nível único; rampas são campos contínuos de target, derivados
de anchors inteiros e posição na grid. Não existe autoridade geométrica RampMesh.

TerrainDesignationTool (F10) mantém preview separado de ordens confirmadas.
Avaliação incremental consulta os vértices finais e deriva estados/volumes.
TerrainDesignationOverlay renderiza quadrados e números com ArrayMesh/MultiMesh,
dois nós de desenho para milhares de células. Nenhum overlay participa da física.

DEV APPLY valida revisões, limites e todos os vértices antes de uma transação
de deltas. A geração/material/recorte/colisão existentes continuam inalterados.
Plano atingido e revisão visual/física publicada são estados distintos no HUD.
O passo finito da API prepara execução gradual futura, sem implementar máquinas.
Detalhes e limitações: [Etapa 14](stages/14_grid_levels.md).

## Superfície publicada e consumidores de designação — Etapa 15

O contrato transversal passa a distinguir revisão dos dados e revisão publicada.
MiningBuildJob fornece buffers CPU de altura natural, altura final e vértices;
MiningSurfaceManager publica esses buffers junto da mesh e colisão correspondentes.
PlanetEditableTerrain.published_node é uma consulta à representação publicada,
sem readback GPU ou nova consulta natural. A autoridade de composição permanece
natural + delta. Durante rebuild, Current visual continua na publicação antiga;
os novos dados são explicitamente pendentes.

TerrainDesignationStore cacheia Current por chunk/revisão. Avaliação grande e
preparação de transação usam snapshots destacados e workers limitados; workers
nunca acessam nós vivos, GPU ou PhysicsServer. Revisão/epoch/publicação antiga
invalida o resultado. Apply troca buffers validados por chunk na main thread e
publica revisões coerentes, incluindo o halo; geração e commit existentes seguem.
PlanetRoot mantém/polla esses trabalhos mesmo se a interface F10 for fechada.

A apresentação da Etapa 14 foi substituída: grid de linhas segue Current,
números próximos mostram Current arredondado e um contorno distinto mostra Target.
F9 observa e alterna visibilidade, sem alterar atividade da zona. O único contrato
novo de câmera é CameraManager.designation_dragging: todos os controladores e a
troca por input cedem o movimento durante a seleção e retomam depois da soltura.
Detalhes e evidências: [Etapa 15](stages/15_ux_performance_designacao.md).
