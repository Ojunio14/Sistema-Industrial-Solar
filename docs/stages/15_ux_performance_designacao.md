# Etapa 15 — UX, grid 3D e performance da designação

Implementação técnica no Planet Lab, Godot 4.6.1. Sem máquinas, personagens,
logística ou recursos minerais. Não foi utilizado Git. Esta etapa substitui a
apresentação de níveis da Etapa 14; seus registros históricos permanecem intactos.

## Current e Target

`Current Level = (Current Final Height − datum.origin_height) / datum.level_step`.
O Current de uma célula é a altura no centro dos triângulos realmente publicados:
média dos dois vértices da diagonal compartilhada. O dado mantém a fração; o
rótulo próximo arredonda ao inteiro mais próximo. O HUD mostra o intervalo
fracionário de Current e distingue **TARGET LEVEL** e **TARGET HEIGHT**.

O datum permanece único por planeta, padrão 0 m / passo 1 m. Não existe datum
por seleção. Na demonstração em terra firme, o datum técnico é 88 m: Level 10
corresponde a 98 m e Level 5 a 93 m. A demonstração histórica de 72 células usa
91 m, como antes. Esses valores de fixture não alteram o Lab normal.

O início do arraste escolhe o Target a partir do Current da célula inicial.
Subir o morro com o mouse não modifica esse Target. Mudar o Target recalcula
estados/volumes e o contorno planejado, sem reamostrar a superfície atual nem
reconstruir a geometria da grid. CUT_REQUIRED / AT_TARGET / FILL_REQUIRED e
PLANNED / IN_PROGRESS / COMPLETE continuam dados independentes das cores.

## Grid 3D, rótulos e contorno

A grid usa **Current publicado + 7 cm de offset visual** em cada vértice de 2 m.
Não usa `max(current, target)` nem uma superfície horizontal no alvo. Tiles de
16 × 16 células compartilham 17 × 17 vértices e usam linhas opacas indexadas.
O shader recebe apenas limites de seleção e plano de Target para classificar
as cores. Chunks e tiles sem mudança de revisão reutilizam a geometria.

O Target é um contorno amarelo tracejado, separado e sem colisão, visível mesmo
quando está sob o relevo. Não substitui o terreno. A grid não possui quads
translúcidos sobre toda a área, sombras ou GI. Há no máximo 96 tiles no cache
quente; instâncias fora da seleção são liberadas após a nova publicação visual.

Números usam um atlas bitmap com fundo escuro e um MultiMesh, sem Label3D por
célula. São Current, não Target. Altura projetada próxima de 18 pixels, posição
acima dos cantos reais, limite de 128 rótulos, stride 1/2/4 conforme distância,
e ocultação além de 110 m por padrão. Não são gerados glifos fora da região
próxima ou da tela. Movimento, rotação ou FOV atualizam somente esse conjunto
de rótulos, com cadência de 150 ms; não reavaliam alturas.

## Mouse, picking e ownership de input

- `first_cell` é congelada no mouse-down; somente `last_cell` muda no movimento.
- Snap de 2 m, histerese de 15 cm na célula anterior e filtro de 1,5 pixel.
- Eventos são coalescidos: o handler solicita atualização; o processamento
  ocorre uma vez por frame. Retângulos crescem/encolhem por faixas adicionadas
  ou removidas. Trabalho parcial é preservado entre eventos.
- Mouse-up, inclusive sobre o HUD, termina apenas o preview. Enter/confirmação
  guarda a ordem; DEV APPLY é uma ação separada.
- Raycast aceita somente corpos locais identificados por zona/chunk e com
  revisão de colisão igual à mesh e aos dados. Durante reconstrução, mantém o
  último endpoint e informa pendência. Não projeta no terreno natural oculto.
- `CameraManager.designation_dragging` bloqueia movimento e troca de câmera
  durante o arraste. FreeFly/RTS/Orbital retomam os controles ao soltar, cancelar
  ou fechar F10. Com F10 aberto, botão direito permite navegar fora do arraste.

## Cache e avaliação assíncrona

MiningBuildJob retorna alturas naturais/finais e vértices CPU de sua revisão.
MiningSurfaceManager publica esses dados junto da mesma mesh/colisão, sem
readback da GPU. Payload lógico: 332.820 bytes por chunk, além dos caches de
avaliação e recursos já existentes; não é uma medida da memória total.

Current é cacheado por zona/chunk/nó, revisão de dados e revisão publicada.
Uma publicação invalida somente os chunks envolvidos. A avaliação retém os
registros de células e nós fora das faixas alteradas. Uma faixa de 64 células
adiciona 65 nós e 64 avaliações; encolher não reavalia os registros retidos.

Seleções publicadas com mais de 128 itens pendentes são avaliadas em um worker
destacado, limitado a um por store. Metadados, mapas e buffers copy-on-write são
capturados; o worker não lê nem escreve nós vivos da cena. Resultado obsoleto
por clock, epoch ou publicação é rejeitado. A grid começa a aparecer enquanto
estados/volumes terminam. A API offline mantém avaliação incremental limitada
para testes sem superfície publicada.

