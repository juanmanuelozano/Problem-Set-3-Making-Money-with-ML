# Bitácora del proyecto

Diario de trabajo. **Se actualiza al final de cada sesión**: la entrada más reciente va arriba y la sección *Estado actual* siempre refleja el último punto.

---

## Estado actual (2026-11-18)

**Validación:** se deja afuera una localidad a la vez, con buffer de 500 m (D9). No es comparable con la ronda k-means. **Ningún modelo lleva dummies de localidad** (D10).

**Mejores modelos (MAE OOF, millones de COP):**

| Modelo | Total | Chapinero (n=307) | Promedio por localidad |
|---|---:|---:|---:|
| m06_hibrido_en_xgb | 133,6 | **148,5** | 150,5 |
| m02_elastic_net | **132,2** | 154,7 | 149,8 |
| m02b_elastic_net_m2 | 135,0 | 153,8 | 162,1 |
| reg_ols_sin_loc | 132,6 | 155,5 | 150,2 |
| m05_xgb_precio_m2 | 132,3 | 156,1 | **146,8** |
| m90_ensamble | *129,3* | *154,7* | *146,5* |

**Envíos a Kaggle:** `reg_ols_sin_loc.csv` está listo (¿ya se subió? anotar el score). Recomendado: `m06_hibrido_en_xgb.csv` y luego `m90_ensamble.csv` para comparar.

**Pendientes / próximos pasos:**
- [ ] Subir m06 (y reg_ols_sin_loc / m90) a Kaggle y anotar el score público aquí. Comparar con los 148,5 M de m06 en Chapinero para ver si la validación está calibrada
- [ ] Híbrido: el número de rondas quedó en el mínimo de la grilla (10). Probar de 1 a 10 rondas
- [ ] Corregir la subpredicción en Chapinero (sesgo de −82 M en m02): pesos por cambio de covariables o calibración del nivel
- [ ] Rezago espacial del precio por m² (kNN dentro de cada fold)
- [ ] Decidir si se permite explotar los 200 duplicados exactos train-test (reglas del curso)
- [ ] TF-IDF del texto con lasso. Arreglar las regex de amenidades (negaciones como "sin ascensor" y "apartaestudio" → `tx_estudio`)
- [ ] Recuperar los decimales perdidos en el área del texto: los valores mayores de 1.000 (2.391) son áreas multiplicadas por 10 o 100. Dividir y aceptar si pasa la regla de coherencia
- [ ] Arreglar las regex de parqueaderos y baños (falta `\b` antes del número: "10 parqueaderos" se lee como 0)
- [ ] `bedrooms` = 0 (186) y 11 (97): ¿tratarlos como faltantes o como tope?
- [ ] Estrato por manzana y avalúo catastral (Datos Abiertos Bogotá)

---

## 2026-11-19 · Sesión 6: librerías con pacman

- Todas las librerías se cargan ahora con `pacman::p_load()` al inicio de cada script, justo después de los `source()` (ya no hay `library()`). `00_config.R` instala pacman si falta. Se mantuvo el orden de carga, así que los conflictos de nombres se resuelven igual. La convención quedó en `CLAUDE.md`.
- La columna de texto original (`title`, `description`) está en `data/raw/*.csv` y en `base_enriquecida.csv`, pero no en `base_modelo.rds`. Para TF-IDF hay que unirla por `property_id`.
- Verificación: todos los scripts se leen sin errores de sintaxis y `check_validacion.R` pasa. No cambió ningún modelo.

---

## 2026-11-18 · Sesión 5: grilla del elastic net

