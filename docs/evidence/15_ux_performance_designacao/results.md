# Resultados — Etapa 15

Execuções em 27–28/09/2026. Godot 4.6.1, Windows, AMD Radeon Vega 3,
Vulkan Forward+, 1100 × 760 nas capturas. Não houve uso de Git.

## Comparação controlada de CPU

O MESMO `designation_benchmark.gd` foi executado sequencialmente na cópia
preservada da Etapa 14 e na implementação final. Mesmo seed, anchor, câmera
apontada à superfície natural, viewport 1100 × 760, planos, datum e limite
de 120 FPS. A superfície local estava publicada antes da primeira seleção.
LOD global congelado; cada tamanho amplia a seleção anterior. Headless:
estas linhas medem CPU/latência, não GPU. Uma execução por versão, sem outros
ensaios Godot em paralelo; não são garantias nem percentis entre execuções.
O anchor é (0,680414; 0,272166; 0,680414), com Target Level −348 no datum padrão.
P95/máximo de frames começam após o retorno do handler; o bloqueio do handler
antigo é medido na linha própria e não está embutido nesses percentis.

| Medida (ms) | Etapa 14 | Etapa 15 |
|---|---:|---:|
| Seleção 16: início → preview completo | 25.461 | 25.527 |
| Seleção 256: início → preview completo | 76.353 | 39.014 |
| Seleção 1024: início → preview completo | 365.150 | 83.194 |
| Seleção 4096: início → preview completo | 1466.790 | 318.811 |
| Apply 4096: handler | 78.185 | 0.101 |
| Apply: todas as meshes/colisões publicadas | 3528.457 | 3532.264 |
| Frames durante rebuild: p95 | 8.350 | 8.355 |
| Frames durante rebuild: máximo | 8.403 | 9.214 |

Fontes: [antes](matched_before/metrics.json), [depois](matched_after/metrics.json).
Glifos da seleção de 4096: 16384 antes,
100 depois nesta pose. A API nova deixa de construir
números fora da região próxima/visível. O ensaio mede até o preview completo;
a UI real também pode mostrar tiles antes de terminar a avaliação de volumes.

## Cena gráfica e semântica

O percurso final em terra firme passou **4325 verificações, zero falhas**.
A encosta de teste é uma fixture de edição publicada no terreno PBR real,
não uma superfície visual falsa. Arraste baixo → alto manteve Target 10;
Current variou de 10,00 a 19,25. Após Apply, Current convergiu a 10. O teste
confere cada vértice da grid contra a superfície publicada, histerese,
soltura sobre HUD, câmera preservada e crescimento por uma única faixa.

| Seleção | Preview completo na cena PBR (ms) |
|---|---:|
| 16 células | 2.231 |
| 256 células | 485.855 |
| 1024 células | 721.629 |
| 4096 células | 2125.849 |

A avaliação de 4096 terminou em 235.674 ms;
o restante inclui apresentação incremental de tiles em uma cena limitada pela GPU.
Não confundir com os 17,6 s da reconstrução física após Apply.

Capturas finais inspecionadas:
[encosta/Current/Target](final_graphical/A_hillside_current_target.png),
[aplicada](final_graphical/B_hillside_applied.png),
[F9](final_graphical/C_f9_cached.png),
[4096 células](final_graphical/D_4096_bounded_numbers.png),
[rampa antes](final_graphical/E_ramp_before.png),
[rampa depois](final_graphical/F_ramp_after.png).

## F9

A medição inicial do código antigo encontrou 65,870 ms na primeira alternância
e chamadas posteriores de até 23,869 ms. Incluía recriação do diagnóstico e
ativação/desativação local. Fonte: [baseline inicial](baseline/baseline.json).
O novo F9 só alterna recursos persistentes; essa mudança de trabalho é parte
da correção e deve ser considerada ao comparar os tempos.

Na execução headless final: primeira chamada 8.187 ms;
toggle quente entre 0.027 e 0.034 ms.
Dados/min-max, criação de nodes e geometria têm contadores separados no JSON.
Após um único chunk dirty, exatamente 1 geometria foi
reconstruída. Nenhuma zona é criada/descartada pelo toggle.
Primeira utilização de fonte/shader ainda pode ter custo frio: houve 32 ms
em uma execução gráfica preliminar; o warm toggle permaneceu abaixo de 0,1 ms.

## Apply por fases

