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

### D11 · Texto procesado en Python con ConTexto, sin nombres de lugares (2026-11-19)
**Contexto:** el texto de los anuncios solo entraba a través de regex y de 22 dummies `tx_*`. Se quiere una representación TF-IDF. El texto crudo viene en minúsculas y sin tildes, y en cerca de 1/4 de los anuncios las tildes y la ñ se *perdieron* (`baos`, `usaqun`).
**Decisión:**
- El texto se procesa en Python con ConTexto (DNP): `03c_texto.py` y `03d_tfidf.py`. Es la única parte del proyecto que no está en R.
- Las tildes y ñ perdidas se reparan insertando una vocal o una `n` cuando la palabra no existe y la versión reparada es frecuente en el corpus.
- **Se eliminan los nombres de lugares**: localidades, UPZ y barrios de OSM, más una lista manual. Funcionarían como efectos fijos de ubicación, en contra del espíritu de D10.
- La corrección ortográfica es conservadora: solo palabras raras, desconocidas y a distancia 1 de una palabra frecuente.
- Se lematiza con spaCy (`es_core_news_md`) y un diccionario de lemas del dominio (`data/external/dict_lemas.json`).
- Se conservan las stopwords `sin` y `no`, para capturar negaciones en bigramas.
- El TF-IDF (unigramas y bigramas) se ajusta con train + test: no usa el precio, así que no hay fuga (mismo criterio que la imputación del área en 03).
**Por qué:** ConTexto lo pidió el equipo. Las reglas conservadoras evitan que el corrector dañe palabras del gremio o "corrija" la falta de tildes. Quitar los lugares mantiene la ubicación en las variables espaciales, que la validación por localidad sí sabe medir.

### D12 · PCA por separado: variables que no son de texto y TF-IDF (2026-11-19)
**Decisión:**
- `03e_pca.R` hace dos PCA, ajustados con train + test (no usan el precio).
- El primero toma 37 variables finales de `base_modelo` que no vienen del texto, estandarizadas. Quedan fuera `lat_rot1/2`, que son combinaciones lineales de lat/lon.
- El segundo es un PCA truncado del TF-IDF (50 componentes con `irlba`), centrado pero **sin escalar**: el TF-IDF ya pondera los términos, y escalar inflaría los términos raros.
**Pendiente:** las dos primeras componentes del texto capturan plantillas de inmobiliarias (`rentahouse`, `contactame`, en 6% y 2% de los anuncios), no características del inmueble.

### D13 · Modelo STAR con XGBoost y encoders (Mayer et al., 2022) (2026-11-20)
**Decisión:** `08_xgb_star.R` ajusta un XGBoost con `interaction_constraints` en forma de partición:
- cada variable estructural y temporal va sola, así que su efecto es aditivo;
- un grupo de ubicación (lat/lon, rotadas, `dist_*`, `n500_*` y `estrato_final`, porque el estrato es casi todo espacial);
- un grupo de texto (los 1.000 términos TF-IDF más frecuentes: un filtro no supervisado que conserva las palabras de lujo).

Los encoders de cada grupo se extraen con el Algoritmo 1 del paper (verificado contra `predcontrib`). `08b_en_star.R` los usa en un elastic net, el paso 2 del paper.

Los encoders del paso 2 se ajustan dentro de cada fold externo, sin CV interna. La validación no se infla, porque las filas evaluadas nunca entran al encoder. Respeta D10: la ubicación entra por el grupo o por su encoder, nunca con dummies de localidad.

**Ajustes por tiempo:**
- 1.000 términos en vez de 5.000;
- `max_bin` = 64;
- búsqueda aleatoria de 12 configuraciones con profundidad ≤ 6 y eta = 0,1;
- la búsqueda se hace con el objetivo m², y el objetivo precio y la pérdida MAE usan la mejor configuración.

