# Etapa 3 — Relevo macro

Estado: implementação e validação técnica concluídas em 22/09/2026.
O usuário confirmou não perceber pausas relevantes no voo manual com o relevo.

## Contratos e escopo

Autoridade central determinística `PlanetTerrain.sample(direction) -> altura em
metros`, relativa ao nível do mar 0. Direção unitária global, sem face, patch, LOD,
câmera ou ordem de consulta. Seed na definição planetária; descritores construídos
uma vez por RNG local e somente lidos durante amostragem. Mesh é representação
derivada. Meta padrão: 42–48% de terra em amostragem aproximadamente uniforme.

Preservados seis quadtrees, SSE/histerese, 2:1, 16 máscaras, morph coarse-terreno →
fine-terreno e budgets da Etapa 2. Sem WorkerThreadPool, aumento do LOD máximo ou
mudança das convenções matemáticas da Etapa 1.

## Seed e pipeline efetivo

Cinco âncoras continentais orientadas pela seed, múltiplos lóbulos, regiões menores
nos espaços oceânicos, arquipélagos e mares internos explícitos. Campo direcional
contínuo, warp costeiro de baixa frequência e calibração global na construção.
Macroformas regionais orientadas: planícies, colinas, planaltos, serras, cadeias,
vales/bacias e relevo excepcional. Batimetria costeira e bacias profundas genéricas.
Limites globais: −3.100 a +2.200 m. Esses limites não são metas por vértice.

Seed padrão **73129**, em `PlanetDefinition.terrain_seed`, explícita no resource
padrão. `terrain_enabled=false` conserva a esfera de referência. Recriar PlanetLab
após alterar seed/configuração; não há hot reload/save-load. Com terreno habilitado,
o raio precisa superar 3.100 m para evitar inversão da superfície. Alturas são
convertidas uma única vez de metros para unidades.

1. RNG local constrói rotação global, fases, raios e orientações.
2. Cinco âncoras Fibonacci, cada uma com três lóbulos; não é threshold de noise.
3. Busca de espaços oceânicos posiciona dois continentes menores, duas ilhas
   relevantes e quatro arquipélagos de ilha-base + quatro ilhas menores.
4. Duas regiões subtraídas geram mares internos. Algumas bacias também cruzam zero.
5. Caps afins em direção 3D, união por máximo/subtração por mínimo; warp de baixa
   frequência (amplitude angular 0,025). Sem convenções de faces duplicadas.
6. Construção calibra bias por busca binária em 4.096 direções aproximadamente
   uniformes, alvo continental 45,3%; depressões reduzem um pouco a terra efetiva.
7. Regiões terrestres orientadas e batimetria consultam esse campo.

`sample_fields` devolve Vector4: altura, continentalidade, macroforma e
proximidade costeira. Não cria RNG, descritores, arrays ou dicionários por consulta.
Índice espacial imutável 8³ em direções cartesianas descarta apenas caps incapazes
de vencer em toda a célula fechada e regiões fora de suporte conservador.
Comparação com todos os descritores e testes nas fronteiras verificam equivalência.

## Costas e batimetria

Envelopes smoothstep de largura angular 0,045 conectam terra e oceano continuamente
em zero. Warp subordinado à estrutura, sem fractal de alta frequência. A largura
física varia com o gradiente: pequenas regiões podem ter costas mais rápidas.
Não há sistema de falésias/erosão.

Faixa rasa, aprofundamento até oceano comum e três bacias profundas genéricas,
uma mais estreita/intensa; variação global suave, sem tectônica. Azul é o próprio
fundo oceânico, **não água física** nem uma segunda esfera.
Uniões são contínuas, não necessariamente C1: cristas submarinas/transições de
inclinação podem ficar visíveis. Isso não corresponde a seams entre cube faces.

## Macroformas e parâmetros calibráveis

Elipses no plano tangente local, suporte finito, centros/orientações globais.
Permitem futura influência regional sem transferir autoridade ao renderer.

| Forma | Configuração atual |
|---|---|
| Planície | Base 190 m, variação ±65 m; extensas áreas simples |
| Colinas | Até 260 m adicionais, variação regional moderada |
| Planalto | 450–700 m adicionais, interior plano e borda gradual |
| Serra | Amplitude 520 m, orientada |
| Cadeia | Amplitude 950–1.300 m, suporte longitudinal 16–25 km a R=50 km |
| Vale | Até 260 m abaixo da região |
| Bacia | Até 420 m abaixo da região, em alguns continentes |
| Excepcional | Região rara, amplitude 1.800 m |

