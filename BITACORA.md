# Bitácora del proyecto

Diario de trabajo. **Se actualiza al final de cada sesión**: la entrada más reciente va arriba y la sección *Estado actual* siempre refleja el último punto.

---

## Estado actual (2026-11-16)

**Mejores modelos (MAE OOF, folds espaciales, millones de COP):**

| Modelo | Total | Chapinero (n=307) | Fold 2 |
|---|---:|---:|---:|
| m06_hibrido_en_xgb | 134,0 | **155,2** | 148,0 |
| m05_xgb_precio_m2 | 133,8 | 180,8 | 143,3 |
| m90_ensamble | **131,1** | 163,9 | **141,6** |
| m02_elastic_net | 134,9 | 159,0 | 147,3 |

**Envíos a Kaggle:** ninguno todavía. Recomendado: `m06_hibrido_en_xgb.csv`, y luego `m90_ensamble.csv` para comparar.

**Pendientes / próximos pasos:**
- [ ] Subir m06 y m90 a Kaggle y anotar el score público aquí (confirmar que la métrica es MAE)
- [ ] Corregir la subpredicción en Chapinero (sesgo de −135 M): pesos por cambio de covariables o calibración del nivel
- [ ] Rezago espacial del precio por m² (kNN dentro de cada fold)
- [ ] Decidir si se permite explotar los 200 duplicados exactos train-test (reglas del curso)
- [ ] TF-IDF del texto con lasso
- [ ] Recuperar los decimales perdidos en el área del texto: los valores mayores de 1.000 (2.391) son áreas multiplicadas por 10 o 100. Dividir y aceptar si pasa la regla de coherencia
- [ ] Arreglar las regex de parqueaderos y baños (falta `\b` antes del número: "10 parqueaderos" se lee como 0)
- [ ] `bedrooms` = 0 (186) y 11 (97): ¿tratarlos como faltantes o como tope?
- [ ] Estrato por manzana y avalúo catastral (Datos Abiertos Bogotá)

---

## 2026-11-16 · Sesión 3: valores extremos y rangos de validez

- Nuevo script `scripts/02b_extremos.R` y nueva sección 7 del informe de descriptivas, con la figura f10 y 3 tablas. Las secciones 7–10 del informe pasan a ser 8–11.
- **Rangos de validez:** en casi todas las variables cortan pocos errores evidentes. La excepción es el área del texto (2.391 valores por encima de 1.000).
- **Hallazgo:** el texto perdió los puntos decimales ("4.0 habitaciones 96.0 m2" aparece como "40 habitaciones 960 m2"). En 121 de 396 títulos con ese formato, N = 10 × `bedrooms`. La regla de coherencia de D3 ya descarta en la modelación la mayoría de las áreas infladas: el p99 del precio por m² con área del texto baja de 37,7 a 10,6 M/m².
- **Precio:** no tiene outliers propios. 509 en 300 M y 106 en 1.650 M. El valor de 300 M es menos frecuente que otras cifras redondas, lo que apunta a *heaping* y no a censura. En Chapinero, el 3,3% está en 1.600 M o más (0,9% en el resto). Hay *bunching* justo por debajo de 1.000 M.
- Entorno: el proyecto ahora corre en macOS (`Rscript` en el PATH). Ojo: `Rscript` sin `< /dev/null` puede quedarse esperando la entrada estándar.
- Decisión D8 en `docs/decisiones.md`.
- Nueva guía de variables: `docs/guia_variables.md`, con nombre, definición, fuente, script y uso en los modelos. Reemplaza el diccionario parcial de `data/README.md`. Al revisarla se encontró que `sup_total_ok` (en el 03) se calcula pero no se usa.
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
