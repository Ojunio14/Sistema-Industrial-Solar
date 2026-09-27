# Resultados da Etapa 13

Godot 4.6.1, Vulkan Forward+, AMD Radeon Vega 3, 1100×760, iluminação e PBR do
Planet Lab. Host com 4 processadores lógicos. Execuções sequenciais,
Engine.max_fps=120 e apresentação padrão, sem executar suíte headless em paralelo.
Mesma escolha determinística de anchor na borda de cube face, poses e sequência
de operações. O LOD evolui por tempo real; não é um replay de folhas idênticas.

## Comparação final: um e dois slots de jobs locais

| Medida | 1 worker configurado | 2 workers configurados |
|---|---:|---:|
| Primeiro chunk preparado (ms) | 1903.573 | 2147.530 |
| Zona publicada inicialmente (ms) | 12406.156 | 14613.186 |
| Reconstrução de quatro chunks editados (ms) | 7026.190 | 7252.410 |
| Frame durante edição: p50 (ms) | 29.941 | 30.400 |
| Frame durante edição: p95 (ms) | 30.495 | 31.547 |
| Frame durante edição: máximo (ms) | 40.253 | 37.932 |
| Frame na ativação: p95 (ms) | 21.764 | 31.135 |
| Frame na ativação: máximo (ms) | 44.829 | 44.750 |
| Job aceito, mesh ou transição: p50 (ms) | 1596.546 | 1632.540 |
| Job aceito, mesh ou transição: p95 (ms) | 3275.623 | 3488.812 |
| Atualização CPU local: p95 (ms) | 3.109 | 2.944 |
| Atualização CPU local: máximo (ms) | 31.042 | 29.420 |
| Commits por frame: p95 (ms) | 3.753 | 3.665 |
| Commits por frame: máximo (ms) | 5.730 | 5.254 |
| Commit de colisão incluindo inserção: p95 (ms) | 3.634 | 3.598 |
| Commit de colisão incluindo inserção: máximo (ms) | 4.364 | 4.268 |
| Render GPU: p95 (ms) | 28.796 | 28.875 |
| Jobs locais em voo: máximo | 1.000 | 2.000 |
| Resultados pendentes: máximo | 1.000 | 1.000 |
| Fila local: máximo | 3.000 | 2.000 |

**Padrão mantido: um job local.** Dois slots não reduziram a latência total
nesta execução. O pool da engine permanece na configuração automática;
slots em voo não garantem que duas tarefas de baixa prioridade executem
fisicamente ao mesmo tempo. Não houve aumento global da quantidade de threads.
O renderer global usa um slot enquanto houver zona ativa e recupera os dois
anteriores quando a última zona é desativada.

## Comparação direta com a Etapa 12

- Etapa 12: **2.439,475 ms** para reconstruir quatro chunks sincronamente,
  no visor técnico, sem PBR completo nem colisão integrada; trabalho pesado
  no frame principal, com pausas de centenas de milissegundos por chunk.
- Etapa 13, padrão: **7.03 s de latência total**,
  com material e física, preparados em segundo plano. Durante a reconstrução,
  frame p50/p95/máximo: **29.94 / 30.50 / 40.25 ms**.
- A latência total aumentou porque a malha agora consulta o sistema PBR,
  prepara física e respeita commits entre frames. O ganho é responsividade;
  não se declara ganho de throughput em comparação com o builder técnico.

Ativação inicial inclui convergência do LOD global e preparo do recorte/collar.
O primeiro chunk preparado em 1.90 s ainda não
é publicado isoladamente: a troca completa ocorreu em 12.41 s,
com o terreno global cobrindo a área durante a espera.

O cenário que invalida deliberadamente um job teve máximo de frame
63.72 ms (um slot) e 63.84 ms (dois).
Os registros `slow_frames` preservam tempos de update local, publicação,
commit e upload global. O orçamento de 2 ms é flexível, não um limite nativo
preemptivo. No par final, o maior commit local foi 5.73 ms;
o update local completo chegou a 31.04 ms.
O GPU p95 próximo de 29 ms limita a apresentação PBR nesta pose. Não afirmar
que todos os picos externos ao update local foram causalmente isolados.

## Geometria, física e visual

Ambas as execuções gráficas terminaram com **zero falhas**, com
42773 e 40859 verificações. Borda global/collar: erro máximo
**8.73 mm** (tolerância 30 mm).
Raios de física versus sampler final: **5.52 mm**
(tolerância 50 mm). Lados e canto dos quatro chunks têm posições compartilhadas
exatas. Os testes também verificam arrays completos de colisão contra a malha.

As imagens mostram depressão radial cruzando quatro chunks, pequena depressão
e aterro no mesmo World3D do planeta. A vista lateral torna a alteração
geométrica explícita; o material permanece o PBR planetário.

