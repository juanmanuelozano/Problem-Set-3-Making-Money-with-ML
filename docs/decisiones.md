# Registro de decisiones metodológicas

Cada decisión registra el contexto, qué se decidió y por qué. Las más recientes van al final.

---

### D1 · Validación con folds espaciales, no aleatorios (2026-11-14) — reemplazada por D9
**Contexto:** el 94% del test está en Chapinero; el train tiene solo 307 observaciones ahí.
**Decisión:** 5 folds por k-means sobre las coordenadas del train. Además del MAE OOF total se reportan el MAE en Chapinero (307 obs) y el MAE en el fold 2 (Usaquén y la mayor parte de Chapinero, el bloque más parecido al test).
**Por qué:** una validación aleatoria premia memorizar barrios vecinos y sobreestima el desempeño fuera de la zona de entrenamiento.

### D2 · Variable objetivo en logaritmo y recorte al soporte (2026-11-14)
**Decisión:** modelar `log(price)`, predecir `exp(ŷ)` y recortar al intervalo [300, 1.650] millones.
**Por qué:** el precio es asimétrico y está truncado. Con una pérdida MAE, `exp` de la media condicional del log se acerca a la mediana condicional.

### D3 · Jerarquía para el área (2026-11-14)
**Decisión:** observada → texto (solo si está entre 0,5 y 2 veces la predicción del modelo de imputación) → imputada con random forest (R² OOB 0,83), más indicadores de la fuente.
**Por qué:** la extracción del texto es ruidosa (captura áreas de terrazas o lotes). La regla de coherencia descarta los casos absurdos.

### D4 · Estrato imputado espacialmente (2026-11-14)
**Decisión:** usar el estrato mencionado en el texto y, si falta, una predicción con coordenadas y entorno (R² OOB 0,79).
**Por qué:** el estrato es central en la literatura de precios en Colombia y es esencialmente espacial. Pendiente: reemplazarlo con el estrato por manzana de los datos abiertos de Bogotá.

### D5 · Se descarta `rooms` (2026-11-14)
**Por qué:** su correlación con `bedrooms` es 0,99 y le falta el 47% de los datos.

### D6 · Combinar tendencia lineal y árboles (2026-11-14)
**Contexto:** con validación espacial, el RF (203 M) y XGBoost (180 M) son peores que el lasso (159 M) en Chapinero. Los árboles no predicen por encima de los valores de las zonas que vieron.
**Decisión:** priorizar los modelos que extrapolan: XGBoost sobre log(precio/m²) e híbrido lasso (`base_margin`) + XGBoost en residuos, con validación anidada.
**Por qué:** el híbrido da el mejor MAE en Chapinero (155 M) sin perder en el total.

### D7 · Métrica de selección: Chapinero sobre total (2026-11-14)
**Decisión:** para elegir el envío pesa más el MAE en las 307 observaciones de Chapinero que el MAE total, teniendo en cuenta su ruido (error estándar de ±8–10 M).
**Por qué:** el test es Chapinero. El MAE total está dominado por Usaquén (55% del train).

### D8 · No eliminar observaciones por precio extremo (2026-11-16)
**Contexto:** el precio está acotado en [300, 1.650] M. Los valores extremos del precio por m² vienen casi siempre del área extraída del texto, que perdió los puntos decimales ("96.0 m2" aparece como "960 m2").
**Decisión:** no se eliminan observaciones del train por su precio ni por su precio por m². El ruido del área se controla con la regla de coherencia de D3.
**Por qué:** eliminar por precio por m² quitaría anuncios con precios válidos y áreas mal medidas, y en el test no se pueden eliminar filas. Con el área final, solo entre el 0,2% y el 1,6% de las observaciones (según tipo y fuente del área) tienen |z| > 3 en log(precio/m²). Ver la sección 7 de `reports/01_descriptivas/informe_descriptivas.md`.

### D9 · Validación dejando una localidad afuera, con buffer de 500 m (2026-11-18)
**Contexto:** reemplaza los 5 bloques k-means de D1. Se buscaba replicar `spatialsample::spatial_leave_location_out_cv()` combinada con el `buffer` de `spatial_block_cv()`. `spatialsample` no está instalado y `sf` está bloqueado en Windows, así que se implementó en `scripts/utils_modelos.R` (`folds_localidad()` y `cv_oof()`), con una haversine propia.
**Decisión:**
- Cada localidad del train es un fold de evaluación (18 folds). El único anuncio sin localidad toma la de su vecino más cercano.
- Del conjunto de análisis se excluyen los anuncios a menos de 500 m de algún anuncio evaluado.
- Todos los modelos validan con `cv_oof()`. Los hiperparámetros (lambda, rondas de boosting) se eligen por MAE OOF mínimo, porque `cv.glmnet(foldid=)` y `xgb.cv()` no admiten buffer.
- Todas las semillas pasan a 123.

**Por qué 500 m** (`scripts/03b_buffer.R`, figura `m0_buffer_diagnostico.png`):
1. *Autocorrelación de los residuos* de un OLS hedónico:
   - 0,10 a menos de 100 m, 0,05 entre 100 y 200 m, 0,024 entre 300 y 400 m.
   - Menos de 0,01 desde 500 m y prácticamente 0 desde unos 800 m.
   - 500 m es el rango práctico: por encima de esa distancia, los vecinos ya no comparten error.
2. *Distancia al vecino de entrenamiento más cercano* (criterio tipo NNDM):
   - En el test frente al train, la mediana es de 96 m (el 18% está a 0 m).
   - Dejando una localidad afuera, ya sin buffer, la mediana es de 1.046 m (555 m en Chapinero).
   - La validación por localidad ya es más exigente que el test, y el buffer la aleja más (KS de 0,82 a 0,99). Si el único objetivo fuera estimar el MAE de Kaggle, convendría buffer 0. El buffer se justifica como protección contra la fuga entre anuncios casi vecinos a ambos lados de un límite de localidad.
3. *Sensibilidad del MAE:*
   - El random forest es estable hasta 1.000 m (191–196 M en Chapinero).
   - Por encima de 1.000 m se pierde entre el 4% y el 11% del entrenamiento, y el MAE sube.

**Consecuencias:**
- Los MAE no son comparables con los de la validación k-means, que quedaron archivados en `models/registro_modelos_kmeans.csv`.
- La métrica "fold 2" se reemplaza por el MAE promedio entre localidades (`mae_macro`).
- Las dummies de localidad no se pueden estimar para la localidad evaluada, así que esta validación las penaliza (OLS en Chapinero: 156 M sin dummies frente a 220 M con ellas). Se quitaron (D10).

### D10 · Ningún modelo lleva dummies de localidad (2026-11-18)
**Contexto:** con la validación de D9, la dummy de la localidad evaluada no se puede estimar porque es cero en todo el entrenamiento, así que el modelo trata esa localidad como la categoría base. En Chapinero, el OLS empeora de 156 M (sin dummies) a 220 M (con dummies).
**Decisión:** a partir de ahora ningún modelo usa efectos fijos de localidad. Se quitaron de `matriz_lineal()`; los árboles nunca los tuvieron. La ubicación entra con coordenadas, distancias, densidades de OSM y el estrato. La localidad solo define los folds de validación.
**Por qué:** la validación no puede medir lo que aportan las dummies a la localidad evaluada, y con ellas la selección de modelos queda sesgada. Además, el test es casi todo Chapinero, y una dummy estimada con solo 307 observaciones es poco confiable.