Último ensaio headless, 4096 células / 4225 nós / quatro chunks:

| Fase | Tempo (ms) | Execução |
|---|---:|---|
| Handler | 0.077 | main, somente fila |
| A: cálculo de deltas | 11.656 | worker |
| B: preparar buffers | 11.182 | worker |
| B: trocar arrays vivos | 0.016 | main |
| C: deduplicar dirty/halo | 5.150 | worker |
| D: publicar revisões | 0.010 | main |
| E: enqueue, máximo/frame | 0.348 | main |
| F: preparar meshes, total | 3346.174 | worker |
| G: faces de colisão, total | 23.835 | worker |
| H: upload, máximo/frame | 1.738 | main/API GPU |
| I: shape físico, máximo/frame | 4.203 | main/Physics |
| I: publicação atômica, máximo/frame | 0.316 | main |

Dados prontos em 74.287 ms; primeira mesh visível e tudo pronto
em 4176.942 ms. Esses dois últimos tempos coincidem porque a
publicação de vizinhos dirty é atômica; upload individual não é apresentação.
Frame p95/máximo: 8.743/27.655 ms.

Na cena PBR pesada, handler 0.231 ms, dados prontos
em 237.250 ms e mesh/colisão em
17.628 s. Frame p95/máximo durante o rebuild:
237.568/245.539 ms.
A GPU já limita a cena, mesmo com overlay oculto. Não se afirma eliminação
de todas as pausas do renderer/driver/PhysicsServer.

## Overlay: comparação com 4168 células / 8400 glifos

O roteiro histórico de plataforma 10/rampa/plataforma 5 + preview de 4096 foi
reexecutado com a mesma resolução e poses. Passou 9183 verificações.
A amostragem de frames mantém o LOD congelado dentro de cada par de janelas.
Estado de aquecimento, frequência/driver e folhas globais entre execuções não
foram fixados; portanto não interpretar diferenças absolutas de GPU como custo
isolado do overlay.

| Medida | Etapa 14 histórica | Etapa 15, mesmo roteiro |
|---|---:|---:|
| Células | 4168 | 4168 |
| Glifos construídos | 8400 | 128 |
| Buffer de instâncias | 537600 B | 8192 B |
| Construção do overlay, decorrido | 15801 ms | 4097.976 ms |
| Frame p95 oculto / visível | 154,252 / 186,487 ms | 195.082 / 181.120 ms |
| GPU p95 oculto / visível | 148,516 / 180,342 ms | 191.500 / 172.711 ms |

Uma janela visível ficou mais rápida que a oculta: isto evidencia ruído e
aquecimento, não um ganho negativo causado pelo overlay. Fontes:
[roteiro comparável](comparable/metrics.json) e registro histórico da Etapa 14.
Na seleção final isolada de 4096: 4624 vértices,
18 nodes de desenho, 78 rótulos e
156 glifos. Cache de tiles evita reconstrução ao mudar Target.

## Testes e limites

Dez verificações da suíte afetada passaram: câmera/input, 3332 contratos de
designação, transações, 93388 contratos naturais, 484697 checks de mineração,
ownership LOD, integração com dois workers (59243 checks), demo 10 → 5,
UX e inicialização da cena principal. [Resumo da suíte](validation/summary.json).
O teste final de transações ampliado passou 25 checks, incluindo snapshot
isolado, edição concorrente, supersessão, pending Current e cache de Target.
O percurso headless final passou 14171 checks; todos com zero falhas.
Logs: [transações](final_validation/designation_transaction_test.log),
[UX](final_validation/designation_ux_test.log), [métricas](final_validation/ux/metrics.json).
Aviso de certificado raiz do sandbox Windows foi mantido nos logs e separado
de erros do projeto. Nenhum erro de script/shader é aceito como aviso.

A inspeção de PNGs e interação por handlers automatizados foi executada.
O [roteiro manual A–D](../../stages/15_ux_performance_designacao.md) foi fornecido;
não houve alegação de teste subjetivo por um operador humano.

CONFIRMADO: PBR global caro, publicação assíncrona demorada e budgets flexíveis.
SUSPEITO: influência de driver/frequência nos pares GPU. RISCO: ausência de
persistência e leitura em ângulos extremos. DÍVIDA: orçamento global do cache
CPU e cancelamento antecipado de workers obsoletos. Detalhes no documento da etapa.
