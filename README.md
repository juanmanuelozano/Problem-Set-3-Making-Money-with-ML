# Problem Set 3: Making Money with ML

Este repositorio predice el precio de venta de viviendas en Bogotá con datos de Properati. Es el trabajo del curso *Big Data y Machine Learning* (Uniandes, 2026-2). El conjunto de prueba está casi todo en **Chapinero**, así que la validación deja afuera una localidad a la vez (con un buffer de 500 m) y ningún modelo usa efectos fijos de localidad.

| | |
|---|---|
| Mejor envío en Kaggle | `m48_star_nn_xgbsq_area_m2`: NN STAR con catastro + XGB STAR con comparables. MAE público de **153,3 M** |
| Informes | [Descriptivas y motivación espacial](reports/01_descriptivas/informe_descriptivas.md) · [Modelación](reports/02_modelos/informe_modelos.md) |
| Historial y decisiones | [`BITACORA.md`](BITACORA.md) · [`docs/decisiones.md`](docs/decisiones.md) |

---

## Cómo reproducir los resultados

Todo se corre **desde R** con un solo script maestro, [`code/00_main.R`](code/00_main.R), y funciona igual en Windows y en macOS. El main también llama a los scripts de Python, con el intérprete del entorno que le corresponde a cada uno. No hace falta abrir una terminal de Python ni activar entornos a mano.

### 1. Requisitos

