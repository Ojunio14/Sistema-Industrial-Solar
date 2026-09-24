# Etapa 5 — Clima e Biomas

> Estado histórico após a [Etapa 6](06_substituicao_planeta.md): design/código
> preservados e desconectados. O clima foi posteriormente reintegrado sobre
> PlanetShape na [Etapa 8](08_reintegracao_clima.md); biomas continuam pendentes.

Estado: concluída tecnicamente; limites e custo de execução registrados abaixo.
Referência: Godot 4.6.1, seed 73129, raio 50.000 m, escala 1 m/unidade.

## Modelo e autoridade

`PlanetClimate` é um sistema procedural superficial, separado de `PlanetTerrain`
e `PlanetGeology`. É construído uma vez por seed a partir do terreno final da
Etapa 4; terreno não consulta bioma para formar geometria. Nenhuma autoridade de
clima/bioma depende de face, patch, LOD, câmera, malha ou ordem de consulta.
Não há meteorologia temporal.

`query_direction(d)` recebe direção unitária planetária. `query_position(p)`
recebe posição relativa ao centro, finita/não nula, e usa sua direção (não
consulta altitude fornecida pelo raio de `p`; altitude vem do terreno).
Retornam `PlanetClimateSample`, com `climate=Vector4(temperatura em °C, umidade,
influência oceânica, índice de precipitação)`, `rain_shadow` e dez pesos terrestres
normalizados. `dominant`, `secondary` e `top_pair_mix` resumem o resultado para
debug. Em água (altura <=0), pesos são zero e ID dominante −1; os campos
climáticos continuam consultáveis.

`sample_into(d, terrain_fields, output)` usa o `PlanetTerrain.sample_fields`
já calculado pelo consumidor e um output reutilizável de propriedade do job.
O mesh não recalcula o terreno por vértice. O clima lê as macroformas e a geologia
somente na construção de descritores e consulta a superfície final. RNG local
usa seed planetária XOR `0x434C494D` (`CLIM`) para a fase regional; sem RNG,
Node ou alocações de descritores/arrays por consulta quente. Alterar a seed exige
recriar o PlanetLab; não há hot reload.

## Campos e parâmetros

- Latitude: `abs(d.y)` em direção planetária. Temperatura ao nível do mar vai
  aproximadamente de 30 °C equatorial a −26 °C polar, com curva contínua
  `pow(latitude,1.2)`. Não há faixas rígidas por bioma.
- Altitude: lapse explícito de `0,009 °C/m` acima do nível do mar. Oceano
  modera 75% de uma interpolação para 16 °C, sem cancelar o gradiente de latitude.
- Influência marítima: transformação suave da continentalidade assinada do
  terreno, `1−smoothstep(0,01,0,30,c)`. É um proxy de proximidade climática,
  não distância geodésica exata até água; evita busca global por vértice.
- Umidade: faixas latitudinais úmidas equatoriais e médias, seca subtropical e
  polar, termo marítimo, variação regional de baixa frequência (amplitude 0,10),
  barlavento, sotavento e contexto de bacia fechada. Clamped 0..1.
- Precipitação: função contínua da umidade, latitude, barlavento e sombra de
  chuva, também 0..1. É índice climático, não chuva visual/mm reais.
- Ventos: direção tangencial zonal, trades a leste/oeste conforme latitude,
  transições suaves para ventos médios e polares, leve componente meridional.
  Direção perde força da sombra próxima aos polos para evitar singularidade.

Dez cinturões reais CHAIN/RANGE da macroforma fornecem orientação e amplitude
das barreiras. Um índice cartesiano 8³ conservador descarta cinturões fora de
suporte antes da consulta. Em cada cinturão, perfil longitudinal e transversal
cria reforço úmido a barlavento e sombra a sotavento, com alcance de até três
larguras. Não há raymarch nem simulação atmosférica. A geologia altera a mesma
cadeia no relevo, sem que o clima a substitua.

Bacias fechadas da geologia fornecem centros/raios para um peso contextual
contínuo. Aridez forte é condição necessária de salar/deserto extremo; a bacia
aumenta sua probabilidade, mas deserto extremo também pode existir fora dela.
Na seed padrão, a única bacia fechada está quase toda submersa/úmida: apenas
duas amostras terrestres dentro de 0,7 do raio na amostragem de 16.384 pontos,
precipitação mínima 0,685. Não forcei salar nesse local incompatível.

## Classificação e transições

As dez famílias são: tropical úmido, savana, deserto, salar/deserto extremo,
temperado, pântano/planície úmida, taiga, tundra, alpino e polar. Cada score é
função contínua de temperatura e precipitação; contexto topográfico refina
somente famílias específicas. Scores são normalizados para soma 1. O ID do maior
peso é uma descrição discreta; os pesos não dependem desse ID.

- Pântano requer baixas altitudes, saturação/chuva e proxy contínuo de baixo
  relevo; cinturões altos/sopés próximos reduzem o peso. Não há hidrologia.
- Alpino exige altitude >580 m para ter score e frio de montanha; não depende
  de latitude polar. Planície fria não se torna alpina.
- Polar exige alta latitude e forte frio para dominar; tundra/taiga ocupam
  transições mais quentes.
- Salar/deserto extremo exige aridez forte; bacia fechada amplia o peso.
  A variante fora de bacia representa deserto extremo, não um salar geológico.
- Vulcânico não é bioma. Província ígnea mantém classificação climática normal.

