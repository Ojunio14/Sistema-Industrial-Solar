# Etapa 9 — Reintegração dos biomas

Estado: classificação superficial sobre PlanetShape, PlanetClimate e
PlanetGeology atuais. Bioma é dado derivado, nunca altura, textura ou material
final. O clima da Etapa 8 não foi recalibrado: a distribuição abaixo emergiu
diretamente da seed 12051965 e dos campos já aprovados.

## Arquitetura e API

`PlanetBiomes.new(definition, climate, geology)` reutiliza o clima e copia
somente os descritores de bacia fechada já construídos pela geologia.
`sample(direction)` e
`sample_position(local_position)` são conveniências na main thread: amostram
uma vez PlanetShape, reutilizam esses componentes para clima e
retornam `PlanetBiomeSample`. `sample_into` reutiliza a saída do caller.
`sample_with_context_into(direction, surface, climate_sample, output)` é o
caminho sem alocação de objetos por consulta: recebe os contextos já
disponíveis, lê somente arrays climáticos e descritores imutáveis e escreve
no output exclusivo do caller. Não consulta novamente PlanetShape, geologia,
oceanicidade ou rain shadow. É seguro para leitura concorrente por workers.
O cálculo de influência de bacia ocorre somente onde aridez extrema e baixa
altitude deixam o score de salar diferente de zero.
Nenhum passo usa RNG por amostra ou depende de face, chunk, LOD e câmera.

`PlanetBiomeSample` oferece `dominant`, `dominant_weight`, `secondary`,
`secondary_weight`, `top_pair_mix`, dez pesos normalizados e um proxy numérico
de inclinação regional. Água tem IDs −1 e pesos zero. O ID é categórico, mas
os scores e pesos mudam continuamente com os campos de entrada; fronteiras
entre dominantes não apagam a mistura. Consumidores futuros podem ler todos os
pesos ou apenas os dois principais.

## Dez famílias e fatores de adequação

Cada score usa curvas suaves de temperatura e disponibilidade de água. Esta
última combina umidade e precipitação; não é um simulador de hidrologia. A
normalização ocorre depois de calcular todos os scores terrestres.

| Família | Condições favorecidas |
| --- | --- |
| Tropical úmido | Calor, umidade e precipitação altas; equador seco não basta. |
| Savana | Calor e água intermediária, transição úmido–árido. |
| Deserto | Aridez com ampla faixa térmica, inclusive possibilidade fria. |
| Salar/deserto extremo | Aridez extrema, terreno baixo/plano e reforço de bacia fechada. |
| Temperado | Temperatura intermediária e água razoável, sem ser fallback universal. |
| Pântano/planície úmida | Água alta, baixa altitude e baixa inclinação regional. |
| Taiga/frio continental | Frio não extremo, água suficiente e leve preferência continental. |
| Tundra | Frio intenso, com redução quando o contexto montanhoso favorece alpino. |
| Alpino | Altitude, máscara de montanha ou inclinação e frio; planície polar não basta. |
| Polar | Frio extremo combinado a altas latitudes; latitude isolada não basta. |

Para pântano e alpino, `PlanetClimate.regional_slope(direction)` deriva um
gradiente do relevo real já amostrado na grade 192×96, com passo angular de
0,025 rad. É proxy regional (~1,25 km), não slope exato da normal de cada
triângulo. Montanha usa também a máscara z do `PlanetShape.sample_components`.
Salar recebe reforço contínuo da distância aos descritores geológicos
`CLOSED_BASIN`, com queda radial até zero na borda. A troca discreta do tipo
geológico dominante não altera os pesos. Uma bacia úmida não se torna salar;
a família combinada pode representar deserto extremo fora de bacia. Nenhuma
outra família usa geologia; especialmente `IGNEOUS` não é bioma nem altera
os pesos climáticos.

## Distribuição observada

Em 8.192 direções Fibonacci aproximadamente uniformes, 4.436 estão em terra.
Dominantes terrestres, sem quotas impostas:

| Bioma | Amostras | % terra |
| --- | ---: | ---: |
| Tropical úmido | 518 | 11,68 |
| Savana | 171 | 3,85 |
| Deserto | 771 | 17,38 |
| Salar/deserto extremo | 2 | 0,05 |
| Temperado | 905 | 20,40 |
| Pântano/planície úmida | 61 | 1,38 |
| Taiga | 814 | 18,35 |
| Tundra | 647 | 14,59 |
| Alpino | 220 | 4,96 |
| Polar | 327 | 7,37 |

