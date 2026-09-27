# Etapa 14 — designação por grid e níveis

## Decisão de mecânica

A autoridade do plano é GRID + LEVELS. O jogador designa células de 2 × 2 m;
o número em cada célula representa o nível desejado, nunca a altura atual.
Uma plataforma tem um nível comum. Uma rampa conecta dois níveis, com targets
contínuos intermediários. Não existe brush inclinado como autoridade, RampMesh,
máquina, estoque ou conservação de massa nesta etapa.

`TerrainLevelDatum` é uma referência planetária compartilhada por todas as
Mining Zones. No Lab normal: origem = 0 m em relação ao raio de referência,
LEVEL_STEP = 1 m. `target_height = origin + planned_level * level_step`.
`PlanetRoot.level_origin_height` e `level_step` configuram o datum antes da
criação dos planos. Alterá-lo em dados persistidos exigirá uma migração explícita;
não há rebase por seleção, por câmera ou por zona. Níveis negativos são válidos.
Os endpoints são inteiros. Frações da rampa vêm diretamente da coordenada na
grid, sem somar passos float sucessivos. A arquitetura já compartilha a mesma
referência entre zonas; alinhamento de grids de zonas vizinhas continua futuro.

## Dados e contratos

- `TerrainDesignation`: retângulo, tipo, anchors de nível, eixo/sentido,
  operação (CUT_AND_FILL, CUT_ONLY ou FILL_ONLY), identificador e início do trabalho.
- `TerrainDesignationStore`: planos confirmados, datum único, validação,
  avaliação incremental e aplicação DEV. Nenhum dado de cor faz parte do modelo.
- Cada célula avaliada expõe `planned_level`, `target_height`,
  `current_final_height`, `height_difference`, `operation`, `height_state`,
  `work_state`, erro máximo, corte/aterro estimados e indicador de corte/aterro mistos.
- O estado de altura usa a diferença no centro da célula, sobre a mesma diagonal
  da malha. CUT_REQUIRED acima do target+tolerância; FILL_REQUIRED abaixo;
  AT_TARGET dentro. Tolerância técnica configurável: 5 cm.
- COMPLETE exige **todos os quatro vértices** dentro da tolerância. Assim, um
  centro no alvo não mascara terreno irregular nos cantos. IN_PROGRESS resulta
  de aplicação parcial iniciada; PLANNED é uma ordem ainda não executada.
- Volumes CUT/FILL são estimativas por quadratura dos vértices dos dois
  triângulos, com área horizontal da esfera de referência. Sinal misto dentro
  de um triângulo não tem integração exata; estes números não são inventário.

Avaliação consulta altura natural + deltas nos vértices e reutiliza esse
snapshot para estados, volumes e desenho. Avança com até 256 itens / 1,5 ms por
frame (budget flexível). Mudanças de terreno invalidam a avaliação. Antes do
DEV APPLY, revisões do terreno e dos planos são conferidas novamente.

## Rampa e continuidade

A faixa é alinhada a um dos eixos da chart da zona. O arrasto escolhe eixo e
sentido; a largura usa 2–6 células, ou 4/6/8/10/12 m. As bordas externas são
os endpoints. Os níveis mostrados nos centros podem ser fracionários, com até
duas casas apenas na apresentação; os targets não são arredondados para degraus.
Todos os vértices transversais recebem o mesmo nível interpolado.

A detecção consulta as células designadas adjacentes à extremidade inteira.
Se elas fornecem nível inteiro uniforme, ele vira anchor; caso contrário,
permanece o endpoint manual do debug. O HUD apresenta diferença de altura,
comprimento horizontal da chart e grade %. Limite técnico inicial: 30%,
configurável em `max_grade_percent`, sem pretensão de regra final de gameplay.
Rampas inválidas aparecem vermelhas e não podem ser confirmadas/aplicadas.

Planos não podem sobrepor células. Planos adjacentes devem concordar nos
vértices compartilhados, inclusive cantos. Targets conflitantes são recusados.
Uma mudança isolada de nível de plataforma conectada pode ser recusada até a
conexão ser redesenhada; edição conjunta de redes de ordens é trabalho futuro.
Faixa de proteção e limites da Mining Zone continuam sendo respeitados.

## Interação técnica

1. Aproxime-se do terreno e pressione **F10**. Uma zona existente na mira física
   é reutilizada; caso necessário, cria-se a zona técnica perto da câmera.
2. Aguarde mesh/colisão publicadas. Mouse esquerdo pressionado inicia a célula;
   arrastar define retângulo; soltar mantém preview, sem alterar terreno.
3. Use o campo LEVEL ou PgUp/PgDn. Shift+PgUp/PgDn modifica o nível final da rampa.
   Escolha Plataforma/Rampa, largura e operação no painel.
