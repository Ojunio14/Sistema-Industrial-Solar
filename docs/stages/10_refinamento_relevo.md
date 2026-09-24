# Etapa 10 — Refinamento do relevo e resolução próxima

24/09/2026. A correção arquitetural solicitada substitui a tentativa parcial
anterior: não se acrescenta detalhe sobre montanhas antigas. Preservam-se
continentes/costas e infraestrutura; o relevo terrestre é novo e orientado
pela geologia. Sem materiais finais, mineração ou Git.

## Diagnóstico e resolução física

Medição pela conversão canônica cube-sphere, raio 50.000 m: comprimentos de
segmentos entre direções normalizadas, em ambos os eixos. Não é estimativa
visual. As larguras são somas de 16 segmentos na linha central do patch;
os intervalos cobrem os segmentos da grade. Relevo acrescenta pequenas
variações ao comprimento sobre a superfície; a tabela mede o domínio esférico.

| LOD | Patch central (m) | Vértices centrais (m) | Patch de borda (m) | Vértices de borda (m) | Patch de canto (m) | Vértices de canto (m) |
|---|---:|---:|---:|---:|---:|---:|
| 0 | 78.504 | 3.070–6.214 | mesma face | mesma grade | mesma face | mesma grade |
| 4 | 6.206 | 382–391 | 3.328 | 196–294 | 3.107 | 185–205 |
| 6 | 1.562 | 97,5–97,7 | 794 | 48,9–70,1 | 746 | 46,1–47,2 |
| 7 | 781 | 48,8 | 394 | 24,4–34,8 | 371 | 23,0–23,3 |
| 8 | 391 | 24,4 | 196 | 12,2–17,3 | 185 | 11,5–11,6 |
| 9 | 195 | 12,2 | 98 | 6,1–8,7 | 92 | 5,8 |

LOD0 possui somente um patch por face, por isso suas três linhas de medição
coincidem. A distância central entre vértices é ~6.214 m; perto do canto,
~3.070 m. Nos níveis seguintes a distorção continua anisotrópica, sobretudo
nas bordas. No alvo de solo medido, a câmera recebia 14,809 m/segmento em LOD8;
com LOD9 recebe 7,405 m. Em uma planície próxima do centro da face, 12,134 m.

Separação das causas: **A**, a grade LOD8 limitava silhueta próxima; **B**, os
cumes possuíam grandes regiões simples; **C**, normais físicas já funcionavam
e foram preservadas; **D**, orçamento cheio produzia buscas custosas de vítimas
para redistribuir LOD; **E**, trocas continuam discretas, conjuntas por quatro
filhos e protegidas por saias; **F**, o material técnico não tem microdetalhe e
suas máscaras de cor ainda tornam algumas facetas visíveis. Esta etapa atua
na geometria A/B e no custo necessário de D, sem esconder limites com texturas.

## Alternativas e decisão

Foram executadas sequencialmente três variantes sobre a Etapa 9 congelada,
mesmos alvos, luz, material técnico, resolução 1100×760 e orçamento: 510
residentes, 96 em cache, dois workers e dois uploads por frame.

| Variante | Espaçamento no solo (m) | Vértices ativos máximos | Payload mesh+cache (MiB) | Memória de vídeo (MiB) | Chunk observado p50/p95 (ms) | Frame p95 (ms) |
|---|---:|---:|---:|---:|---:|---:|
| 17×17 / LOD8 | 14,81 | 137.088 | 17,64 | 44,35 | 23,78 / 32,92 | 25,92 |
| 17×17 / LOD9 | 7,41 | 137.088 | 17,64 | 44,35 | 22,91 / 26,58 | 24,83 |
| 33×33 / LOD8 | 7,41 | 468.864 | 61,14 | 74,09 | 94,39 / 120,51 | 16,94 |

