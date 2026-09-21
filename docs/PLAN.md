# Plano geral — Planet v0.1

## 0. Auditoria da base atual

- **Objetivo:** estabelecer um baseline confiável e remover o protótipo incompatível com a nova fundação.
- **Implementação em alto nível:** auditar a base, criar o PlanetLab mínimo, preservar as câmeras úteis e eliminar o legado desacoplado.
- **Dependência principal:** projeto original disponível para inspeção.
- **Critério geral de conclusão:** base pequena, documentada, executável e coberta pelos testes permanentes de câmeras.

## 1. Fundação planetária

- **Objetivo:** definir os contratos fundamentais de representação e identificação do planeta.
- **Implementação em alto nível:** formalizar escala, cube-sphere, faces, coordenadas e identidades básicas de regiões.
- **Dependência principal:** Etapa 0 concluída.
- **Critério geral de conclusão:** contratos fundamentais implementados e testados sem iniciar LOD ou terreno avançado.

## 2. Quadtree global

- **Objetivo:** organizar hierarquicamente a superfície planetária.
- **Implementação em alto nível:** estabelecer quadtrees por face e a infraestrutura central de vizinhança entre faces.
- **Dependência principal:** fundação planetária estável.
- **Critério geral de conclusão:** subdivisão, identificação, vizinhança e contratos de LOD validados.

## 3. Relevo macro

- **Objetivo:** representar a macroforma do terreno planetário.
- **Implementação em alto nível:** introduzir dados radiais de elevação e sua representação derivada na superfície.
- **Dependência principal:** quadtree global funcional.
- **Critério geral de conclusão:** relevo macro coerente, reconstruível e validado nas fronteiras relevantes.

## 4. Geologia estrutural

- **Objetivo:** estabelecer estruturas geológicas em escala planetária e regional.
- **Implementação em alto nível:** gerar e armazenar dados geológicos independentes da aparência e do bioma.
- **Dependência principal:** relevo macro estabelecido.
- **Critério geral de conclusão:** estruturas geológicas reproduzíveis e integradas aos dados do terreno.

## 5. Clima e biomas

- **Objetivo:** classificar regiões climáticas e biomas sem confundi-los com geologia.
- **Implementação em alto nível:** derivar clima e biomas a partir dos dados planetários pertinentes.
- **Dependência principal:** relevo macro e geologia estrutural disponíveis.
- **Critério geral de conclusão:** classificação determinística, consultável e testada.

## 6. Materiais/aparência

- **Objetivo:** representar visualmente os dados planetários existentes.
- **Implementação em alto nível:** criar materiais e regras de aparência derivados de relevo, geologia e biomas.
- **Dependência principal:** dados de clima, bioma e geologia estáveis.
- **Critério geral de conclusão:** aparência coerente sem transformar materiais em fonte de verdade.

## 7. Geologia subterrânea e recursos

- **Objetivo:** representar dados subterrâneos e distribuição de recursos minerais.
- **Implementação em alto nível:** introduzir modelos de subsuperfície derivados da geologia, independentes do bioma.
- **Dependência principal:** geologia estrutural estabelecida.
- **Critério geral de conclusão:** recursos consultáveis e reproduzíveis com contratos testados.

## 8. Sistema de zonas

- **Objetivo:** delimitar áreas de gameplay e ativação técnica de maior detalhe.
- **Implementação em alto nível:** criar Mining Zones conectadas às identidades persistentes da superfície.
- **Dependência principal:** coordenadas e dados geológicos estáveis.
- **Critério geral de conclusão:** zonas identificáveis, persistentes e capazes de controlar ativação de detalhe.

## 9. Mining Chunks

- **Objetivo:** disponibilizar dados detalhados de mineração somente onde necessários.
- **Implementação em alto nível:** subdividir Mining Zones em chunks e células calibráveis.
- **Dependência principal:** sistema de zonas funcional.
- **Critério geral de conclusão:** chunks ativáveis, consultáveis e integrados à fonte de verdade do terreno.

## 10. Escavação/aterro v1

- **Objetivo:** permitir a primeira modificação persistente do terreno minerável.
- **Implementação em alto nível:** alterar dados de células e reconstruir as representações derivadas afetadas.
- **Dependência principal:** Mining Chunks funcionais.
- **Critério geral de conclusão:** escavação e aterro consistentes, persistentes e testados.

## 11. Mineração material

- **Objetivo:** transformar escavação em extração de materiais definidos pelos dados geológicos.
- **Implementação em alto nível:** associar remoção de terreno a quantidades e tipos de material.
- **Dependência principal:** escavação e geologia subterrânea integradas.
- **Critério geral de conclusão:** extração determinística e contabilização validada.

## 12. Colisão/máquinas de teste

- **Objetivo:** validar interação física e operacional com o terreno modificável.
- **Implementação em alto nível:** gerar colisões derivadas e introduzir máquinas mínimas de teste.
- **Dependência principal:** terreno minerável e mineração material funcionais.
- **Critério geral de conclusão:** colisão reconstruível e cenários de máquina reproduzíveis.

## 13. Persistência/performance

- **Objetivo:** consolidar salvamento, carregamento e desempenho do Planet v0.1.
- **Implementação em alto nível:** persistir apenas dados não reconstruíveis e medir os fluxos críticos.
- **Dependência principal:** contratos das etapas anteriores estabilizados.
- **Critério geral de conclusão:** restauração correta do estado e metas de desempenho verificadas em cenários representativos.
