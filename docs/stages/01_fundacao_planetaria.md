# Etapa 1 — Fundação Planetária

**Status:** Concluída.

## Objetivo

Implementar os contratos matemáticos e de identidade que permitem representar as seis faces do planeta, converter coordenadas e identificar futuros patches sem depender de geometria, posição XYZ global ou nós de quadtree.

## Dependências

- Etapa 0 concluída;
- escala e direção arquitetural registradas em `docs/DECISIONS.md`;
- contratos transversais registrados em `docs/ARCHITECTURE.md`;
- PlanetLab mínimo e sistema de câmeras existentes.

## Contratos implementados

### Definição e raiz planetária

`PlanetDefinition` contém somente configuração global nesta etapa:

- raio base de `50.000,0` metros;
- `1,0` metro por unidade Godot.

`PlanetRoot` expõe essa definição no nó `Planet` do PlanetLab. O nó continua sem filhos e sem mesh.

### Faces e coordenadas

As faces usam UV público no domínio `[0, 1]²`. Internamente, UV é projetado para `[-1, 1]²` e combinado com uma base ortonormal destrogira, na qual `U × V = normal`.

| Face | Normal | U | V |
|---|---|---|---|
| +X | `(1, 0, 0)` | `(0, 0, -1)` | `(0, 1, 0)` |
| -X | `(-1, 0, 0)` | `(0, 0, 1)` | `(0, 1, 0)` |
| +Y | `(0, 1, 0)` | `(1, 0, 0)` | `(0, 0, -1)` |
| -Y | `(0, -1, 0)` | `(1, 0, 0)` | `(0, 0, 1)` |
| +Z | `(0, 0, 1)` | `(1, 0, 0)` | `(0, 1, 0)` |
| -Z | `(0, 0, -1)` | `(-1, 0, 0)` | `(0, 1, 0)` |

As bordas UV são definidas como `left: u=0`, `right: u=1`, `top: v=0` e `bottom: v=1`.

Conversões disponíveis:

- Face+UV → ponto no cubo;
- Face+UV → direção unitária;
- direção não nula → Face+UV canônico;
- Face+UV → posição radial usando raio e altura radial explícita opcional.

Na conversão direção → face, o maior componente absoluto define a face. Empates exatos são resolvidos na ordem **X, depois Y, depois Z**; o sinal do componente seleciona a face positiva ou negativa. Essa é a regra canônica para arestas e cantos.

### PatchId

`PatchId` é um `RefCounted`, não um `Node`, identificado logicamente por:

```text
face : level : x : y
```

Para o nível `L`, `x` e `y` pertencem a `[0, 2^L)`. O nível zero contém um patch por face em `(0, 0)`.

Operações disponíveis:

- validação;
- root por face;
- quantidade de divisões;
- parent;
- quatro children em ordem top-left, top-right, bottom-left, bottom-right;
- quadrante em relação ao parent;
- bounds UV;
- UV local → UV da face;
- igualdade lógica;
- chave estável `face:level:x:y`;
- representação de debug.

O limite defensivo atual é `MAX_LEVEL = 30`, mantendo subdivisões inteiras e cálculos UV em uma faixa prática segura. Isso não define o nível operacional do futuro quadtree.

### Topologia

`PlanetTopology` centraliza a travessia entre faces. Para cada par face+borda, a relação é derivada das bases centrais e informa:

- face vizinha;
- borda correspondente;
- parametrização direta ou invertida.

A mesma API encontra vizinhos de `PatchId` no mesmo nível. Em bordas externas, o índice ao longo da borda é preservado ou invertido conforme a transição e aplicado à borda correspondente da face vizinha.

## Componentes implementados

- `PlanetDefinition` e recurso padrão;
- `PlanetRoot`;
- `PlanetMath`;
- `PlanetFaceUV`;
- `PlanetEdgeTransition`;
- `PatchId`;
- `PlanetTopology`;
- integração da definição no PlanetLab;
- suíte permanente de testes da fundação.

## Ordem de implementação utilizada

1. definição e raiz planetária;
2. bases das faces e conversões;
3. identidade `PatchId`;
4. topologia e vizinhança;
5. integração no PlanetLab;
6. testes matemáticos e regressão do projeto.

## Testes

Executados com Godot 4.6.1:

- importação/editor headless;
- execução headless da cena principal por 120 frames;
- teste permanente das câmeras;
- `tests/planet/planet_foundation_test.gd`.

A suíte planetária valida:

- seis bases ortonormais, não degeneradas e determinísticas;
- centros, cantos e amostras internas das faces;
- comprimento unitário das direções;
- continuidade com múltiplas amostras nas 12 arestas físicas;
- round-trip Face+UV → direção → Face+UV canônico → direção;
- desempate canônico em arestas e cantos;
- raio de 50.000 unidades;
- roots, parent, children, quadrantes, bounds e UV local de `PatchId`;
- IDs inválidos e limites de coordenadas;
- cobertura exata do parent pelos quatro children;
- vizinhos internos e entre faces em diversos níveis;
- reciprocidade e reversão de bordas;
- determinismo por consultas repetidas.

Todos os processos concluíram com código de saída `0`. As suítes informaram `PLANET_FOUNDATION_TEST_OK` e `CAMERA_MANAGER_TEST_OK`.

## Escopo

Esta etapa implementa somente configuração planetária, bases das faces, conversões matemáticas, identidade de patches e topologia lógica.

## Fora de escopo

Não foram implementados mesh planetária, nós de quadtree, LOD, SSE, balanceamento 2:1, stitching, geomorphing, skirts, terreno, relevo, geologia, clima, biomas, materiais, zonas, chunks de mineração, mineração ou persistência.

## Critério de conclusão

O critério foi atingido: o PlanetLab continua executando, a definição de 50 km está integrada, as faces e conversões são determinísticas, as 12 arestas são contínuas, `PatchId` e vizinhança entre faces estão validados, e não existe geometria planetária ou quadtree implementado.

## Problemas bloqueadores

Nenhum.

O ambiente headless continua emitindo erro ao ler o armazenamento de certificados raiz do Windows. A importação também não consegue salvar configurações globais do editor fora do workspace. Ambos são não bloqueadores e não indicaram falha dos contratos do projeto.

## Documentos relacionados

- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md`
- `docs/CURRENT_STATUS.md`
- `docs/stages/00_auditoria.md`
