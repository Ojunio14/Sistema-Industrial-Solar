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
