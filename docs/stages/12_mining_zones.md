# Etapa 12 — Mining Zones e fundação de terreno editável

25/09/2026. Camada local de dados editáveis e visor técnico no Planet Lab.
Sem gameplay, save completo, collision final, voxel, recursos ou estratigrafia.
ContinentalShape, TerrainRelief, PlanetShape, geologia, clima, biomas, materiais
globais e LOD9 permanecem intactos.

## Autoridades e hierarquia

`PlanetEditableTerrain` recebe o mesmo PlanetShape natural do runtime e oferece:

- `sample_natural_height(direction)` delega ao gerador natural;
- `sample_edit_delta(position)` consulta os charts usando posição/direção planetária;
- `sample_final_height(direction)` usa a única composição `compose_height`;
- `set_node_delta(zone_id, node, value)` e `set_cell_delta(zone_id, cell, value)`;
- `snapshot_chunk` / `accept_mesh` isolam dados e validam resultados derivados;
- `sample_context(position, depth_m)` consulta geologia, clima e bioma sob demanda.

Direções para altura natural/final devem ser normalizadas, como em PlanetShape.
Posições são relativas ao centro do planeta, em metros; o adaptador Node3D usa
`to_local` para converter uma posição mundial. Delta zero retorna o próprio
natural sem operação adicional. A atividade da zona controla suas representações,
não apaga nem desliga os deltas persistentes. Mesmo inativa, uma zona editada
continua participando da consulta final.

Hierarquia lógica: Planet → superfície/cube faces → MiningZone → MiningChunk
→ Cell. Faces são endereçamento da superfície global, não proprietárias dos
charts de mineração. Uma zona atravessa faces sem ser dividida ou duplicada.

MiningZone é RefCounted, com ID textual fornecido pelo proprietário, âncora,
base tangente, raio, retângulo de chunks, atividade, dados e revisão. Nenhuma
identidade persistente depende de Node/instance ID. O ID deve ser salvo junto
à identidade/seed/versão/configuração do planeta; `lab-inspection` é reservado
ao debug. Chave de chunk: `<zone_id>/chunk/<x>/<y>`. Cell é um par inteiro na
grade da zona; não tem Node, Resource ou objeto individual.

## Coordenadas e curvatura

Chart gnomônico: `d = normalize(up + tx*x/R + ty*y/R)`;
inversa `x = R*dot(p,tx)/dot(p,up)`, equivalente para y. A base usa um eixo
auxiliar alternativo junto dos polos, sem depender de UV/orientação de face.
Produtos escalares da inversa usam escalares double do GDScript; vetores e
vértices permanecem float32. Hemisfério oposto é rejeitado. A posição física
é sempre `d*(R+final_height)`, nunca um plano de altura constante.

Limite inicial: até 8×8 chunks por zona, endereços entre −8 e +8, abrangência
máxima de 2.048 m por eixo. São aproximadamente 2 m de resolução horizontal;
a projeção tem pequena distorção e altura natural altera o comprimento físico.
A maior distância admitida à âncora é 2.896 m; a distorção do Jacobiano de área
da esfera de referência é inferior a 0,51%. Os ensaios em ±1.024 m, polos,
centro, bordas/cantos de face mediram erro máximo **4,49 mm**, limite de teste
15 mm. A atribuição de células muito perto de uma linha tem a ambiguidade
milimétrica normal de float32; ferramentas futuras devem operar índices inteiros
depois de selecionar uma célula, sem repetir conversões ruidosas.

Zonas sobrepostas são rejeitadas por calotas angulares conservadoras, inclusive
quando inativas. Isso pode recusar retângulos próximos que não se sobrepõem;
é uma restrição inicial explícita. Evita somar deltas de charts incompatíveis.
No perímetro exterior, amostras ficam obrigatoriamente em zero; o último
intervalo de 2 m interpola até a superfície intacta. Essa borda não é editável.

## Chunk, Cell, amostras e memória

Cada chunk cobre 256×256 m: 128×128 células, **16.384 cells**. Uma malha completa
tem **129×129 = 16.641 vértices**, 32.768 triângulos e 98.304 índices uint32.
Uma célula lógica tem quatro amostras de canto. `set_cell_delta` substitui essas
quatro amostras atomicamente, ou rejeita tudo se um canto não puder ser editado.
As células vizinhas compartilham os cantos: editar uma célula também altera a
interpolação das vizinhas, sem quatro alturas contraditórias no mesmo ponto.

