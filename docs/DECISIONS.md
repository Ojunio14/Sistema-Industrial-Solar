# Decisões aprovadas — Planet v0.1

## Escala do Planet v0.1

- **Status:** Aprovado
- **Decisão:** usar 1 unidade Godot = 1 metro, raio planejado de 50.000 m e diâmetro de 100 km. O protótipo inicial usa float32 e não adota Large World Coordinates.
- **Motivo:** estabelecer uma escala operacional clara para a primeira versão.
- **Consequências:** os sistemas iniciais devem ser validados nessa escala e não podem presumir suporte a Large World Coordinates.

## Escala adaptativa/perceptual

- **Status:** Aprovado
- **Decisão:** o planeta não será a Terra reduzida por um único fator matemático. Escalas planetária, regional, vertical e industrial podem ser comprimidas ou exageradas de formas diferentes.
- **Motivo:** preservar percepção e gameplay nas diferentes escalas de interação.
- **Consequências:** proporções não devem ser inferidas a partir de uma redução uniforme da Terra.

## Terreno

- **Status:** Aprovado
- **Decisão:** definir a macroforma antes do detalhe procedural e evitar a abordagem “noise + noise + noise = planeta”.
- **Motivo:** manter estrutura, controle e legibilidade do relevo.
- **Consequências:** ruído procedural poderá complementar dados estruturados, mas não substituir a macroforma.

## Geologia e bioma

- **Status:** Aprovado
- **Decisão:** geologia e bioma são sistemas distintos; recursos minerais não são determinados diretamente pelo bioma.
- **Motivo:** separar processos físicos e classificações ambientais diferentes.
- **Consequências:** dados minerais devem derivar da geologia, ainda que outros sistemas possam influenciar sua apresentação ou acesso.

## Reaproveitamento do protótipo antigo

- **Status:** Aprovado
- **Decisão:** Planet v0.1 não preserva a arquitetura antiga por compatibilidade. Somente componentes alinhados à arquitetura atual podem ser reaproveitados.
- **Motivo:** evitar que decisões experimentais restrinjam a nova fundação.
- **Consequências:** o protótipo antigo foi removido na Etapa 0 e futuras necessidades serão implementadas sobre contratos atuais.

## Câmeras

- **Status:** Aprovado
- **Decisão:** preservar as responsabilidades FreeFly/debug, RTS e Orbital em um sistema desacoplado da arquitetura planetária.
- **Motivo:** manter ferramentas de navegação úteis sem acoplar a fundação a um planeta ainda não implementado.
- **Consequências:** RTS e Orbital terão validação planetária específica quando existir geometria planetária real.

## Assets/texturas

- **Status:** Aprovado
- **Decisão:** não adicionar texturas finais antecipadamente. Assets entram quando a etapa correspondente exigir e seus requisitos técnicos estiverem definidos.
- **Motivo:** evitar dependências prematuras e assets órfãos.
- **Consequências:** cada etapa deve justificar os assets que introduzir.


## Substituição integral pela fundação doadora — Etapa 6

- **Status:** aprovado explicitamente pelo usuário em 23/09/2026.
- **Decisão:** usar PlanetShape, cube-sphere, chunks, LOD, normais e workers do
  Sistema_Industrial_v1 com preset 100 km/seed 12051965, sem híbrido com renderer
  anterior. Supera a implementação macro e a restrição de geração continental
  das Etapas 2–3: ruído/warp do doador são agora a autoridade natural deliberada.
- **Consequências:** antigas quotas/âncoras não são requisitos; geologia/clima/
  biomas preservados mas desconectados. Mineração e base_height + edit_delta
  continuam no plano. Nenhuma reintegração, efeito ou gameplay nesta execução.

## Continentes separados do relevo e resolução próxima — Etapa 10

- **Status:** direção arquitetural aprovada explicitamente pelo usuário em 24/09/2026.
- **Decisão:** preservar distribuição continental do doador em ContinentalShape,
  substituir completamente seu relevo terrestre por TerrainRelief orientado
  por descritores de geologia estrutural. PlanetShape compõe a altura natural.
  Supera a restrição geométrica da Etapa 7 e a tentativa parcial de apenas
  acrescentar detalhe sobre o relevo antigo.
- **Dependências:** continentes → geologia estrutural → relevo → clima → biomas.
  A classificação geológica superficial consome a altura final, mas não volta
  a dirigir relevo. Não há seleção de geometria por bioma ou clima.
- **Resolução:** 17×17, máximo LOD9, mesmos budgets/workers. LOD9 reduz o
  espaçamento pela metade (24,4→12,2 m no centro). 33×33/LOD8 atingiu densidade
  semelhante, mas ~469 mil vértices ativos e ~94 ms/chunk mediano, contra
  ~137 mil e ~23 ms com 17×17 no ensaio inicial congelado. A busca ordenada
  de vítimas para redistribuição de LOD encerra quando não há prioridade viável.