33×33 tinha menos pressão de seleção na rota, mas multiplicava o trabalho por
chunk e os buffers. A leitura isolada de FPS teria escondido essa diferença.
Foi corrigida a busca em `select_lod`: candidatos a merge são ordenados; quando
a vítima mais barata restante já excede a prioridade admissível, a busca para.
Antes, percorria todas as vítimas para cada split rejeitado. A regra de escolha
e os budgets permanecem; evita-se trabalho quadrático desnecessário.

**Escolha: 17×17, máximo LOD9.** A resolução próxima dobra sem quadruplicar
todos os patches. O alvo é aproximadamente 8–12 m, com 12,2 m no centro e
valores menores nas regiões comprimidas pela projeção. Não é uma garantia de
que toda a área visível receba LOD9: distância, erro e orçamento ainda decidem.

## Separação de PlanetShape e ContinentalShape

O PlanetShape original misturava oito campos: continente/warp definiam a
máscara terra/oceano, enquanto colinas, terraços, cristas, cinturões, vales e
detalhe definiam relevo. A sutileza é que esses últimos também cruzavam o
nível do mar. Preservar só a máscara manteve a área global parecida, mas mudou
458 sinais terra/água em 8.192 direções. Essa primeira tentativa foi descartada.

ContinentalShape conserva exatamente a máscara continental, o warp e o
contorno zero efetivo do doador. Seus campos de compatibilidade reconstroem
apenas o envelope costeiro: fundo/alturas abaixo de zero ficam preservados;
de 0 a 45 m há transição suave para o substrato de elevação continental;
acima de 45 m a altura antiga é completamente descartada. Isso preserva
ilhas/depressões rasas sem perpetuar as antigas montanhas e terraços no interior.
Os campos herdados não constituem uma segunda altura natural consultável.

`PlanetShape.sample_components` compõe ContinentalShape + TerrainRelief.
`sample_height_m` e `sample_base_height` são a API única de altura natural,
independente de face, câmera, mesh e LOD. `relief_enabled=false` mostra o
substrato continental, não a Etapa 9. A Etapa 9 congelada existe somente na
fixture de teste independente, que continua conferida contra o oráculo original.
Nenhuma âncora da Etapa 3 ou quota continental foi reintroduzida.

## TerrainRelief: grandes formas e escalas

A geologia estrutural é construída ANTES da altura final. TerrainRelief usa
seu índice 8³ compartilhado e somente leitura, sem buscar clima, bioma ou
classificação dominante de província. Não há instância de geologia por vértice
ou geração redundante por chunk no runtime. Os objetos são RefCounted sem
referência circular; consultas diretas funcionam sem renderer/SceneTree.

- Cadeias têm centro, direção tangente, extensão regional (~10–13 km de
  semieixo no preset), curvatura de eixo a 3.300/1.100 m e corte transversal
  assimétrico. Crista principal, crista secundária deslocada, ombro e vales
  compõem cada seção. A soma de sobreposições satura suavemente.
- Idade controla largura da crista: jovens estreitas, antigas mais largas;
  idade também reduz amplitude dos canais de média escala. Agrupamentos de
  picos usam campo auxiliar a 1.800 m, canais a 480/650 m. As seções são
  arredondadas para evitar cúspides e detalhe submétrico.
- Planaltos estruturais possuem topo amplo, borda suave e variação de ~12 m
  a 2.800 m. Bacias sedimentares/fechadas abaixam e suavizam regiões amplas.
  Interiores antigos reduzem ondulação regional. Formas ígneas localizadas
  usam domo e anel; não se aplicam cones a todas as montanhas.
- Planícies mantêm ondulações pequenas a 3.200 m; bacias e planaltos suprimem
  essa amplitude. A faixa costeira atenua todo relevo com smoothstep 0–40 m
  e preserva o sinal do substrato. Um segundo envelope costeiro 0–250 no
  campo legado de costa amplia a transição; não soma altitude antiga. Máscaras
  físicas também desvanecem na
  costa, corrigindo a descontinuidade encontrada no primeiro teste geológico.