Autoridade de amostra inteira `(i,j)`: chunk `floor((i,j)/128)`, índice local
`(i,j) - chunk*128`, linear `y*128+x`. Isso vale para negativos; truncar para
zero seria incorreto. A borda +X/+Y é lida do vizinho positivo. A malha pode
duplicar vértices de borda como dado derivado, mas o delta tem um só proprietário.

Um chunk editado usa PackedFloat32Array de 128²: **65.536 bytes / 64 KiB**.
Não se reserva um buffer para o 129º vértice; ele consulta o vizinho/perímetro.
Chunks ativos sem edição só têm metadados. O último delta zerado libera o
buffer. Desativar descarta registros limpos; registros editados permanecem.
Não se permite remover uma zona com deltas sem antes zerá-los explicitamente.
Não há grade global ou clima/bioma/geologia por célula.

| Chunks ativos | Deltas intactos | Todos os chunks com edição | Criação (ms)* | Primeira edição (ms)* |
|---:|---:|---:|---:|---:|
| 1 | 0 | 64 KiB | 0,053 | 0,230 |
| 4 (zona típica 512×512 m) | 0 | 256 KiB | 0,061 | 0,566 |
| 16 | 0 | 1 MiB | 0,179 | 2,977 |
| 64 | 0 | 4 MiB | 0,424 | 13,822 |

*Godot 4.6.1 headless, medição isolada local, sem construção dos serviços
naturais compartilhados. Uma célula editada por chunk; o custo inicial inclui
alocar/zerar cada buffer. Consulta de delta: ~20–22 µs, altura final ~41–49 µs;
alterar uma célula já alocada ~144–182 µs. São médias de 10.000/1.000/100 chamadas,
respectivamente, não percentis ou garantia de frame. Logs finais preservam a
variabilidade entre processos. Payload não inclui Dictionary/RefCounted,
alocador da engine ou duplicações temporárias; não é o working set do processo.

Uma malha técnica possui payload de 1.191.984 bytes (posições, normais, UV,
cores e índices). Snapshot: 131² floats = 68.644 bytes, com halo para normais;
posições temporárias do halo = 205.932 bytes. Esses buffers só são produzidos
para chunks ativos requisitados; não gerar 64 malhas antecipadamente.

## Interpolação, volume e limites

Interpolação **linear por triângulo**, diagonal fixa entre os cantos +X e +Y,
igual à triangulação de MiningMeshBuilder. É contínua nas bordas, sem degraus
quadrados, embora o gradiente possa mudar. A opção bilinear foi evitada para
não criar uma sela cujo delta consultado difere do triângulo desenhado. A
malha ainda aproxima a curvatura/altura natural entre vértices de 2 m, como
qualquer tesselação de um campo contínuo. Normais usam diferenças centrais de
2 m na mesma grade, com halo compartilhado entre chunks.

Área horizontal aproximada da célula: `4/(1+(x²+y²)/R²)^(3/2)` no centro,
medida na esfera de referência, sem multiplicar por slope. Volume líquido
aproximado: área × `(d00+2*d10+2*d01+d11)/6`, integral dos dois triângulos
lineares. Delta uniforme −4 m em célula central corresponde a ~−16 m³. Somar
células uma vez evita dupla contagem; remoção e adição separadas em uma célula
de sinais mistos exigirão integração separada no gameplay futuro. Não há
economia ou material extraído implementado.

Padrão configurável: −100…+100 m. Valores não finitos ou fora dos limites são
rejeitados, não truncados silenciosamente. Existe teto técnico adicional de
min(1.000 m, 10% do raio), e verificação de raio final em cada nó. Não suporta
cavernas, túneis horizontais, overhangs ou várias alturas na mesma coordenada:
é um heightfield radial de uma única superfície.

## Invalidação, ownership e threading

