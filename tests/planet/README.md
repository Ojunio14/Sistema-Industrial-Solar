# Validação da fundação e da geologia — Etapas 6–7

O runner inclui `geology_test.gd` em dois processos independentes e compara o
fingerprint. Verifica 8.192 alturas naturais antes/depois, ID/tipo/idade/
influência, distribuição, bordas/cantos/LOD, fronteiras, workers concorrentes e
igualdade dos atributos naturais de chunk com/sem geologia. Os testes da
fundação permanecem com o oráculo imutável do doador.

`surface_visual_test.gd` também captura F5: modos 1–9 no globo e província/
maturidade nas outras oito poses. A comparação de hashes naturais com a
Etapa 6 fica em `docs/evidence/07_reintegracao_geologia/natural_comparison.json`.

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

Cria 18 PNGs de 9 poses (globo, órbita baixa, quilômetros, centenas de metros,
solo, montanhas, horizonte, borda de face, afastamento) e `report.json` com a
rota contínua de 720 frames. Mesmos parâmetros de produção; nenhum budget ou
LOD reduzido. As imagens têm material técnico do doador, sem texturas finais,
clima, atmosfera, nuvens ou água. O chão submarino é terreno opaco.

A suíte LOD usa adicionalmente uma configuração pequena para testar transições
rapidamente. A captura gráfica exercita separadamente 17×17, nível 8, 510
residentes, 96 em cache e dois workers/uploads. As suítes antigas estão
preservadas em `archive/stages_02_05/tests/planet`, fora do runtime atual.