Não há erosão física, hidrologia, dunas por bioma ou ruído uniforme de muitas
oitavas acrescentado ao planeta. Constantes antigas de montanhas/vales do
preset sobrevivem para a compatibilidade costeira; mountain_height_m e
plateau_height_m também dimensionam as novas formas. Não confundir o antigo
max_terrain_height_m (escala de cor legada) com teto da nova altura natural.

## Geologia, clima e biomas

Pipeline: **continentes → descritores geológicos → relevo natural → clima → biomas**.
A geologia versão 3 seleciona descritores em 3.072 candidatos com continentalidade
e potenciais estruturais amplos, nunca pela altura final. Orientação e idade são
determinísticas. O serviço de classificação geológica superficial pode consultar
a altura final, mas seu resultado não retorna ao relevo. Isso evita a dependência
circular da antiga construção sobre PlanetShape. IDs versionados mudaram.

Configure compartilha a geologia com shape, clima e biomas, reconstrói os campos
climáticos e invalida jobs/cache/texturas anteriores. Nenhum parâmetro climático
ou regra de bioma foi recalibrado para conservar os percentuais da Etapa 9.

## Normais, erro, bounds e transições

Normais usam o stencil físico de 2 m sobre a nova função, sem normal map ou
normal dependente de LOD. O teto conservador é 45 + lowland_height_m +
3*mountain_height_m + 2*plateau_height_m + 400 m; culling usa esse teto. AABB
inclui mesh/saias e margem para relevo não resolvido. SSE combina pontos médios
com envelope pelo espaçamento, sem ligar/desligar terreno por LOD.

Os pontos compartilhados de LOD6/7/8/9 dão altura e normal idênticas. A malha
converge ao refinar; a nova função não contém detalhe de poucos metros.
A troca conjunta de quatro filhos, histerese, workers e saias permanece. Não
há morph novo: transição discreta pode continuar perceptível, especialmente
com budget cheio. As imagens de movimento são salvas fora da rota medida,
para não atribuir leitura PNG ao custo do runtime.

## Mineração futura

`natural_height + terrain_edit_delta = final_height` continua o contrato.
Mining Zones poderão consultar o mesmo PlanetShape determinístico antes de
aplicar deltas locais. A grade global ~8–12 m não substitui células futuras
~2 m em chunks locais ~256×256 m. Nenhuma deformação foi implementada.

## Resultados geométricos e dados derivados

Em 8.192 direções, máscara continental e sinal terra/água são exatamente os da
Etapa 9: **4.436 terrestres**, zero mudanças de sinal. O novo relevo difere em
até **796,91 m**; o maior ponto amostrado tem **644,83 m**. Mudar somente a
subseed geológica alterou mais de 2.400 alturas, sem alterar continentes.
A curvatura regional RMS em amostras das novas cadeias, medida com intervalo
físico de 150 m, cresceu ~49,8% frente à Etapa 9 nas mesmas direções. Não é
uma métrica universal de qualidade visual; as capturas são a verificação separada.
Fora da faixa costeira e das máscaras montanha/planalto, 2.237 amostras de
planície tiveram variação máxima de **1,75 m em 20 m**.

O teste de interpolação em quartos de célula (não os pontos usados no builder)
mediu **44,247 / 17,851 / 5,772 / 2,421 m** em LOD6/7/8/9 na escarpa amostrada.
Todos os erros ficam dentro do SSE reportado, diminuem a cada nível e o erro
próximo é menor que um quarto da célula física (~10,6 m). Não se exige erro
vertical de 2 m de uma malha global de ~8–12 m: isso confundiria o alvo com
as futuras Mining Zones. A amplitude nova não recebe os degraus dos terraços
legados: o campo costeiro usado para atenuação é calculado sem quantização.
O contorno exato conserva a expressão original apenas na faixa compatível.

