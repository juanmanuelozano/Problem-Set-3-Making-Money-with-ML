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

### D14 · Dummies de amenidades con negaciones y 10 amenidades comunales; sin volver a correr los modelos anteriores (2026-11-21)

Las dummies `tx_*` (`02_descriptivas.R`) se construyen ahora con `detectar_caracteristica()`, de la complementaria *Texto como datos*:
- primero se borran las menciones negadas ("sin", "no tiene", "no cuenta con", "no dispone de", "no hay", con artículo opcional);
- después se busca si queda una mención positiva.

Además:
- se busca sobre el texto sin tildes;
- se exigen palabras completas (`\b`), así que "apartaestudio" ya no es `tx_estudio`;
- se agregan 10 amenidades comunales: parqueadero de visitantes, parque infantil, salón comunal o social, zonas verdes, terraza comunal, turco o sauna, squash, planta eléctrica, club house y jacuzzi.

En total pasan de 22 a 32. Los cambios más grandes en las existentes: `tx_estudio` −1.916 anuncios y `tx_ascensor` −601 ("sin ascensor").

**Decisión del equipo:** los modelos ya registrados (hasta m15) **no se vuelven a correr**. Se quedan con la base anterior, de 22 dummies, que está en git en el commit 75db2f2. Los modelos nuevos usan la base nueva.

Por eso las métricas de los modelos viejos y de los nuevos no son del todo comparables. Además de las dummies, cambiaron dos imputaciones:
- **El área imputada:** el random forest de `03_features.R` usa las `tx_*` como predictores. Cambia `log_area` en el 49% de las filas, en promedio un 2,8%.
- **El estrato imputado:** cambia en promedio 0,03 puntos. Esto no viene de las dummies, porque ese modelo no las usa, sino de haber corrido `ranger` en otro equipo (Windows, ranger 0.18.0).

Los folds de validación no cambian.

### D15 · Variables de contexto de OSM: cerros, vías, área verde, altura de edificios y zona de lujo (2026-11-21)

Se agregan a la base (`01_osm_descarga.R` las descarga y `02_descriptivas.R` las calcula). Como en D14, solo las usan los modelos nuevos.

- **`dist_cerros`**: distancia al borde de la Reserva Forestal Bosque Oriental de Bogotá.
  - En OSM es la relación 13780896, con `leisure=nature_reserve` y no `boundary=protected_area`.
  - La Avenida Circunvalar no aparece con ese nombre en OSM, así que no se usó.
  - Es continua de Usaquén a Chapinero, así que un modelo lineal la puede extrapolar.
  - La reserva también bordea el sur, donde estar cerca de los cerros no indica lujo, pero en el train casi no hay anuncios ahí (138).
- **`dist_via_principal`**: distancia a la vía `highway=trunk|primary` más cercana. Su efecto es ambiguo: acceso frente a ruido.
- **`area_verde500`**: hectáreas de parque (polígonos `leisure=park`) con algún punto del borde a menos de 500 m.
  - Complementa a `n500_parque`, que solo cuenta parques: así un parque grande pesa más que uno de bolsillo.
  - El área se calcula con la fórmula del área de un polígono (*shoelace*), en una proyección local en metros.
- **`pisos_prom500` y `n500_edif_pisos`**: pisos promedio (`building:levels`) de los edificios a menos de 500 m y cuántos edificios tienen ese dato.
  - En OSM solo 11.725 edificios tienen el número de pisos, así que la cobertura es irregular.
  - Donde no hay ningún edificio con dato, se imputa la mediana; `n500_edif_pisos = 0` le indica al modelo que no hay información.
- **Zona de lujo y de oficinas** (`dist_*` y `n500_*` de embajadas, oficinas, hoteles y clubes). **Experimental:**
  - se concentran en Chapinero y Usaquén y casi funcionan como una dummy de localidad (D10);
  - hay que vigilar que no se lleven todo el peso del modelo;
  - de todas las nuevas, `dist_embajada` es la más correlacionada con el log del precio en el train (−0,30, frente a −0,29 de `dist_cbd`).

