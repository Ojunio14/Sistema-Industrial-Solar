# Etapa 8 — Reintegração do clima

Estado: implementada sobre a fundação planetária da Etapa 6, após a geologia de
classificação da Etapa 7. PlanetShape continua sendo a única autoridade da
superfície natural. Clima é dado consultável; não produz biomas ou delta de altura.

## API e autoridade

`PlanetClimate.new(definition)` constrói campos globais uma vez. A subseed é
`definition.seed XOR 0x434C4938` (CLI8); um override explícito serve a testes
e configurações climáticas. `sample(direction)` e `sample_position(local_position)`
retornam `PlanetClimateSample`. `sample_into(direction, output)` permite reutilizar
o objeto de saída na main thread. Para workers, o consumidor fornece os componentes
de superfície já amostrados a `sample_with_surface_into(direction, surface, output)`.
Este último caminho só lê arrays e escalares imutáveis depois da construção; não
acessa Node, SceneTree, Resource mutável, RNG ou estado global e não aloca um
objeto de resultado por chamada. O output pertence exclusivamente ao caller.

O resultado contém temperatura em °C, umidade, índice de precipitação,
influência oceânica, sombra de chuva, exposição ao vento e altitude em metros.
`fields()` agrupa temperatura, umidade, oceanicidade e precipitação em Vector4
para debug. Nenhum ID ou peso de bioma é calculado. Latitude, direção e altitude
vêm do PlanetShape atual, não do terreno arquivado. A consulta é independente de
face cúbica, chunk, LOD, câmera e ordem de chamada.

## Modelo climático

- **Temperatura:** curva contínua pela latitude absoluta, aproximadamente 30 °C
  no equador e −25 °C nos polos antes do relevo. Há duas perturbações regionais
  suaves, e o oceano modera extremos. A altitude real acima do nível do mar
  reduz a temperatura em 0,0065 °C/m sob as demais condições iguais.
- **Oceano e continentalidade:** grade global equiretangular 192×96, amostrada
  de PlanetShape. Água e costa alimentam 16 passos de propagação local com
  longitude periódica e atenuação por distância angular. `1 - ocean_influence`
  é um índice de continentalidade, não distância costeira exata. A máscara de
  água local reforça a influência marítima quando necessário.
- **Umidade:** combina cinturões latitudinais, oceanicidade, duas variações
  regionais suaves, exposição barlavento e sombra de chuva. Precipitação deriva
  da umidade, com reforço barlavento e redução a sotavento. São índices
  relativos estáticos, não meteorologia temporal nem milímetros de chuva.
- **Circulação:** direção predominante varia com latitude: alísios, vento de
  médias latitudes e reversão polar simplificados, com componente meridional.
  Não há simulação atmosférica.
- **Sombra de chuva:** na construção da grade, seis amostras a montante do vento
  local leem a altitude e a máscara de montanhas reais de PlanetShape. Uma
  barreira mais alta que o local cria sombra; relevo ascendente exposto reforça
  barlavento. Os campos passam por uma suavização curta. Não há raymarch na
  consulta quente e as montanhas nunca são alteradas para produzir o efeito.

Geologia é independente e não entra na fórmula climática. O código antigo de
clima/biomas da Etapa 5 permanece em arquivo como histórico, fora do runtime.

## Debug e custo

F6 alterna desligado → temperatura → umidade → oceanicidade → precipitação →
sombra de chuva → desligado. F4 mantém o LOD e F5 mantém geologia; os modos
de material F5/F6 são mutuamente exclusivos. As duas texturas globais do debug
só são criadas ao pedir F6, e o shader as lê por direção planetária. O material
natural e a malha não recebem atributos climáticos extras. Desligar F6 restaura
o material natural sem reconstruir chunks.

