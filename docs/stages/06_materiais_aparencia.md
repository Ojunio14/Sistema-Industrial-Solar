# Etapa 6 — Materiais e Aparência

Estado: implementação em validação gráfica e de performance.
Referência: Godot 4.6.1, seed 73129, raio 50.000 m, 1 m/unidade.

## Assets auditados

`assets/textures/terrain/` contém exatamente oito famílias, com índices
estáveis: 0 `rock_generic`, 1 `rock_sedimentary`, 2 `rock_volcanic`, 3 `soil`,
4 `sand`, 5 `arid_ground`, 6 `snow_ice`, 7 `gravel`. Cada pasta contém
`<family>_albedo.png`, `_normal.png`, `_roughness.png`, `_ao.png` e
`_displacement.png`. `snow_ice_bump.exr` foi preservado, mas não é usado.
Os mapas essenciais são 2048×2048; vários originais são PNG de 16 bits,
preservados sem conversão destrutiva. Os mapas adicionais não geram
displacement geométrico nesta etapa.

Os nomes de origem foram normalizados de pastas `textures/` aninhadas:
`rocks_ground_02` → `rock_generic`; `rocks_ground_04` →
`rock_sedimentary`; `gray_rocks` → `rock_volcanic`;
`brown_mud_leaves_01` → `soil`; `coast_sand_01` → `sand`;
`forest_ground_04` → `arid_ground`; `snow_02` → `snow_ice`;
`ganges_river_pebbles` → `gravel`. O usuário confirmou explicitamente
`forest_ground_04` como a família árida, apesar do nome potencialmente
ambíguo. Nenhum arquivo Normal DX ou de licença/atribuição foi encontrado no
inventário; a procedência/licença dos assets não é afirmada por este teste.

Os sidecars de import foram renomeados com os fontes; o Godot regenerou os
caminhos internos. Albedo, Normal GL e roughness usam compressão VRAM e
mipmaps. Normal usa `compress/normal_map=1`, sem inversão Y; roughness usa
canal linear otimizado. No shader, somente albedo é amostrado como `source_color`;
normal e roughness são dados lineares. Fontes permanecem 2K; os arrays GPU
convertem em memória para formatos uniformes de 8 bits.

## Pipeline de material

`PlanetMaterialLibrary` valida o contrato dos arquivos e constrói uma única
vez por execução três `Texture2DArray` com oito camadas na ordem acima:
albedo RGB8, Normal GL RGB8 e roughness R8, todos com mipmaps. Os PNGs
originais continuam como fonte; arrays não são autoridade persistente.

`PlanetTerrain` permanece autoridade radial; `PlanetGeology` e `PlanetClimate`
permanecem autoridades de seus campos. A malha é derivada e não seleciona
altura a partir da aparência. O job reaproveita as consultas de terreno,
geologia, clima e pesos de bioma da Etapa 5. Transporta apenas dois fatores
geológicos (`UV2`) e afinidade pelos biomas secos (`COLOR.a`), além dos campos
já existentes. `PlanetSurfaceSelection` documenta e testa a regra de pesos
superficiais, espelhada pelo shader. Não há oito materiais por patch: um shader
PBR central mistura no máximo as duas famílias de maior peso por fragmento;
o shader técnico anterior continua disponível para F4/F5/F6.

## Triplanar e escalas

Triplanar usa coordenadas planetárias locais multiplicadas por
`meters_per_unit`, não UV do patch. Projeções ±X/±Y/±Z usam bases tangentes
com sinais explícitos para Normal GL. Peso dos três eixos é proporcional a
`abs(normal)^4` e normalizado. O normal map é tratado como perturbação da normal
suave; mapa plano preserva a normal de base. Escala inicial do tile é 6 m,
uniforme e calibrável. Variação macro procedural contínua opera em quilômetros,
meso em dezenas de metros; micro usa albedo, normal e roughness reais. Mipmaps
e fade do normal map entre 5 e 22 km atenuam ruído distante.

## Mistura superficial

Oito pesos são funções suaves de temperatura, umidade/precipitação, afinidade
de biomas secos, tipo/peso geológico dominante, altitude, proximidade costeira
e inclinação. Encostas expõem rocha; províncias sedimentares/ígneas favorecem
suas respectivas famílias sem substituir clima. Costa baixa e suave favorece
areia, mas litoral íngreme favorece rocha. Aridez com afinidade por
savana/deserto favorece `arid_ground`; frio polar/montanhoso favorece
`snow_ice`, reduzido em declives. `gravel` ocupa encostas intermediárias.
Pesos de base normalizam para 1 em terra. A soma total dos oito é a regra
matemática; o top-2 é uma aproximação de render de custo controlado, sujeita
a erro em transições com três ou mais famílias comparáveis. O fundo oceânico
continua uma visualização técnica azul-escura da batimetria, não água física.

## Normais e low-poly

O caminho técnico anterior usava normais radiais e iluminação unshaded por
derivada do triângulo morphed. Isso evidenciava cada triângulo e não iluminava
a orientação real da encosta. No caminho PBR, cada vértice obtém uma normal
do heightfield global final por duas amostras diferenciais a 10 m em bases
tangentes planetárias. O passo independe de face, patch e LOD. A malha não
ganha vértices; índices, SSE, morph, stitching e budgets não são alterados.
Esse método tem custo CPU adicional, medido abaixo quando a validação terminar.
Facetamento restante na silhueta é geométrico, não deve ser escondido com
textura ou aumento automático de LOD.

## Debug, visual, testes e performance

F7: PBR, família dominante, blend, slope, exposição de rocha, normais,
macro, meso e fade micro. F4/F5/F6 são preservados. Uma luz direcional
neutra no PlanetLab permite avaliar albedo/normal/roughness; não há atmosfera.

Resultados de regressão, capturas em diferentes distâncias, comparação de
perfil pareado e limites serão registrados aqui após a validação final.

## Limites de escopo

Não há vegetação, objetos de pedra, grass geometry, recursos minerais,
estratigrafia, mineração, deformação, colisão detalhada, tessellation ou
atmosfera avançada. A Etapa 7 não foi iniciada.