**Cálculo de las distancias:**
- La distancia a una línea o a un borde se aproxima con la distancia al vértice más cercano, después de densificar los segmentos cada 25 m (cerros) o 50 m (vías y parques).
- Las búsquedas solo miran los puntos dentro de una caja alrededor de cada bloque de anuncios.

**No se agregaron:**
- *Rezago espacial del precio*: usa precios, así que debe calcularse dentro de cada fold.
- *Avalúo catastral por manzana*: falta conseguir los datos.
- *Altitud SRTM*: es redundante con `dist_cerros` y necesita paquetes de rasters.

### D18 · "Chapinero sintético": validación ponderada hacia el test (TWCV, Brenning y Suesse 2026) (2026-11-22)

`91_validacion_sintetica.R` repondera los errores out-of-fold ya guardados (no se vuelve a entrenar nada) para que los anuncios validados se parezcan al test. Sigue a Brenning y Suesse (2026, arXiv 2603.29981).

**Cómo se hace:**
- **TWCV:** pesos por *raking* que igualan a las del test las proporciones de 5 variables discretizadas: estrato, apartamento o casa, habitaciones, quintiles de log del área y quintiles de distancia al CBD. Los pesos se encogen un 20% hacia pesos iguales, como en el artículo.
- **IWCV (comparación):** pesos p/(1−p) de un logit que distingue test de train.
- Solo se usan las variables del test, nunca su precio.

**Resultados (7 modelos con score en Kaggle):**
- El MAE por localidad es optimista en 45 M en promedio. Con TWCV el sesgo baja a 32 M e IWCV queda en 41 M.
- La correlación de Spearman con el orden del leaderboard sube de 0,46 a 0,64 con TWCV y a 0,79 con IWCV.
- El MAE en los 307 anuncios de Chapinero del train es el más cercano en nivel (−21 M), pero ordena peor (0,50).

**Diagnósticos:**
- El test es muy distinto: el 100% de los anuncios está a menos de 1,27 km de un CBD (en el train, el 4%); hay 63% de estrato 6 (23% en el train) y 97% de apartamentos.
- El tamaño efectivo de muestra de TWCV es de solo 1.160 anuncios (3%). El 32% del peso queda en los anuncios de Chapinero del train y el 40% en Usaquén.
- **No hay cobertura en la distancia de predicción `d`.** En el test, `d` tiene una mediana de 96 m y el 99% está por debajo de 500 m. En la validación con buffer, ninguna observación baja de 500 m. Por eso `d` no puede balancearse; el artículo lo resolvería con buffers de radio aleatorio, lo que obliga a volver a entrenar.
- Aun con un `d` mucho menor (que debería facilitar la predicción), Kaggle sale peor que la validación. El sesgo viene del cambio en las variables, no de la distancia.
- Con solo 7 modelos, y 4 de ellos entre 172 y 177 M, las correlaciones de orden son ruidosas.

**Uso:** reportar TWCV junto al MAE por localidad y al de Chapinero. Para elegir entre modelos con MAE parecido, preferir el que gane en TWCV o en IWCV.

### D19 · Sin variables de lujo y oficinas en los modelos; los pesos del Chapinero sintético solo para evaluar (2026-11-22)

**1. Embajadas, oficinas, hoteles y clubes salen de los modelos** (`03_features.R`). Se quedan en `base_enriquecida.csv` para las descriptivas. La base de modelos queda con 81 variables.

En el lasso por m² (04e), quitarlas cambia mucho el resultado:

| | MAE total | Chapinero | TWCV |
|---|---:|---:|---:|
| Con ellas | 135,9 M | 168,2 M | 150,5 M |
| Sin ellas | 135,1 M | 152,9 M | 142,8 M |