No Godot 4.6.1 desta máquina, a construção custou cerca de 0,86–1,07 s;
8.192 consultas de campos com superfície já fornecida custaram 80–95 ms
(~10–12 µs/consulta). A medição mista, que também confere seed, altura e
estatísticas, custou ~530 ms. O chunk comparado antes/depois permaneceu em
~25–28 ms, dentro da variação da medição, pois o builder não consulta clima.
`climate.sample()` inclui uma nova consulta a PlanetShape e um objeto de saída;
8.192 chamadas diretas custaram ~188 ms na medição isolada.
O caminho normal do worker, filas, uploads e contagem de residentes seguem
iguais; a grade ocupa seis arrays Float32 de 192×96 amostras (~432 KiB antes de
overhead), mais as texturas opcionais. Construção síncrona na inicialização
continua um custo se houver muitos planetas ou reconfiguração frequente.

## Validação e calibração

`tests/planet/climate_test.gd` testa 8.192 direções quase uniformes, igualdade
exata de `base_height` antes/depois, determinismo entre processos, subseed,
controles de latitude/altitude/oceano, ordem de consulta, workers concorrentes,
12 arestas, oito cantos e mesmas direções construídas para cinco profundidades
de LOD. Índices, normais, bounds e erro LOD do chunk permanecem iguais.
`run_validation.ps1` inclui duas execuções climáticas e exige fingerprints iguais,
além das regressões anteriores de geologia e fundação.

Para a seed 12051965, 4.436 das 8.192 amostras ficam em terra. Nelas:

| Campo | Mínimo | Média | Máximo |
| --- | ---: | ---: | ---: |
| Temperatura (°C) | −26,18 | 3,53 | 29,27 |
| Umidade | 0,000 | 0,481 | 0,972 |
| Precipitação | 0,000 | 0,355 | 0,790 |
| Continentalidade | 0,002 | 0,483 | 0,937 |

Por latitude absoluta `abs(y)` em quatro quartos, temperaturas médias em terra:
22,66; 10,84; −1,81; −15,38 °C. Por altitude `<150`, `150–450` e `≥450` m:
4,44; 2,99; −0,56 °C. Essas últimas médias também refletem onde se localizam
as montanhas; a prova isolada do gradiente é o teste controlado de 6,5 °C/km.
Os polos não foram forçados à simetria: norte −24,33 °C, umidade 0,298 e
oceanicidade 0,145; sul −17,34 °C, umidade 0,532 e oceanicidade 1,000.

Um caso reproduzível na cadeia de médias/altas latitudes mede barlavento
`(0,596880, 0,795306, 0,105938)` com precipitação 0,467 e sombra 0,070;
sotavento `(0,621577, 0,783287, 0,010171)` com precipitação 0,329 e sombra
0,360. A barreira tem 406 m de altitude e máscara montanhosa 0,564. Esse par
mostra tendência coerente, não um modelo hidrológico físico completo.

`surface_visual_test.gd` captura nove poses naturais, cinco modos climáticos
em cada uma e alvos de equador, médias latitudes, polos, costa, interior e
lados opostos da cadeia. Os 43 PNGs comparáveis de superfície natural, F4 e
F5 tiveram hashes idênticos aos da Etapa 7 no mesmo renderizador. No projeto
principal, a rota de 720 frames passou com p95 17,00 ms e máximo 18,13 ms;
filas e workers estavam drenados nas capturas. Capturas, comparação de hashes
e logs completos da suíte ficam em `docs/evidence/08_reintegracao_clima/`
(`validation_logs_final/` registra a execução definitiva, com 34.865
verificações climáticas em cada um de dois processos e fingerprints iguais).

## Limitações

A grade global é deliberadamente baixa resolução: aproxima costas e sombras,
podendo suavizar vales pequenos e marcar padrões de células em zoom extremo.
Os campos são estáticos, sem estações, advecção real, chuva em mm, rios ou
hidrologia. A textura de debug interpola a grade; a consulta da API também
considera a altitude exata local, portanto as cores são aproximação visual.
Biomas, materiais finais, nuvens, atmosfera, chuva/neve visual, recursos e
mineração ficam para etapas futuras. A composição geométrica futura continua
`base_height(direction) + terrain_edit_delta(position_m) = final_height`.
