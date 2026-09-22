# Estado atual — Planet v0.1

## Etapa atual

Etapa 1 concluída.

Próxima: Etapa 2 — Quadtree global.

## Concluído

- PlanetLab mínimo;
- nó `Planet` vazio;
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
- raiz `Planet` formal integrada ao PlanetLab, ainda sem mesh;
- bases centralizadas das seis faces da cube-sphere;
- conversões Face+UV ↔ direção e posição radial base;
- regra canônica de desempate X → Y → Z;
- identidade matemática `PatchId` com parent, children, quadrante e bounds;
- topologia central de faces e bordas;
- vizinhança de patches no mesmo nível, inclusive entre faces;
- testes permanentes da fundação planetária.

## Em andamento

Nenhuma implementação.

## Próximo marco

Planejar e especificar a Etapa 2 — Quadtree global.

## Problemas conhecidos

- navegação RTS esférica ainda não validada;
- Orbital ainda não validada sobre geometria planetária real;
- alinhamento radial definitivo das câmeras ainda depende de geometria planetária real.

Os contratos matemáticos da fundação estão validados. Os itens de câmera não bloqueiam o início da Etapa 2.

## Última validação

Projeto validado com Godot 4.6.1 por meio de:

- importação/editor headless;
- execução da cena principal;
- teste permanente das câmeras;
- teste permanente da fundação planetária.