- `04b_elastic_net.R` reescrito: pérdida cuadrática (glmnet), mismas variables que `reg_ols_sin_loc`, para el precio (m02) y el precio por m² sin variables de área (m02b). Se descartó la pérdida MAE: glmnet no la admite.
- Grilla con respaldo en la literatura: α ∈ {0; 0,1; 0,25; 0,5; 0,75; 0,9; 1} (Zou y Hastie, 2005), `nlambda` ∈ {50, 100, 200} y `lambda.min.ratio` ∈ {10⁻³, 10⁻⁴, 10⁻⁵} (Friedman, Hastie y Tibshirani, 2010). 126 configuraciones en 3 minutos. Tabla: `tables/elastic_net_grilla.csv`.
- Resultado: solo el ridge (α = 0) es peor; los parámetros del camino de λ no mueven el MAE (< 0,5 M). Gana el lasso en ambos objetivos. En el precio, λ queda en el borde inferior: m02 ≈ OLS (132,2 / 154,7). En el precio por m², la penalización ayuda: m02b mejora 6,7 M a m09 en Chapinero (153,8), pero pierde 3 M en el total.
- `interacciones()` pasó a `utils_modelos.R`. Se volvió a correr el 90: nuevos pesos m04 0,35 · m02 0,30 · m02b 0,20 · m05 0,15. m06 sigue siendo el mejor en Chapinero (−6,3 M frente a m02, *t* = −4,3).
- El 90 ahora reporta el MAE por fold al estilo de `collect_metrics()`: `tables/mae_por_fold.csv` y `tables/resumen_cv.csv`, con el promedio ponderado por los anuncios del train (= `mae_total`), el promedio simple (= `mae_macro`) y el error estándar entre folds (≈ 10 M en todos los modelos).
- Nuevo `05b_cart.R`: CART con ranger (1 árbol), grilla `max.depth` × `min.bucket` (incluye 500), pérdidas MSE (media) y MAE (mediana en la hoja), para el precio y el precio por m². Mejor: m11_cart_m2_mse (150,0 total; 182,7 Chapinero). Todos son peores que los lineales y no entran al ensamble.
- Coeficientes estandarizados (β × sd(x), sin dejar código): lo que más pesa es el área con sus interacciones con estrato y tipo de inmueble, luego la distancia al Centro Internacional y al CBD.

---

## 2026-11-18 · Sesión 4: validación por localidad con buffer, regresiones y primer envío

**Validación (D9)**
- Se reemplazaron los 5 bloques k-means por una validación que deja afuera una localidad a la vez (18 folds), con buffer. Funciones comunes en `utils_modelos.R`: `folds_localidad()`, `cv_oof()`, `xgb_rondas()`, `mejor_columna()` y `ols_coef()`. `check_validacion.R` las verifica.
- Elección del buffer (`03b_buffer.R`): los residuos dejan de estar correlacionados hacia los 500 m. La validación por localidad ya es más exigente que el test (vecino más cercano: 1.046 m de mediana frente a 96 m en el test). Se eligieron 500 m.
- Las semillas pasan a 123. El registro anterior quedó archivado en `models/registro_modelos_kmeans.csv`, y la métrica "fold 2" se reemplazó por el MAE promedio entre localidades.

**Modelos**
- Nuevo `04_regresiones.R`: la mediana (m00), especificaciones OLS acumulativas (tabla), m01, `reg_ols_sin_loc` (+ habitaciones × distancia a cada CBD), m08 (LAD por IRLS) y m09/m10 (precio por m² × m²). El elastic net pasó a `04b_elastic_net.R`.
- **D10:** se quitaron las dummies de localidad de todos los modelos (en Chapinero, el OLS mejora de 225 a 155 M).
- El ensamble del 90 pasó de la grilla 21^k a la selección codiciosa (Caruana).
- El mejor en Chapinero es m06 (148,5 M), con ventaja significativa en la comparación pareada sobre m02 y `reg_ols_sin_loc`. El precio por m² no mejora.
- Envío generado: `submissions/reg_ols_sin_loc.csv`. Se agregó una verificación del formato de Kaggle en `registra()`.

**Otros**
- Auditoría de complejidad: `PATRONES` y `num_txt()` en `00_config.R`, sin la `hav()` duplicada, sin `sup_total_ok`, y `matriz_arboles` simplificada. Se verificó que `base_modelo.rds` queda idéntica.
- Nueva guía de variables (`docs/guia_variables.md`). El informe de modelos se reescribió para esta ronda.

---

## 2026-11-16 · Sesión 3: valores extremos y rangos de validez

