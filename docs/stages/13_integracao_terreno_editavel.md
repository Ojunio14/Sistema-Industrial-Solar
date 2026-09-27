# Etapa 13 — Integração da superfície editável e geração assíncrona

25/09/2026. A superfície editada agora pertence ao World3D do Planet Lab.
Não há ferramentas jogáveis, escavadeira, inventário, minério ou material removido.

## Ownership global/local e decisão de recorte

Foi escolhido **recorte geométrico em CPU dos triângulos globais efetivamente
visíveis**, preparado em worker, com uma faixa externa de transição de 16 m.
PlanetShape, ContinentalShape e TerrainRelief permanecem inalterados.

Somente a região local possui chão dentro da zona. O worker subtrai o retângulo
da zona mais sua faixa externa de cada triângulo global atingido, incluindo
saias. O restante é coplanar ao triângulo original e conserva seus atributos
interpolados. Não existe offset de altura, superfície global escondida logo
abaixo da escavação, descarte por transparência ou segunda superfície de colisão.
As malhas globais originais ficam retidas para restauração na desativação.
O shader PBR e os shaders técnicos existentes não foram modificados.

Alternativas consideradas:

- Discard espacial no shader resolveria exclusividade visual, mas isoladamente
  não fecha a diferença entre o triângulo global de 8–24 m e a malha local de
  2 m. Também não resolve colisão nem a junção geométrica.
- Suprimir patches inteiros deixaria buracos fora do chart ou vincularia a zona
  às cube faces. Alterar PlanetShape ou aumentar toda a resolução global
  contrariaria a separação das autoridades e elevaria o custo global.
- O recorte com faixa de transição permite fechar a junção contra a geometria
  exibida, conservar o material e retirar fisicamente o chão concorrente. Seu
  custo é preparação extra na ativação e estabilidade temporária dos patches
  envolvidos, descrita a seguir.

O renderer reserva refinamento pelo menos LOD8 na vizinhança e fixa as folhas
capturadas e seus ancestrais contra split/merge. O restante do planeta continua
usando seu LOD e os mesmos limites de 510 residentes/96 cache. A captura registra metadados de folhas; o worker reconstrói seus arrays com
o mesmo PlanetChunkBuilder determinístico, sem readback da GPU e sem
reter buffers CPU de todo o planeta. Os pins são liberados ao desativar. Uma tabela de
ancestrais evita procurar todos os pins para cada candidato de merge.

## Borda da zona e faixa de transição

A malha local tem sua borda em `natural_height(direction)`, sem nova função
natural. O contorno externo da faixa vem das interseções com os triângulos
globais reais. Um zipper une os segmentos de 2 m do contorno interno aos pontos
de interseção do contorno externo; as coordenadas do chart são corrigidas
perspectivamente ao interpolar atributos 3D. Isso evita tratar coordenadas
gnomônicas como coordenadas baricêntricas afins.

O próprio corpo da faixa interpola entre essas duas aproximações geométricas.
Portanto a **faixa externa** não promete igualdade pontual com a função
analítica natural; ela é uma costura entre tesselações. O interior editável
continua usando exclusivamente altura natural mais delta. A costura não precisa
ser regenerada a cada edição interior. Trocas discretas de LOD fora da área
fixada continuam sendo uma limitação anterior.

Na representação integrada, os nós a até 4 m do perímetro externo são
protegidos. Isso mantém altura e stencil de normal intactos na junção. Edição
de Cell é rejeitada integralmente se algum canto estiver nessa faixa. Uma zona
histórica com deltas nessa faixa não é ativada visualmente: a API retorna false
e informa a razão, sem apagar dados. O serviço independente da Etapa 12 conserva
seu perímetro zero original até a zona adotar a política integrada.

Bordas internas entre chunks não recebem essa proteção. Nós compartilhados
continuam com um único proprietário; snapshots contêm os buffers vizinhos.
Edição cruzando lados ou o encontro de quatro chunks invalida as dependências
do halo e publica a atualização correspondente numa mesma transação.

