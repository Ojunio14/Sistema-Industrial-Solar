# Estado atual — Planet v0.1

## Etapa atual

Etapa 4 — Geologia Estrutural concluída tecnicamente, com regressão,
inspeção gráfica e profiling comparável. Confirmação manual específica da
geologia ainda não recebida (a confirmação anterior era da Etapa 3).
Contratos, evidências e limites: `docs/stages/04_geologia_estrutural.md`.

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
- 44,39% terra / 55,61% altura negativa com geologia na seed padrão,
  medidos independentemente de câmera/LOD;
- bounds/SSE/morph com terreno; índices espaciais imutáveis;
- debug F4: faces/LOD, terra/oceano, altitude, continentalidade, macroformas,
  nível do mar e costas; material técnico unshaded, sem materiais finais.
- geologia superficial global por seed, IDs versionados, maturidade e influência
  dominante; províncias derivadas das macroformas, sem clima/recursos/profundidade;
- modificadores estruturais graduais integrados à mesma autoridade de terreno,
  resultado reutilizado por mesh/debug e erro estrutural incorporado ao SSE;
- debug F5 de províncias/maturidade/tipos; F4 preservado;
- testes geológicos e toda a suíte de terreno executada também com geologia.

## Em andamento

Nenhuma implementação em andamento. Retorno manual da Etapa 4 solicitado.

## Próximo marco

Aguardar instrução explícita para a próxima etapa; não iniciada.

## Problemas conhecidos

- navegação RTS esférica ainda não validada;
- Orbital visualiza o globo real; navegação planetária completa e alinhamento radial
  definitivo das câmeras ainda não foram validados;
- o usuário não percebeu pausas relevantes na Etapa 3; isso não garante
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
- geologia aumenta custo por vértice (~35% no gerador no profile comparável);
  mantém frames controlados na rota medida, mas pode atrasar refinamento sob budget;
- debug categórico é facetado por triângulo; layouts geológicos ainda simplificados;
- parágrafo histórico de quadtree em ARCHITECTURE.md está desatualizado;
  o estado operacional implementado é o registrado aqui e nas Etapas 2–4.

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
- suíte de relevo base: 694.703; com geologia: 694.706 verificações, saída 0;
- geologia: 158.752 verificações, oito seeds e zero falhas;
- fingerprints idênticos de terreno base e geologia em processos independentes;
- percurso gráfico Vulkan: 26 poses/73 capturas, hemisférios, macroformas,
  geologia, borda entre faces e debug, com `TERRAIN_VISUAL_OK`;
- profiling base/geologia, 2.580 updates: frame p95 16,645 → 16,717 ms;
  pico 28,741 → 21,929 ms, sem redução de budgets/qualidade;
- evidências persistentes em `docs/evidence/04_geologia_estrutural/`.

Todos os testes headless passaram fora do sandbox; somente warnings esperados dos
casos negativos de CameraManager. Instruções em `tests/planet/README.md`.