- **Consequências:** geologia v3 muda descritores e IDs; clima e biomas são
  reconstruídos sem preservar percentuais. O oráculo histórico fica somente
  em testes; runtime não requer projeto doador. Não há morph novo nem malha
  global de 2 m. Natural height + terrain edit delta continua o contrato futuro.
- **Evidências e limites:** [Etapa 10](stages/10_refinamento_relevo.md).

## Terreno editável separado do natural — Etapa 12

- **Status:** implementado conforme o escopo da Etapa 12, sem gameplay.
- **Decisão:** PlanetEditableTerrain é a autoridade da composição natural+delta.
  Zonas usam chart tangente gnomônico, IDs próprios e chunks 256 m/células 2 m;
  cube face não determina identidade ou orientação local. Heightfield radial
  de uma altura por coordenada, sem cavernas/overhangs.
- **Fronteiras:** amostras pertencem a um único chunk via floor(index/128),
  inclusive negativos. Perímetro externo zero, sobreposição de charts rejeitada
  por caps conservadoras. Interpolação por triângulo coincide com a malha técnica.
- **Ownership:** dados vivos na main thread, snapshots copiados para builders;
  revisões/epoch/atividade protegem a aceitação. Desativar nunca apaga deltas.
  Invalidação é regional, inclui halo de normais; collision terá consumidor próprio.
- **Renderização inicial:** inspeção técnica em World3D separado. O mundo principal
  continua exclusivamente global e natural. Não há superfície sobreposta nem
  mudança do shader PBR. Handoff global/local integrado continua futuro e deve
  manter cobertura exclusiva, com transição atômica e fronteira compatível.
- **Consequências:** preview pode pausar porque ainda é síncrono; não representa
  escavação jogável. Save, collision, jobs de produção e ferramentas ficam para
  depois. [Contrato completo](stages/12_mining_zones.md).

## Ownership integrado da superfície local — Etapa 13

- **Status:** implementação técnica conforme o escopo solicitado, sem gameplay.
- **Decisão:** recortar geometricamente os patches globais em worker e costurar
  o contorno cortado à borda natural de 2 m usando collar externo de 16 m.
  A captura registra folhas visíveis; o mesmo PlanetChunkBuilder reconstrói
  seus arrays deterministicamente, evitando bloqueio por readback da GPU.
- **Motivo:** máscara no shader sozinha não fecha diferenças entre tesselações
  nem resolve colisão; suprimir patches inteiros criaria lacunas fora do chart.
- **Consequências:** refinamento mínimo local LOD8, pins de folhas/ancestrais,
  faixa protegida de 4 m, separação conservadora de zonas e publicação inicial
  por zona após uploads progressivos. Nenhuma mudança de PlanetShape.
- **Async/física:** snapshots/revisões/sessão, fila limitada, um worker local
  por padrão, commits com budget flexível. Colisão final dividida em 16 shapes
  por chunk para distribuir criação/inserção. Render e física publicados
  mudam juntos; desativação conserva dados e restaura meshes globais originais.
- **Detalhes e limitações:** [Etapa 13](stages/13_integracao_terreno_editavel.md).


## Etapa 14 — GRID + LEVELS e rampas entre níveis

A correção de mecânica aprovada pelo usuário torna nível planejado a autoridade
conceitual da célula. Target height permanece derivado internamente. Datum é
planetário, estável e comum às zonas; origem 0 m e LEVEL_STEP 1 m são defaults
técnicos. Não há origem relativa a cada seleção.

Ramp conecta dois níveis: anchors detectados em plataformas adjacentes ou
informados manualmente. Targets de vértices são interpolados continuamente,
evitando degraus ao aplicar. Números fracionários nos centros são apresentação
do plano, nunca altura atual. Bordas de planos incompatíveis são rejeitadas.

Confirmar designação não altera terreno. Somente DEV APPLY escreve deltas;
FinalTerrain e a geração assíncrona da Etapa 13 continuam sendo a autoridade.
Grid/números usam batch, e os estados não dependem de cores no modelo de dados.
Implementação técnica com limites configuráveis, sem máquinas ou logística.

## Etapa 15 — Current e Target separados

Correção explícita de mecânica solicitada pelo usuário: os números da grid passam
a representar o nível do terreno final atualmente publicado. O nível planejado
continua autoridade da ordem, exibido como Target no HUD e em contorno separado.
Esta decisão substitui a apresentação descrita na Etapa 14, preservando seu
registro histórico, o datum planetário e a interpolação contínua das rampas.

F9 mantém recursos e muda visibilidade; ativar/desativar diagnóstico não controla
atividade do terreno. Apply da interface enfileira preparação em worker e troca
buffers por chunk em uma publicação coerente. Avaliações grandes usam snapshots
da mesma superfície CPU publicada que render/colisão. Ver contrato e limitações
em [Etapa 15](stages/15_ux_performance_designacao.md).
