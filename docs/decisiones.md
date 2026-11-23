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

### D16 · Pérdida ponderada hacia el test en XGBoost; casas y apartamentos en el mismo modelo (2026-11-21)
**Contexto:** el test es 97% apartamentos y está en Chapinero. El train tiene 24,5% de casas, casi todas lejos, y solo 307 anuncios en Chapinero. Todos los modelos subpredicen Chapinero.
**Decisión:**
- Cada fila del train se pondera según qué tanto se parece al test (corrección por cambio de covariables; Shimodaira, 2000). Los pesos se calculan solo con covariables, nunca con el precio, y se normalizan a media 1.
- Pesos elegidos: **tipo × distancia**. El tipo lleva la proporción casa/apartamento del train a la del test; la distancia es `exp(−d/2 km)` al anuncio del test más cercano, con piso de 0,05. Ese modelo es m17b. m17 usa solo la distancia.
- Casas y apartamentos van en el **mismo modelo**, diferenciados por `es_apto` y por los pesos. Un modelo solo de apartamentos no mejoró.
- Se descarta la razón de densidades de un clasificador train vs. test. Separa casi perfectamente por ubicación (AUC 0,997) y concentra el peso en pocas filas.
**Por qué:** baja el MAE OOF en Chapinero de 156,8 a 143,3 M (diferencia pareada −13,5 M, *t* = −3,2) y el sesgo de −100 a −61 M, a cambio de +3,6 M en el total.
**Cautela:** se eligió entre 9 variantes mirando Chapinero; la confirmación debe venir de Kaggle (comparar con m04).