- Nuevo script `scripts/02b_extremos.R` y nueva sección 7 del informe de descriptivas, con la figura f10 y 3 tablas. Las secciones 7–10 del informe pasan a ser 8–11.
- **Rangos de validez:** en casi todas las variables cortan pocos errores evidentes. La excepción es el área del texto (2.391 valores por encima de 1.000).
- **Hallazgo:** el texto perdió los puntos decimales ("4.0 habitaciones 96.0 m2" aparece como "40 habitaciones 960 m2"). En 121 de 396 títulos con ese formato, N = 10 × `bedrooms`. La regla de coherencia de D3 ya descarta en la modelación la mayoría de las áreas infladas: el p99 del precio por m² con área del texto baja de 37,7 a 10,8 M/m².
- **Precio:** no tiene outliers propios. 509 en 300 M y 106 en 1.650 M. El valor de 300 M es menos frecuente que otras cifras redondas, lo que apunta a *heaping* y no a censura. En Chapinero, el 3,3% está en 1.600 M o más (0,9% en el resto). Hay *bunching* justo por debajo de 1.000 M.
- Entorno: el proyecto ahora corre en macOS (`Rscript` en el PATH). Ojo: `Rscript` sin `< /dev/null` puede quedarse esperando la entrada estándar.
- Decisión D8 en `docs/decisiones.md`.
- Nueva guía de variables: `docs/guia_variables.md`, con nombre, definición, fuente, script y uso en los modelos. Reemplaza el diccionario parcial de `data/README.md`. Al revisarla se encontró que `sup_total_ok` (en el 03) se calculaba pero no se usaba; se eliminó.
- Validación cruzada: no hay una función común. Cada script hace su ciclo sobre el mismo `FOLD` y evalúa con `evalua()`.

---

## 2026-11-16 · Sesión 2: repositorio conectado a GitHub

- El proyecto tenía un `git init` local (rama `master`, sin remoto) y, dentro, un clon vacío de GitHub en la subcarpeta `Problem-Set-3-Making-Money-with-ML/`. Por eso no se podía hacer push.
- Arreglo: se reemplazó el `.git` externo (no tenía commits) por el del clon, se movió `.gitattributes` a la raíz y se eliminó la subcarpeta.
- Se hizo el commit de todo el proyecto en `main` y el push a `origin`.
- Los `.rds` y `.ubj` de `models/` siguen ignorados. El archivo más grande versionado es `data/processed/base_enriquecida.csv` (48 MB, por debajo del límite de 100 MB de GitHub).

---

## 2026-11-14 · Sesión 1 — Exploración, estructura del repo y primera ronda de modelos

**Exploración y descriptivas**
- Se exploraron los datos: 38.644 train y 10.286 test, todos de Bogotá y en venta. El precio está truncado en [300, 1.650] M. Al área le falta el 69% de los datos.
- **Hallazgo clave:** el test está en Chapinero (9.690/10.286) y el train solo tiene 307 observaciones ahí. Se confirmó con polígonos de OSM y con el texto ("Rosales": 15% del test frente a 0,2% del train).
- Se descargaron de OSM (Overpass) 19 localidades, 111 UPZ y 11 capas de servicios. Se calcularon distancias y densidades a 500 m.
- Se extrajeron del texto el área, los baños, el estrato, el piso, la antigüedad, los parqueaderos y 22 amenidades.
- Regresión hedónica de motivación: el R² pasa de 0,44 (estructural) a 0,53 (+ ubicación), 0,57 (+ texto) y 0,59 (+ EF de localidad).
- Informe: `reports/01_descriptivas/informe_descriptivas.md` (9 figuras, 5 tablas).

**Estructura del repo**
- Se creó la estructura `data/ scripts/ models/ submissions/ reports/ docs/`, junto con `README.md`, `BITACORA.md`, `CLAUDE.md` y `docs/decisiones.md` (D1–D5).

**Modelación (ronda 1)**
- Variables: imputación del área con RF (R² OOB 0,83) y regla de coherencia para el área del texto; estrato imputado espacialmente (R² OOB 0,79).
- Validación con 5 folds espaciales por k-means. Métricas: MAE total, MAE en Chapinero y MAE en el fold 2.
- Modelos: mediana, OLS, elastic net, random forest, XGBoost, XGBoost sobre precio/m², híbrido lasso + XGBoost (anidado) y ensamble.
- **Aprendizaje:** los árboles puros no extrapolan hacia Chapinero (RF 203 M, XGB 180 M frente a 159 M del lasso). Los modelos que combinan la tendencia lineal con árboles funcionan mejor.
- Todos los modelos subpredicen Chapinero, sobre todo por encima de 1.000 M.
- Informe: `reports/02_modelos/informe_modelos.md`.

**Problemas del entorno resueltos**
- Windows (Control de aplicaciones) bloquea `sf`, `units`, `geosphere` y `tidymodels`. Se usan alternativas.
- `Rscript -e` falla con código largo, así que todo se corre desde archivos. La lectura de CSV se hace con `num_threads = 1`.

**Otros hallazgos para después**
- 200 anuncios del test tienen una descripción idéntica en el train (117 con la misma ubicación). 1.807 comparten coordenadas exactas con el train.
- En el train hay 8.078 descripciones duplicadas; en el 80% de esos grupos el precio es idéntico.
