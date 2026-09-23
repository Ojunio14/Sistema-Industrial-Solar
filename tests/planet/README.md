# Planet foundation tests

## Geologia estrutural (Etapa 4)

O PlanetLab habilita geologia por `PlanetDefinition.geology_enabled`. F5 percorre
províncias, maturidade, interiores antigos, cinturões, sedimentares, ígneos,
planaltos, bacias fechadas e antigas áreas marinhas. F4 retorna aos modos do relevo.
IDs são categóricos por triângulo; maturidade/peso interpolam entre vértices.
Os filtros mostram o **tipo dominante**, não todas as influências sobrepostas.

```powershell
./tests/planet/run_validation.ps1
./tests/planet/run_validation.ps1 -Only geology
./tests/planet/run_validation.ps1 -Only structural_terrain
./tests/planet/run_terrain_visual.ps1 -Geology
./tests/planet/run_profile.ps1 -Label macro-baseline -Graphics -MacroRoute -SettledRoute -NoGeology
./tests/planet/run_profile.ps1 -Label geology -Graphics -MacroRoute -SettledRoute
```

Execute os dois profiles sequencialmente. A rota, resolução, budgets e SSE são os
mesmos; muda apenas a integração geológica (que pode exigir mais patches).
Sem `-Geology`, a captura visual mantém a referência da Etapa 3. Sem
`-NoGeology`, o profile usa a geologia atual. O construtor `PlanetTerrain.new(seed)`
preserva a base da Etapa 3; passe `true` no segundo argumento para a integração.

A suíte completa executa geologia, dois processos independentes e toda a suíte de
terreno também com geologia, incluindo SSE, 16 máscaras, morph e budgets. Os testes
novos cobrem IDs/descritores, seed/ordem, classificação, continuidade geológica real,
12 arestas/8 cantos, LODs até 24, equivalência do índice espacial e consulta integrada.
O benchmark geológico usa direções pré-calculadas e mediana de três passagens;
consulta isolada inclui o contexto continental, integrado o reutiliza uma vez.

## Relevo macro (Etapa 3)

Seed padrão: 73129, em `systems/planet/default_planet_definition.tres`.
F4 alterna faces/LOD, terra/oceano, altitude, continentalidade, macroformas,
nível do mar e costas. Material técnico unshaded; azul representa batimetria,
não uma segunda esfera de água nem materiais/biomas.

```powershell
./tests/planet/run_validation.ps1
./tests/planet/run_validation.ps1 -Only terrain
./tests/planet/run_terrain_visual.ps1
./tests/planet/run_profile.ps1 -Label sphere -Graphics -Sphere -MacroRoute -SettledRoute
./tests/planet/run_profile.ps1 -Label terrain -Graphics -MacroRoute -SettledRoute -NoGeology
```

A suíte completa compara também fingerprints de duas execuções independentes.
O teste de relevo mede 16.384 direções Fibonacci, land ratio/alturas/profundidades,
determinismo, 12 arestas/8 cantos, fronteiras dos índices espaciais, SSE amostrado,
malhas/16 máscaras, coarse/fine/stitching/morph e budgets. Opcionalmente, passe
um caminho PNG absoluto após `--` ao script `planet_terrain_test.gd` para gerar
um mapa longitude/seno(latitude) de área igual. Não derive land ratio das malhas.

`-MacroRoute` usa distância mínima 53 km (fora do limite máximo de relevo), nos
dois casos. `-SettledRoute` estabiliza a visão orbital antes da medição e estende
o percurso para 2.580 updates. O aquecimento é informado separadamente.
Não compare diretamente essa rota com a antiga de 1.200 updates/50,5 km.
`terrain_displace_us` é subconjunto de `generate_us`: inclui o sampler, aplicar
altura e preencher cores técnicas, medido por bloco, nunca com timer por vértice.
O benchmark da suíte isola consultas em direções globais (inclui gerar a direção).
Mais relevo implica mais patches pela mesma política SSE; compare também contagens.
Os testes de screenshot aguardam convergência, mas não medem FPS.

Run from the project root with Godot 4.6:

```powershell
godot --headless --path . --script res://tests/planet/planet_foundation_test.gd
```

The process exits with code `0` and prints `PLANET_FOUNDATION_TEST_OK` when the face bases, conversions, edge continuity, `PatchId`, topology, patch neighbors and determinism contracts pass.

## Quadtree (Stage 2)

```powershell
godot --headless --path . --script res://tests/planet/planet_quadtree_test.gd
./tests/planet/run_validation.ps1
```

The full quadtree test prints `QUADTREE_TEST_OK` and exits with code 0.
It includes transition endpoints, cross-face stitching, hysteresis and budgets.
Controller tests cover both restrictive (1 split / 1 merge) and batched
(8 splits / 2 merges) budgets, with 3 mesh commits per update.
For the geometry subset only, append `-- --geometry-only`.
The PowerShell runner accepts `-Godot <executable>` and writes logs to a fresh
temporary directory. It never uses Git.

To capture the real renderer (requires a graphical session):

```powershell
godot --path . --windowed --resolution 1100x760 --script res://tests/planet/planet_visual_test.gd -- <absolute-output-directory>
```

Static screenshots cannot prove the absence of transient visual artifacts during
arbitrary manual flight. FreeFly/RTS/Orbital remain accessible with keys 1/2/3;
Tab cycles cameras and Escape releases FreeFly mouse capture.
The visual route is CPU-heavy and may require several minutes; use a process
timeout of at least 600 seconds on low-end hardware. It is not an FPS benchmark.

## Stutter profiling

```powershell
./tests/planet/run_profile.ps1 -Label debug-on -Graphics -Sphere
./tests/planet/run_profile.ps1 -Label debug-off -Graphics -Sphere -DebugOff
```

Run these **sequentially**, without other tests in parallel. Omit `-Graphics`
for CPU-only headless diagnostics, not for claims about perceived smoothness.
The original Stage 2 visual script explicitly disables terrain on a private
definition copy. For Stage 3, use the terrain visual script and macro route above;
the old 50.5 km camera path can intersect mountain peaks.
The route uses 1,200 updates, a fixed simulation delta of 0.05 s, the same
camera poses and a 1100×760 viewport. It covers distance, progressive approach,
surface proximity, lateral movement, retreat and a fixed settling interval.
Output JSON includes per-update timings/counters and summaries; files go to a
fresh temporary directory printed by the runner. No per-frame file I/O occurs.

`update_us` measures the coordinator's CPU work. `selection_total_us` includes
structural/balance work during selection; `selection_sse_us` subtracts those
instrumented subsets. Do not add overlapping timers. `frame_us` is wall-clock
time to the next process-frame signal, including rendering/engine/waiting; it is
not a GPU timer. For component p95, only updates containing that timer are used;
update/frame percentiles cover all samples. Visual removal times measure queuing
of deletion, with deferred engine cost reflected in frame time.

The 4 ms CPU budget is **soft**, additional to operation budgets: it yields at
64-vertex blocks, leaf checks, or a complete ArrayMesh commit. It cannot preempt
an engine call. A value of 0 disables the time deadline for deterministic
operation-budget tests. CPU timing changes intermediate states, so compare
latency, work counts and final convergence, not only elapsed time. A fixed-length
route can end before all merges have completed; the visual test additionally
waits for stable states. Profiling is opt-in through `view.profile.enabled`.