**Actualización (2026-11-21):** la grilla quedó en el borde en los seis parámetros. Se cambia por tres búsquedas aleatorias de 20 configuraciones en un espacio ampliado:
- **Búsquedas:** m² con pérdida cuadrática, m² con pérdida absoluta (con eta ∈ {0,1; 0,2; 0,3} y hasta 5.000 rondas) y precio con pérdida cuadrática.
- **Espacio:** depth 2–5, mcw {1, 3, 5, 10}, subsample {0,8; 0,9; 1}, colsample {0,7–1}, lambda {0–3} y alpha {0–10}.
- **Punto de partida:** la primera candidata de cada búsqueda es la mejor configuración anterior.
- **Encoders:** salen del mejor modelo m², sea de pérdida cuadrática o absoluta.

### D14 · Redes neuronales con Keras desde R: NN STAR y red general del mismo tamaño (2026-11-21)
**Decisión sobre el entorno:** las redes se escriben en R con `keras3`, como en el paper (que usó keras en R). TensorFlow es solo el backend, instalado en un venv aparte (`.venv-tf`, `requirements-tf.txt`) para no romper las versiones de numpy del entorno de texto (D11). Así se reutilizan `cv_oof`, `evalua` y `registra`.

**NN STAR (`08c_nn_star.R`):**
- **Estructura:** salida = suma de tres ramas que nunca se mezclan, como en el NN STAR del paper (sección 3.2):
  - estructura lineal;
  - ubicación 64-32-16 ReLU con dropout p_u y un atajo lineal;
  - texto (TF-IDF, 1.000 términos) 64-32-16 ReLU con dropout p_t y un atajo lineal.
- **Por qué ReLU y atajos:** el paper usa tanh, que se satura como los árboles. Con ReLU y un atajo lineal, la ubicación puede extrapolar hacia Chapinero.
- **Interpretabilidad:** se conserva igual que en el XGB STAR. Las ICE de estructura son paralelas, y los encoders son las salidas de las ramas.
- **Variables que se quitan:** las interacciones que cruzan grupos (`log_area_x_estrato`, `dist_cbd_x_apto`).

**Red general (`08d_nn_general.R`):** 64-32-16 ReLU con dropout y todas las variables mezcladas. Tiene 71.489 parámetros, frente a 72.757 del NN STAR, así que la comparación aísla el efecto de la estructura aditiva y no el del tamaño.

**Entrenamiento:**
- Adam con lr 1e-3, batch 512, MSE y L2 de 1e-4.
- Estructura y ubicación se estandarizan con las filas de análisis de cada fold; el TF-IDF no se estandariza.
- Las épocas (de 1 a 80) se eligen por bloques con `mejor_columna()`, como las rondas del boosting, porque el early stopping no admite el buffer (D9).
- **Las capas de salida empiezan en cero:** el Dense(1) final de cada rama profunda, los atajos lineales y la capa de estructura. Con la inicialización aleatoria por defecto (Glorot), cada rama arrancaba con ruido grande y las ramas se compensaban entre sí. Por ejemplo, la desviación estándar de la rama de estructura era 0,66 y la de texto 0,68, en sentidos opuestos. El primer intento del NN STAR dio un MAE de 200, frente a unos 130 de la red general.
  - Con ceros, en 3 folds de prueba el NN STAR queda igual o mejor que la red general: Usaquén 125 frente a 130, Suba 126 frente a 131 y Chapinero 153 frente a 153.
  - El óptimo pasa a estar entre 5 y 10 épocas; después, la red sobreajusta.
- El nivel se calibra para que la predicción media del análisis sea igual a la media observada (Remark 6 del paper).

**Afinación:** solo el dropout. NN STAR: p_u ∈ {0; 0,1; 0,2} × p_t ∈ {0; 0,25; 0,5}. Red general: p ∈ {0; 0,1; 0,2; 0,3; 0,5}. En los dos casos se afina con el objetivo m², y con la mejor configuración se ajusta también el objetivo precio.
