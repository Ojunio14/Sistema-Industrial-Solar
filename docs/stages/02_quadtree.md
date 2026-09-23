# Etapa 2 — Quadtree global

> Nota histórica: esta implementação de superfície/renderização foi substituída
> integralmente na [Etapa 6 — Substituição do planeta](06_substituicao_planeta.md).
> Seus parâmetros e resultados descrevem a implementação anterior.

Status: concluída após otimização, regressão estrutural e confirmação do usuário
de que não percebe mais pausas relevantes no voo manual. Limites abaixo.

## Objetivo e dependências

Renderizar a esfera-base de 50 km com seis quadtrees, usando exclusivamente
PlanetMath, PlanetTopology, PlanetDefinition e PatchId da Etapa 1.
Documentos relevantes: ARCHITECTURE.md, DECISIONS.md e 01_fundacao_planetaria.md.

## Contratos

- Seis roots; patches lógicos RefCounted; identidade PatchId.
- 33 × 33 vértices por patch; nenhuma elevação.
- 2:1 em todas as arestas, inclusive entre faces.
- Índices de stitching em até 16 máscaras; sem skirts.
- Atualização central, budgets separados, troca visual transacional e morph no shader.

## Componentes e configuração inicial

Implementação em systems/planet/quadtree: PlanetPatch, PlanetQuadtree,
PlanetLodConfig, PlanetSSE, PlanetPatchMesh, PlanetSurfaceSampler,
PlanetQuadtreeView e material técnico planet_debug.gdshader.

SSE = erro × altura_viewport / (2 × tan(FOV_vertical/2) × distância).
Distância é a distância até o volume conservador do patch, limitada a 0,1 m.
O volume usa centro radial e raio `R × sqrt(2) / 2^level`: a meia diagonal do
patch no cubo. A normalização no plano da face é 1-Lipschitz (norma >= 1), logo
esse raio contém a superfície curva. O fator 2 excedente anterior foi removido;
testes com a matemática da Etapa 1 verificam a contenção. Não há horizon culling.
Erro-base = raio × (2 / (32 × 2^level))², com termo adicional de terreno
opcional zero nesta etapa. Projeção ortográfica usa altura_viewport / tamanho_vertical.

Defaults calibráveis: split 2 px, merge 0,8 px, nível máximo renderizável 6,
até 8 splits, 2 merges e 4 commits de mesh por update; morph de 0,35 s.
Um orçamento adicional de CPU de 4 ms distribui validação/planejamento e geração
em updates distintos. É um limite flexível: uma chamada indivisível da engine,
inicialização de topologia ou bloco de trabalho pode ultrapassá-lo. Não é limite
de frame time; seleção estrutural e custos da engine também são medidos.
O limite renderizável é independente do limite de identidade 24.
O default 6 limita o custo do protótipo; não é uma exigência arquitetural nem
garantia de atingir 2 px em toda situação próxima à superfície. O limite encerra
o refinamento mesmo que o SSE ainda exceda o threshold.

## Balanceamento, stitching e morph

Split calcula o fechamento dos vizinhos mais grossos antes de alterar a árvore;
merge só ocorre se os vizinhos resultantes respeitarem 2:1.
Com budget pequeno, uma dependência de split pode ser resolvida primeiro.

Cada bloco 2×2 de quads é triangulado como um leque em torno do vértice central.
Isso mantém diagonais alternadas de 45 graus que se alinham à triangulação do pai.
Stitching omite os pontos ímpares do contorno do leque nas bordas contra vizinhos
grossos; os 1.089 vértices continuam presentes, mas aqueles pontos não são indexados.
As 16 máscaras são armazenadas em cache. Não existem triângulos degenerados ou
arestas abertas no interior do patch. A orientação entre faces pertence a PlanetTopology.

Mudanças são preparadas invisíveis dentro do budget de commits.
O estado visual anterior permanece até a preparação terminar.
O shader interpola posições amostradas na triangulação grossa real para a esfera fina.
Um único relógio coordena o morph de todas as bordas; merge usa o sentido inverso
e substitui a representação somente ao alcançar o endpoint grosso.
Malhas com identidade e máscara inalteradas são reaproveitadas. As outras recebem
CUSTOM0 com deslocamento até a superfície grossa; somente o uniform de morph muda
durante a transição. O sampler interpola os triângulos efetivos, inclusive stitching,
usando bins UV por máscara; não interpola apenas a esfera analítica.

Arrays geométricos são imutáveis e guardados somente para nós lógicos ainda
existentes (incluindo pais internos, úteis no merge); órfãos são removidos após
a transação. Mudança de stitching reutiliza posições/normais/UV e troca a
topologia, sem recalcular a esfera. Não existe geração oculta de geometria grossa
durante o commit: o sampler reutiliza esses arrays.

