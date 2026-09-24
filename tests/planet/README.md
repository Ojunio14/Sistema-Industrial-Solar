# Validação da fundação, geologia, clima e biomas — Etapas 6–9

O runner inclui `geology_test.gd` em dois processos independentes e compara o
fingerprint. Verifica 8.192 alturas naturais antes/depois, ID/tipo/idade/
influência, distribuição, bordas/cantos/LOD, fronteiras, workers concorrentes e
igualdade dos atributos naturais de chunk com/sem geologia. Os testes da
fundação permanecem com o oráculo imutável do doador.

O runner inclui também `climate_test.gd` em dois processos e compara o
fingerprint climático. Ele valida 8.192 direções, campos finitos, seed e ordem,
latitude/altitude/oceano controlados, caso barlavento/sotavento, 12 bordas,
oito cantos, cinco LODs, consultas concorrentes e igualdade de altura, arrays,
bounds e erro LOD antes/depois. Estatísticas globais são impressas pelo teste.

`biome_test.gd` também roda em dois processos com comparação de fingerprint.
Valida dez famílias, pesos normalizados, água sem bioma terrestre, controles de
clima/topografia/geologia, distribuição global, 12 arestas/oito cantos/cinco
LODs, workers concorrentes e invariância de altura/malha/erro LOD. F7 é
capturado nas nove poses e em alvos de cada família, com debug desligado
comparado por hash à Etapa 8.

`surface_visual_test.gd` também captura F5: modos 1–9 no globo e província/
maturidade nas outras oito poses. A comparação de hashes naturais com a
Etapa 6 fica em `docs/evidence/07_reintegracao_geologia/natural_comparison.json`.
F6 captura cinco modos nas nove poses e oito alvos climáticos em
`docs/evidence/08_reintegracao_clima/`; as nove imagens naturais são comparadas
por hash com a Etapa 7.

`./tests/planet/run_validation.ps1` importa o projeto, abre PlanetLab em headless,
testa câmeras, matemática, PlanetShape, geometria e LOD/WorkerThreadPool.
`contracts_a/b` confrontam dois processos independentes com o mesmo oráculo do
doador (`donor_contracts.json`). Erros de script/engine invalidam a execução,
mesmo se o exit code for zero.

O oráculo foi obtido executando os arquivos originais de Sistema_Industrial_v1
num projeto de referência isolado, com `test_planet_100km.tres`. Registra 8.192
direções e 24 chunks (6 faces × níveis 0/1/4/8), com hashes de posições, normais
e índices. Proveniência: `docs/evidence/06_substituicao_planeta/donor_sources.json`.
Mudanças no gerador não devem atualizar esse oráculo automaticamente.

Captura gráfica, com Godot 4.6.1 (não usar headless):

```powershell
& $Godot --path . --rendering-method forward_plus --script res://tests/planet/surface_visual_test.gd -- C:/Temp/planet-stage6-visual
```

Cria capturas naturais e de debug de 9 poses (globo, órbita baixa, quilômetros, centenas de metros,
solo, montanhas, horizonte, borda de face, afastamento) e `report.json` com a
rota contínua de 720 frames. Mesmos parâmetros de produção; nenhum budget ou
LOD reduzido. As imagens têm material técnico do doador, sem texturas finais,
biomas, atmosfera, nuvens ou água. O chão submarino é terreno opaco.

A suíte LOD usa adicionalmente uma configuração pequena para testar transições
rapidamente. A captura gráfica exercita separadamente 17×17, nível 8, 510
residentes, 96 em cache e dois workers/uploads. As suítes antigas estão
preservadas em `archive/stages_02_05/tests/planet`, fora do runtime atual.
# Etapa 10 — contratos atuais

O histórico acima registra Etapas 6–9. Não se exige mais igualdade de geometria
com a Etapa 9. `surface_contract_test` valida a função atual, o contorno/máscara
continental exatos e a topologia preservada. A fixture `fixtures/stage9_shape.gd`
é somente de teste e é confrontada com `donor_contracts.json` imutável; nunca
se importa o projeto doador no runtime. Os fingerprints atuais são confrontados
entre dois processos.

`relief_test.gd` verifica determinismo, preservação terra/costa, causação por
geologia, orientação e maturidade controladas, planalto/bacia/ígneo, aumento de
curvatura em cadeias e planícies suaves fora da transição costeira. Verifica
workers, faces/cantos, normais, bounds, winding, erro em quartos de célula e
pontos idênticos nos LODs 6/7/8/9. Clima/biomas devem usar a nova altura.
`relief_enabled=false` agora significa apenas substrato continental, não Etapa 9.

`relief_profile.gd -- OUTPUT 17 9 --transitions` captura dez poses e sete fases
em 840 frames, CPU/GPU, memória, filas, uploads e espaçamento do patch sob a
câmera. `landmarks.json` no pai de OUTPUT fixa posições para ambas as versões.
Gere-o com a versão atual; copie somente o harness para uma cópia congelada da
Etapa 9 e reutilize esse arquivo. A altura de enquadramento usa o maior valor
entre ambas; a folga real é registrada. Material técnico e iluminação iguais.
As 30 capturas de movimento são posteriores à rota medida.

`summarize_relief.ps1 -Evidence OUTPUT_PARENT` consolida percentis e fases.
Alternativas: 17/8, 17/9, 33/8, mesmos budgets 510/96 e dois workers/uploads.
Capturas históricas eram iguais por hash; na Etapa 10 mudam deliberadamente.

Diagnóstico adicional: `--route-only` aquece somente a pose de horizonte antes
da mesma rota de 840 frames. `--uncapped` desliga VSync/limite de FPS apenas
no processo de teste; a rota por frames então dura menos tempo real e exercita
uma convergência diferente. Não comparar esse FPS diretamente com o ensaio
normal de apresentação. O timeout de estabilização usa 120 segundos reais.
