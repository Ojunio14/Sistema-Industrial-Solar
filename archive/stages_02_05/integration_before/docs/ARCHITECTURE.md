# Arquitetura aprovada — Planet v0.1

## Superfície planetária

Existe uma única superfície física e visual do planeta. Mineração futura não será uma segunda malha sobre o terreno.

## Autoridade dos dados

Dados do terreno são a fonte de verdade. Mesh, colisão e caches são representações derivadas e reconstruíveis.

Fluxo conceitual:

```text
dados do terreno → mesh / colisão / caches
```

## Terreno principal

A direção arquitetural aprovada é um heightfield esférico/radial. Voxel global não será usado como fundação do planeta.

Cavernas, túneis e overhangs complexos não fazem parte do escopo inicial.

## Coordenadas

A direção hierárquica prevista é:

```text
Planet
→ Cube Face
→ UV
→ Quadtree Patch
→ Mining Chunk
→ Cell
```

Identidades persistentes de regiões não devem depender exclusivamente de XYZ global.

## Cube-sphere e quadtree

Cada face da cube-sphere terá seu próprio quadtree.

A API de vizinhança entre faces deverá ser centralizada; sistemas individuais não deverão inventar regras próprias de borda.

O quadtree definitivo deverá posteriormente trabalhar com:

- Screen Space Error;
- balanceamento 2:1;
- edge stitching;
- geomorphing;
- skirts somente como fallback.

Esses mecanismos ainda não estão implementados.

## Mining Zones

Mining Zone será simultaneamente um conceito de gameplay e um mecanismo técnico para ativação de dados detalhados de mineração. Não é uma segunda superfície.

## Mining Chunks

A direção aprovada é:

- aproximadamente 256 × 256 m;
- células nominais de aproximadamente 2 × 2 m;
- dados detalhados apenas onde necessários.

Esses valores permanecem calibráveis.

## Persistência

Salvar apenas aquilo que não puder ser reconstruído deterministicamente. Meshes, normals, colisões e caches não são persistência permanente.

## Geologia estrutural superficial

`PlanetGeology` é uma autoridade procedural separada de terreno, clima, biomas e
recursos. É construída a partir da seed e de um snapshot do contexto continental
e das macroformas, sem reter a instância de terreno. Descritores são somente-leitura
após a construção; consultas não usam RNG nem dependem de face, patch, LOD ou câmera.

`query_direction(d)` recebe direção unitária planetária; `query_position(p)` recebe
posição relativa ao centro planetário e normaliza a direção (não consulta profundidade).
O resultado é `Vector4(ID local, maturidade, influência dominante, deformação em metros)`.
`type_of(ID)` e `describe(ID)` resolvem tipo e metadados; identidade entre consumidores
usa `stable_key(ID)`, incluindo versão do gerador e seed, não apenas o ID local.

IDs são discretos; maturidade e deformação são campos misturados contínuos. O ID
dominante nunca determina sozinho a altura. `PlanetTerrain` permanece a autoridade
radial única: macroforma base + modificador estrutural limitado. Mesh e debug derivam
da mesma consulta; `sample_into` reutiliza um resultado pertencente ao consumidor,
sem scratch mutável compartilhado pela autoridade. Profundidade, estratigrafia e
recursos continuam futuros; o contrato e seus limites estão na Etapa 4.

## Clima e biomas superficiais

`PlanetClimate` é uma autoridade determinística de consulta derivada do terreno
final, sem influência inversa sobre sua altura ou sobre a geologia. Direção
planetária unitária (ou posição relativa ao centro normalizada) e seed determinam
campos climáticos contínuos. Dez pesos de bioma terrestres somam 1 em terra;
água não recebe bioma terrestre. ID dominante é diagnóstico e não alimenta os
próprios pesos. `PlanetClimateSample` é saída reutilizável pelo consumidor, e
`sample_into` recebe a amostra de terreno já calculada. A mesh e o shader são
derivados dessa API. Parâmetros e limites operacionais estão na Etapa 5.

## Planet Lab

O Planet v0.1 usa uma cena/laboratório planetário mínima própria. Ela não depende da antiga hierarquia Galaxy / ScaledSpace / Local_Space.

Isso não impede que sistemas espaciais equivalentes sejam introduzidos futuramente no jogo completo.