A geração usa um referencial afim obtido pela API de cubo da Etapa 1, sem bases
de face duplicadas. Geração e morph avançam em blocos de até 64 vértices. O sampler
resolve uma folha grossa por patch, consulta somente triângulos das células UV
pertinentes e reutiliza até 80 padrões de índices/pesos (16 máscaras × patch/4
filhos), preenchidos incrementalmente. O buffer gravável de morph é independente
dos arrays compartilhados; cache frio/quente e imutabilidade são testados.

No split a representação fina começa sobre a grossa e avança à esfera.
No merge a representação fina permanece até coincidir com a grossa.
A geometria grossa/fina é preparada antes da troca, evitando buracos por falta
de commits. Somente uma transação ocorre por vez, contendo splits independentes
e suas dependências ou merges compatíveis, até o respectivo budget configurado.

## Debug e culling

Cores de face, nível e bordas opcionais; overlay com contadores,
PatchId radial sob a câmera, máscara L/R/T/B e progresso da transição.
Godot faz frustum culling de cada mesh com AABB incluindo os dois endpoints.
A árvore mantém a cobertura lógica mesmo fora do frustum.
As contagens visíveis são aproximações de frustum; não são oclusão por horizonte.
O estado 2:1 exibido é a última validação da árvore transacional.
Validação e cálculo das máscaras compartilham a travessia, distribuída pelo budget;
a árvore preparada só é ativada após validação completa. Seleção calcula cada SSE
uma vez, ordena chaves existentes e reutiliza o resultado em câmera estacionária.
O overlay atualiza a 5 Hz e não calcula texto quando desligado.
Configuração editável: systems/planet/quadtree/default_planet_lod.tres.

## Câmeras e escala

FreeFly inicia em (0, 0, 140.000), com velocidade-base 15.000 m/s.
Orbital usa raio inicial 140.000 m, intervalo 51.000..350.000 m e passo 5.000 m.
RTS inicia acima de +Y, com zoom 20.000..150.000 m. Near/far de 10/500.000 m
permitem inspeção do globo. Não há restrição física que impeça FreeFly de
atravessar a superfície; colisão planetária continua fora de escopo.

## Testes e conclusão

Suíte permanente: tests/planet/planet_quadtree_test.gd.
Inclui seis roots, IDs/parent/children, cobertura, split/merge, vizinhos,
splits forçados e merges bloqueados intra/cross-face, propriedades de SSE,
16 máscaras de índices, raio/normais/winding, área/manifold,
continuidade 2:1 nas 24 transições direcionadas, endpoints de morph nos vértices
e no interior dos triângulos, bordas durante morph, determinismo, convergência
estacionária, aproximação/afastamento e budgets.
O controlador é exercitado com budgets 1/1/3 e 8/2/3, incluindo operações em lote,
recuperação das seis roots no afastamento e repetição determinística.
A tolerância espacial desses testes é 0,04 m, compatível com float32 a 50 km;
isso não é uma afirmação de igualdade bit a bit de todos os pontos interpolados.

Runner: tests/planet/run_validation.ps1; executa import, cena principal por
120 frames, câmeras, fundação e quadtree. Logs ficam em diretório temporário.
O runner distingue saída 0 de erros de script; possui timeout por processo.
Na regressão da otimização, importação/editor, cena principal, câmeras, fundação
e quadtree terminaram com saída 0. A suíte ampliada verificou 630.955 contratos,
incluindo geração incremental versus a API da Etapa 1, bounds, todas as 80 tabelas
de interpolação, caches imutáveis/limitados, orçamento de CPU e ausência de
regeneração em repouso. Testes de seleção determinística desativam somente o
deadline de tempo; budgets de operações e testes específicos de slicing permanecem.

O teste gráfico tests/planet/planet_visual_test.gd usa o backend real, a cena
principal e as câmeras existentes, registra contagens e salva capturas no
diretório fornecido após --. Não substitui avaliação manual contínua de popping.

Critério: testes anteriores e novos passam; esfera-base visível; SSE/histerese,
2:1, stitching, morph e budgets funcionais; nenhuma implementação de relevo.

## Validação gráfica e limites operacionais

Godot 4.6.1, Vulkan Forward+, AMD Radeon Vega 3, viewport 1100×760:

| Posição/cenário | Folhas | Patches lógicos | Resultado |
|---|---:|---:|---|
| FreeFly a 140.000 m do centro | 9 | 10 | globo visível, árvore estabilizada |
| FreeFly a 50.500 m, centro de +Z | 72 | 94 | LOD conforme SSE e bounds corrigidos |
| FreeFly a 50.500 m, região +X/+Z | 111 | 146 | LOD máximo 6, borda sem abertura evidente |
| Afastamento para 180.000 m | 21 | 26 | LOD 0..1, merges e estabilização |