## F9

Antes, F9 construía/destruía diagnóstico, consultava alturas para bordas e podia
ativar/desativar a superfície local. Agora mantém CanvasLayer, meshes, material
e labels de chunks. Alternâncias quentes só mudam visibilidade/processamento.
F9 não cria nem desativa zonas; F10 continua responsável pela ativação da área.

O diagnóstico faz trabalho adiado em no máximo um chunk por frame visível.
Limites vêm dos vértices CPU publicados. Min/max de deltas são cacheados pela
revisão de dados; geometria pela revisão da mesh. Mudança de status de fila
atualiza texto sem reamostrar alturas. Com um chunk dirty, só sua geometria muda.

## DEV APPLY

O handler valida o preview pronto e enfileira a solicitação. Não percorre os
4225 vértices escrevendo deltas na main thread. O HUD distingue:
**dados pendentes → dados aplicados / mesh-colisão pendentes → publicação pronta**.

DesignationTransaction prepara em worker os deltas, buffers e conjunto dirty.
Uma cópia por chunk substitui milhares de `_write_node`, revisões e invalidações.
No commit, a main thread troca buffers e publica uma revisão coerente por chunk
afetado, incluindo halo de normais. O pipeline existente agenda geração,
uploads e colisão. Targets permanecem fixos; CUT_ONLY/FILL_ONLY e passo finito
continuam respeitados. Solicitação nova substitui a pendente; worker antigo,
mudança de plano ou edição concorrente não podem fazer rollback.

Instrumentação separa cálculo de deltas, buffers, dirty, troca de arrays,
revisão, enqueue, mesh em worker, faces de colisão em worker, upload e física.
`apply_evaluations` síncrono permanece somente como API offline de compatibilidade;
a interface usa exclusivamente `queue_apply`.

## Rampa

Anchors inteiros 10 → 5 permanecem níveis de extremidade. O Target é interpolado
continuamente nos vértices, sem degraus. Antes do Apply, números mostram Current
e o contorno mostra a inclinação planejada. Depois, Current converge ao Target.
A ligação plataforma 10 → rampa de 20 m / 8 m → plataforma 5 foi revalidada,
inclusive normais, vértices de fronteira e raycasts. Erro máximo físico: 3,906 mm.

## Performance e evidências

Veja [resultados e tabelas](../evidence/15_ux_performance_designacao/results.md).
São separados ensaios headless controlados e ensaios gráficos na Vega 3.
Medição de tempo total de quadro não equivale ao custo exclusivo do overlay.

## Roteiro manual curto

A. Aproxime a câmera de uma encosta e abra F10. Aguarde a superfície local.
Comece na parte baixa, arraste morro acima e solte: Current deve subir, Target
deve ficar fixo. PgUp/PgDn muda o alvo; Enter confirma sem editar terreno.

B. Clique DEV APPLY e navegue imediatamente com botão direito/WASD no FreeFly.
Observe dados pendentes, filas e mesh/colisão pendentes. A câmera deve responder;
Current muda quando a nova superfície é publicada.

C. Ligue/desligue F9 repetidamente. O diagnóstico deve reaparecer sem recriar
a zona. Após uma edição, somente chunks dirty atualizam seus limites.

D. Confirme plataformas 10 e 5, conecte-as com uma rampa suficientemente longa
(20 m para 5 m de desnível atende 25%), confira anchors/Target e aplique.
O resultado deve ser contínuo; os números continuam sendo Current.

O percurso foi executado por handlers reais em testes de cena e houve inspeção
visual das capturas. A avaliação subjetiva com uma pessoa operando o mouse não
é apresentada como teste manual executado.

## Limitações e classificação

- **CONFIRMADO:** a cena PBR completa continua limitada pela GPU Vega 3; há
  quadros acima de 200 ms mesmo com overlay oculto. Esta etapa não reescreve
  o renderer/material natural. A publicação de quatro chunks na cena pesada
  levou 17,6 s, em background, apesar do handler de 0,231 ms.
- **CONFIRMADO:** upload de mesh, criação de shape e publicação na main thread
  possuem passos indivisíveis; o budget é flexível, não um limite universal.
  A primeira ativação local e a compilação inicial de recursos continuam frias.
- **SUSPEITO:** frequência do hardware, driver e aquecimento de caches explicam
  parte da variação entre janelas GPU. Não atribuir ganho negativo de frame ao
  overlay nem comparar cenas diferentes como se fossem o mesmo ensaio.
- **RISCO:** sem persistência de ordens/deltas, fechar a execução perde o estado;
  grids muito oblíquas e níveis com muitos dígitos ainda exigem zoom. Rótulos
  arredondados são apresentação, não quantização da rampa.
- **DÍVIDA TÉCNICA:** orçamento global de memória/evicção dos caches CPU de
  Current, cancelamento antecipado de worker supersedido e otimização do PBR
  global. Atualmente workers obsoletos terminam e têm o resultado descartado.

Não foram iniciadas máquinas ou outras etapas de gameplay.
