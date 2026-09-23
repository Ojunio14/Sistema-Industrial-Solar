# Evidências da substituição

- comparison_1..3.png: pares de capturas reais, doador à esquerda e Lab à direita.
- reference/target/target_repeat: nove poses, nove diagnósticos LOD e report.json.
- performance_summary.json: resumo das três rotas Vulkan, sem esconder a inicial.
- image_difference.json: diferença pixel a pixel nas capturas originais.
- donor_sources.json: SHA256 dos arquivos runtime originais usados na referência.
- validation/: logs da regressão completa, todos exit 0.
- old_stage5_profile.json: perfil anterior, rota diferente, não comparação causal.

Comandos em tests/planet/README.md; interpretação/limites na Etapa 6.
O material de comparação é o técnico original do doador, sem PBR/efeitos.