Por qué: se concentran en Chapinero y Usaquén, así que al dejar Chapinero afuera el modelo extrapola a valores que nunca vio. Es el mismo argumento de D10 contra las dummies de localidad.

Es un buen ejemplo para la presentación: `dist_embajada` es la variable nueva más correlacionada con el precio (−0,30) y aun así empeora la predicción fuera de muestra.

**2. Entrenar con pesos hacia el test no ayuda** (`04e_elastic_net_pesos.R`).

Se probó el lasso ponderado con pesos IWCV o TWCV elevados a γ ∈ {0,25; 0,5; 1}:

| | TWCV | Chapinero |
|---|---:|---:|
| Sin pesos (`m20_en_sin_pesos_m2`) | 142,4 M | 151,7 M |
| Mejor con pesos (TWCV, γ = 0,25) | 142,3 M | 153,8 M |
| Pesos completos | hasta 153,7 M | hasta 177 M |

Con pesos fuertes, el modelo aprende de muy pocos anuncios (el tamaño efectivo es del 2–3%).

**Decisión:** los pesos se usan para **evaluar y elegir** hiperparámetros (`mae_twcv` y `mae_iwcv`, que ahora salen en `evalua()` y en el registro), no para entrenar. La red (`09`) elige por `mae_twcv` y entrena sin pesos.

`m20_en_sin_pesos_m2` es el mejor lasso por m² hasta ahora en Chapinero, TWCV e IWCV.

### D20 · Comparables: precio por m² de los vecinos del train, un "control sintético" por anuncio (2026-11-22)

`04f_lasso_comparables.R` agrega al lasso por m² cuatro variables: el precio por m² (en log) de los 5 y de los 20 anuncios del train más cercanos **del mismo tipo** (apartamento o casa), ponderados por 1/(distancia + 30 m), y la distancia media a ellos. Es la lógica de un avaluador y el rezago espacial que estaba pendiente.

**Motivación (de D18):** el 99% del test tiene un anuncio del train a menos de 500 m (mediana 96 m). Los modelos no usaban esa información.

**Sin fuga de información:**
- En cada fold, los comparables salen solo del conjunto de análisis, y nunca es el anuncio mismo.
- No se usan como comparables los anuncios con la **misma descripción**: el mismo inmueble publicado dos veces (8.078 descripciones repetidas en el train y 200 compartidas con el test; `USA_DUPLICADOS = FALSE`).

**Validación (lambda elegido por TWCV en la CV aleatoria):**

| | Sin comparables | Con comparables |
|---|---:|---:|
| CV aleatoria: total | 130 M | 116 M |
| CV aleatoria: Chapinero | 150 M | 141 M |
| CV aleatoria: TWCV | 138 M | 130 M |
| CV por localidad con buffer: TWCV | 143 M | 193 M |

El buffer quita justo los vecinos que la variable necesita, así que esa CV no sirve para estos modelos.

**Cuidado:** en la CV aleatoria, los 5 comparables de un anuncio del train están a 19 m en la mediana (a menudo en el mismo edificio); los del test, a 151 m. La CV aleatoria exagera la ganancia. El lasso pone más peso en el promedio de 20 vecinos que en el de 5, que es menos sensible a eso.

**Registro:** `m21_en_comparables_m2`, con las predicciones out-of-fold de la CV por localidad, para que sea comparable con el resto del registro. Por eso ahí luce mal. El juez es Kaggle; la referencia es m20 sin comparables, con 171,6 M.

