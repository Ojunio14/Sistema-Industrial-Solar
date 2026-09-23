# Etapa 4 — Geologia Estrutural

Estado: concluída tecnicamente, com regressão, inspeção gráfica e profiling.
Confirmação de voo manual específica desta etapa ainda não recebida.
Referência: Godot 4.6.1, seed 73129, raio 50.000 m.

## Contratos

Sistema separado de terreno, clima, biomas e recursos. Províncias derivadas das
âncoras/macroformas da Etapa 3; não simula placas. Seed local = seed planetária
XOR 0x47454F31 (GEO1). IDs procedurais versionados, independentes de Node/LOD/face.
Consulta superficial, sem profundidade/estratigrafia/depósitos.

PlanetGeology.query_direction(unit_direction) retorna Vector4:
ID local, maturidade normalizada, peso dominante, deformação em metros.
type_of(ID) resolve tipo; stable_key(ID) inclui versão/seed; describe(ID) retorna
cópia de metadados. Consultas quentes não alocam objetos ou usam RNG.
Pesos suaves de todas as províncias influenciam altura, não a seleção discreta.

Terreno continua autoridade radial única. Modificadores limitados a −180/+260 m,
altura final permanece −3.100/+2.200 m. SSE recebe erro estrutural adicional.
Budgets, LOD máximo, 2:1, stitching e morph da base devem permanecer válidos.

## Modelo e geração

`systems/planet/geology/planet_geology.gd` constrói descritores regionais a partir
das âncoras e do blueprint das macroformas existentes. Não sorteia manchas
independentes: crátons pertencem aos grandes continentes; cinturões reaproveitam
orientação e suporte das cadeias/serras; bacias acompanham depressões/vales;
planaltos ganham contexto estrutural, um deles ígneo. A elevação excepcional
recebe contexto vulcânico localizado. Uma bacia interior recebe caráter fechado.

Antigas áreas marinhas são selecionadas por busca determinística nas margens
continentais baixas e emersas (altura base >20 m, continentalidade 0,025..0,16),
não pelo clima atual. A classificação é uma hipótese procedural de história,
não uma simulação temporal de transgressão marinha.

Cinco interiores antigos amplos têm maturidade intrínseca 0,82..0,98. Cadeias
jovens usam 0,12..0,42; serras antigas 0,65..0,90; igneísmo é mais jovem. Valores
normalizados não representam anos reais. A consulta mistura idades pelos mesmos
pesos contínuos: a idade intrínseca do descritor não é a maturidade misturada
perto de uma fronteira. Província dominante não significa maioria absoluta.

Fundo oceânico tem maturidade 0,35; plataformas continentais de fundo 0,65,
com transição costeira. O domínio oceânico estrutural usa continentalidade <=0;
depressões continentais abaixo de zero continuam continentais geologicamente.
Por isso porcentagem de fundo oceânico não é igual à fração de altura <0.

## Identidade e API

Versão do gerador: 1. IDs locais inteiros cabem exatamente em float32 (<2^24).
Os quatro bits baixos codificam o tipo. Chaves estruturais usam âncora continental
e tipo de macroforma, não Node nem posição arredondada. Plataformas de fundo têm
IDs próprios associados à âncora/ilha mais próxima; fundo oceânico usa ID 0.
A chave externa é `geo1:<seed>:<ID>`; não persista só o número local. Alterar
geração/layout de macroformas exige rever a versão antes de prometer compatibilidade
de saves. Ainda não existe migração/persistência de geologia.

- `query_direction(d)`: direção **unitária** em espaço local planetário.
- `query_position(p)`: posição finita, não nula, relativa ao centro; normaliza,
  ignora altitude/profundidade. Não recebe posição global do mundo.
- `query_with_continentality(d,c)`: integração interna com o mesmo contexto
  continental do terreno, evitando duplicar a consulta por vértice.
- `type_of(ID)`, `stable_key(ID)`, `describe(ID)`: tipo, chave e cópia dos metadados;
  `describe` retorna vazio para ID desconhecido.
- `descriptors()`: cópias das províncias estruturais explícitas; não enumera os
  domínios de fundo (estes são resolvidos por `describe`).
- `PlanetTerrain.sample_into(d, output)`: saída reutilizável `PlanetTerrainSample`
  pertencente ao job/consumidor, com campos terreno e geologia; sem estado scratch
  global. Geologia vive independentemente da instância de terreno que a construiu.

Consulta retorna só o peso normalizado do dominante, não um vetor de todos os
tipos. Internamente todas as influências contribuem. Consulta matemática não
aloca arrays/dicionários/objetos por amostra; metadados são uma API de diagnóstico,
fora do loop de vértices. Um índice cartesiano 8³ conservador reduz candidatos
sem mudar valores; não é quadtree e não depende das cube faces.

## Integração e idade no relevo

