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
- **Excepción de Python (solo el texto, D11):** `scripts/03c_texto.py` (limpieza, lematización, n-gramas y nubes con ConTexto) y `scripts/03d_tfidf.py` (TF-IDF → `data/processed/tfidf.parquet`, formato largo y disperso que R lee con `arrow`). Se corren con `.venv/bin/python scripts/03c_texto.py`; la instalación está en `requirements.txt` (uv, Python 3.11, `contexto --no-deps`). ConTexto necesita la línea `collections.Iterable = collections.abc.Iterable` antes de importarlo.
- **Redes neuronales (D17):** en R con `keras3`; TensorFlow vive en un venv aparte, `.venv-tf` (`requirements-tf.txt`), para no romper el entorno de texto. Los scripts hacen `source("scripts/utils_redes.R")` (que llama a `reticulate::use_virtualenv(normalizePath(".venv-tf"))`) y validan con `cv_red()`/`cv_oof()`. Las épocas se eligen por bloques, como las rondas del boosting. Con `PRUEBA=1` en el entorno, 08, 08c, 08d y 08e corren el flujo completo en minutos. Las redes excluyen la zona de lujo de D15 (`LUJO` en `utils_redes.R`).
- Librerías: solo con `pacman::p_load()`, en la parte de arriba del script (justo después de los `source()`), nunca `library()` en medio del código. `00_config.R` carga las comunes (`tidyverse`, `scales`) e instala pacman si falta; cada script carga solo las suyas: `suppressMessages(pacman::p_load(glmnet))`.
- Numeración: `0x` = datos y descriptivas, `03` = variables, `04+` = un modelo por script, `9x` = ensambles y envíos.
- Cada modelo se registra con `registra()` (en `scripts/utils_modelos.R`), que escribe `models/registro_modelos.csv`, las predicciones OOF y de test, y `submissions/<modelo>.csv`.
- Métrica principal: MAE en pesos sobre predicciones *out-of-fold* **dejando una localidad afuera, con buffer** (`BUFFER_M` en `scripts/utils_modelos.R`, decisión D9). Se reportan también el MAE en las observaciones del train ubicadas en Chapinero (la mejor aproximación al test) y el MAE promedio entre localidades.
- Validación cruzada: usar siempre `cv_oof(function(analisis, evaluacion) ...)` de `utils_modelos.R` (no `cv.glmnet(foldid=)` ni `xgb.cv`, que no admiten buffer). Para boosting, `xgb_rondas()` y `mejor_columna()`. Semillas: 123.
- **Ningún modelo puede llevar dummies (efectos fijos) de localidad** (D10). La localidad solo define los folds de validación.
- No modificar `data/raw/`.
- Git: **nunca** agregar `Co-Authored-By: Claude` ni otra atribución a Claude en commits o PRs.

## Entorno
- macOS (desde 2026-11-16): `Rscript` está en el PATH. Correr siempre con `< /dev/null` para que no se quede esperando la entrada estándar.

### Windows (equipo anterior)
- R: `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe"` (no está en el PATH; no hay Python).
- El Control de aplicaciones de Windows bloquea `sf`, `units`, `geosphere`, `tidymodels` y `spatialsample`. Usar `sp`, una haversine propia y Overpass vía `httr`.
- Escribir los `.R` con la herramienta Write (los heredocs de bash eliminan las barras invertidas de las regex). Leer CSV con `num_threads = 1`.
- xgboost 3.2: `xgb.cv(..., folds=, prediction=TRUE)` -> `cv$early_stop$best_iteration`, `cv$cv_predict$pred`.
