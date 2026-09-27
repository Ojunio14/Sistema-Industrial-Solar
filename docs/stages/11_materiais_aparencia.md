# Etapa 11 — Materiais e aparência

## Escopo e autoridade

Esta etapa altera somente os dados de aparência por vértice e o material de
superfície. `ContinentalShape`, `TerrainRelief`, `PlanetShape`, LOD, raio e
resolução continuam iguais à Etapa 10. Geologia, clima e biomas permanecem
serviços consultáveis; `PlanetMaterialWeights` é um consumidor derivado. A malha
não é autoridade de clima ou bioma.

## Inventário de assets e importação

`assets/textures/terrain/` já continha as oito famílias oficiais, cada uma
com `<família>_albedo.png`, `_normal.png` e `_roughness.png`, todas 2048×2048:

| Índice | Família | Uso principal |
|---:|---|---|
| 0 | rock_generic | encostas/afloramentos |
| 1 | rock_sedimentary | bacias e exposições sedimentares |
| 2 | rock_volcanic | províncias ígneas |
| 3 | soil | superfícies estáveis e úmidas |
| 4 | sand | praia e parte do deserto |
| 5 | arid_ground | solo árido |
| 6 | snow_ice | contexto frio e alto |
| 7 | gravel | detrito/transições rochosas |

Os arquivos AO/displacement e `snow_ice_bump.exr` continuam guardados, sem
ligação ao shader desta etapa. Não foi necessário renomear ou mover assets.
Não há arquivo de licença/atribuição dentro de `assets`; a origem/licença
individual desses assets ainda exige confirmação documental. Os arquivos de
textura não foram alterados.

O inventário histórico em [06_materiais_aparencia.md](06_materiais_aparencia.md)
registra os nomes de origem (`rocks_ground_02/04`, `gray_rocks`,
`brown_mud_leaves_01`, `coast_sand_01`, `forest_ground_04`, `snow_02` e
`ganges_river_pebbles`) e a confirmação anterior do usuário para mapear
`forest_ground_04` a `arid_ground`. Essa informação ajuda a rastrear os
arquivos, mas não substitui comprovante de licença.

Os 24 mapas essenciais usam importação Godot em modo VRAM S3TC/BPTC e mipmaps.
Os oito normais são marcados `compress/normal_map=1`, sem inversão de Y; foram
inspecionados como orientação GL, sem variante DX escolhida. Albedo é amostrado
com `source_color` (sRGB); normais/roughness são dados lineares. Roughness tem
`channel_pack=1` e é lido no canal R. Não há upscale.

## Seleção contínua e custo de amostragem

`PlanetChunkBuilder` já obtinha superfície e normal em um passo. Agora usa essa
mesma amostra para clima, depois bioma, e enfim `PlanetMaterialWeights`, sem
invocar `sample()` completo de cada serviço. Oito pesos normalizados por
vértice são enviados por CUSTOM1/2; CUSTOM0 geológico e os atributos antigos
permanecem. Não há material por chunk: todos compartilham uma instância de
`ShaderMaterial`. Na água, os oito pesos são zero e o shader mostra apenas
chão submarino técnico opaco.

Os pesos combinam os dez pesos contínuos de bioma, temperatura, umidade,
altitude, influência oceânica, inclinação da normal física e falloffs
contínuos das províncias sedimentares/ígneas. IDs geológicos dominantes não
produzem degraus nas fronteiras. Inclinação reduz solo e eleva rocha; a faixa
costeira favorece areia só em terreno baixo e suave. Frio e altitude elevam
neve, enquanto parede íngreme expõe rocha. Nenhum desses campos altera bioma.

