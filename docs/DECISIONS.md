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