Clima terrestre: mínima/média/máxima **−24,10 / 4,20 / 29,42 °C**;
umidade média **0,51784**, precipitação média **0,38980**. Um par real mantém
barlavento mais úmido que sotavento; altitude local é a altura natural exata,
enquanto transporte/sombra continuam regionais na grade 192×96.

| Bioma dominante | Amostras / 4.436 | Percentual terrestre |
|---|---:|---:|
| Tropical úmido | 539 | 12,15% |
| Savana | 50 | 1,13% |
| Deserto | 683 | 15,40% |
| Salar/extremo | 0 | 0,00% |
| Temperado | 1.139 | 25,68% |
| Pântano/planície úmida | 163 | 3,67% |
| Taiga | 908 | 20,47% |
| Tundra | 706 | 15,92% |
| Alpino | 0 | 0,00% |
| Polar | 248 | 5,59% |

Oito famílias são dominantes na amostra; as dez continuam funcionando nos
casos controlados. Zero dominância amostrada não prova ausência global de
pesos de alpino/salar. A nova altitude e topografia mudam naturalmente os
resultados; nenhuma quota da Etapa 9 foi conservada.

## Visual e limitações observadas

A comparação usa globo, continente, cadeia, lateral, planalto, planície,
costa, centenas, solo e horizonte, com câmeras/luz/material técnico iguais.
A altitude do enquadramento é o maior valor das duas versões: por isso a pose
fixa de solo fica ~88 m sobre o relevo novo e ~390 m sobre o antigo. Há também
uma captura adicional de cada versão a **30 m reais** sobre sua superfície.
O azul é chão submarino opaco, não água; não interpretar todas as bordas da
cor técnica como a linha d’água.

As imagens mostram continentes reconhecíveis, cadeias alongadas com cristas
secundárias e vales e áreas extensas suaves. O globo perde o espalhamento de
montanhas pequenas em quase toda a terra. Escarpas marcantes já existem na
Etapa 9 no alvo costeiro; o novo modelo preserva o litoral e reorganiza os cumes.
Não se afirma equivalência visual a um terreno erodido fisicamente ou PBR.

A sequência adicional tem 30 quadros por versão, fora da medição de frame.
Ao saltar da órbita distante para o voo baixo, a malha começa grosseira e
converge durante o voo. **Popping de convergência é confirmado**; não foi
eliminado por morph. Não foi observada nova fissura aberta nas capturas
inspecionadas. Saia e troca conjunta continuam garantindo cobertura; isso não
é prova de ausência de artefatos em todos os movimentos possíveis.

## Problemas classificados

- **CONFIRMADO:** relevo é uma aproximação geomorfológica e algumas cristas/
  escarpas ainda têm aparência procedural; comparação entregue para revisão
  visual do usuário, sem declarar aprovação artística em seu nome.
- **CONFIRMADO:** geração por chunk ficou mais cara (compatibilidade costeira +
  formas geológicas). A melhoria de frame vem da seleção de LOD, não de um
  sampler mais barato. Convergência após teleporte/viagem rápida continua visível.
- **RISCO:** budgets podem impedir LOD9 em toda a área próxima ao mesmo tempo;
  a meta ~8–12 m vale para o patch refinado sob a câmera, não todo o horizonte.
- **DÍVIDA TÉCNICA:** inicialização geológica/climática síncrona, grade climática
  regional, ausência de erosão física, colisão, edição regional e Mining Zones.
- **SUSPEITO:** nenhum item novo aberto além da variação de apresentação dos frames
  descrita na seção de performance; sem correções fora do escopo.

## Validação final

`run_validation.ps1` terminou com exit 0 no projeto principal. Importação,
Planet Lab, câmeras, fundação, terreno, LOD e as cinco suítes determinísticas
passaram. Por processo: **93.388** contratos de superfície, **52.416** geologia,
**34.883** clima, **75.497** biomas, **65.331** relevo. Fingerprints coincidem
em dois processos independentes. Apenas os dois warnings intencionais dos
casos negativos de câmera. Logs completos e `validation.json` acompanham a entrega.