Modificadores usam coordenadas tangentes das macroformas, envelopes suaves e
mistura normalizada. Crátons: variação ampla de baixa amplitude. Cinturões:
diferença entre perfil original e perfil estrutural orientado; maturidade altera
largura, agressividade da crista e frequência de picos longitudinais. Bacias:
rebaixamento amplo, centro suave; fechadas têm depressão e ombros. Igneísmo:
edifício ou planalto localizado com depressão central simplificada. Planaltos:
reforço amplo com variação regional. Não são offsets constantes por enum.

Envelope continental/costeiro impede descontinuidade em c=0. A escolha discreta
do ID não entra no cálculo de altura/maturidade. Altura final é a base da Etapa 3
mais delta, limitada aos bounds globais já usados pelo renderer. SSE adiciona
estimativa de curvatura estrutural, sem mudar thresholds, budgets, grid, LOD máximo,
2:1 ou índices de stitching. É estimativa de engenharia validada por amostragem,
não prova universal para futuras calibrações.

`PlanetDefinition.geology_enabled` é true no PlanetLab. O construtor isolado
`PlanetTerrain.new(seed)` mantém a base da Etapa 3 para compatibilidade dos testes;
`PlanetTerrain.new(seed, true)` habilita integração. Ambas usam a mesma implementação
base, não duas superfícies. CUSTOM1 transporta geologia já calculada para o shader;
não há nova consulta por vértice exclusivamente para debug (16 bytes/vértice extras).

## Debug e inspeção

F4 preserva os sete modos de terreno/quadtree. F5 percorre modos 7..15: província,
maturidade, cráton, cinturão, sedimentar, ígneo, planalto, bacia fechada e antiga
área marinha. F4 sai da família geológica. Overlay mostra chave/tipo/maturidade,
peso e delta da direção da câmera, atualizado na cadência do debug existente.
Geologia não depende do overlay. Desligar overlay/bordas continua disponível.

IDs/tipos são categóricos por triângulo (`flat`); idade/peso interpolam.
Filtros exibem **dominância**, não todas as influências. O material é técnico,
sem texturas/biomas/materiais finais. Fronteiras categóricas facetadas e alterações
de amostragem durante LOD não significam seam no campo global.

## Distribuição medida

16.384 direções Fibonacci de área aproximadamente igual, sem ponderação pela mesh:

| Tipo dominante | Área global |
|---|---:|
| Fundo oceânico | 54,651% |
| Plataforma continental de fundo | 29,846% |
| Interior antigo | 8,594% |
| Cinturão | 2,228% |
| Antiga região marinha | 1,752% |
| Bacia sedimentar | 1,434% |
| Planalto estrutural | 0,818% |
| Bacia fechada | 0,342% |
| Ígneo/vulcânico | 0,336% |

33 descritores estruturais; 63 IDs observados incluindo fundos. Delta amostrado
−107,6965..+157,7445 m (média global −0,7747 m); 2.399 amostras com |delta|>0,1 m.
Maturidade misturada 0,218891..0,871543 (média global 0,481796).
Terra: 44,4397% → 44,3909%; altura terrestre média 201,3717 → 201,0502 m;
máxima 1.761,67 → 1.919,41 m. A batimetria oceânica estrutural não foi alterada;
a estatística de altura negativa inclui depressões continentais modificadas.

## Testes permanentes

`tests/planet/run_validation.ps1`: import/editor headless, cena principal,
câmeras, fundação, quadtree, terreno base, geologia, terreno integrado e repetição
de fingerprints em processos independentes. Execução completa: saída 0.

- Quadtree: 630.955 verificações.
- Terreno base: 694.703; integrado: 694.706; zero falhas.
- Geologia: 129.427; zero falhas.
- Ampliação final da suíte geológica: 158.752; zero falhas. Inclui oito seeds
  (0/1/2/42/73128/73129/73130/999983), IDs/finite/bounds/domínio oceânico;
  centros antigos marinhos ainda emersos e contraste/ombros jovens versus antigos.
- Geologia testa mesma seed/ordem invertida/seed diferente, contexto compartilhado,
  lifetime separado, IDs/metadados, classificação coerente e vulcanismo localizado.
- 12 arestas físicas/24 transições, oito cantos, UVs comuns nos níveis
  0/1/2/4/6/17/24; igualdade de classificação/campos em direções coincidentes.
- 110 fronteiras geológicas reais localizadas por bisseção: idade/delta contínuos,
  com tolerâncias 0,001 e 0,1 m; índices conservadores comparados com consulta
  completa, inclusive fronteiras dos bins.
- Alturas finitas/bounds, atributos derivados da API, composição base+delta,
  SSE global amostrado, 16 máscaras, coarse/fine, bordas durante morph em cinco
  fatores, AABB dos endpoints, controlador 2:1/budgets/convergência.
- Maior razão residual/SSE amostrada: 0,62617, tanto base quanto integração.
- Somente warnings esperados dos casos negativos de câmeras.

Fingerprints SHA256: geologia
`363a3680fbb2a31c98f8fc6e73ddadb8e7f301913be23cd72e2173cc84b735e7`;
terreno integrado
`62b5d4955196c029c60e560c3ae2066bd910e9ee261c3ab8cc70b1671e6fa0bb`.
A base manteve o fingerprint da Etapa 3. Determinismo validado neste build/plataforma,
sem promessa de igualdade binária entre engines/arquiteturas diferentes.

