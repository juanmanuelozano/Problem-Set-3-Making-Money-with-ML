# Problem Set 3 — Making Money with ML?

Predicción del precio de venta de viviendas en Bogotá a partir de datos de Properati, para el curso *Big Data y Machine Learning* (Uniandes, 2026-2).

## Estado actual

| | |
|---|---|
| Mejor modelo en Chapinero | `m06_hibrido_en_xgb` — MAE OOF de 155 M en Chapinero, 134 M en total |
| Mejor modelo en el total | `m90_ensamble` — MAE OOF de 131 M |

Detalle e historial en [`BITACORA.md`](BITACORA.md).

## Informes

1. [**Estadísticas descriptivas y motivación espacial**](reports/01_descriptivas/informe_descriptivas.md): qué hay en los datos, la geografía del precio y las variables candidatas según la literatura hedónica.
2. [**Modelación: primera ronda**](reports/02_modelos/informe_modelos.md): validación espacial, elastic net, random forest, XGBoost, híbridos y ensamble.

## Estructura

```
├── README.md              ← este archivo
├── BITACORA.md            ← diario del proyecto (se actualiza en cada sesión)
├── CLAUDE.md              ← instrucciones y convenciones para Claude
├── data/
│   ├── raw/               ← datos originales de Kaggle (no se tocan)
│   ├── external/osm/      ← OpenStreetMap: localidades, UPZ y servicios
│   ├── processed/         ← bases construidas por los scripts
│   └── README.md          ← diccionario de variables
├── scripts/               ← todo el código, numerado en orden de ejecución
├── models/                ← registro de métricas, predicciones OOF y de test, modelos guardados
├── submissions/           ← archivos listos para Kaggle (uno por modelo)
├── reports/
│   ├── 01_descriptivas/   ← informe + figures/ + tables/
│   └── 02_modelos/        ← informe + figures/ + tables/
└── docs/
    └── decisiones.md      ← decisiones metodológicas y su justificación
```

## Cómo reproducir

Requiere R 4.6 con `tidyverse`, `sp`, `httr`, `jsonlite`, `stargazer`, `ranger`, `glmnet` y `xgboost` (≥ 3.0). Los scripts se corren desde la raíz del repo:

```bash
Rscript scripts/01_osm_descarga.R    # datos de OpenStreetMap (usa la caché si ya existe)
Rscript scripts/02_descriptivas.R    # informe 1: figuras, tablas y base enriquecida
Rscript scripts/03_features.R        # imputaciones, variables finales y folds espaciales
Rscript scripts/04_regresiones.R     # mediana de referencia y OLS (especificaciones)
Rscript scripts/04b_elastic_net.R    # elastic net
Rscript scripts/05_random_forest.R   # ~10 min
Rscript scripts/06_xgboost.R
Rscript scripts/07_hibridos.R        # XGBoost sobre precio/m² e híbrido lasso + XGBoost
Rscript scripts/90_comparacion.R     # ensamble, figuras e informe 2
```

| Script | Qué hace |
|---|---|
| `00_config.R` | Rutas, paleta, tema gráfico y funciones (haversine, MAE, recorte) |
| `utils_modelos.R` | Matrices para modelos lineales y de árboles, evaluación OOF y `registra()` (registro, predicciones y envío) |
| `01`–`02` | Datos externos y descriptivas |
| `03` | Ingeniería de variables y folds |
| `04`–`07` | Un script por familia de modelos |
| `90` | Comparación y ensamble |

**Nota del entorno:** en este equipo Windows bloquea `sf`, `units` y `geosphere`. El código usa alternativas (`sp`, haversine propia, Overpass vía `httr`).