O fragment recebe pesos interpolados, identifica as duas famílias mais fortes
e calcula uma cor-base contínua a partir das médias lineares das oito texturas.
Só os detalhes em torno dessa média vêm das duas famílias principais. O
detalhe da segunda diminui suavemente quando seus pesos empatam com os da
terceira; a camada em segunda escala da dominante diminui quando o primeiro
e o segundo empatam. Assim, a troca de ranking não troca abruptamente toda a
cor nem deixa uma linha reta de textura. Roughness segue a mesma base contínua
e os mapas de normal são lidos apenas de perto. Projeções triplanares abaixo
de 0,5% são omitidas suavemente. Debug e fundo submarino desviam da rota PBR.
O teto é de 21 leituras próximas (duas famílias × três eixos × três mapas,
mais três leituras de albedo em segunda escala), em geral menos, porque eixos
fracos e detalhes secundários empatados são pulados.

## Triplanar, escala e normais

O shader projeta em coordenadas locais planetárias, nas quais 1 unidade = 1 m;
não usa UV de face nem origem de chunk. Os mesmos pontos recebem as mesmas
coordenadas em todas as faces e LODs. Pesos de projeção são `abs(normal)^4`
normalizados. As escalas finais, editáveis por uniforme, são:

| Família | Metros por tile principal | Segundo tile do dominante |
|---|---:|---:|
| rock_generic | 6 | 9,52 |
| rock_sedimentary | 8 | 12,70 |
| rock_volcanic | 6 | 9,52 |
| soil | 4,5 | 7,14 |
| sand | 6 | 9,52 |
| arid_ground | 6 | 9,52 |
| snow_ice | 8 | 12,70 |
| gravel | 3 | 4,76 |

O primeiro protótipo desta etapa tinha tiles de 12–18 m: um grão de 2K
ocupava área física excessiva e o mesmo motivo reaparecia em grade. Agora a
camada dominante combina a projeção principal e uma segunda projeção a 0,63×
da frequência, girada em 3D, transladada por constantes e com no máximo 60%
do detalhe. As duas camadas recebem um offset pseudoaleatório 3D por
células planetárias de 16 m, interpolado suavemente entre células; oito hashes
aritméticos evitam saltos, sem acrescentar amostras de textura. O offset e a
segunda camada desvanecem entre 800 m e 3,6 km da câmera. Um warp
contínuo de amplitude 2,0+1,3+0,8+0,23 m em períodos 17/31/43/113 m desloca
as repetições da camada principal. A macrovariação usa períodos
aproximados de 97–241 m e se reduz de 1,5 a 10 km da câmera; a mesovariação
usa 27–39 m e desaparece entre 1,3–7 km. Ela modula suavemente albedo e
roughness sem desenhar listras vistas da órbita. Tudo é função da posição
planetária, portanto determinístico e contínuo entre chunks, LODs e faces.
Mipmaps/aniso controlam aliasing distante. A força do normal map micro cai
entre 150 m e 1,2 km da câmera.

Na costa, a base de areia usa altitude relativa ao mar, terreno plano, bioma
e influência oceânica. O shader varia esse peso em um intervalo de 7–100 m
segundo inclinação e macrovariação planetária; solo/cascalho/rocha continuam
participando da mistura. Isso evita duas consultas trigonométricas adicionais
por vértice no builder. Um fragmento costeiro classificado como terra com
oito pesos zerados recebe areia como fallback e mistura com a cor aquática
pela máscara terrestre, evitando fragmentos pretos ou manchas azuis internas.

Cada projeção constrói uma base destra T/B/N para sinais positivo e negativo
do eixo. A importação VRAM do Godot guarda normais em dois canais RG/BC5: o
shader reconstrói Z positivo com `sqrt(max(1 - dot(XY, XY), 0))`. Ler o canal
B importado daria zero e inverteria a iluminação, erro detectado e corrigido
na inspeção gráfica. Os canais de Normal GL são orientados para ±X, ±Y, ±Z
antes do blend triplanar; a normal composta é transformada de espaço local
para view space.
Roughness vem do mapa real de cada família; `METALLIC=0`.
Médias dos arquivos de origem, normalizadas (não valores constantes do shader):
rocha sedimentar ~0,54, cascalho ~0,81, solo ~0,92 e areia ~0,96. Essa
diferença mantém a resposta especular apropriada a cada superfície.

## Debug e compatibilidade