## Mesh, normals e material

Mantidos 256×256 m, 128×128 cells, 129×129 vértices e 32.768 triângulos por chunk.
MiningBuildJob amostra PlanetShape uma vez por posição do halo 131×131, aplica
os deltas destacados e calcula diferenças centrais da **superfície final**.
Os vértices e normais são gerados no referencial planetário; os mesmos índices
globais do chart produzem bordas idênticas, mesmo atravessando uma cube face.
O antigo MiningMeshBuilder continua como builder puro de compatibilidade dos
contratos da Etapa 12; não existe mais renderer/visor isolado usando-o.

MiningAppearance consulta PlanetMaterialWeights e os serviços da Etapa 11,
reutilizando os componentes naturais já amostrados. Geologia, clima e biomas
continuam serviços compartilhados somente para leitura; não são copiados para
Cells. CUSTOM0/1/2, cores e coordenadas planetárias alimentam o mesmo
ShaderMaterial PBR do renderer global. F4–F7 e debug de materiais também usam
as instâncias compartilhadas. A inclinação final participa da seleção visual;
não existem estratos, recursos expostos ou material de corte especializado.

## Workers, revisões e filas

MiningSurfaceManager é o único consumidor visual do estado vivo. O padrão é
um worker local; dois são configuráveis para comparação. Com zonas ativas,
o limite de jobs globais passa de dois para um e volta ao original quando a
última zona sai. Não são reservadas todas as CPUs do host.

Snapshot assíncrono copia no máximo nove buffers de delta e os metadados do
chart. Não percorre 17.161 nós na main thread. O worker expande seu halo,
amostra a superfície, gera posições/normais/atributos/índices e prepara os
triângulos de colisão. Cada job possui seu PlanetShape/definição; descritores e
serviços imutáveis são compartilhados conforme o contrato do renderer existente.
Workers não tocam Nodes, SceneTree, ArrayMesh ou o estado editável vivo.

ID, epoch, revisão do chunk, atividade, sessão visual e revisão do renderer
protegem o resultado. A validação ocorre ao recolher, antes de cada commit e
antes da publicação. Um resultado obsoleto não altera mesh/collision atuais.
Desativação não espera fisicamente pela thread: resultados antigos são
descartados; o shutdown recolhe cada tarefa uma vez.

Fila deduplicada e recalculada a partir dos chunks ativos: visíveis próximos
primeiro, depois edições recentes distantes, depois dependências/chunks ainda
nunca publicados por distância. Limite total de 64 chunks visuais, um ou dois
jobs e dois resultados pendentes por padrão. Uma tarefa concluída espera em
seu slot quando não há espaço; não há fila ilimitada de buffers.

## Upload progressivo e publicação

Configurações: um commit por frame, budget flexível de 2 ms e até dois resultados
pendentes. Cada upload de ArrayMesh e cada parte de colisão é uma operação
individual. O budget temporal impede começar outra operação quando esgotado;
não pode interromper uma chamada nativa já iniciada. Excedentes são medidos.

Malhas e corpos novos são preparados ocultos, com collision_layer=0. Os shapes
são inseridos nesses corpos durante o budget, evitando concentrar o custo de
inserção física no frame da troca. Só depois a publicação habilita o conjunto
e desabilita a representação anterior. Mesh e collision têm a mesma revisão.

**O carregamento é progressivo, mas a visibilidade inicial muda por zona.**
O primeiro chunk pronto fica preparado enquanto seus vizinhos e a faixa de
transição terminam. A cobertura global permanece intacta durante todo esse
intervalo. Esta escolha evita inventar uma borda temporária contra um vizinho
ainda global. Atualizações posteriores conservam a versão anterior coerente
até todos os chunks dirty dependentes estarem preparados. Não há espera por
worker na main thread durante o jogo. A latência até o primeiro chunk preparado
e até a publicação completa são métricas distintas.

## Colisão técnica