Escritas/consultas do estado vivo pertencem à main thread. Alterar uma amostra
incrementa a revisão dos chunks atingidos pelo suporte da célula e pelo halo
de normais; no máximo quatro. O caso uma amostra além da borda também invalida
o vizinho, pois a normal na borda depende dela. Não há configure/rebuild global.
Reescrever o mesmo valor float32 não invalida nada. Mesh e collision têm
revisões consumidas independentes; collision permanece pendente nesta etapa.

Snapshots copiam deltas e base/raio/coordenadas; não contêm Nodes ou ponteiros
ao estado editável. Cada worker deve possuir seu PlanetShape/configuração,
podendo compartilhar apenas descritores naturais imutáveis. O builder retorna
arrays. ArrayMesh/Nodes/upload e aceitação pertencem à main thread. ID, epoch,
atividade e revisão rejeitam resultados anteriores a edições, descarte,
desativação/reativação ou recriação de zona. Epoch é só um token runtime,
nunca identidade persistente. O teste executa o mesmo builder em WorkerThreadPool
com snapshot isolado e compara os vértices exatos.

O visor ainda gera sincronamente, um chunk por frame. A medição gráfica inicial
observou ~0,43–0,71 s/chunk e ~1,8–2,55 s para quatro chunks, portanto há pausa
confirmada no debug. Não é um orçamento de tempo real. Mover o trabalho para
jobs e consumir resultados aceitos é o próximo passo antes de ferramentas
interativas. O caminho normal, com F9 fechado, não gera essas malhas.

## Integração global/local e debug

**Modo implementado: inspeção isolada.** O planeta global continua sendo o único
renderer de terreno no World3D principal, inclusive com zona ativa. F9 abre um
SubViewport com World3D próprio e uma zona de quatro chunks sob a direção radial
da câmera. Nesse visor, apenas MiningMeshBuilder renderiza natural+delta.
Não há segundo chão na cena principal, clip shader, depth bias, z-fighting ou
alteração dos materiais globais. As edições são visíveis no visor técnico;
**a substituição visual de patches no mundo principal ainda não está implementada**.
Esta etapa prova os dados e atualização local; não entrega terreno jogável.

F9 fecha/desativa o visor e solta as malhas; reabrir conserva deltas e recria
derivados. `[` afasta e `]` aproxima a câmera de inspeção. Contorno/limites de
chunk em verde, dirty em vermelho, IDs/coordenadas, memória e custo de geração
no visor. Grade de células aparece apenas próxima (desvanece 90–230 m).
Azul indica remoção; laranja indica aterro. O F9 normal não escava nem aplica
um preset: as edições demonstrativas pertencem exclusivamente ao teste.

Para futura renderização integrada, será necessário entregar a região ao renderer
local e retirar a cobertura global correspondente de forma atômica, com borda
compatível; a condição de exclusividade entre renderers deve ser mantida.
Não basta adicionar estas malhas sobre as globais. Nenhum mascaramento definitivo,
costura com LOD planetário ou alteração do shader PBR foi antecipado.

## Contexto e persistência futura

`sample_context(position, depth)` retorna Vector4 de geologia (ID, maturidade,
influência, tipo), clima e bioma atuais. Profundidade é apenas um parâmetro
validado e ecoado; `stratigraphy_available=false`. Geologia/clima/bioma não
participam da composição geométrica nem são duplicados por célula.

Persistir futuramente versão do formato, identidade/configuração natural,
ID/âncora/base/limites da zona e chunks com valores não zero. Não salvar malha,
normais, atividade, instance IDs, epochs, revisões derivadas ou arrays de clima.
Reconstituir os dados e gerar snapshots novos após carregar. Não existe save
completo ou migração de versões nesta entrega.

## Testes e evidências

`mining_test.gd`: 484.697 verificações por execução, coordenadas/índices negativos,
limites, precisão, polos, bordas e canto de cube face, zero/excavação/aterro/reset,
memória, sobreposição, atomicidade, volume, halo, vizinhos, quatro chunks,
stale snapshots e worker. Fingerprint inclui alturas naturais e snapshots dos
deltas editados: `6d20dd3c1a706da1583bd4dc9bb03eef9449b8664fdf6e496e7a4bbc27ad6d88`.