**Actualización (XGBoost con comparables, `06b_xgb_comparables.R`, `m22_xgb_comparables_m2`):**
- Kaggle: **162,9 M**, el mejor XGBoost del equipo (el de Juan Manuel, sin comparables, sacó 165,5 M) y el tercer mejor modelo.
- Los comparables mejoran tanto el lasso (de 171,6 a 167,1 M) como los árboles.
- La CV aleatoria **no sirve para estimar el nivel del error en árboles**: el XGBoost sin comparables da 100 M en ella, frente a 133 M en la CV por localidad y 172,7 M en Kaggle. Los árboles memorizan anuncios del mismo edificio y descripciones repetidas que quedan en folds distintos, y las rondas llegan al tope de la grilla (2.500). Solo sirve para comparar con y sin comparables a igual configuración: el TWCV baja de 116 a 110,5 M con profundidad 4.
- Siguiente paso: una CV aleatoria agrupada por edificio (mismas coordenadas en el mismo fold), para elegir hiperparámetros sin memorización.
- Las funciones de comparables (`prepara_comparables()`, `comparables_*()`) y `FOLDS_ALEAT` están en `utils_modelos.R`, para que los use cualquier modelo.

### D21 · Ensamble del XGBoost con comparables y la NN STAR de Samuel (2026-11-22)

`92_ensamble_xgb_nnstar.R` promedia (aritméticamente) el precio de `m22_xgb_comparables_m2` (162,9 M en Kaggle) y de la NN STAR de Samuel (`m17_nn_star_m2`, 158,3 M; leída de su rama `redes-neuronales` con `git show`, sin unir ramas).

- Las predicciones de los dos tienen una correlación de 0,94 en log, pero difieren 94 M por anuncio en promedio: se equivocan distinto.
- Los pesos no se estiman con validación, porque las OOF de los dos vienen de CV distintas (aleatoria y por localidad). Se prueban dos pesos fijos: 50/50 y 70% para la red. Como el valor absoluto es convexo, el MAE del promedio no supera el promedio de los MAE: el peor caso es 160,6 M (50/50) o 159,7 M (70% red). Con un solo envío disponible se sube 70% red.
- Envíos: `m23_ens_xgbcomp_nnstar_50.csv` y `m23_ens_xgbcomp_nnstar_70nn.csv`.
- `03f_comparables.R` exporta `data/processed/comparables.csv` (las 4 variables de comparables, train y test) para que Samuel pruebe su red con ellas.

### D22 · Pesos del ensamble estimados con los scores públicos de Kaggle (2026-11-22)

`93_pesos_ensamble.R` elige los pesos de un ensamble **sin gastar envíos**.

**Cómo:**
- Se conoce el MAE público de cada modelo y sus predicciones sobre el test.
- Bajo errores aproximadamente normales, E|e| = σ·√(2/π) y E|p_i − p_j| = √(2/π)·sd(e_i − e_j). De ahí sale la covarianza de los errores sin conocer los precios del test: Cov(e_i, e_j) = (σ_i² + σ_j² − D_ij)/2.
- Los pesos (no negativos, que suman 1) minimizan w'Σw.
- **Garantía exacta:** el MAE del promedio de precios no supera el promedio ponderado de los MAE, porque el valor absoluto es convexo.

**Verificación en el train** (OOF de la CV por localidad, 8 modelos): MAE estimado del ensamble óptimo 126,5 M; real 125,1 M; el mejor individual tenía 132,2 M. El método acierta y es algo conservador.

**Test (10 candidatos con score público):** el óptimo usa NN STAR 53%, XGB con comparables 40% y m14 7%. Su MAE estimado es 153,3 M, con cota garantizada de 160,8 M; el mejor individual tiene 158,3 M.

| Alternativa | Estimado | Cota |
|---|---:|---:|
| 70/30 (NN/XGB) | 153,8 M | 159,7 M |
| 59/41 | 153,4 M | 160,2 M |

**Envío:** `m24_ens_optimo.csv`. Las predicciones de Samuel (`m17_nn_star_m2.csv`, `m18_nn_64_m2.csv`) se traen de su rama con `git show` y no se suben a esta rama.

**Resultado en Kaggle:** 152,3 M (público), el mejor del equipo: 6 M menos que la NN STAR sola (158,3 M) y dentro de lo estimado (153,3 M; cota 160,8 M). El método queda validado también en el test.