O percurso terminou com VISUAL_TEST_OK e saída 0. Os picos de operações por
update foram 8 splits, 2 merges e 4 commits. A troca para Orbital produziu uma
captura com o globo visível. A histerese permite conjuntos diferentes conforme
o histórico de aproximação; determinismo é exigido para o mesmo estado inicial
e percurso, não para históricos diferentes.

Capturas estáticas foram inspecionadas. Após reiniciar o PlanetLab e repetir o voo,
o usuário informou não perceber mais pausas relevantes. Isso não comprova ausência
de todo artefato em trajetórias arbitrárias. Continuidade durante morph e
convergência estacionária foram verificadas por testes numéricos. A navegação
RTS sobre a esfera e o alinhamento radial definitivo das câmeras continuam sem
validação funcional completa; não foram reimplementados nesta etapa.

Geração, amostragem do morph e commits ainda ocorrem na main thread. Não há
garantia de frame time ou FPS. Bounds conservadores e ausência de horizon culling
podem manter detalhes no lado oculto, sem perda da cobertura lógica.
O cenário validado usa transformação de escala unitária no Planet.

## Profiling e conclusões permanentes da otimização

Roteiro reproduzível: `tests/planet/run_profile.ps1`, com/sem debug, sequencialmente.
Detalhes de métricas e execução estão em `tests/planet/README.md`; logs/JSON ficam
fora do repositório. A instrumentação é opt-in, sem I/O por frame ou timers por
vértice. Mede atualização, seleção/SSE, 2:1, geração, amostragem, ArrayMesh,
stitching, ciclo visual, fila, níveis e operações solicitadas/executadas/forçadas.

No percurso gráfico de 1.200 updates, antes/depois com debug ligado:

| Medida | Antes | Depois |
|---|---:|---:|
| Pico de CPU do quadtree durante navegação, excluindo inicialização distante | 1.012,46 ms | 16,35 ms |
| p95 da CPU do quadtree, percurso completo | 659,75 ms | 4,91 ms |
| Pico de seleção/SSE, descontados subconjuntos instrumentados | 818,93 ms | 4,28 ms |
| Pico de geração por update | 318,34 ms | 4,98 ms |
| Pico de amostragem por update | 791,07 ms | 9,48 ms |
| Pico de stitching por update | 170,72 ms | 2,77 ms |
| Pico de debug | 21,82 ms | 2,59 ms |

O A/B sem debug manteve o pico antigo perto de 1 s; desligar o overlay antes não
eliminava seu cálculo. Agora esse custo é zero quando desligado. Os maiores
custos antigos eram amostragem/regeneração e consultas repetidas na ordenação,
não a criação habitual de nodes; não foi introduzido pool de objetos.

O sampler realizou 1.130 gerações extras de geometria no percurso antigo e zero
no final. Mesh 33×33, thresholds 2/0,8 px, LOD máximo 6, stitching e morph foram
mantidos. Bounds corrigidos reduzem trabalho excessivo; o deadline altera latência
e estados intermediários, logo as contagens não são um benchmark de carga idêntica.
Na inspeção estática houve convergência em 9/72/111/21 folhas, com LOD 6 alcançado
na borda entre faces. O percurso fixo pode terminar com merges ainda pendentes;
o teste de convergência verifica separadamente seu término.

Persistem picos: criação visual inicial de aproximadamente 97 ms; frame completo
de até 92 ms durante navegação com debug e até 58 ms no A/B sem debug. Parte desses
tempos fica fora da atualização instrumentada do quadtree e não foi atribuída a
uma causa específica de engine/GPU/espera/SO. Não se declara ausência de stutter
perceptível. Em medição intermediária também houve commit isolado de 56 ms.
Chamadas da engine não podem ser interrompidas pelo orçamento de CPU. A geração
de arrays deixou de dominar: os dados atuais não justificam afirmar que
WorkerThreadPool, sozinho, resolveria os picos restantes. A confirmação manual
do usuário foi positiva; picos medidos permanecem registrados, sem promessa de
frame time ou eliminação universal de stutter.

O headless no sandbox apresentou restrições do armazenamento de certificados
e de gravação das configurações globais do editor; a repetição fora do sandbox
eliminou essas mensagens. Warnings de câmera inexistente/ID duplicado são esperados
nos casos negativos do teste de CameraManager.

## Fora de escopo

Sem relevo, geologia, clima, biomas, texturas finais, colisão, mineração,
persistência ou WorkerThreadPool.