| | Versión | Notas |
|---|---|---|
| R | ≥ 4.5 (probado con 4.6.1) | <https://cran.r-project.org> |
| RStudio | opcional | recomendado: se abre el proyecto con doble clic |
| Python | **no hace falta instalarlo** | el setup crea los entornos con Python 3.11 la primera vez que se necesitan (ver [R y Python](#r-y-python)) |
| [uv](https://docs.astral.sh/uv/) | opcional | si está instalado, los entornos de Python se crean más rápido |
| Internet | solo la primera vez | paquetes de R y de Python y, si se piden, las descargas de OpenStreetMap y del catastro |

Los paquetes de R se instalan solos: [`code/01_setup.R`](code/01_setup.R) los carga con `pacman::p_load()` e instala los que falten.

### 2. Correr

**Opción A: RStudio**

1. Abrir `Problem-Set-3-Making-Money-with-ML.Rproj`. El proyecto fija la raíz y todas las rutas salen de ahí con `here::here()`.
2. Abrir `code/00_main.R`, revisar los interruptores (sección 1 del script) y correr:

   ```r
   source("code/00_main.R")
   ```

**Opción B: terminal** (sirve desde cualquier carpeta)

```bash
Rscript code/00_main.R                    # línea principal; reutiliza lo que ya está calculado
Rscript code/00_main.R --todo             # reproduce TODO desde cero (varias horas)
Rscript code/00_main.R --python --redes   # enciende solo algunos bloques
Rscript code/00_main.R --solo=04_regresiones.R,90_comparacion.R   # solo esos pasos
```

En Windows, si `Rscript` no está en el PATH: `"C:\Program Files\R\R-4.6.1\bin\Rscript.exe" code\00_main.R`.

### 3. Interruptores

Están al principio de `code/00_main.R`. También se encienden con las opciones de la terminal.

| Interruptor | Qué enciende | Tiempo aprox. | Si queda en `FALSE` |
|---|---|---|---|
| `DESCARGAS` (`--descargas`) | OpenStreetMap (`01b`) y catastro de Bogotá (`03f`, `03h`) | 10–30 min | se usa la caché de `data/` |
| `PYTHON` (`--python`) | texto con ConTexto (`03c`), TF-IDF (`03d`) y embeddings (`03g`) | 20–30 min, más la primera instalación | se usan los archivos guardados |
| `REDES` (`--redes`) | redes neuronales con Keras (`08c`–`08q`) y XGB STAR con comparables (`08p`) | varias horas | se usan las predicciones registradas |
| `LENTOS` (`--lentos`) | buffer (`03b`), random forests (`05`, `05c`), `nnet` (`09`), XGB ponderado (`10`), XGB STAR (`08`, `08b`) | 4–5 h | se usan las predicciones registradas |
| `PRUEBA` (`--prueba`) | grillas mínimas en las redes y en los XGB STAR | minutos | — |

**Regla de seguridad.** Un paso apagado **corre de todos modos** si falta alguno de los archivos que produce y que otros pasos necesitan. Por ejemplo, en un clon nuevo faltan `tfidf.parquet` y `base_texto.rds`, que no se suben a git por su tamaño. En ese caso el main corre `03d` y `03e` aunque `PYTHON = FALSE`, y crea el entorno de Python si no existe.

### 4. Qué queda al final

- `output/figures/` y `output/tables/`, con subcarpetas `01_descriptivas/` y `02_modelos/`: todas las figuras y tablas de los informes.
- `models/registro_modelos.csv` (métricas de cada modelo), `models/oof_predicciones.csv` y `models/test_predicciones.csv`.
- `submissions/<modelo>.csv`: archivos listos para Kaggle.
- `output/session_info.txt`: versión de R, sistema operativo y versión de cada paquete (`sessioninfo::session_info()`).
- `output/python_<entorno>.txt`: versión de Python y paquetes exactos (`pip freeze`) de cada entorno usado.
- `output/logs/<script>.log` y `output/logs/resumen_corrida.csv`: la salida completa de cada script, qué corrió, qué se saltó y por qué, y cuánto tardó cada paso. No se versionan.

Cada script corre en un **proceso nuevo** (de R o de Python), con la raíz del proyecto como directorio de trabajo. Ningún objeto pasa de un script a otro: solo pasan los archivos que cada uno guarda. Si un script falla, el main se detiene, dice cuál fue y señala su log.

---

## R y Python

Casi todo el proyecto está en R. Hay tres scripts de Python, para el texto de los anuncios. Las redes neuronales están escritas en R, pero usan TensorFlow por debajo.

| Script | Lenguaje | Entorno | Para qué |
|---|---|---|---|
| `03c_texto.py` | Python | `texto` ([`requirements.txt`](requirements.txt)) | limpieza, lematización (spaCy), n-gramas y nubes con [ConTexto](https://github.com/ucd-dnp/ConTexto) |
| `03d_tfidf.py` | Python | `texto` | TF-IDF, que R lee con `arrow` desde `data/processed/tfidf.parquet` |
| `03g_embeddings.py` | Python | `emb` ([`requirements-emb.txt`](requirements-emb.txt)) | embeddings de oraciones (sentence-transformers, PyTorch) |
| `08c`–`08q`, `utils_redes.R` | **R** (`keras3`) | `tf` ([`requirements-tf.txt`](requirements-tf.txt)) | redes neuronales; R se conecta con TensorFlow a través de `reticulate` |
| todo lo demás | R | — | datos, variables, modelos, ensambles, figuras |

**Por qué hay tres entornos.** Sus dependencias son incompatibles. ConTexto (2021) necesita versiones viejas de algunas librerías, mientras que TensorFlow y PyTorch piden versiones recientes de numpy.

**Cómo se crean.** Los crea `01_setup.R` (función `asegura_venv()`) la primera vez que el main necesita cada uno:

1. Si [uv](https://docs.astral.sh/uv/) está instalado: `uv venv --python 3.11`, que descarga Python 3.11 si hace falta, y después `uv pip install -r <requirements>`.
2. Si no está: `reticulate` busca un Python 3.11 en el equipo o lo instala (`reticulate::install_python()`), y después crea el entorno e instala con pip.
3. En el entorno `texto`, además: `contexto==0.2.0` con `--no-deps`, porque sus dependencias fijadas de 2021 no compilan con Python 3.11, y el modelo `es_core_news_md` de spaCy.

**Dónde quedan.** En `~/.virtualenvs/ps3-texto`, `ps3-emb` y `ps3-tf`, **fuera de la carpeta del proyecto**. OneDrive e iCloud sincronizan miles de archivos pequeños y a veces los sacan del disco, y entonces Python se cuelga al importar. El ejecutable cambia según el sistema operativo (`Scripts/python.exe` en Windows y `bin/python` en macOS); `python_de()` lo resuelve. Si ya existen las ubicaciones anteriores del equipo (`.venv`, `.venv-tf`, `~/.venvs/ps3-tf`), se usan esas. También se puede elegir la carpeta con las variables de entorno `PS3_VENV_TEXTO`, `PS3_VENV_EMB`, `VENV_TF` o `PS3_VENVS`.

**Si la creación automática falla**, se pueden crear a mano con uv, desde la raíz del proyecto. En macOS el python está en `bin/python`:

```bash
uv venv ~/.virtualenvs/ps3-texto --python 3.11 --seed
uv pip install --python ~/.virtualenvs/ps3-texto/Scripts/python.exe -r requirements.txt
uv pip install --python ~/.virtualenvs/ps3-texto/Scripts/python.exe --no-deps contexto==0.2.0
~/.virtualenvs/ps3-texto/Scripts/python.exe -m spacy download es_core_news_md

uv venv ~/.virtualenvs/ps3-tf --python 3.11
uv pip install --python ~/.virtualenvs/ps3-tf/Scripts/python.exe -r requirements-tf.txt

uv venv ~/.virtualenvs/ps3-emb --python 3.11
uv pip install --python ~/.virtualenvs/ps3-emb/Scripts/python.exe -r requirements-emb.txt
```

Para correr un .py suelto, fuera del main: `<python del entorno> code/03d_tfidf.py`, desde cualquier carpeta. Las rutas de los .py se arman desde la ubicación del propio archivo.

---

## Estructura

```
Problem-Set-3-Making-Money-with-ML/
├── README.md                ← este archivo
├── Problem-Set-3-Making-Money-with-ML.Rproj
├── requirements*.txt        ← entornos de Python: texto, tf, emb
├── BITACORA.md              ← diario del proyecto: estado actual, resultados y pendientes
├── code/
│   ├── 00_main.R            ← script maestro: corre todo, en orden
│   ├── 01_setup.R           ← paquetes, rutas, paleta, funciones comunes y entornos de Python
│   ├── 01b_ … 03h_          ← datos externos, descriptivas, texto y variables
│   ├── 04_ … 10_            ← un script por familia de modelos
│   ├── 90_ … 94_            ← comparación, validación ponderada y ensambles
│   ├── utils_*.R            ← validación cruzada, registro de modelos, redes, comparables
│   └── exploratorio/        ← verificaciones que no forman parte de la corrida
├── data/
│   ├── raw/                 ← datos de Kaggle (no se modifican)
│   ├── external/            ← OpenStreetMap (en caché) y catastro (se descarga)
│   ├── processed/           ← bases construidas por los scripts
│   └── README.md            ← diccionario de variables
├── models/                  ← registro de métricas y predicciones OOF y de test
├── submissions/             ← un .csv por modelo, listo para Kaggle
├── output/
│   ├── figures/             ← 01_descriptivas/, 02_modelos/
│   ├── tables/              ← 01_descriptivas/, 02_modelos/
│   ├── logs/                ← salida de cada corrida (no se versiona)
│   └── session_info.txt     ← entorno de R de la última corrida
├── reports/                 ← informes en Markdown (enlazan a output/)
└── docs/                    ← decisiones metodológicas, guía de variables, enunciado
```

### Scripts por etapa

La numeración sigue el orden lógico del proyecto: `0x` son datos y descriptivas, `03x` variables, `04`–`10` un modelo por script y `9x` ensambles. El orden exacto de ejecución, con sus dependencias, está en la tabla `pasos` de `00_main.R`.

| Etapa | Scripts | Qué hacen |
|---|---|---|
| Configuración | `01_setup.R` | paquetes, rutas con `here`, tema gráfico, haversine, extracción de números del texto, entornos de Python |
| Datos externos | `01b_osm_descarga.R` | localidades, UPZ, barrios, servicios, vías, parques y edificios de OpenStreetMap (Overpass, con caché) |
| Descriptivas | `02_descriptivas.R`, `02b_extremos.R`, `02c_composicion_test.R` | informe 1: mapas, gradientes, extremos, composición de train y test |
| Variables | `03_features.R`, `03b_buffer.R`, `03c`/`03d`/`03g` (Python), `03e_pca.R`, `03f_catastro.R`, `03h_construcciones.R` | imputaciones, folds de validación, buffer, texto, PCA, catastro |
| Modelos | `04`–`07`, `09`, `10` | OLS, elastic net, CART, random forest, XGBoost, híbridos, `nnet`, XGBoost ponderado |
| STAR y redes | `08`–`08q` | XGB STAR, elastic net con encoders, NN STAR y red general (Keras) |
| Ensambles | `90_comparacion.R`, `91_validacion_sintetica.R`, `94_star_nn_xgb.R` | comparación, validación ponderada hacia el test (TWCV), combinaciones STAR |

### Convenciones del código

- Las rutas siempre salen del objeto `P` de `01_setup.R` (`P$raw`, `P$processed`, `P$fig_mod`, …), construido con `here::here()`. No hay `setwd()` en los scripts ni rutas relativas sueltas.
- Los paquetes se cargan **solo** en `01_setup.R`. Si un script necesita uno nuevo, se agrega ahí.
- Cada modelo se registra con `registra()` (`code/utils_modelos.R`), que actualiza el registro, las predicciones y el envío.
- La validación cruzada siempre pasa por `cv_oof()`: una localidad afuera con buffer de 500 m (D9). La semilla es 123.

---

## Problemas conocidos

- **Control de aplicaciones de Windows.** En algunos equipos bloquea paquetes compilados como `sf`. Si `sf` no carga, el main salta `03f` y `03h` con un aviso y usa `catastro.csv` y `construcciones.csv`, que están en git.
- **Tiempos.** La corrida por defecto reutiliza los modelos caros. Con `--todo`, la reproducción completa tarda varias horas; las redes y el XGB STAR son la mayor parte.
- **Modelos de versiones anteriores del código.** Algunos modelos del registro (por ejemplo, `m04_xgboost` y `m17_nn_star`) se entrenaron con la base anterior a D14 y D15. Si se vuelven a correr, sus scripts usan la base actual, y las métricas pueden cambiar respecto de las del informe. El detalle está en la bitácora.