O timeout de estabilização do harness gráfico usa tempo real (120 s), não
quantidade de frames: um ensaio sem VSync revelou que 3.600 frames podiam
terminar antes de os workers terem tempo de concluir. Corrigido no harness;
budgets/runtime não foram alterados para fazer a medição passar.

Evidências em `docs/evidence/10_refinamento_relevo/`: `comparison.html`,
`comparison.png`, `near_comparison.png`, capturas originais/F4, rotas, sequências,
`summary.json`, alternativas de resolução, `source_manifest.json` e logs.
As cópias temporárias não são dependência do runtime ou da suíte principal.

## Performance: repetição comparável final

Godot 4.6.1, Vulkan Forward+, Radeon Vega 3, 1100×760. Mesma rota de 840 frames
(órbita, aproximação, quilômetros, centenas, próximo, lateral, afastamento),
mesmos landmarks e budgets; aquecimento na pose horizonte (`--route-only`).
Rodadas sequenciais, sem a suíte headless concorrendo, VSync normal. O editor
permaneceu aberto em ambas. Isso é uma repetição distinta da coleta visual
com dez poses de aquecimento; não é a rota histórica de 720 frames da Etapa 9.

| Medida | Etapa 9 | Etapa 10 |
|---|---:|---:|
| Frame p50 / p95 / máximo (ms) | 16.585 / 23.432 / 56.045 | 16.620 / 16.971 / 17.165 |
| Update CPU p50 / p95 / máximo (ms) | 0.903 / 19.956 / 53.658 | 0.643 / 5.146 / 8.289 |
| Último chunk observado p50 / p95 / máximo (ms) | 23.703 / 27.973 / 33.291 | 51.748 / 61.473 / 75.297 |
| Render CPU p95 (ms) | 0.493 | 0.410 |
| Render GPU p95 (ms) | 8.819 | 8.660 |
| Upload p95 (ms) | 0.344 | 0.316 |
| Frames >50 ms | 8.00 | 0.00 |
| Fila máxima | 318.00 | 338.00 |
| Workers máximos | 2.00 | 2.00 |
| Uploads máximos/frame | 2.00 | 2.00 |
| Residentes máximos | 510.00 | 510.00 |
| Cache máximo | 96.00 | 96.00 |
| Vértices ativos máximos | 137088.00 | 137088.00 |
| Payload mesh/cache (MiB) | 17.64 | 17.64 |
| Memória estática máxima (MiB) | 54.68 | 53.56 |
| Memória de vídeo máxima (MiB) | 42.91 | 43.71 |

A seleção de LOD custa menos; o sampler novo custa aproximadamente o dobro
por chunk. Não esconder essa troca: custo geológico + contorno costeiro
compatível pode atrasar convergência em deslocamentos rápidos, mesmo quando
o frame principal é estável. `last_build_ms` é o último job recolhido, não
amostragem independente de todos os jobs. Memória estática é o monitor Godot,
não o working set do processo; payload não inclui overhead da engine.

**Variabilidade registrada:** a coleta visual final teve p95 31,08 ms e máximo
102,49 ms, apesar de CPU update p95 6,79 ms e GPU p95 8,92 ms. Uma execução
anterior da versão quase final tinha p95 16,93 ms. Um editor foi aberto durante
a coleta, mas não foi isolado como causa. A repetição comparável acima voltou
à apresentação ~16,97 ms no novo terrain. Conservam-se os dados brutos de todas
as rodadas finais; não se promete esse FPS em qualquer estado do computador.

O diagnóstico sem VSync também passou (ambas as versões com timeout real e
mesmo aquecimento). Seus frames de ~3–7 ms não são FPS de produção: a trajetória
por número de frames dura menos e dá menos tempo aos workers para convergir.
Usar CPU/GPU/filas e as condições do ensaio, não selecionar somente o melhor FPS.