Parâmetros centralizados no sampler. Comprimentos angulares calibrados para raio
50 km; alterar amplitude/frequência/raio exige revalidar distribuição e SSE.
Não há garantia estética para qualquer seed nem promessa de bit-identidade entre
versões da engine/plataformas.

## Distribuição e alturas medidas

16.384 direções Fibonacci; altura > 0 conta como terra:

- **44,4397% terra / 55,5603% oceano**, dentro do assert 42–48%.
- Terra: mínimo 0,0037 m, média 201,37 m, máximo 1.761,67 m.
- Profundidade: mínimo praticamente 0, média 907,98 m, máximo 2.667,45 m.
- 93 cruzamentos costeiros bissetados; diferença final de altura < 0,10 m.
- Todos finitos/dentro dos limites. Amostragem não prova extremos globais.

Macroforma dominante (inclui bordas, sobreposições e costa; não amplitude pura):

| Forma | Média / máximo observado (m) |
|---|---:|
| Planície | 163,66 / 254,94 |
| Colinas | 270,92 / 504,20 |
| Planalto | 624,15 / 904,55 |
| Serra | 312,81 / 921,61 |
| Cadeia | 529,26 / 1.247,77 |
| Excepcional | 682,92 / 1.761,67 |
| Vale | média 25,06; mínimo −121,25 |
| Bacia | média −84,20; mínimo −262,11 |

Cinco grupos continentais explícitos. Forma/conectividade inspecionadas no mapa de
área igual e nos hemisférios; não há contador topológico robusto de continentes.
Quantidade de descritores não é medição independente de componentes conectados.

## Integração: quadtree, SSE, morph e normais

- Geração incremental: até 64 vértices por bloco, uma consulta de campo por vértice.
- Bound de seleção/culling: bound da esfera + 3.100 m convertidos; desigualdade
  triangular cobre deslocamentos positivos e negativos.
- AABB contém vértices fine e endpoints coarse, logo todo o morph.
- SSE mantém política/histerese e soma estimativa de erro de relevo por envelopes
  de curvatura global/regional, escala de célula ao quadrado e teto da faixa
  vertical. Colinas incluem a frequência secundária no envelope.
- Dois resíduos acima da estimativa inicial foram corrigidos. Teste adicional
  de 32.768 pontos/níveis/máscaras: pior erro/(estimativa+epsilon) **0,62617**.
  É evidência amostral, não prova analítica universal.
- Mantidos LOD máximo **6**, split **8**, merge **2**, commits **4**, CPU **4 ms**,
  morph **0,35 s**. Sem WorkerThreadPool.
- Coarse sampler usa a mesma instância de terreno e triângulos coarse reais;
  caches imutáveis, 2:1/16 máscaras/clock comum preservados inclusive no merge.
- Material técnico **unshaded**: iluminação auxiliar por derivadas da posição
  do triângulo morphed, não normal radial como normal física do relevo.
  Facetamento é possível; não são normais suaves/materiais finais.

## Debug e visual

F4: faces/LOD → terra/oceano → altitude → continentalidade → macroformas →
nível do mar → costas. IDs, bordas e contadores da Etapa 2 preservados.
Overlay informa seed, altura radial e macroforma. Costas incluem também |h| < 50 m
para reconhecer bordas de depressões. Sem texturas externas.
IDs de macroformas usam interpolação flat por triângulo: não inventam categorias
intermediárias entre vértices. Esse debug categórico tem a resolução da mesh,
não é um mapa contínuo de materiais/biomas.

Godot 4.6.1, Forward+/Vulkan, AMD Radeon Vega 3, 1100×760: seis vistas globais,
colinas, planalto, cadeia, serra, vale, bacia, excepcional, arquipélago, mar interno,
oceano, borda +X/+Z, afastamento e debug. Capturas aguardam estado estável/2:1;
roteiro alcançou 552 folhas. Evidências: `docs/evidence/03_relevo_macro/`.

**Estética aberta:** ilhas/mares internos e algumas massas bastante arredondados;
colinas têm regularidade perceptível. Macroformas deliberadamente simples.
Costas/debug podem evidenciar facetamento da representação finita. Não houve
ajuste indefinido para esconder esses aspectos.
Screenshots não provam ausência de popping em qualquer voo; endpoints, interiores
de triângulos e bordas em cinco fatores de morph possuem validação numérica.
Usuário confirmou não perceber pausas relevantes após testar o relevo.

## Testes

