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

## Planet Lab

O Planet v0.1 usa uma cena/laboratório planetário mínima própria. Ela não depende da antiga hierarquia Galaxy / ScaledSpace / Local_Space.

Isso não impede que sistemas espaciais equivalentes sejam introduzidos futuramente no jogo completo.
