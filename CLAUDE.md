# Instrucciones para Claude en este repo

Proyecto: **Problem Set 3 – Predicting Prices** (Big Data y Machine Learning, Uniandes 2026-2). Predecir el precio de venta de inmuebles en Bogotá; el conjunto de prueba es casi todo **Chapinero**.

## Al empezar cada conversación
1. Leer [`BITACORA.md`](BITACORA.md): estado actual, mejor modelo y pendientes.
2. Revisar `models/registro_modelos.csv` para conocer las métricas vigentes.

## Al terminar cada conversación (obligatorio)
- Agregar una entrada en `BITACORA.md` (fecha, qué se hizo, resultados y siguientes pasos) y actualizar la sección **Estado actual**.
- Si cambió la modelación, actualizar `reports/02_modelos/informe_modelos.md`.
- Si se tomó una decisión metodológica, anotarla en `docs/decisiones.md`.

## Convenciones
- Idioma: español para código comentado, informes y bitácora.
- Los scripts se corren desde la raíz: `Rscript scripts/NN_nombre.R`. Todos hacen `source("scripts/00_config.R")`.
- Numeración: `0x` = datos y descriptivas, `03` = variables, `04+` = un modelo por script, `9x` = ensambles y envíos.
- Cada modelo se registra con `registra()` (en `scripts/utils_modelos.R`), que escribe `models/registro_modelos.csv`, las predicciones OOF y de test, y `submissions/<modelo>.csv`.
- Métrica principal: MAE en pesos sobre predicciones *out-of-fold* **dejando una localidad afuera, con buffer** (`BUFFER_M` en `scripts/utils_modelos.R`, decisión D9). Se reportan también el MAE en las observaciones del train ubicadas en Chapinero (la mejor aproximación al test) y el MAE promedio entre localidades.
- Validación cruzada: usar siempre `cv_oof(function(analisis, evaluacion) ...)` de `utils_modelos.R` (no `cv.glmnet(foldid=)` ni `xgb.cv`, que no admiten buffer). Para boosting, `xgb_rondas()` y `mejor_columna()`. Semillas: 123.
- No modificar `data/raw/`.
- Git: **nunca** agregar `Co-Authored-By: Claude` ni otra atribución a Claude en commits o PRs.

## Entorno
- macOS (desde 2026-11-16): `Rscript` está en el PATH. Correr siempre con `< /dev/null` para que no se quede esperando la entrada estándar.

### Windows (equipo anterior)
- R: `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe"` (no está en el PATH; no hay Python).
- El Control de aplicaciones de Windows bloquea `sf`, `units`, `geosphere`, `tidymodels` y `spatialsample`. Usar `sp`, una haversine propia y Overpass vía `httr`.
- Escribir los `.R` con la herramienta Write (los heredocs de bash eliminan las barras invertidas de las regex). Leer CSV con `num_threads = 1`.
- xgboost 3.2: `xgb.cv(..., folds=, prediction=TRUE)` -> `cv$early_stop$best_iteration`, `cv$cv_predict$pred`.