F8 percorre PBR, família dominante, cor ponderada top-2, slope, influência de
rochas, neve e índices codificados em R/G (mix em B). F4 LOD continua no
material; F5 geologia, F6 clima e F7 biomas mantêm os materiais de diagnóstico
anteriores. Escolher um desses modos desativa o diagnóstico conflitante.
`set_technical_material_enabled()` permite comparar o shader técnico da Etapa
10 com PBR usando as mesmas malhas e a mesma rota de câmera.

## Comparação visual de escala e repetição

O controle A/B usa as mesmas poses e uma luz solar acompanhando cada alvo
**somente no teste visual**. O controle reproduz tiles de 12–18 m, warp antigo
e ausência de segunda escala; a versão final usa a tabela de 3–8 m acima,
dual-scale e offset estocástico interpolado. Nenhuma das duas capturas muda
altura, LOD ou bioma. Os pares estão em:

| Cena | Controle | Final |
|---|---|---|
| Planície | [antes](../evidence/11_materiais_aparencia/comparison_control_before/plain.png) | [depois](../evidence/11_materiais_aparencia/visual_final_lit/plain.png) |
| Costa | [antes](../evidence/11_materiais_aparencia/comparison_control_before/coast.png) | [depois](../evidence/11_materiais_aparencia/visual_final_lit/coast.png) |
| Rocha/encosta | [antes](../evidence/11_materiais_aparencia/comparison_control_before/mountains.png) | [depois](../evidence/11_materiais_aparencia/visual_final_lit/mountains.png) |
| Área árida | [antes](../evidence/11_materiais_aparencia/comparison_control_before/desert.png) | [depois](../evidence/11_materiais_aparencia/visual_final_lit/desert.png) |
| Centenas de metros | [antes](../evidence/11_materiais_aparencia/comparison_control_before/hundreds.png) | [depois](../evidence/11_materiais_aparencia/visual_final_lit/hundreds.png) |
| A 30 m do solo | [antes](../evidence/11_materiais_aparencia/comparison_control_before/ground.png) | [depois](../evidence/11_materiais_aparencia/visual_final_lit/ground.png) |

Em 30 m, os motivos grandes e idênticos do controle viram detalhe menor e
menos alinhado. Planície e costa deixam de exibir faixas periódicas tão largas;
no continente a modulação macro some ao longe. Capturas próximas adicionais
de [área árida](../evidence/11_materiais_aparencia/visual_arid_close/desert_close.png)
e [área úmida](../evidence/11_materiais_aparencia/visual_arid_close/wet_close.png)
testam densidade de texel; a segunda pose permanece dominada por água e não
serve como prova visual isolada do solo úmido. Há repetição fina residual em
superfícies homogêneas, herdada dos motivos dos mapas de origem. Seis poses
±X/±Y/±Z em `visual_final_lit/` não revelaram linha de textura na borda de
face. O contorno de costa ainda reflete a malha/nível do mar existente.

## Evidência, desempenho e limites

Os testes automatizados e a rota 840 frames com resolução 1100×760, 17×17,
LOD9, 510 residentes, 96 cache, dois workers e uploads por frame são registrados
em `docs/evidence/11_materiais_aparencia/`. Godot 4.6.1, Vulkan Forward+,
Radeon Vega 3. Ambas as corridas fizeram a mesma convergência
na pose horizonte e geraram os mesmos pesos de material na CPU; o toggle
técnico/PBR isola o custo de amostragem do shader. A versão técnica desta
comparação também carrega os 24 mapas para manter a residência de textura igual.
Os JSONs da medição final sem VSync ficam em `technical_final2_uncapped/profile.json`
e `pbr_final3_uncapped/profile.json`; `final3_paired_summary.json` contém os
percentis. `pbr_uncapped/` guarda o PBR anterior para medir o custo adicional.
`comparison_control_before/` (tiles de 12–18 m, sem dual-scale) e
`visual_final_lit/` (versão final) usam as mesmas poses, iluminação e seleção
CPU, permitindo comparar os seis enquadramentos obrigatórios. O controle foi
renderizado com os parâmetros antigos no mesmo shader e restaurado byte a byte
antes da versão final. `comparison_before/` também registra imagens reais da
candidata anterior. `visual_final_lit/` inclui as poses regionais, seis
orientações de face e F8.