Por chunk há um StaticBody3D com 16 ConcavePolygonShape3D, cada um contendo
2.048 dos triângulos originais. Não há redução de resolução; a divisão serve
para distribuir criação e inserção física entre frames. O primeiro protótipo
com um único shape mostrou commits de dezenas de milissegundos e foi substituído.
A faixa de transição também recebe colisão. O terreno global continua sem
colisão planetária, como antes; não há collider natural competindo com o local.

A invalidação é a mesma da mesh. Recursos/corpos anteriores ficam em uso até
a publicação da revisão nova. A consulta analítica pode refletir uma edição
pendente antes dessa publicação; a revisão consumida permite distinguir esse
estado. **Render e física publicados** permanecem concordantes. O teste de raios
usa tolerância de 5 cm para triangulação de 2 m e precisão float32 a 50 km.

## Múltiplas zonas e ciclo de vida

As tabelas usam ID de zona; não existe singleton de Mining Zone. Duas zonas
técnicas separadas são exercitadas simultaneamente, uma junto de borda de face.
Nesta versão exige-se uma separação conservadora adicional de 1.024 m entre
as calotas para que capturas de patches globais não concorram. Zonas mais
próximas são recusadas explicitamente, mesmo que seus retângulos não se toquem.
Compartilhar um patch entre collars diferentes fica para evolução futura.

Desativar restaura as ArrayMeshes globais originais, remove representações
locais/colisão/pins, invalida sessões pendentes e preserva deltas. Reativar
reconstrói a representação com as edições anteriores. O ciclo integrado carrega
uma zona completa; streaming independente de chunks dentro da mesma zona ainda
não faz parte desta API. Uma reconfiguração natural invalida a representação;
o proprietário deve reconstruir os serviços editáveis junto da nova definição.

## Memória

Payload exato dos arrays de um chunk, sem overhead do alocador/engine:

| Buffer | Bytes | KiB |
|---|---:|---:|
| Posições | 199.692 | 195,01 |
| Normais | 199.692 | 195,01 |
| UV | 133.128 | 130,01 |
| Cores float32 | 266.256 | 260,02 |
| CUSTOM0/1/2 | 798.768 | 780,05 |
| Índices | 393.216 | 384,00 |
| Total arrays de mesh | 1.990.752 | 1.944,09 |
| Faces de colisão (soma dos 16 shapes) | 1.179.648 | 1.152,00 |
| Delta editado | 65.536 | 64,00 |

ArrayMesh converte/empacota atributos internamente: **1,899 MiB é o payload de
entrada**, não uma medição de VRAM exclusiva nem do objeto ArrayMesh. Os buffers
de faces também não incluem BVH, broadphase ou objetos PhysicsServer.
Na execução gráfica final, os buffers empacotados reportados pelo servidor para
um ArrayMesh real somaram **1.527.888 bytes / 1,457 MiB**. Esse valor foi medido
fora da janela de performance e também não inclui overhead do driver/objeto.

| Chunks | Arrays de mesh | Faces de colisão | Deltas | Soma base |
|---:|---:|---:|---:|---:|
| 4 | 7,59 MiB | 4,50 MiB | 0,25 MiB | 12,34 MiB |
| 16 | 30,38 MiB | 18,00 MiB | 1,00 MiB | 49,38 MiB |
| 64 | 121,51 MiB | 72,00 MiB | 4,00 MiB | 197,51 MiB |

Por job somam-se até 576 KiB de snapshots (nove chunks editados), 67,04 KiB
de halo de deltas, 201,11 KiB de posições e 268,14 KiB de componentes naturais.
Um resultado completo aguarda upload com aproximadamente 3,02 MiB de arrays
de mesh+faces, além do snapshot. A divisão das faces duplica temporariamente
1,125 MiB durante o build. Jobs e pendentes são limitados; o conjunto de
recursos já preparado para uma troca atômica pode chegar a uma segunda versão
dos chunks visuais. As malhas globais originais, substitutas recortadas e a
faixa externa têm custo adicional dependente da posição/LOD, não fixo por chunk.
Estes números são limites de payload auditáveis, não promessa de working set.

