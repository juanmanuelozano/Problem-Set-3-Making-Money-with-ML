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
- **Estructura (D27):** el código está en `code/`, las figuras y tablas en `output/figures|tables/{01_descriptivas,02_modelos}/` y los informes `.md` en `reports/`, que enlazan a `../../output/`. Todo se reproduce con `code/00_main.R`. Un script nuevo se agrega a la tabla `pasos` del main, con su bandera, sus variables de entorno y los archivos que produce.
- Todos los scripts de R empiezan con `source(here::here("code", "01_setup.R"))`, y los utils se cargan igual: `source(here::here("code", "utils_modelos.R"))`. **Las rutas salen solo del objeto `P`** (`P$raw`, `P$processed`, `P$models`, `P$external`, `P$fig_desc`, `P$tab_desc`, `P$fig_mod`, `P$tab_mod`…); nunca rutas relativas sueltas ni `setwd()`. Un script suelto se corre desde la raíz con `Rscript code/NN_nombre.R`, o con el main: `--solo=NN_nombre.R`.
- **Los paquetes se cargan solo en `code/01_setup.R`**, en un único `pacman::p_load()`. `sf` y `keras3` son opcionales y se controlan con `HAY_SF` y `HAY_KERAS`. Los scripts nunca llaman a `library()` ni a `p_load()`.
- **Python (D11, D25):**
  - Scripts: `code/03c_texto.py` y `03d_tfidf.py` usan el entorno `texto` (`requirements.txt`); `03g_embeddings.py` usa el entorno `emb` (`requirements-emb.txt`).
  - El main los corre con `python_de(dir_venv(...))`. Los entornos los crea `asegura_venv()` de `01_setup.R` (con uv o reticulate, Python 3.11) en `~/.virtualenvs/ps3-*`.
  - En los .py, las rutas salen de `RAIZ = Path(__file__).resolve().parents[1]`.
  - ConTexto necesita la línea `collections.Iterable = collections.abc.Iterable` antes de importarlo.
- **Redes neuronales (D17):**
  - Se escriben en R con `keras3`; TensorFlow vive en el entorno `tf` (`requirements-tf.txt`).
  - Los scripts hacen `source(here::here("code", "utils_redes.R"))`, que llama a `reticulate::use_virtualenv(dir_venv("tf"))`, y validan con `cv_red()`/`cv_oof()`.
  - Las épocas se eligen por bloques, como las rondas del boosting.
  - Con `PRUEBA=1` en el entorno (o `--prueba` en el main), 08, 08c, 08d y 08e corren el flujo completo en minutos.
  - Las redes excluyen la zona de lujo de D15 (`LUJO` en `utils_redes.R`).
- Numeración: `0x` = datos y descriptivas, `03` = variables, `04+` = un modelo por script, `9x` = ensambles y envíos.
- Cada modelo se registra con `registra()` (en `code/utils_modelos.R`), que escribe `models/registro_modelos.csv`, las predicciones OOF y de test, y `submissions/<modelo>.csv`.
- Métrica principal: MAE en pesos sobre predicciones *out-of-fold* **dejando una localidad afuera, con buffer** (`BUFFER_M` en `code/utils_modelos.R`, decisión D9). Se reportan también el MAE en las observaciones del train ubicadas en Chapinero (la mejor aproximación al test) y el MAE promedio entre localidades.
- Validación cruzada: usar siempre `cv_oof(function(analisis, evaluacion) ...)` de `utils_modelos.R` (no `cv.glmnet(foldid=)` ni `xgb.cv`, que no admiten buffer). Para boosting, `xgb_rondas()` y `mejor_columna()`. Semillas: 123.
- **Ningún modelo puede llevar dummies (efectos fijos) de localidad** (D10). La localidad solo define los folds de validación.
- No modificar `data/raw/`.
- Git: **nunca** agregar `Co-Authored-By: Claude` ni otra atribución a Claude en commits o PRs.

## Entorno
El equipo trabaja en macOS y en Windows. Correr siempre con `< /dev/null` para que R no se quede esperando la entrada estándar.

### macOS
- `Rscript` está en el PATH.

### Windows
- R: `"/c/Program Files/R/R-4.6.1/bin/Rscript.exe"` (no está en el PATH). `uv` está en `~/.local/bin` y lo encuentra `asegura_venv()`.
- En Windows, `Rscript -e` con caracteres no ASCII se cae (segfault). Escribir el código en un archivo `.R` y correrlo.
- El Control de aplicaciones de Windows bloqueaba `sf`, `units`, `geosphere`, `tidymodels` y `spatialsample`. El 2026-11-24, `sf` ya cargaba. El código usa `sp`, una haversine propia y Overpass vía `httr`, y el main salta 03f/03h si `sf` no carga.
- Escribir los `.R` con la herramienta Write (los heredocs de bash eliminan las barras invertidas de las regex). Leer CSV con `num_threads = 1`.
- xgboost 3.2: `xgb.cv(..., folds=, prediction=TRUE)` -> `cv$early_stop$best_iteration`, `cv$cv_predict$pred`.