`tests/planet/run_validation.ps1`, Godot 4.6.1, todos saída 0:

- editor/importação, cena principal, câmeras e Fundação Planetária;
- quadtree: **630.955 verificações**;
- roteiro visual legado da Etapa 2, fixado na esfera lisa: `VISUAL_TEST_OK`;
- relevo: **694.703 verificações** (inclui benchmark/oráculo completo final);
- dois processos independentes, fingerprint idêntico:
  `e0785384a84e9d50ea5a0f8b0ec1d7973aad58717e7ebc609e120548f70b3d2e`.

Cobertura: determinismo/ordem/seed diferente; finitude/limites/distribuição;
12 arestas (24 dirigidas)/8 cantos/patches/LODs; índices espaciais e unidades;
costas; radius+height/winding/índices/16 máscaras; bounds/AABB/SSE;
coarse/fine/stitching/morph forward/reverse nas montanhas, planalto e costa;
2:1/budgets/convergência às seis raízes.

Somente dois warnings esperados de CameraManager. Primeira importação em sandbox
teve erros ambientais de configurações/certificados; repetição autorizada fora
do sandbox eliminou esses erros. Comandos: `tests/planet/README.md`.

## Performance

Capturas sequenciais, mesma trajetória/viewport/debug/budgets. Rota de **2.580
updates**, delta simulado 0,05 s, distância mínima **53 km** em ambos os casos.
Visão orbital estabilizada antes da captura, aquecimento separado.

| Medida | Esfera | Relevo |
|---|---:|---:|
| Update p95 | 4,320 ms | 4,710 ms |
| Update pico | 10,686 ms | 30,897 ms |
| Frame p95 | 30,398 ms | 16,731 ms |
| Frame pico | 74,441 ms | 35,215 ms |
| Geração acumulada | 249,367 ms | 5.027,459 ms |
| Vértices gerados | 291.852 | 553.212 |
| Geração/vértice (inclui preparação) | 0,854 µs | 9,088 µs |
| Pico de folhas | 114 | 495 |
| Aquecimento orbital | 26 updates | 546 updates |
| Inicialização PlanetLab | 7,073 ms | 91,801 ms |

Comparação isolada final (mesmos descritores e 16.384 direções pré-calculadas,
mediana de três passagens): **16,117 µs/consulta** sem descarte espacial versus
**8,351 µs/consulta** indexada, com igualdade exata de todas as alturas.
O benchmark geral, incluindo gerar direção, mediu ~9–13 µs depois dos índices.
Sem timer individual por vértice. Na rota prolongada,
sampler+deslocamento/atributos: total 4.778,827 ms, pico/update 5,065 ms;
é subconjunto do tempo de geração, não somar os dois.

Pico maior no afastamento: seleção/balanceamento 30,879 ms, sendo 21,003 ms
em balanceamento. Relevo gera mais trabalho/patches pelo mesmo SSE. Não houve
retorno aos travamentos graves anteriores; confirmação manual positiva do usuário.

Limites: frame inclui engine/render/wait, não é GPU timer; não concluir que terreno
acelera GPU pelo p95 menor. Budget CPU é soft. A rota fixa terminou com merges
ainda em preparação no relevo; roteiro visual separado aguardou convergência.
Inicialização/cache/shader frio podem ter picos fora da captura aquecida.
Não é garantia de FPS perfeito nem ausência de qualquer microstutter.

## Problemas e limites restantes

- **CONFIRMADO, não bloqueador:** regularidade/facetamento técnico, sampler/shader;
  estética sujeita à avaliação.
- **CONFIRMADO, não bloqueador:** pico residual ~31 ms na seleção/balanceamento
  de árvore maior, `planet_quadtree_view.gd`; budget soft.
- **RISCO:** estimativa SSE validada para parâmetros/casos atuais, não prova
  universal. Revalidar ao alterar frequências/amplitudes.
- **DÍVIDA TÉCNICA delimitada:** acabamento de normais/materiais é técnico.
- Fora de escopo, já conhecido: FreeFly atravessa terreno; RTS/Orbital ainda não
  constituem navegação planetária completa. Sem correções oportunistas.
- Nenhuma suspeita adicional de falha estrutural encontrada nos casos testados.

## Fora de escopo

Geologia/tectônica, clima, biomas, materiais finais, erosão, rios simulados,
vegetação, mineração, colisão detalhada e save/load.
Sem operações Git.

Próxima etapa prevista: **Etapa 4 — geologia**, não iniciada; aprovar sua
especificação antes de acrescentar significado geológico às macroformas.
