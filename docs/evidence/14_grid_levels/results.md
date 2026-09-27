# Resultados — Etapa 14: GRID + LEVELS

Implementação e capturas no Planet Lab real, Godot 4.6.1 / Vulkan Forward+ /
AMD Radeon Vega 3, 1100 × 760. Os números da grid representam o plano.

## Demonstração verificada

- Plataforma Level 10 → rampa → plataforma Level 5: **72 células**, rampa de
  20 m de comprimento e 8 m de largura, grade técnica de 25%.
- Datum único da demonstração: **91 m**, passo de 1 m.
  Assim, Level 10 = 101 m e Level 5 = 96 m. O Lab normal continua origem 0 m.
- Arrasto por handlers reais de mouse + picking físico; soltura sem alteração
  do terreno, confirmação explícita e DEV APPLY separado.
- **10603 verificações gráficas, zero falhas.**
- Depois de aplicar, **72/72 células COMPLETE**. Erro máximo FinalTerrain/target:
  **1.370 mm**; raycast/target:
  **3.906 mm**.
- Verificadas normais da inclinação, normais/vértices compartilhados entre
  chunks, arrays físicos contra render e ausência de quantização em degraus.
- DEV APPLY das 72 células: **2.330 ms** para escrever deltas.
  Este tempo não inclui a geração/publicação assíncrona posterior da Etapa 13.

## Custo do overlay

O teste adiciona uma seleção de 4.096 células às 72 já confirmadas:
**4168 células / 8400 glyphs / 2 nós de desenho**.
Não existe Node nem Label3D por célula. O buffer de instâncias mede
**537,600 bytes**, além de grid, atlas, arrays
temporários e avaliações. Isso não representa a memória total do processo.

| Medida | Resultado |
|---|---:|
| Maior passo de avaliação CPU | 1.655 ms |
| Maior passo de construção/publicação do overlay | 5.735 ms |
| Construção incremental: tempo decorrido | 15.801 s |
| Frame p50, overlay oculto | 146.784 ms |
| Frame p50, overlay visível | 150.411 ms |
| Frame p95, overlay oculto | 154.252 ms |
| Frame p95, overlay visível | 186.487 ms |
| GPU p95, overlay oculto | 148.516 ms |
| GPU p95, overlay visível | 180.342 ms |

A seleção de folhas globais fica congelada na comparação; são 90 frames por
janela, mesma câmera e resolução, sem regressões headless em paralelo. A
diferença observada de p50 foi **3.627 ms**;
no p95, **32.235 ms**.
São medidas do quadro inteiro; driver, escalonamento e frequência do hardware
não foram isolados. O planeta já é caro nesta pose sem overlay. Não inferir
que todo o aumento de cauda pertence ao shader dos números.

**CONFIRMADO:** a preparação grande demora muitos frames neste host. Os budgets
de 1,5/2 ms são flexíveis e o upload nativo final pode excedê-los. Há espaço para
reduzir alocações e tempo de preparo antes de uso produtivo intensivo.
O limite de números foi elevado a 250 m apenas no benchmark para exercitar
todos os glyphs; a interface usa 140 m. A captura distante testa sua ocultação.

## Regressões executadas

- Contratos da Etapa 14: **3.332 verificações, zero falhas**.
- CameraManager: troca cíclica/direta, câmera inexistente e ID repetido passaram.
- Etapa 12: **484.697 verificações**, fingerprint preservado
  `6d20dd3c1a706da1583bd4dc9bb03eef9449b8664fdf6e496e7a4bbc27ad6d88`.
- Ownership/LOD: **4 verificações, zero falhas**.
- Integração da Etapa 13: **58.440 verificações, zero falhas**.
- Importação final sem erros de parsing, script ou shader.

O runner permanente contém os 22 casos anteriores mais contratos e demonstração
da Etapa 14. Nesta alteração foram executados os testes pertinentes acima;
não se afirma uma nova execução conjunta dos 24 casos. A auditoria por hashes
registra os arquivos de terreno natural/material/física preservados.
`validation_main/` registra a importação e repetição dos contratos/demonstração
no projeto principal depois da aplicação.

## Capturas reais

- [Rampa detectando os dois níveis](visual_verified/00_ramp_preview_anchors.png).
- [Plano sobre terreno irregular](visual_verified/01_grid_levels_before.png).
- [Números próximos antes de aplicar](visual_verified/01b_levels_close.png).
- [72 células concluídas](visual_verified/02_grid_levels_complete.png).
- [Níveis e rampa após aplicar, detalhe](visual_verified/02b_levels_complete_close.png).
- [Geometria sem overlay](visual_verified/03_applied_profile.png).
- [4.096 células adicionais em batch](visual_verified/04_batched_4096_cells.png).
- [Distância: números ocultos](visual_verified/05_distant_no_numbers.png).

## Depuração e limites

Na inspeção gráfica foram corrigidas orientação invertida dos números e
oclusão parcial em rampas. A orientação agora acompanha a câmera dentro do
plano local da célula. O painel tem rolagem para resoluções menores.
Um ensaio inicial excedeu seu prazo de avaliação; outro teve a seleção de
benchmark alterada durante eventos de entrada. O teste final aguarda o trabalho
incremental e desativa entrada externa, chamando explicitamente os handlers
testados. Ensaios intermediários permanecem em `.stage14`, não são resultados
finais. Um encerramento do Godot ao abrir log foi resolvido usando caminho absoluto.

**RISCO:** transação DEV síncrona em seleções grandes; mais memória e fragmentos
com muitos glyphs. **DÍVIDA TÉCNICA:** comandos menores, undo, salvamento de
planos, rampas fora dos eixos e redes de ordens conectadas. **SUSPEITO:** variação
de driver/host nas caudas de frame; sem atribuição causal conclusiva.
Não foram implementadas máquinas, estoque, transporte ou conservação de massa.