- [Natural próxima](visual_one_final/03_natural_close.png).
- [Edição próxima](visual_one_final/04_edited_close.png).
- [Perfil de escavação e aterro](visual_one_final/04b_edited_profile.png).
- [Zona completa](visual_one_final/05_edited_zone.png).
- [F9 integrado](visual_one_final/06_f9_states.png).
- [Órbita com zonas ativas](visual_one_final/07_orbit_active.png).
- [Órbita desativada](visual_one_final/08_orbit_inactive.png).
- [Edições recuperadas após reativação](visual_one_final/09_reactivated_edits.png).
- [Galeria comparativa](comparison.html).

## Memória medida e limites

Os buffers de um ArrayMesh real, reportados por
`RenderingServer.mesh_get_surface`, somaram **1,527,888 bytes
(1.457 MiB)**. São os buffers empacotados
do servidor de render; não incluem overhead de objeto, cópias internas do
driver ou BVH. Os arrays float32 de entrada somam 1.990.752 bytes (1,899 MiB).
Faces de colisão: 1.179.648 bytes (1,125 MiB); deltas: até 65.536 bytes.

Somando buffers empacotados + faces + deltas, 4/16/64 chunks correspondem a
**10.58 / 42.31 / 169.25 MiB**,
antes de overhead, arrays temporários e versões antiga/nova durante a troca.
O custo dos patches recortados/collar é adicional e depende da geometria local.

O monitor do processo após a primeira zona registrou memória estática
77.05 MiB e vídeo 190.81 MiB.
Esses totais incluem planeta, LOD, texturas, serviços e engine; não são custo
isolado da zona. As tabelas e limites de buffers por job estão no relatório
[da etapa](../../stages/13_integracao_terreno_editavel.md).

## Investigação preservada

`headless`, `headless_two`, `headless_final` e `visual_one` preservam ensaios
intermediários. Não confundir com `visual_one_final`/`visual_two_final`.
O primeiro shape monolítico custou dezenas de ms; foi dividido em 16 partes.
Inserir todos os shapes na publicação também causou picos; a inserção passou
para o preparo oculto com budget. Readback de patches globais apresentou
stalls gráficos: foi removido em favor do PlanetChunkBuilder em worker.
O par final acima usa essa solução, não seleciona o melhor frame dos protótipos.

Os logs de regressão completos e fingerprints ficam em `validation/`.
`source_audit.json` relaciona arquivos preservados e hashes; os geradores
naturais, material global, geologia, clima e biomas não foram alterados.

## Regressão completa e variabilidade posterior

`run_validation.ps1` terminou com **exit 0 em todos os 21 casos**: importação,
Lab, câmeras, fundação, terreno, LOD, contratos naturais, geologia, clima,
biomas, relevo, materiais, mineração e integração com um/dois slots.
As suítes determinísticas foram repetidas em processos independentes.
Etapa 12: 484.697 verificações por processo, fingerprint preservado.
Integração headless: **64839 / 65324 verificações, zero falhas**,
incluindo o acionamento/fechamento real do F9.

Na configuração de dois slots, os timestamps dentro dos jobs observaram no
máximo **1 job local efetivamente executando** de cada vez. Logo, dois
slots em voo não foram evidência de paralelismo físico local neste pool/host.
O padrão de um slot evita reservar buffers extras sem ganho observado.

A execução headless posterior teve variabilidade maior: na edição de quatro
chunks, máximos de frame **35.15 / 125.30 ms**;
máximos de commit local **23.17 / 104.53 ms**.
O cenário que força obsolescência chegou a **208.97 ms**.
Esses valores são confirmados e estão preservados, mesmo sendo superiores
ao par gráfico. Não foi isolada a causa da variação entre execuções. O budget
continua limitando a quantidade de operações por frame, mas não torna uma
chamada nativa preemptível. Portanto a implementação elimina a espera síncrona
pela geração, **não garante ausência de qualquer engasgo** neste hardware.

`validation/summary.json` contém casos e fingerprints; `validation/*.log`
mantém os logs completos, incluindo avisos conhecidos do host Windows.

Nota de procedimento: houve uma consulta inicial inadvertida a `git status`
antes da leitura completa do anexo. Ela falhou na pasta sem repositório;
nenhuma outra operação Git foi executada e nenhuma alteração foi feita via Git.


## Fechamento da seleção orbital

Após a captura gráfica, uma revisão encontrou um ancestral protegido que
impedia a redução de detalhe também em descendentes fora da zona. A seleção
agora percorre esse ancestral e permite merge dos ramos sem pins. A geometria
editável, materiais e geração dos chunks permanecem iguais às capturas.
O novo teste permanente `mining_lod_ownership_test.gd` passou (4 verificações),
e o teste LOD existente passou novamente (8.394 verificações). O runner contém
agora 22 casos: 21 executados juntos, mais o novo caso executado separadamente.
A primeira validação no projeto principal passou com 58.431 verificações;
`validation_main/` guarda a repetição final após a correção orbital.
