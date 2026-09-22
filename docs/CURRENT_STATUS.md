# Estado atual — Planet v0.1

## Etapa atual

Etapa 3 — relevo macro concluído tecnicamente, com regressão e profiling.
O usuário confirmou não perceber pausas relevantes no voo manual com relevo.
Aspectos estéticos/limites: `docs/stages/03_relevo_macro.md`.

## Concluído

- PlanetLab mínimo;
- novo sistema de câmeras;
- FreeFly;
- RTS;
- Orbital;
- CameraManager;
- troca cíclica e seleção direta;
- debug da câmera ativa;
- testes permanentes do CameraManager;
- remoção completa do protótipo legado;
- definição planetária com raio base de 50.000 m e escala de 1 m por unidade;
- raiz `Planet` integrada ao PlanetLab e responsável pela atualização central do quadtree;
- bases centralizadas das seis faces da cube-sphere;
- conversões Face+UV ↔ direção e posição radial base;
- regra canônica de desempate X → Y → Z;
- identidade matemática `PatchId` com parent, children, quadrante e bounds, limitada ao nível 24 pela precisão UV float32;
- topologia central de faces e bordas;
- vizinhança de patches no mesmo nível, inclusive entre faces;
- testes permanentes da fundação planetária;
- seis quadtrees lógicos baseados em `PatchId`, com split/merge e vizinhança;
- planeta de raio base 50 km com relevo radial, 33×33 vértices por patch;
- SSE com histerese e nível máximo renderizável padrão 6;
- balanceamento 2:1, stitching com 16 máscaras e geomorphing no shader;
- budgets padrão de 8 splits, 2 merges e 4 commits de mesh por update;
- orçamento adicional de CPU de 4 ms, com preparação incremental e caches limitados;
- debug de faces, bordas, LOD, IDs, contadores e transições;
- testes estruturais do quadtree e roteiro gráfico reproduzível.
- sampler global determinístico por seed (padrão 73129), continentes, ilhas,
  arquipélagos, mares internos, batimetria e macroformas regionais;
- 44,44% terra / 55,56% oceano medidos independentemente de câmera/LOD;
- bounds/SSE/morph com terreno; índices espaciais imutáveis;
- debug F4: faces/LOD, terra/oceano, altitude, continentalidade, macroformas,
  nível do mar e costas; material técnico unshaded, sem materiais finais.

## Em andamento

Nenhuma implementação pendente. Avaliação estética permanece aberta.

## Próximo marco

Etapa 4 — geologia, ainda não iniciada. Aguardar especificação/instrução.

## Problemas conhecidos

- navegação RTS esférica ainda não validada;
- Orbital visualiza o globo real; navegação planetária completa e alinhamento radial
  definitivo das câmeras ainda não foram validados;
- o usuário não percebe mais pausas relevantes após a otimização; isso não garante
  ausência de artefatos em todo percurso; endpoints e continuidade têm testes numéricos;
- picos residuais de inicialização e de frame completo persistem nas medições;
  o orçamento de CPU é flexível e não interrompe chamadas da engine;
- geração/amostragem/commits continuam na main thread; relevo aumenta o trabalho;
  seleção/balanceamento chegou a ~31 ms em árvore maior, sem pausa relevante
  relatada pelo usuário; bounds continuam conservadores;
- algumas massas, ilhas e mares internos têm formas arredondadas; colinas
  regulares e facetamento técnico permanecem como aspectos estéticos conhecidos;
- estimativa SSE validada por amostragem, não prova universal; repetir testes
  ao alterar parâmetros do relevo;
- FreeFly pode atravessar a superfície; colisão planetária não pertence à etapa atual.

Nenhum bloqueador confirmado de topologia, 2:1 ou stitching permanece nos casos
testados. Limites/evidências: `docs/stages/02_quadtree.md` e
`docs/stages/03_relevo_macro.md`.

## Última validação

Projeto validado com Godot 4.6.1 por meio de:

- importação/editor headless;
- execução da cena principal;
- teste permanente das câmeras;
- teste permanente da fundação planetária;
- suíte completa do quadtree: 630.955 verificações, saída 0;
- suíte de relevo: 694.703 verificações, saída 0;
- fingerprint idêntico de terreno em dois processos independentes;
- percurso gráfico Vulkan: hemisférios, macroformas, borda entre faces,
  afastamento e modos de debug, com `TERRAIN_VISUAL_OK`;
- profiling gráfico esfera/relevo e confirmação manual positiva do usuário;
- evidências persistentes em `docs/evidence/03_relevo_macro/`.

Todos os testes headless passaram fora do sandbox; somente warnings esperados dos
casos negativos de CameraManager. Instruções em `tests/planet/README.md`.