`mining_lab_test.gd` abre o Planet Lab, ativa a zona, mostra malha natural,
aplica uma escavação de 12 m e aterro de 8 m, exige reconstrução de somente
quatro chunks locais, remove edições e verifica retorno exato dos vértices e
normais. Fecha/reabre e rejeita snapshots anteriores. Verifica mundo separado
e revisão/raízes globais intactas. Capturas Vulkan complementam a versão headless.
Comparação de imagens exige menos de 0,01% de canais diferentes e erro absoluto
médio inferior a 0,002/255; a estrutura do renderer é verificada separadamente.
Na investigação do harness, mesmo com a árvore congelada, 37 canais de 3,34 milhões
variaram, até 12/255. O overlay é congelado para não medir texto de stats.

Runner principal ampliado para 20 casos, incluindo duas execuções determinísticas
de mineração e teste do Lab. As regressões das Etapas 6–11 continuam incluídas;
nenhum hash natural/climático/geológico/bioma/relevo foi atualizado para aceitar
mudança de terreno. Evidências finais em `docs/evidence/12_mining_zones/`.

## Problemas e próximos limites

- **CONFIRMADO:** geração síncrona do visor pausa frames; não usar como editor
  interativo antes de integrar jobs. O mundo principal ainda exibe altura natural.
- **CONFIRMADO:** borda externa não editável e zonas sobrepostas rejeitadas;
  caps podem recusar vizinhas sem sobreposição real.
- **RISCO:** muitas zonas tornam a busca linear cara; limites atuais são
  adequados ao protótipo, não substituem índice espacial/streaming futuro.
- **DÍVIDA TÉCNICA:** handoff visual global/local, collision por chunk,
  persistência versionada e ferramentas de escavação/aterro/nivelamento futuras.
- **SUSPEITO:** arredondamento/execução GPU pode explicar as diferenças esparsas
  entre frames Vulkan, mas a causa não foi isolada. O dado confirmado são os
  canais diferentes registrados; nenhuma alteração do material foi aplicada.

Não foram iniciados gameplay, recursos minerais, teor, estratigrafia profunda,
transporte de terra, cavernas, túneis ou voxel global. Nenhuma operação Git.

## Validação final no projeto principal

Os 20 casos da suíte principal passaram com exit 0. Após a revisão de remoção
de zona/âncora inválida, mineração foi repetida em dois processos independentes:
484697 verificações por processo, zero falhas, mesmo fingerprint.
O teste headless do Lab e a execução Vulkan no projeto principal também passaram.
Os 39 arquivos protegidos de superfície/geologia/clima/biomas permanecem com
hash SHA-256 idêntico. Logs completos: validation_main/ e validation_final/.

Medições finais (Godot 4.6.1, CPU do host; payload de deltas sem overhead):

| Chunks | Bytes delta | Criar ms | Editar inicialmente ms | Consultar delta µs | Altura final µs | Atualizar Cell µs |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 65536 | 0.066 | 0.204 | 19.7858 | 47.16 | 147.72 |
| 4 | 262144 | 0.072 | 0.656 | 20.0504 | 41.253 | 147.22 |
| 16 | 1048576 | 0.121 | 2.094 | 20.7183 | 42.527 | 169.75 |
| 64 | 4194304 | 0.474 | 12.549 | 21.1956 | 48.824 | 159.13 |

Na captura gráfica final: edição programática 70.974 ms;
reconstrução dos quatro chunks 2439.475 ms de parede
(inclui frames/apresentação). Revisão global preservada. A comparação global
registrou 53 canais diferentes, diferença máxima
7/255 e soma absoluta 84.
Não é uma afirmação de identidade binária entre frames GPU.

Comparação visual: [natural próxima](../evidence/12_mining_zones/visual_main/03_natural_close.png),
[escavação/aterro](../evidence/12_mining_zones/visual_main/05_edited_close.png),
[quatro chunks](../evidence/12_mining_zones/visual_main/06_edited_zone.png),
[restaurado](../evidence/12_mining_zones/visual_main/07_restored.png).
Diretórios visual, visual_final e visual_settled preservam a investigação
anterior do harness, incluindo comparações rejeitadas; visual_main é a validação
gráfica final. Sem alteração de continentes, relevo, clima, biomas, material global
ou LOD9; nenhuma operação Git.