## Performance

Microbenchmark com direções pré-calculadas e mediana de três passagens de 16.384
consultas: base 10,157 µs; integrado 14,312 µs (+4,155 µs, ~41%). Consulta geológica
isolada 10,476 µs inclui recomputar contexto continental, que é reutilizado no
caminho integrado. Não somar esses tempos como se fossem o loop real.

Comparação gráfica sequencial da rota de 2.580 updates da Etapa 3, Vulkan Forward+,
Vega 3, 1100×760, delta simulado 0,05 s, debug/bordas ligados e modo altitude.
Near radius 53 km; sem outras suítes concorrentes. Base = código atual com
geologia desabilitada, preservando o mesmo pipeline de mesh/debug.

| Medida | Base Etapa 3 | Com geologia |
|---|---:|---:|
| Update CPU p95 / máximo | 4,711 / 25,544 ms | 5,095 / 18,726 ms |
| Frame p95 / máximo | 16,645 / 28,741 ms | 16,717 / 21,929 ms |
| Geração total | 5.744,298 ms | 6.466,265 ms |
| Vértices gerados na janela | 470.448 | 392.040 |
| Geração / vértice | 12,210 µs | 16,494 µs |
| Pico de folhas / folhas finais | 438 / 252 | 393 / 207 |
| Construção | 104,700 ms | 101,740 ms |
| Warmup updates / pico CPU | 636 / 9,447 ms | 845 / 22,616 ms |

Frame p95/máximo com geologia por fase: aproximação 16,799/17,157 ms;
próximo 16,739/17,052; lateral 16,590/16,872; afastamento 16,558/16,787.
O maior frame global ocorreu durante settle. Não foi observado retorno de picos
graves nessa medição; isso não prova ausência de stutter em qualquer voo/hardware.
O orçamento é flexível, não teto rígido; construção/warmup são custos separados.

Não interpretar o máximo menor como otimização: geologia custa mais por vértice
(~35% no gerador) e a janela limitada conclui menos trabalho. Ambas terminaram
com trabalho pendente (base planning; geologia morph); camera/time budget muda
os estados intermediários. Não houve redução de qualidade/thresholds/budgets.
A captura visual separada aguardou convergência/2:1 e alcançou até 576 folhas.
Geologia pode atrasar refinamento sob o mesmo budget; acompanhar em etapas futuras.
Nenhuma otimização adicional/WorkerThreadPool foi necessária com esses resultados.

## Resultado visual e evidências

73 capturas reais, 26 poses estabilizadas, saída `TERRAIN_VISUAL_OK`. Inspecionados
seis hemisférios de províncias, maturidade global, cadeia jovem/serra antiga,
planalto, bacias, ígneo e borda entre faces. Cinturões continuam alongados e ligados
às cadeias, interiores amplos e ígneo localizado; modificações de altitude são
graduais e discretas na visão global. Comparação direta de chain com a captura
da Etapa 3 preserva a macroforma. Nenhuma fissura visível nas poses inspecionadas.

Persistem contornos arredondados e semelhanças entre layouts continentais herdados
da base, sem aparência geológica final. Debug de dominância tem serrilhado/facetas
do raster de triângulos; maturidade permanece suave. Não se confunde fronteira
real de província com borda de cube face. Imagens estáticas não validam todos os
estados transitórios; testes numéricos complementam a inspeção.

Evidências e comandos reproduzíveis: `docs/evidence/04_geologia_estrutural/README.md`.
JSON contém rows brutos e resumos; logs completos e capturas estão preservados.

## Parâmetros calibráveis e limitações

Seed na definição; em PlanetGeology: suportes/prioridades por tipo, faixas de idade,
amplitudes, perfis e envelopes costeiros. Limites −180/+260 m controlam a integração;
mudar esses parâmetros exige repetir continuidade, classificação, SSE e profiling.
Não são novas configurações de LOD. A versão da identidade deve acompanhar mudanças
incompatíveis de geração, antes de qualquer consumidor persistente.

Modelo simplificado, sem tectônica física nem erosão. Layout herda as macroformas
e suas limitações estéticas; não prova plausibilidade geológica física. Fundo
oceânico usa uma identidade global; ilhas usam plataformas de fundo sem histórias
estruturais detalhadas. Camadas, litologias/minerais e profundidade continuam futuras.
Consultas/reconstruções continuam na main thread; orçamento CPU é flexível.
Sem WorkerThreadPool. As limitações prévias de câmera/colisão permanecem fora do escopo.

Inconsistência documental pré-existente confirmada: o parágrafo histórico de
quadtree em ARCHITECTURE.md ainda diz que seus mecanismos não estão implementados,
ao contrário da Etapa 2/CURRENT_STATUS e dos testes existentes. Não bloqueia a
geologia; não foi feita revisão histórica ampla desse documento nesta etapa.

## Fora de escopo

Recursos minerais, teor, estratigrafia em profundidade, tectônica física, clima,
biomas, materiais finais, erosão, vegetação e mineração. Sem operações Git.