## F9 e reprodução visual

F9 ativa/desativa a zona técnica sob a direção radial inicial da câmera.
Limites, coordenadas, status (fila/dirty, worker, upload, pronto e carregado),
revisão de dados/mesh/collision e intervalo dos deltas aparecem no mundo.
O cabeçalho mostra filas, tempo de commit, memória de deltas e descartes.
Não existe mais SubViewport/World3D separado nem câmera de inspeção redundante.
F9 sozinho não escava. O teste técnico aplica brushes radiais suaves:
depressão cruzando quatro chunks, depressão menor e aterro separado.

`tests/planet/mining_integration_test.gd` executa o Planet Lab real. Sem
`--headless`, salva capturas de natural, integrado, editado próximo, zona,
F9, órbita ativa/inativa e reativação. O primeiro argumento depois de `--`
é o diretório de evidências; `--two-workers` compara a configuração com dois
workers. Capturas e verificações extensivas ficam fora das janelas medidas.

## Validação e performance

Os resultados finais e sua comparação com os **2.439,475 ms síncronos** da
Etapa 12 estão em [results.md](../evidence/13_integracao_terreno_editavel/results.md).
Incluem duração dos jobs, filas, latências, frames p50/p95/máximo, commits,
colisão e registros dos frames lentos. A Etapa 12 usava material técnico no
visor; esta etapa inclui PBR e colisão. A comparação de tempo total não isola
somente threading: o objetivo principal é retirar a geração do frame principal.

Testes permanentes cobrem geração real em WorkerThreadPool, rejeição de
resultado antigo, prioridade, limites de fila/upload por quantidade e tempo,
ativação/desativação durante job, reativação, igualdade natural, delta final,
lados/canto compartilhados, normais, banda protegida, exclusividade geométrica,
junção global/local, duas zonas, borda de face e render/física. O runner mantém
as regressões das Etapas 6–12 e acrescenta a configuração com dois workers.

## Limitações e próximos passos

- **CONFIRMADO:** publicação inicial ocorre por zona após preparo progressivo;
  a latência total não desaparece. A faixa de 16 m adapta duas tesselações.
- **CONFIRMADO:** budget de tempo é flexível; operações nativas individuais,
  publicação e custos de LOD/SO podem excedê-lo. Medidas finais distinguem isso
  de espera síncrona por geração. Não há promessa de frame máximo universal.
- **CONFIRMADO:** faixa externa de 4 m protegida, distância conservadora entre
  zonas, limite total de 64 chunks, pins locais e ausência de colisão global.
- **RISCO:** 64 chunks com física e duas versões de recursos podem consumir
  centenas de MiB; a tabela de payload não inclui BVH/GPU/alocador.
- **RISCO:** prioridade de refinamento para muitas zonas compete pelo budget
  global. O fallback conserva chão global enquanto não há captura completa.
- **DÍVIDA TÉCNICA:** streaming parcial com fronteira móvel, collars compartilhados,
  redução de latência, cache natural/material, física de produção e persistência.
- **SUSPEITO:** picos externos à atualização local não devem ser atribuídos a
  workers sem isolar LOD, contenção, apresentação e tarefas do host.

A próxima etapa pode construir ferramentas sobre revisões publicadas de
mesh/collision, com política explícita para edição pendente e testes de contato.
Esta entrega não inicia gameplay de escavação/aterro.


### Proteção de LOD em órbita

Um ancestral de patch protegido continua percorrendo seus filhos durante a
seleção. Assim, ramos fora da zona podem fazer merge ao afastar a câmera,
enquanto a cobertura capturada permanece estável. O teste permanente
`mining_lod_ownership_test.gd` verifica preservação, merge dos vizinhos,
residentes e liberação dos pins. Veja a distinção entre a execução completa
de 21 casos e a validação adicional do 22º caso em `results.md`.