| Medida na rota, VSync desligado | Técnico | PBR |
|---|---:|---:|
| Frame p50 / p95 / máximo (ms) | 3,323 / 5,594 / 25,421 | 4,930 / 10,947 / 23,270 |
| Update CPU p50 / p95 (ms) | 0,387 / 3,363 | 0,464 / 4,382 |
| Render GPU p50 / p95 (ms) | 2,252 / 3,118 | 2,942 / 8,748 |
| Render CPU p95 (ms) | 0,451 | 0,438 |
| Upload p95 (ms) | 0,027 | 0,320 |
| Último chunk observado p50 / p95 (ms) | 83,476 / 104,577 | 83,241 / 110,311 |
| Frames >50 ms | 0 | 0 |
| Fila / jobs / uploads máximos | 363 / 2 / 2 | 357 / 2 / 2 |
| Residentes / cache / vértices ativos máximos | 510 / 96 / 137.088 | 510 / 96 / 137.088 |
| Payload mesh+cache / vídeo máximos (MiB) | 24,25 / 175,71 | 24,25 / 175,71 |

Nas medições anteriores à correção de escala, com VSync normal, a apresentação variou muito: na repetição pareada p95
19,08/31,08 ms (técnico/PBR); noutra rodada da versão ainda em refinamento
ambos ficaram ~17,1 ms. A rodada PBR de 31 ms também mostrou ~31 ms na
fase de órbita com render GPU ~1,5 ms, evidenciando que esse patamar não
é explicado só pelo shader. Dados brutos e resumos pareados com VSync ficam
em `technical_paired/`, `pbr_paired/` e `paired_summary.json`. O custo PBR
medido na GPU é real, porém o frame com VSync nesta máquina é variável;
por isso a tabela sem VSync isola melhor o custo nesta execução.

Frente à Etapa 10, o custo observado por chunk aumentou (~51,75→72–74 ms
p50 na primeira versão, e 83,24 ms no PBR desta repetição) por
clima/bioma/pesos por vértice e possivelmente por contenção variável com a
GPU integrada; a memória de vídeo aumentou
~43,71→175,71 MiB com texturas 2K. A medição técnica desta etapa não é um
retorno ao custo de CPU da Etapa 10; apenas compara fragment shading em malhas
idênticas. Capturas PNG e mudanças de pose não
integram a rota medida. `last_build_ms` é o último chunk visto em cada frame,
não uma amostragem independente de todos os jobs.

Ante o PBR antes desta correção, o frame p95 sem VSync subiu 9,001→10,947 ms
e o render GPU p95 6,588→8,748 ms; é o custo observado do anti-tiling e da
escala menor nessa rota. A vista estática de costa em 1200 m registrou
~13,56 ms de GPU e a vista árida a 60 m ~19,72 ms; portanto a rota de 840
frames não é o pior caso de todos os ângulos. A memória de vídeo e o número
de vértices ficaram iguais. O tempo do último chunk varia entre execuções:
uma corrida intermediária do PBR final registrou p50 111,19 ms, enquanto a
repetição técnica/PBR aqui mostrada registrou 83,48/83,24 ms.
Uma versão experimental que calculava macrovariação costeira por vértice foi
retirada; o custo final de geração não deve ser inferido apenas de uma amostra.

O material não introduz água translúcida, vegetação, objetos rochosos, neve
dinâmica ou alterações de relevo. A costa ainda pode mostrar escarpas legadas;
trocas de LOD ainda são discretas. O uso de 24 samplers e oito floats extras
por vértice aumenta consumo de GPU/memória. A licença dos assets e a aparência
artística final dependem de revisão humana; as capturas documentam o estado
técnico, sem afirmar aprovação estética.
