# Etapa 0 — Auditoria da base atual

**Status:** Concluída.

## Objetivo

Estabelecer o baseline técnico do projeto, separar componentes úteis do protótipo experimental e entregar uma base mínima, clara e executável para o Planet v0.1.

## Estado inicial encontrado

O projeto Godot existente continha uma hierarquia experimental de sistema solar, GalaxyMap, ScaledSpace e Local_Space, câmeras acopladas a essa hierarquia, um gerador planetário cube-sphere experimental, quadtree/LOD inicial, materiais, shaders e texturas de teste.

O repositório ainda não possuía documentação técnica persistente nem uma fundação planetária aprovada implementada.

## Principais conclusões

- A arquitetura planetária antiga era experimental e não atendia como fundação do Planet v0.1.
- As responsabilidades úteis de câmera eram FreeFly/debug, RTS e Orbital.
- A nova fundação precisava de um laboratório mínimo independente da hierarquia espacial antiga.
- Nenhum componente do antigo gerador planetário justificava preservar o sistema legado inteiro.

## Decisão sobre o legado

Foi aprovada a remoção da arquitetura antiga sem camada de compatibilidade. Foram eliminados o antigo sistema de câmeras, CameraManager, gerador planetário, cube-sphere, quadtree experimental, hierarquia Galaxy/ScaledSpace/Local_Space, proxies, recursos, materiais, shaders e assets exclusivos desse protótipo.

## Base entregue

Foi criado um PlanetLab mínimo com três responsabilidades principais:

- `Planet`, mantido vazio;
- `Cameras`, contendo FreeFly, RTS e Orbital;
- `Debug`, exibindo a câmera ativa.

O novo CameraManager permite troca cíclica, seleção direta e garante uma única câmera controladora ativa. O sistema de câmeras permanece desacoplado da futura arquitetura planetária.

## Testes realizados

A Etapa 0 foi validada com Godot 4.6.1 por meio de:

- importação/editor headless;
- execução headless da cena principal;
- teste permanente do CameraManager, cobrindo registro, câmera padrão, troca cíclica, seleção direta, tentativas inválidas e IDs duplicados;
- busca estática por referências quebradas e ligações residuais ao legado.

Os três processos Godot concluíram com código de saída 0, e o teste permanente informou `CAMERA_MANAGER_TEST_OK`.

## Resultado da limpeza

A base passou a conter somente a cena PlanetLab, o novo sistema de câmeras, seus testes e os arquivos básicos do projeto. Não permaneceram referências de código-fonte aos sistemas legados nem entradas legadas no cache global de classes após a validação.

## Critério de conclusão

A Etapa 0 está concluída porque o projeto possui uma base mínima executável, responsabilidades de câmera preservadas e testadas, legado removido e estado técnico documentado para orientar a próxima etapa.

A Fundação Planetária não foi iniciada.
