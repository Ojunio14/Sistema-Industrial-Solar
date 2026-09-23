# Etapa 7 — Reintegração da geologia

## Contrato e autoridade

`PlanetShape.sample_base_height(direction)` permanece a única altura natural.
PlanetGeology é um serviço separado, superficial e somente de dados. A consulta
não muda altura, seed natural, costa, mesh, normais, erro LOD ou quadtree.
O gerador da Etapa 4, baseado nas âncoras da antiga Etapa 3 e com deslocamento
de relevo, permanece arquivado. Reaproveitamos seus conceitos geológicos e
consulta leve, não seu modificador de altura ou geografia antiga.

## Geração e seed

`geology_seed = planet_seed XOR 0x47454F32` (namespace GEO2), com override
opcional apenas ao construir o serviço. O override não toca a seed natural.
Não há RNG durante consulta. Uma varredura Fibonacci de 3.072 direções amostra altitude, máscara de
terra, montanha/planalto e quatro vizinhos para relevo/depressão. Para cada tipo,
um score com desempate de hash da subseed seleciona candidatos espaçados.
Números fixos de candidatos são limites de descritores, não quotas de área.
Nenhum centro oceânico é criado para província continental. A classificação
local ainda usa os componentes reais do PlanetShape para adequação suave.

Tipos: fundo oceânico, interior antigo/cráton, cinturão montanhoso, bacia
sedimentar, ígneo/vulcânico, planalto estrutural, bacia fechada, antiga região
marinha e plataforma continental de fundo. Cinturões preferem a máscara de
montanha e o relevo; bacias áreas baixas; crátons interiores de baixa energia;
ígneo é pequeno e raro; planaltos usam sua máscara; bacias fechadas preferem
depressões; antiga região marinha prefere terra emersa baixa e marginal. São
hipóteses procedurais, não simulação de tectônica, vulcanismo ou transgressão.

## Identidade, maturidade e transições

`sample(direction)` ou `sample_position(local_position)` retornam `Vector4`:
`(province_id, maturity, influence, province_type)`. ID e tipo são discretos;
idade/maturidade e influência são campos contínuos. `sample_with_surface(d,
components)` evita outra amostragem de ruído quando um consumidor já possui
`PlanetShape.sample_components(d)`. `type_of(id)`, `stable_key(id)`,
`describe(id)` e `descriptors()` oferecem metadados fora do loop quente.
Chave `geo2:<planet_seed>:<geology_seed>:<local_id>`; ID local não deve ser persistido sozinho.
Os quatro bits baixos codificam tipo. Versão 2 é deliberadamente incompatível
com IDs da Etapa 4. Não existe migração de saves nesta etapa.

As idades intrínsecas são valores normalizados de hipótese: crátons ~0,89,
orógenos ~0,30, sedimentos ~0,68, ígneo ~0,22, planalto ~0,72, bacia fechada
~0,61, antiga área marinha ~0,76. Hash local varia ±0,07. A idade consultada
é mistura de pesos suaves e dos fundos oceânico/plataforma; não representa anos.
Influencia retornada é o peso normalizado da província dominante. Identidade
discreta pode mudar em fronteiras; campos numéricos não dependem de face.

## Runtime, debug e workers

Os descritores são construídos uma vez por `configure`. O índice conservador
cartesiano 8³ restringe os candidatos no loop; a consulta não cria Array,
Dictionary, objeto ou RNG. O objeto é compartilhado somente para leitura.
Workers chamam `sample_with_surface` com componentes obtidos por seu próprio
PlanetShape; esse método lê só números, vetores e descritores já construídos.
`sample` usa um PlanetShape privado para consultas diretas na thread principal.

O builder transporta `CUSTOM0` de quatro floats por vértice como **payload
descartável de debug**, inclusive nas saias. Isso não é armazenamento de geologia
como fonte de dados: futuras zonas de mineração consultam PlanetGeology mesmo
quando mesh/LOD mudar. O material natural anterior permanece intacto. F5 cicla:
natural, província dominante, maturidade, interiores, cinturões, sedimentos,
ígneo, planaltos, bacias fechadas, antigas áreas marinhas. F4 alterna LOD e
volta ao modo natural. Filtros técnicos mostram dominância, não peso de todos
os tipos; fronteiras categóricas podem parecer facetadas no LOD atual.

## Validação

`tests/planet/geology_test.gd` compara 8.192 alturas antes/depois, seed igual e
diferente, ordem invertida, consulta direta e com superfície compartilhada,
12 bordas/8 cantos, atributos de chunks em LOD 0/1/2/4/8, fronteiras, distribuição, dados
finitos, workers simultâneos e arrays de uma malha antiga/nova. O runner executa
dois processos e confronta fingerprints. A suíte da Etapa 6 continua como
regressão da fundação. `surface_visual_test.gd` captura nove poses com o material
natural, LOD e modos geológicos, medindo ainda navegação de 720 frames.

Medição em cinco processos (Godot 4.6.1, headless): 40 descritores, criação
0,69–1,25 s; 8.192 consultas puras com superfície pré-amostrada 39–85 ms
(4,8–10,4 µs por consulta). Em 12 pares de chunks 17×17, o custo mediano
adicional variou de aproximadamente −1,6 a +4,5 ms entre processos; valores
negativos são ruído de agendamento/CPU, não ganho causado pela geologia.
P95 dos pares também variou significativamente (20–57 ms sem payload,
22–49 ms com). O custo real do payload precisa de benchmark controlado se
virar gargalo, mas os budgets de workers/uploads/residentes permaneceram válidos.
A construção síncrona pode provocar uma pausa ao configurar um planeta e deve
ser reavaliada antes de múltiplos planetas em tempo real.

Em nove poses de captura Vulkan, cada PNG natural da Etapa 7 teve hash de
arquivo **idêntico** ao PNG equivalente da Etapa 6 (`target_repeat`). Globo,
órbita, quilômetros, centenas, solo, montanhas, horizonte, borda de face e
afastamento foram comparados. A rota de 720 frames respeitou orçamento de 510
residentes, 96 em cache e dois workers/uploads, sem erro de shader. Capturas
e relatório estão em `docs/evidence/07_reintegracao_geologia`. Os modos
geológicos são diagnósticos; a visualização categórica depende da resolução
atual da mesh e pode mostrar facetas perto de limites de província.

## Preparação para recursos e mineração

Uma futura consulta `(posição local, profundidade)` poderá usar ID, tipo,
maturidade e influência como contexto para materiais/recursos e estratigrafia.
Profundidade ainda não existe. Zonas/chunks de mineração continuarão usando
`base_height + terrain_edit_delta` e persistirão apenas edições locais. A
geologia independe da mesh e da deformação visual; ela não produz minério,
escavação, colisão ou novos materiais nesta etapa.