As dez famílias aparecem. Temperado é o maior, mas representa cerca de um
quinto da terra. Deserto aparece nas zonas áridas reais. Polar concentra-se
na faixa alta de latitude, alpino nas maiores altitudes e pântano em áreas
baixas e planas. Salar/deserto extremo é muito raro: as duas amostras
dominantes caíram em bacia fechada com aridez extrema, sem reproduzir a quota
histórica da Etapa 5. Nos dominantes, pântano ficou abaixo de 131 m e
inclinação regional 0,068; alpino começou acima de 461 m; polar apareceu
somente em `abs(y) ≥ 0,823`.
O teste registra matrizes por quatro faixas de latitude, altitude, temperatura
e umidade em `BIOME_GLOBAL`; elas identificam anomalias sem tornar percentuais
exatos uma condição frágil de aprovação.

## Debug F7 e geometria

F7 alterna desligado → dominante categórico → blend de todos os dez pesos →
intensidade do dominante → desligado. F4, F5 e F6 permanecem disponíveis; os
materiais técnicos F5/F6/F7 são mutuamente exclusivos. Duas texturas globais
192×96 são criadas somente no primeiro F7. A primeira guarda cor categórica e
peso do dominante; a segunda, mistura colorida de todos os pesos. O shader F7
é técnico e não aplica texturas PBR. O visual é uma aproximação de resolução
global, enquanto a API por direção continua a classificação consultável.
Nenhum payload de bioma é anexado aos vértices ou chunks. Desligar F7 restaura
o mesmo material natural da Etapa 8, sem reconstrução.
Na captura gráfica final do projeto principal, os 88 PNGs comparáveis de superfície natural,
F4, F5 e F6 mantiveram hashes idênticos aos da Etapa 8. F7 foi capturado em
nove poses e dez alvos, um por família. A rota de 720 frames passou com p95
17,294 ms, máximo 31,107 ms e nenhum erro de shader. A cor categórica em zoom
próximo expõe a resolução da grade; o blend interpola pesos suavemente.

`biome_test.gd` prova igualdade de `base_height` em 8.192 direções, invariância
de arrays de posições, normais, UV, cor, índices, bounds e erro LOD antes/depois,
12 arestas, oito cantos e cinco níveis de LOD. A consulta concorrente de dois
workers usa contextos e outputs locais. Controles isolam quente/úmido, aridez,
bacia árida versus úmida, continuidade na borda de cada bacia, planície versus
encosta, montanha versus planície, frio polar e província ígnea. O runner
executa dois processos e compara o
fingerprint, além de manter todas as regressões das Etapas 6–8.

## Performance e preparação futura

A construção copia três descritores de bacia, sem varrer o globo; mediu
1,030 ms na última suíte do projeto principal. Nessa execução, 1.024
classificações com clima e superfície já fornecidos custaram 25,251 ms;
1.024 chamadas diretas `sample()` custaram 60,047 ms. A passagem de 8.192
direções com contexto já fornecido levou 344,758 ms, e a que também amostra
clima e superfície levou 1.779,050 ms. Há variação de CPU; estes
números não são orçamento fixo. O builder de chunks não consulta biomas, portanto
não há custo por vértice adicional na mesh natural. O primeiro F7 criou as
texturas sob demanda em 744,201 ms nesta máquina, uma pausa técnica confirmada,
sem custo por chunk nos quadros seguintes. A rota de 720 frames e os alvos
estão nas evidências da etapa.

Uma etapa de materiais poderá combinar os dez pesos com tipo/influência
geológica, inclinação, altitude e costa para obter pesos de `rock_generic`,
`rock_sedimentary`, `rock_volcanic`, `soil`, `sand`, `arid_ground`, `snow_ice`
e `gravel`. Bioma não equivale a textura; rocha vulcânica virá da geologia.
Nenhum desses materiais foi aplicado. Zonas de mineração futuras poderão
consultar clima, bioma e geologia por posição, mas o bioma nunca será
autoridade geométrica. A composição continua
`base_height(direction) + terrain_edit_delta(position_m) = final_height`.

## Limitações

Clima e classificação são estáticos, sem estações, rios ou hidrologia completa.
O proxy de inclinação regional não resolve vales pequenos; pântanos locais
exigirão dados finos quando houver vegetação/mineração. A textura global de
debug pode suavizar ou perder manchas raras em zoom próximo, sobretudo salar;
ela não substitui a API. Materiais finais, vegetação, recursos e deformação
permanecem fora desta etapa.
