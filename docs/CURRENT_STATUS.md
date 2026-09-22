# Estado atual — Planet v0.1

## Etapa atual

Etapa 2 — concluída após correção de stutter, profiling comparativo e regressão.
O usuário confirmou não perceber mais pausas relevantes no voo manual.

Próxima: Etapa 3, ainda não iniciada.

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
- esfera-base visível de 50 km, sem relevo, com 33×33 vértices por patch;
- SSE com histerese e nível máximo renderizável padrão 6;
- balanceamento 2:1, stitching com 16 máscaras e geomorphing no shader;
- budgets padrão de 8 splits, 2 merges e 4 commits de mesh por update;
- orçamento adicional de CPU de 4 ms, com preparação incremental e caches limitados;
- debug de faces, bordas, LOD, IDs, contadores e transições;
- testes estruturais do quadtree e roteiro gráfico reproduzível.

## Em andamento

Nenhuma implementação. Etapa 3 não iniciada.

## Próximo marco

Especificar a Etapa 3 de relevo/macroforma antes de implementar novos sistemas.

## Problemas conhecidos

- navegação RTS esférica ainda não validada;
- Orbital visualiza o globo real; navegação planetária completa e alinhamento radial
  definitivo das câmeras ainda não foram validados;
- o usuário não percebe mais pausas relevantes após a otimização; isso não garante
  ausência de artefatos em todo percurso; endpoints e continuidade têm testes numéricos;
- picos residuais de inicialização e de frame completo persistem nas medições;
  o orçamento de CPU é flexível e não interrompe chamadas da engine;
- geração/amostragem/commits continuam na main thread, sem evidência de que geração
  de arrays seja o gargalo dominante restante; bounds ainda são conservadores;
- FreeFly pode atravessar a superfície; colisão planetária não pertence à etapa atual.

Nenhum bloqueador confirmado de topologia, 2:1 ou stitching permanece nos casos
testados. Limites e evidências: `docs/stages/02_quadtree.md`.

## Última validação

Projeto validado com Godot 4.6.1 por meio de:

- importação/editor headless;
- execução da cena principal;
- teste permanente das câmeras;
- teste permanente da fundação planetária;
- suíte completa do quadtree: 630.955 verificações, saída 0;
- percurso gráfico Vulkan: aproximação, borda entre faces, afastamento e Orbital,
  com `VISUAL_TEST_OK` e saída 0.
- profiling gráfico comparativo, com/sem debug, e confirmação manual positiva do usuário.

Todos os testes headless passaram fora do sandbox; somente warnings esperados dos
casos negativos de CameraManager. Instruções em `tests/planet/README.md`.
