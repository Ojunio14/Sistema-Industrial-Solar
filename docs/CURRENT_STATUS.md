# Estado atual — Planet v0.1

## Etapa atual

Etapa 5 — Clima e Biomas concluída tecnicamente, com regressão, inspeção
gráfica, profiling comparável e confirmação manual de voo sem pausas
relevantes. Contratos, evidências e limites:
`docs/stages/05_clima_biomas.md`.

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
- clima estático global por seed/posição, independente de face/LOD/câmera, com
  temperatura por latitude/altitude, influência oceânica, umidade, chuva e
  sombra de chuva das cadeias reais;
- dez famílias de bioma terrestre com pesos contínuos; geologia não é bioma e
  terreno não depende da classificação climática;
- debug F6 de campos climáticos e biomas; F4/F5 e quadtree/relevo/geologia
  preservados; testes permanentes de continuidade, distribuição e integração.

## Em andamento

Nenhuma implementação em andamento.

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
- clima acrescenta ~77% ao custo de geração por vértice em perfil comparável
  e aumenta o tempo de convergência; um pico inicial isolado de 119 ms não
  teve causa confirmada e não se repetiu na captura instrumentada; a repetição
  teve um frame isolado de 123 ms fora do update medido, também sem causa
  confirmada; usuário não percebeu pausas relevantes no voo da Etapa 5;
- maritimidade usa continentalidade como proxy, não distância exata até a costa;
  rain shadow é envelope estático, e o blend do debug mostra só os dois pesos
  principais enquanto a API preserva os dez;
- debug categórico é facetado por triângulo; layouts geológicos ainda simplificados;
- parágrafo histórico de quadtree em ARCHITECTURE.md está desatualizado;
  o estado operacional implementado é o registrado aqui e nas Etapas 2–5.

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
- clima: 142.252 verificações, zero falhas; fingerprints idênticos de clima,
  terreno e geologia em processos independentes;
- percurso gráfico Vulkan: 39 poses/194 capturas, seis hemisférios, campos
  climáticos, dez biomas, macroformas, geologia e borda entre faces,
  com `TERRAIN_VISUAL_OK`;
- perfil climático comparável, 2.580 updates: geração 21,12 → 37,40 µs/vértice,
  warmup até idle 925 → 1.554 updates; frames variaram entre execuções;
- evidências persistentes em `docs/evidence/05_clima_biomas/`.

Todos os testes headless passaram fora do sandbox; somente warnings esperados dos
casos negativos de CameraManager. Instruções em `tests/planet/README.md`.