4. **Confirmar plano / Enter** guarda a ordem. Clique sem arrastar num plano
   existente para editar. Esc cancela preview; o botão de exclusão remove a ordem.
5. **DEV APPLY** aplica os planos confirmados da zona, após avaliações atuais.
   O HUD distingue targets atingidos nos dados de mesh/colisão ainda pendentes.
6. F10 fecha a interface, preservando planos em memória, zona e edições.

A roda permanece com a câmera. Enquanto o modo está aberto, Esc pertence ao
preview, não captura o mouse do FreeFly. F9 continua diagnóstico da Etapa 13.

## Overlay em batch

`TerrainDesignationOverlay` usa **dois nós de desenho**, independentemente da
quantidade de células: um ArrayMesh para quadrados e um MultiMesh para glyphs.
O atlas de dígitos de sete segmentos é gerado em memória; não há Label3D por célula.
As cores de corte/alvo/aterro pertencem ao renderer e podem ser substituídas.
Tracejado indica planejado, tom claro em execução e canto branco COMPLETE.

O desenho é restrito aos planos/preview da zona. A projeção fica sobre o maior
entre superfície atual e target, com pequeno afastamento **somente decorativo**.
Não possui colisão nem participa de FinalTerrain. Números desaparecem a mais de
140 m do centro do conjunto por padrão; a grid/colorização continua visível.
Há limite técnico de 4.096 células por plano e 8.192 no total. Construção da
geometria avança por lotes de até 256 células / 2 ms; upload final nativo não é
preemptível. Resultados medidos ficam no relatório de evidências.

## DEV APPLY e trabalho futuro

Fluxo: targets das designações → terrain_edit_delta → FinalTerrain → jobs
existentes da Etapa 13 → mesh e colisão publicadas juntas. A rampa não introduz
uma segunda malha de terreno. Limites de delta são checados para a transação
inteira antes de qualquer escrita; não ocorre aplicação parcial por erro.
Snapshots obsoletos, zonas inativas e conflitos de operações compartilhadas
são recusados. Reaplicar um plano concluído não suja chunks desnecessariamente.

`apply_evaluations(..., max_change_m)` permite um passo finito por vértice,
testado sem máquina ou progresso percentual armazenado. O target permanece
fixo enquanto a quantidade restante muda. O botão DEV aplica de uma vez; essa
transação de escrita é síncrona e limitada pelo tamanho máximo das ordens.
Antes de execução produtiva por máquinas, deve ser particionada em comandos
pequenos com política de prioridade e publicação das revisões.

## Demonstração e testes

`tests/planet/designation_test.gd`: níveis/datum, zonas, frações, limites,
anchors, continuidade, operações, progresso, idempotência e revisões obsoletas.

`tests/planet/designation_demo.gd`: Planet Lab real, seleção por eventos de
mouse e raycast, plataforma Level 10, rampa 20 × 8 m (25%) e plataforma Level 5.
Apenas nessa demonstração, o datum planetário é escolhido uma vez antes dos
planos para colocar 10/5 perto do terreno natural. A origem é registrada nos
resultados e não muda entre plataformas ou zonas. Após DEV APPLY, verifica
todos os targets, normais e vértices compartilhados, colisão e raycasts.
Também mede o overlay de 4.096 células adicionais e ocultação distante dos números.

Execute com `--script res://tests/planet/designation_demo.gd`; sem `--headless`,
ele grava as capturas reais. Argumento após `--` escolhe a pasta de evidência.
O runner permanente acrescenta contratos e demonstração às regressões existentes.

## Limitações classificadas

- **CONFIRMADO:** rampas retangulares alinhadas à chart; sem curvas/arcos.
- **CONFIRMADO:** datum global consistente, mas sem costura de designações entre
  charts diferentes, persistência de planos ou seleção de várias zonas na UI.
- **CONFIRMADO:** dados podem atingir COMPLETE antes da publicação assíncrona;
  o HUD informa separadamente o estado de mesh/colisão. Picking usa a física publicada.
- **CONFIRMADO:** aplicação DEV é atômica/síncrona; upload do batch é indivisível.
- **RISCO:** seleções extensas e muitos glyphs podem elevar CPU/GPU e memória.
- **DÍVIDA TÉCNICA:** aplicação gradual por comandos, undo, salvamento, rede de
  ordens conectadas, políticas de operações e rampas arbitrariamente orientadas.
- **SUSPEITO:** diferenças de tempo entre ensaios podem incluir LOD, driver e SO;
  medições do overlay não isolam todo custo externo ao renderer de designações.

Não foi implementada máquina, material removido, transporte, estoque ou mineração jogável.