Os dez pesos completos são a API para consumidores futuros. A malha transporta
campos e apenas os dois IDs principais com razão entre seus scores, para debug
leve. O modo blend visual é aproximação de duas cores; não representa todos os
dez pesos, que permanecem consultáveis pela API.

## Integração e debug

`PlanetDefinition.climate_enabled=true` no PlanetLab. Se o terreno estiver
desabilitado, clima também não é construído. O quadtree mantém SSE/histerese,
LOD, 2:1, stitching, morph e budgets anteriores; nenhum bioma move vértices.
CUSTOM2 guarda os quatro campos climáticos; CUSTOM3 guarda rain shadow, dois IDs
e mistura visual. São 8 bytes/vértice adicionais em RGBA8_UNORM, com arrays alocados por patch,
não por consulta. Material permanece técnico/unshaded.

F4 conserva relevo/quadtree; F5 conserva geologia; F6 percorre temperatura,
umidade, influência oceânica, precipitação, sombra de chuva, bioma dominante
e blend. Overlay informa valores na direção da câmera. Cores categóricas são
`flat` por triângulo e podem facetar; campos contínuos interpolam. Nenhuma
textura/material final, neve, rio, vegetação ou recurso mineral é produzido.

## Estatísticas globais, testes e performance

Amostragem de 16.384 direções Fibonacci de área aproximadamente igual,
independente da malha, na seed 73129: 7.273 pontos terrestres (44,39%).
Temperatura terrestre mínima/média/máxima: −30,12/4,30/29,18 °C; umidade:
0/0,567/1. Os dominantes em terra foram tropical úmido 7,70%, savana 3,24%,
deserto 2,09%, salar/deserto extremo 4,50%, temperado 26,95%, pântano 9,57%,
taiga 20,49%, tundra 8,76%, alpino 0,98% e polar 15,73%. A tabela por quatro
bandas de latitude e três de altitude, bem como os extremos de precipitação,
está na saída `CLIMATE_GLOBAL` preservada em `docs/evidence/05_clima_biomas/`.
Essa distribuição é específica da seed; não foi ajustada para quotas rígidas.

Testes permanentes cobrem seed/ordem de consulta, controles de latitude,
altitude, maritimidade, barreiras reais, bacia árida, dez famílias, pesos
normalizados, fronteiras de bioma, 12 arestas entre faces, oito cantos e
LODs 0/1/2/4/6/17/24. O teste de mesh confere os canais climáticos após
quantização RGBA8; teste de controlador mantém 2:1, budgets e convergência.
A regressão integral de câmera, fundação, quadtree, terreno base e geologia
permanece separada. A inspeção gráfica convergiu em 39 poses globais e
regionais, incluindo borda entre faces e afastamento; F6 foi capturado nos
modos 16..22. Não houve fissura visível nas poses inspecionadas. O usuário
relatou ausência de pausas relevantes em aproximação, voo lateral próximo e
afastamento, e considerou os mapas visualmente coerentes; isso não prova
ausência de picos em todo hardware/percurso.

Validação headless final: importação e cena principal com saída 0; câmeras,
fundação, quadtree (630.955), terreno base (694.703), terreno geológico
(694.706), geologia (158.752) e clima (142.252 verificações), todos com
saída 0. Fingerprints de terreno, geologia e clima coincidiram em processos
independentes. Apenas os dois warnings intencionais dos casos negativos do
CameraManager foram emitidos; nenhum erro de script foi encontrado.

Perfil Vulkan Forward+ na AMD Radeon Vega 3, rota idêntica de 2.580 updates,
warmup orbital separado, 1100×760, mesmo SSE/budgets e geologia ligada:
sem clima → com clima, tempo de geração 21,12 → 37,40 µs/vértice
(+77%); vértices gerados na janela fixa 322.344 → 226.512 e warmup até
idle 925 → 1.554 updates. O trabalho fica parcelado pelos budgets existentes,
mas o refinamento pode levar mais tempo. Nesta dupla, update p95
5,59 → 7,07 ms; frame p95 31,24 → 17,39 ms. O p95 de frame variou
substancialmente entre execuções mesmo sem clima, portanto a redução de
frame **não** demonstra aceleração. Uma captura climática isolada registrou
warmup 119,12 ms; na repetição instrumentada o pico foi 26,35 ms,
24,89 ms em `visual_create_us` do primeiro visual. A origem do pico isolado
de 119 ms não foi confirmada. O custo incremental por vértice e o atraso
de convergência são confirmados. Dados brutos e capturas em
`docs/evidence/05_clima_biomas/`.

Na repetição gráfica, o frame p95 foi 30,14 ms e houve um frame isolado de
123,03 ms na fase próxima, embora `update_us` máximo tenha sido 17,85 ms e
`generate_us` máximo 8,56 ms. A origem do restante desse frame não foi
identificada; não atribuí-lo à consulta climática sem medição adicional.
A execução headless não é comparável ao perfil Vulkan, pois não exercita a
mesma renderização. O teste manual não percebeu pausa relevante nas manobras
solicitadas. Nenhum budget, limite de LOD ou SSE foi reduzido.

## Limites

Oceano usa continentalidade como proxy, não alcance físico de ventos a partir de
cada costa. O cinturão é envelope estático, não fluido/pressão atmosférica. Não há
estações, neve dinâmica, rios, drenagem, solos ou ecologia. Biomas são famílias
procedurais para testes/futuras transições, sem material final. Alterar parâmetros
de relevo/geologia exige revalidar clima, especialmente montanhas e costa.
Pesos são contínuos no campo; IDs podem mudar em fronteiras reais. A amostragem
não prova estatísticas universais para qualquer seed/engine.
