# Modelos

Los archivos los escribe automáticamente `registra()` (en `scripts/utils_modelos.R`).

| Archivo | Contenido |
|---|---|
| `registro_modelos.csv` | Una fila por modelo: fecha, descripción, hiperparámetros y métricas OOF (`mae_total`, `mae_chapinero`, `mae_fold2`, `mape_chapinero`), en pesos |
| `oof_predicciones.csv` | Predicciones out-of-fold en log de cada modelo para el train, con el fold y el indicador de Chapinero. Insumo de los ensambles |
| `test_predicciones.csv` | Predicciones en log de cada modelo para el test |
| `*.rds`, `*.ubj` | Modelos finales ajustados con todo el train (excluidos de git; se regeneran) |

Nomenclatura: `mNN_nombre`. `m0x` son las referencias y los modelos base, y `m9x` los ensambles.
