# Bitácora del proyecto

Diario de trabajo. **Se actualiza al final de cada sesión**: la entrada más reciente va arriba y la sección *Estado actual* siempre refleja el último punto.

---

## Estado actual (2026-11-24)

**Reproducción:** todo se corre con `code/00_main.R` (D27; instrucciones en el [README](README.md)). El código está en `code/` y las figuras y tablas en `output/`.

**Validación:** se deja afuera una localidad a la vez, con buffer de 500 m (D9). No es comparable con la ronda k-means. **Ningún modelo lleva dummies de localidad** (D10).

**Mejor envío en Kaggle:** `m48_star_nn_xgbsq_area_m2`, con 153,3 (detalle en `models/kaggle_scores.csv`). La tabla de abajo no se ha actualizado con los modelos m24–m50 de la rama de redes.

**Mejores modelos (MAE OOF, millones de COP):**

| Modelo | Total | Chapinero (n=307) | Promedio por localidad |
|---|---:|---:|---:|
| **m17_nn_star_m2** (NN STAR, Kaggle **158,3**) | 131,4 | 146,9 | 153,5 |
| m19_nn_star_afinada_m2 (base nueva sin zona de lujo; empata con m17, no se sube) | 131,6 | 146,6 | 154,3 |
| m18_nn_64_m2 (red general del mismo tamaño, Kaggle 167,5) | 131,5 | 155,9 | 156,7 |
| m12_en_pca_nt_tx | **131,1** | 149,7 | 146,0 |
| m14_en_enc_tx (m02 + encoder texto STAR) | 132,2 | 143,6 | **144,1** |
| m51b_xgb_tipo_dist (XGB ponderado, D16b) | 134,6 | **143,3** | 152,3 |
| m51_xgb_ponderado (XGB ponderado, D16b) | 132,4 | 147,6 | 146,8 |
| m06_hibrido_en_xgb | 133,6 | 148,5 | 150,5 |
| m02_elastic_net | 132,2 | 154,7 | 149,8 |
| m02b_elastic_net_m2 | 135,0 | 153,8 | 162,1 |
| reg_ols_sin_loc | 132,6 | 155,5 | 150,2 |
| m05_xgb_precio_m2 | 132,3 | 156,1 | 146,8 |
| m90_ensamble | *129,3* | *154,7* | *146,5* |

**Envíos a Kaggle:** scores en `models/kaggle_scores.csv`. **Mejor: m17_nn_star_m2 con 158,3**, seguido de m18_nn_64_m2 con 167,5; antes, el mejor era m04 o m02b con 172,7. Con 9 envíos, la predicción media del test es lo que mejor ordena el score (Spearman −0,87), por encima del MAE total (0,63) y del de Chapinero (0,53).

**Candidatos de `main` (XGB ponderado, D16b):** `m51_xgb_ponderado.csv` (pesos por distancia; TWCV 143,2, −6,6 M frente al mismo XGBoost sin pesos) y, detrás, `m51b_xgb_tipo_dist.csv` (gana solo en los 307 de Chapinero; TWCV 147,5). La comparación en Kaggle es contra los 172,7 de m04. Antes se llamaban m17 y m17b; se renombraron para no chocar con `m17_nn_star`.

**Pendientes / próximos pasos:**
- [ ] **Catastro (03f, D18):** valor de referencia del suelo por m² (UAECD 2026) y estrato oficial por manzana (SDP), en el grupo de ubicación. Mini corrida en `08h_nn_star_catastro.R` (configuración de m17, con y sin catastro) antes de una corrida completa
- [ ] **Embeddings de texto (Shen y Ross, 2021, JUE; Sentence-BERT):** `03g_embeddings.py` con `paraphrase-multilingual-MiniLM-L12-v2` (384 dim, ~5 min) sobre el texto original SIN nombres de lugares (no el lematizado), hasta 256-512 tokens. NN STAR: sub-rama 32-16 + atajo lineal dentro del grupo de texto (un solo encoder). XGB STAR: mismo grupo de texto. Medir el aporte con y sin embeddings; e5-base solo si MiniLM muestra señal
- [ ] Correr `09_red_neuronal.R` (m16, nnet) en el servidor y subirla a Kaggle. La familia de redes ya está cubierta con m17 y m18 (Keras, D17)
- [x] NN STAR con la base nueva (08e → m19): la zona de lujo de D15 lo empeora mucho y se excluye de las redes; sin ella, la afinación empata con m17
- [ ] Volver a correr el STAR (08 y 08b) con la base nueva, sin la zona de lujo, y con la grilla más rápida (tope de 1.000 rondas; eta 0,2 en la absoluta)
- [ ] Decidir con el equipo si la zona de lujo de D15 se excluye también de los demás modelos nuevos
- [ ] NN STAR: promediar varias semillas, y probar sin el contexto de OSM (en la ablación, 131,9 / 148,3 frente a 133,6 / 148,8 con él)
- [ ] Subir `m15_rf_m2.csv` a Kaggle (RF por m²: 177,3 M en Chapinero en la validación)
- [ ] Llegar a ≥ 20 envíos a Kaggle con las 6 familias (van 9)
- [ ] CV aleatoria frente a CV espacial: ¿cuál ordena los modelos como el leaderboard?
- [ ] Análisis de negocio: sobrepredicción, regla de compra, recomendación
- [ ] Presentaciones `best_equipo_XX` y `compare_equipo_XX`
- [ ] Subir m06 (y reg_ols_sin_loc / m90) a Kaggle y anotar el score público aquí. Comparar con los 148,5 M de m06 en Chapinero para ver si la validación está calibrada
- [ ] Híbrido: el número de rondas quedó en el mínimo de la grilla (10). Probar de 1 a 10 rondas
- [ ] Corregir la subpredicción en Chapinero (sesgo de −82 M en m02): pesos por cambio de covariables o calibración del nivel. **Avance (D16b):** en XGBoost, los pesos por distancia al test bajan el sesgo de −100 a −61 M y el TWCV en 6,6 M (m51). Falta probarlos en el elastic net (m14) y en el híbrido m06, y confirmarlo en Kaggle
- [ ] Rezago espacial del precio por m² (kNN dentro de cada fold): función en `utils_modelos.R`
- [x] Variables de contexto de OSM: cerros, vías principales, área verde, altura de edificios y zona de lujo (D15)
- [ ] Decidir si se permite explotar los 200 duplicados exactos train-test (reglas del curso)
- [x] TF-IDF del texto: `03c_texto.py` + `03d_tfidf.py` → `data/processed/tfidf.parquet` (D11)
- [ ] Usar el TF-IDF en R: PCA (`irlba::prcomp_irlba`, sin densificar) o lasso directo sobre la matriz dispersa dentro de `cv_oof`
- [x] Arreglar las regex de amenidades (negaciones y "apartaestudio") y agregar 10 amenidades comunales (D14). Los modelos nuevos ya usan la base con 32 dummies; los anteriores no se vuelven a correr
- [ ] Recuperar los decimales perdidos en el área del texto: los valores mayores de 1.000 (2.391) son áreas multiplicadas por 10 o 100. Dividir y aceptar si pasa la regla de coherencia
- [ ] Arreglar las regex de parqueaderos y baños (falta `\b` antes del número: "10 parqueaderos" se lee como 0)
- [ ] `bedrooms` = 0 (186) y 11 (97): ¿tratarlos como faltantes o como tope?
- [ ] Estrato por manzana y avalúo catastral (Datos Abiertos Bogotá)

### ⚠️ Para la presentación (discusión de negocio: ¿se pierde plata?)
**Predecir Chapinero con un modelo entrenado en toda la ciudad genera subpredicción por construcción.** El modelo aprende sobre todo de Usaquén y Suba (27 mil de 38 mil anuncios) y solo de 307 anuncios en Chapinero, una de las localidades más caras. Al estimar con toda la ciudad, las predicciones se encogen hacia la media de Bogotá, y en la cola alta (Chapinero, estrato 6) eso se convierte en un sesgo sistemático hacia abajo. Para una empresa que valora con este modelo, eso puede ser costoso.

**Lo que respalda el argumento:**
- **Todos los modelos subpredicen Chapinero en la validación:** el sesgo va de −58 M (los mejores) a −115 M (los árboles).
- **Kaggle premia al que menos subpredice:** con 11 envíos, la predicción media del test ordena los scores con Spearman −0,93. m17 (predicción media de 826 M) saca 158,3; m19 y m20 (~801 M) sacan 162,1, aunque eran mejores en Chapinero en la validación.
- **El error de nivel no se ve en la validación cruzada:** la localidad evaluada nunca está en el entrenamiento, y en el test el anuncio de entrenamiento más cercano queda a 96 m en promedio (D16).

**La propuesta:** para las localidades cercanas a la media de precios hay más datos parecidos y menos extrapolación, así que un modelo de ML sería más efectivo y confiable ahí (Usaquén: MAE ~125 M). Para un mercado de lujo como Chapinero haría falta un modelo con datos propios de la zona, una calibración del nivel o información externa sobre el nivel de precios (por ejemplo, el valor catastral del suelo, D18).

**Matiz para la discusión:** si el modelo se usa para comprar, la subpredicción hace perder negocios (ofertas demasiado bajas), mientras que la sobrepredicción hace pagar de más. Hay que discutir cuál de los dos errores le cuesta más a la empresa (el análisis de negocio está en los pendientes).

---

## 2026-11-24 · Sesión 11: organización del repositorio y script maestro (D27)

- **Estructura de la guía del curso:**
  - `scripts/` pasa a `code/`, y las figuras y tablas de `reports/*/` pasan a `output/figures|tables/{01_descriptivas,02_modelos}/`. Se usó `git mv`, así que la historia se conserva.
  - Se crearon `Problem-Set-3-Making-Money-with-ML.Rproj` (ahora se versiona) y `code/exploratorio/`, donde quedó `check_validacion.R`.
  - Cambios de nombre: `00_config.R` → `01_setup.R` y `01_osm_descarga.R` → `01b_osm_descarga.R`. Los demás conservan su número.
- **`code/00_main.R`:**
  - Corre los 51 pasos en orden, incluidas las variantes por variables de entorno (`CATASTRO`, `CRITERIO`, `GANADORA`, `VARIANTE`). Cada uno corre en un proceso nuevo de R o de Python y deja su log en `output/logs/`.
  - Los interruptores son `DESCARGAS`, `PYTHON`, `REDES`, `LENTOS` y `PRUEBA`. En la terminal también funcionan `--todo`, `--solo=…` y las opciones con el mismo nombre de cada interruptor.
  - Si a un paso apagado le falta un archivo que produce y que otro paso necesita, corre igual.
  - Al final escribe `output/session_info.txt` y `output/python_<entorno>.txt`.
- **`code/01_setup.R`:**
  - Es el único lugar donde se cargan paquetes: un solo `p_load`, más `sf` y `keras3` como opcionales. Se quitaron los `p_load` de los 22 scripts que los tenían.
  - Todas las rutas salen de `here::here()` (`P$fig_desc`, `P$tab_mod`, `P$external`…).
  - Funciones de Python: `dir_venv()`, `python_de()` (Windows o macOS) y `asegura_venv()`, que crea los entornos `texto`, `emb` y `tf` con uv o con reticulate en `~/.virtualenvs/ps3-*`.
  - `descarga_zip()` baja el catastro de 03f y 03h si falta.
- **Python:**
  - Los tres .py arman sus rutas desde `Path(__file__)`.
  - Archivo nuevo: `requirements-emb.txt`, para el entorno de embeddings, que antes solo estaba documentado en un comentario.
  - `utils_redes.R` usa `dir_venv("tf")`.
- **Corrección:** `08e_nn_star_afinacion.R` tenía una comilla mal puesta en la descripción de `registra()` y no se podía ni leer (error de sintaxis en `main`). Se corrigió.
- **Corrección:** `04_regresiones.R` fallaba con la base actual, porque `area_verde500` y `pisos_prom500` (D15) no estaban en ningún bloque. Se agregaron al bloque de ubicación (regla `500$`, como en las redes). El main ahora acepta `--desde=<script>` para retomar una corrida.
- **Nombres:** los XGB ponderados m17 y m17b pasan a **m51_xgb_ponderado** y **m51b_xgb_tipo_dist**, porque chocaban con `m17_nn_star`. Se renombraron en el registro, en las predicciones, en los envíos y en los textos; no se reentrenó nada.
- **Documentación:**
  - README reescrito: cómo correr en RStudio y en la terminal, interruptores, R frente a Python, entornos, estructura y problemas conocidos.
  - Rutas actualizadas en los informes, CLAUDE.md, `docs/` y los README de `data/` y `models/`. Todos los enlaces relativos de los `.md` resuelven.
- **Verificación:**
  - `00_main.R --solo=02c_composicion_test.R`, llamado desde fuera del proyecto, regenera tablas y figura idénticas.
  - `--solo=03d_tfidf.py` crea el entorno `texto` desde R en Windows y corre el .py.
  - Todos los `.R` y `.py` se leen sin errores de sintaxis.
  - **Corrida completa del main con las banderas por defecto (Windows):** termina sin errores. Desde `04b` hasta `91` (38 pasos) tardó unos 131 min; el más lento es `06_xgboost.R` (~57 min).
- **Cambios en las métricas al regenerar** (MAE OOF total, frente al registro anterior):
  - La base procesada no sale idéntica a la del commit anterior: cambia la fuente del área en 8 avisos y se regenera el TF-IDF. Por eso los modelos que se reentrenan se mueven entre −2 y +4 millones (m01 +1,2; m02 +2,9; m04 −2,3, con min_child_weight = 10 y 975 rondas; m05 −2,3).
  - **m90_ensamble** pasa de 129,3 a 109,2 millones. El registro anterior no se había recalculado después de agregar los modelos STAR y los ponderados; no es un efecto de la base.
  - No se reentrenaron las redes ni los XGB STAR (`REDES` y `LENTOS` en FALSE), así que sus métricas no cambian.
- **Pendiente:**
  - Las decisiones D18–D26 se citan en el código, pero no están escritas en `docs/decisiones.md`.
  - Probar el main en macOS.

---

## 2026-11-22 · Sesión 8c (rama main): TWCV de los XGBoost ponderados y composición del test

- **TWCV e IWCV de las 10 variantes de `10_xgb_ponderado.R`**, todas sobre la misma base, de modo que la diferencia frente a `base` aísla el efecto de los pesos. Tabla: `output/tables/02_modelos/ponderados_twcv.csv`.

  | Variante | Chapinero | TWCV | Dif. TWCV | IWCV | Dif. IWCV |
  |---|---:|---:|---:|---:|---:|
  | base | 156,8 | 149,8 | — | 138,6 | — |
  | **dist2km (m51)** | 147,6 | **143,2** | **−6,6** | 137,1 | −1,5 |
  | apto_dist2km | 145,0 | 144,5 | −5,3 | 137,7 | −0,9 |
  | tipo | 148,4 | 145,7 | −4,2 | 137,0 | −1,6 |
  | tipo_dist2km (m51b) | 143,3 | 147,5 | −2,3 | 138,5 | −0,1 |
  | razon_g1 | 162,2 | 153,7 | +3,9 | 146,6 | +8,0 |

  - **m51 es la mejor variante en TWCV, y m51b pierde esa posición.** La ventaja de m51b se concentra en los 307 anuncios de Chapinero; en la composición completa del test, que incluye Usaquén, bajar el peso de las casas no ayuda tanto.
  - En IWCV las diferencias son menores (−1,6 a +8 M), porque esa validación ya concentra el peso cerca de Chapinero.
  - El `m04_xgboost` del registro usa la base anterior a D14, así que no sirve para aislar el efecto de los pesos. La comparación correcta es contra `base` en `ponderados_twcv.csv`.
- **Descriptivas (`02c_composicion_test.R`, sección 3.1–3.3 del informe 1):** composición de train y test por tipo, estrato, habitaciones, área y distancia al CBD; perfil de casas y apartamentos; cercanía del train al test. Figura `f15_composicion_train_test.png`.
  - El test tiene la misma composición que los anuncios del train en Chapinero: la diferencia entre muestras es geográfica.
  - Los 61 anuncios marcados como casa en Chapinero tienen el perfil de un apartamento (126 m², 2,7 habitaciones, ascensor en el 41%). La etiqueta de tipo es ruidosa en la zona de interés.
- **Corrección:** la Sesión 10 y D16 decían que el 100% del test está a menos de 1,27 km de un CBD. La cifra correcta es 96% a menos de 2 km (14% en el train) y 52% a menos de 1 km (2,6%). La distancia máxima en el test es 6,4 km. Se corrigió en ambos documentos.
- **Siguientes pasos:** subir m51 a Kaggle (comparar con m04); aplicar los pesos por distancia al elastic net con encoder (m14).

---

## 2026-11-21 · Sesión 8b (rama main): XGBoost con pérdida ponderada y casas frente a apartamentos (D16b)

- **Diagnóstico:**
  - El test tiene 97% de apartamentos; el train, 75,5%. Las 9.467 casas del train están casi todas lejos de Chapinero (4.753 a más de 5 km).
  - Las casas del train tienen área mediana de 206 m² frente a 99 de los apartamentos, estrato 3,8 frente a 4,8 y casi nunca mencionan ascensor (1% frente a 21%).
  - Todos los modelos subpredicen Chapinero, con sesgos de −62 a −120 M.
- **`10_xgb_ponderado.R`:** XGBoost con los hiperparámetros de m04, sobre la base actual, con la validación por localidad y buffer de 500 m. Se compararon pesos por tipo, por distancia al test (núcleo exponencial) y por razón de densidades (clasificador train vs. test), además de un modelo solo de apartamentos. `xgb_rondas()` ahora acepta pesos (`wa`).
- **Resultados (MAE OOF en millones; diferencia pareada en Chapinero frente a la base, con su *t*):**

  | Variante | Total | Chapinero | Dif. Chapinero (*t*) | Sesgo Chapinero |
  |---|---:|---:|---:|---:|
  | base | 131,0 | 156,8 | — | −100 |
  | tipo_dist2km (m51b) | 134,6 | **143,3** | −13,5 (−3,2) | −61 |
  | apto_dist2km | 132,5 | 145,0 | −11,8 (−3,0) | −64 |
  | dist2km (m51) | 132,4 | 147,6 | −9,2 (−2,6) | −61 |
  | tipo | 132,1 | 148,4 | −8,4 (−3,1) | −91 |
  | razon_g05 | 132,1 | 148,8 | −8,0 (−1,9) | −62 |
  | razon_g1 | 140,0 | 162,2 | +5,4 (+1,0) | −69 |

- **Aprendizajes:**
  - Los pesos que se concentran *moderadamente* cerca del test mejoran Chapinero de forma significativa y reducen el sesgo en unos 40 M. Cuestan entre 1 y 4 M de MAE total.
  - La razón de densidades del clasificador es demasiado extrema: AUC de 0,997, separa casi solo por ubicación, y con γ = 1 el tamaño de muestra efectivo cae al 3%. Empeora.
  - El modelo solo de apartamentos no mejora frente a ponderar por tipo. XGBoost ya separa por `es_apto`, y quitar las casas reduce los datos.
  - La métrica de "zona objetivo" (Chapinero + 1 km, 3.913 anuncios), fijada antes de correr, **no discriminó**: todas las variantes empeoran un poco ahí (+0,5 a +6 M). La ganancia está en Chapinero mismo. Por eso m51 (elegido por zona) es dist2km y no la mejor en Chapinero.
  - Las predicciones ponderadas del test son más altas (media de 768 M en m04 frente a 804 M en m51b). Para el análisis de negocio esto importa: menos subpredicción también implica más riesgo de sobrepredecir.
- **Siguientes pasos:** subir m51b y m51 a Kaggle (la comparación limpia es contra m04, con 172,7). Si mejoran, aplicar los mismos pesos al elastic net y al híbrido (`glmnet` acepta `weights`).

---

## 2026-11-22 · Sesión 10: "Chapinero sintético" (validación ponderada, D16)

- Nuevo `91_validacion_sintetica.R`. Sigue a Brenning y Suesse (2026), *Target-Weighted CV*: repondera los errores out-of-fold para que se parezcan al test. Tarda segundos y no vuelve a entrenar.
- **Sesgo frente a Kaggle**, en 7 modelos:

  | Validación | Sesgo medio | Spearman con Kaggle |
  |---|---:|---:|
  | MAE por localidad | −45 M | 0,46 |
  | TWCV | −32 M | 0,64 |
  | IWCV | −41 M | 0,79 |
  | Solo los 307 de Chapinero del train | −21 M | 0,50 |

  Todas siguen siendo optimistas.
- **Composición del "Chapinero sintético" (TWCV):** Usaquén 40%, Chapinero 32%, Santa Fe 12%, Suba 5%. El tamaño efectivo de muestra es del 3%.
- **El test casi no se parece al train:**
  - 96% de los anuncios a menos de 2 km de un CBD (14% en el train) y 52% a menos de 1 km (2,6%);
  - 63% de estrato 6 (23%);
  - 97% de apartamentos (76%).
- **Distancia de predicción `d`:** mediana de 96 m en el test, y ningún anuncio de la validación por debajo de 500 m. Aun así, Kaggle sale peor: el sesgo viene del cambio en las variables.
- Figura para la presentación: `output/figures/02_modelos/m6_validacion_sintetica.png`.

---

## 2026-11-21 · Sesión 9: datos nuevos en la red y afinación del NN STAR

- **Merge con `origin/main`:** trae las 32 amenidades con negaciones (D14) y las 13 variables de contexto de OSM (D15). En el merge, nuestras redes se renumeraron: m15 → **m17_nn_star**, m16 → **m18_nn_64**. Las decisiones de redes pasan a D17.
- **Ablación de la base nueva** (configuración de m17; `tables/nn_ablacion_datos.csv`):
  - la base nueva completa da 137,0 / 166,5;
  - **sin la zona de lujo** (embajadas, oficinas, hoteles y clubes), 133,6 / 148,8;
  - sin la zona de lujo ni OSM, 131,9 / 148,3;
  - las amenidades nuevas no aportan;
  - la base vieja reproduce m17 exactamente (control).
  
  **Por decisión del equipo, las redes excluyen la zona de lujo y conservan OSM.**
- **`utils_redes.R`:** la tasa de aprendizaje, la pérdida y las épocas ahora son parámetros, con los mismos valores por defecto. `area_verde500` y `pisos_prom500` pasan al grupo de ubicación (también en 08).
- **Afinación por etapas (`08e_nn_star_afinacion.R`, 93 min; `tables/nn_star_afinacion.csv`):**
  - **Etapa 0 (datos):** 133,6 / 148,8.
  - **Etapa 1 (tasa):** gana lr 1e-4, con 132,4 / 144,7 y 12 épocas en vez de 3.
  - **Etapa 2 (dropouts):** gana 0,15 / 0,7, con 131,6 / 146,6, aunque las diferencias son de décimas.
  - **Etapa 3 (pérdida absoluta):** 132,4 / **142,2**. Es la mejor en Chapinero, pero pierde en el total y la diferencia no es significativa (*t* = −1,8).
- **Registrada `m19_nn_star_afinada_m2`** (lr 1e-4, p_u 0,15, p_t 0,7, MSE, 20 épocas): 131,6 / 146,6 / 154,3.
  - Frente a m17: −0,3 M en Chapinero (*t* = −0,1) y +0,3 M en el total (*t* = 1,3).
  - Su predicción media del test es 801, frente a 826 de m17.
  - **No cumple el criterio para subirla a Kaggle**, así que m17 sigue siendo la referencia.
- **Grilla ampliada del XGB STAR:** aplazada. La medición mostró que el texto pesa el 80% del costo por ronda y que el 75% de las rondas se descarta, porque siempre se entrena hasta el tope. Antes de volver a correrla, se acelera.

---

## 2026-11-21 · Sesión 8: NN STAR, red general y grilla ampliada del XGB STAR (en curso)

- **Interpretación del STAR, para la presentación:**
  - El STAR es un solo XGBoost con restricciones de interacción: los grupos se entrenan juntos y compiten por el mismo residuo. El encoder es el rubro de su grupo en la "factura" del modelo, en log del precio por m². Por ejemplo, Chapinero tiene +0,20 ≈ +22%.
  - Los autores interpretan cada variable aditiva con curvas ICE paralelas, y el grupo de ubicación con un mapa de su encoder (el *projection trick*). Lo comprueban con el H de Friedman; nosotros con una verificación árbol por árbol, que es más estricta.
  - Frente a SHAP, el STAR no explica un modelo después de entrenarlo: lo restringe para que su explicación sea exacta y única.
  - **El ascensor no interactúa con nada** (`tx_ascensor` es aditivo en el STAR y lineal en el EN). Solo se combina con otras palabras dentro del texto: "ascensor privado" queda en el puesto 27 de 1.000 y "sin ascensor" en el 49.
- **Grilla del XGB STAR (08) ampliada.** La anterior quedó en el borde en todos los parámetros. Ahora son tres búsquedas de 20 configuraciones: m² cuadrática, m² absoluta (eta hasta 0,3 y hasta 5.000 rondas) y precio. Detalles en D13. Se registra el mejor de cada búsqueda (nuevo: `m13_xgb_star_m2_mae`), los encoders salen del mejor m² y luego se vuelve a correr 08b.
- **Redes con Keras desde R (D17):** `code/utils_redes.R` y TensorFlow en `.venv-tf`.
  - **NN STAR (`08c_nn_star.R`, m17):** estructura lineal más ramas de ubicación y de texto 64-32-16 ReLU, cada una con atajo lineal y dropout propio. Tiene 72.757 parámetros. Diagrama: https://claude.ai/artifact/2QqQEJDpwcaxDdsKrqRYhk
  - **Red general (`08d_nn_general.R`, m18):** 64-32-16 con todo mezclado y 71.489 parámetros, para comparar con el mismo tamaño.
  - **Afinación:** solo el dropout.
  - **Prueba de humo (`PRUEBA=1`):** la suma de las ramas coincide con la predicción (diferencia de 5e-7), las ICE salen paralelas y la calibración deja los residuos con media 0.
- **Primer intento del NN STAR fallido** (MAE 200 en la primera configuración): con pesos aleatorios, las ramas lineales arrancaban con ruido grande y se compensaban entre sí. Se corrigió iniciando las capas de salida en cero (D17). En una prueba con 3 folds queda igual o mejor que la red general, con el óptimo entre 5 y 10 épocas (la grilla de épocas pasa a 1–80).
- **Resultados del NN STAR (08c, 73 min):**
  - **Mejor configuración:** p_u = 0,1 y p_t = 0,5, con 3 épocas. El óptimo de p_t está en el borde de la grilla; queda pendiente probar 0,6–0,7.
  - **`m17_nn_star_m2`:** 131,4 / **146,9** / 153,5. Sesgo en Chapinero −67 M y la **predicción media del test más alta de todos (826 M)**.
  - **Frente a m13_xgb_star_m2:** −8,4 M en Chapinero (*t* = −2,3). **Frente a m02b:** −6,9 M (*t* = −2,0).
  - **Objetivo precio (`m17_nn_star`):** 136,8 / 154,0, peor que el m².
  - **Encoders:** correlación con los del XGB STAR de 0,955 en ubicación y 0,815 en texto.
- **Resultados de la red general (08d, 35 min, mismo tamaño):**
  - **Mejor dropout:** p = 0,2 con 7 épocas. `m18_nn_64_m2` da 131,5 / 155,9 / 156,7, con sesgo de −99 M y predicción media del test de 783 M. El objetivo precio da 130,5 / 173,6.
  - **NN STAR frente a la red general (m²):** el mismo total (−0,1 M), pero **−9,0 M en Chapinero** (*t* = −2,0). Con objetivo precio, −19,6 M en Chapinero (*t* = −4,2).
  - **Para la presentación:** a igual número de parámetros, la estructura aditiva no le quita precisión al resto de la ciudad y sí mejora la extrapolación a Chapinero.
- **Kaggle:** `m17_nn_star_m2` obtuvo **158,3** (−14,4 M frente al mejor anterior, 172,7) y `m18_nn_64_m2` obtuvo 167,5. La red general también mejora, pero el STAR le gana por 9,2 M, igual que en la validación en Chapinero (−9,0 M). Con 9 envíos, la predicción media del test ordena los scores con Spearman −0,87.
- **Grilla ampliada del XGB STAR (08) detenida** a los 13 minutos, porque se van a agregar más datos. El script ya está modificado y probado; se corre después, seguido del 08b. La primera configuración reprodujo exactamente el resultado anterior (133,0 / 155,3).
- **Merge con origin/main (sesión 7 del otro equipo):** las redes pasan de m15/m16 a **m17_nn_star** y **m18_nn_64**, porque m15 ya era el RF por m² y m16 está reservado para `09_red_neuronal.R`. Su decisión pasa de D14 a D16 y luego a **D17** (D14, D15 y D16 son de amenidades, OSM y la validación ponderada). Los CSV de `models/` se combinaron sin volver a correr nada. m17 y m18 usan la base anterior a D14/D15.

---

## 2026-11-21 · Sesión 7: enunciado, random forest por m² y red neuronal

- Se agregó el enunciado del taller (`docs/Problem_Set_3.pdf`). Se comparó con lo hecho y faltan:
  - Una **red neuronal**, que es una de las seis familias obligatorias.
  - Llegar a **≥ 20 envíos a Kaggle**, con al menos uno por familia (van 7).
  - **CV aleatoria** además de la espacial, para comparar cuál refleja mejor el leaderboard.
  - El **análisis de negocio**: sobrepredecir cuesta más que subpredecir, ¿se puede confiar en el modelo para comprar?
  - Las **dos presentaciones** (`best_equipo_XX`, `compare_equipo_XX`).
  - Cada integrante debe tener **≥ 5 contribuciones** en `main`.
- **Random forest por m² (`05c_rf_m2.R`, m15).** Objetivo log(precio/m²), 200 árboles en la CV y 500 en el modelo final, mtry = 12, min.node.size = 5.
  - Con coordenadas: 142,4 M total / **177,3 M en Chapinero** (m03: 140,5 / 183,0).
  - Sin lat/lon ni rotaciones: 142,7 / 180,1. Las distancias no reemplazan del todo a las coordenadas.
  - El RF sigue lejos del elastic net en Chapinero: los árboles no extrapolan por encima del rango de precios del train.
  - Variables más importantes: estrato, apartamento o casa, habitaciones, distancia al Parque 93 y a la Calle 72.
  - mtry = 25 no alcanzó a correr.
- **Red neuronal (`09_red_neuronal.R`, m16).** Escrita pero **sin correr**.
  - Red de una capa oculta con `nnet`, sobre log(precio/m²), con las variables del elastic net estandarizadas dentro de cada fold.
  - Grilla: size ∈ {5, 15} × decay ∈ {0,1, 1}. Tarda cerca de 1 h, así que se corre en el servidor.
  - En el curso las redes se hacen con keras3, pero no está instalado en este equipo (Python 3.14, sin TensorFlow). Por eso se usó `nnet`.
- **Dummies de amenidades (D14).** En `02_descriptivas.R`, las `tx_*` usan ahora `detectar_caracteristica()` (complementaria *Texto como datos*), que atiende negaciones. Además, la búsqueda es sin tildes y con palabras completas.
  - Pasan de 22 a 32. Las 10 nuevas son: parqueadero de visitantes, parque infantil, salón comunal, zonas verdes, terraza comunal, turco/sauna, squash, planta eléctrica, club house y jacuzzi.
  - Varias se reparten muy distinto entre train y test:
    - zonas verdes: 9,6% en train / 3,8% en test;
    - parque infantil: 11,5% / 6,3%;
    - parqueadero de visitantes: 11,5% / 16,5%;
    - planta eléctrica: 2,1% / 5,5%.
  - Correcciones en las existentes: `tx_estudio` −1.916 (apartaestudios) y `tx_ascensor` −601 ("sin ascensor").
  - Se regeneraron `base_enriquecida.csv` y `base_modelo.rds` (02 y 03). También cambió la imputación del área, porque usa las `tx_*`, y un poco la del estrato, por correr ranger en otro equipo.
  - El equipo decidió **no volver a correr los modelos anteriores**: los nuevos (desde m16) usan la base nueva. `09_red_neuronal.R` todavía no se ha corrido, así que usará la base nueva.
  - No se corrieron `03e_pca.R` ni el STAR (`08_xgb_star.R`). `pca_no_texto.csv` y `star_encoders.csv` siguen siendo de la base anterior; un modelo nuevo que los use debe regenerarlos primero.
- **Variables de contexto de OSM (D15).** La base pasa de 76 a 89 variables. Las nuevas son:
  - `dist_cerros`;
  - `dist_via_principal`;
  - `area_verde500` (ha de parque a menos de 500 m);
  - `pisos_prom500` y `n500_edif_pisos`;
  - `dist_*` y `n500_*` de embajadas, oficinas, hoteles y clubes.

  Detalles:
  - En OSM, los cerros son la relación 13780896 (reserva forestal, `leisure=nature_reserve`); la Circunvalar no aparece con ese nombre.
  - `overpass()` ahora reintenta con espera, porque Overpass limita las consultas seguidas.
  - `02_descriptivas.R` tarda unos 6 min.
  - Correlación con el log del precio en el train (norte de la ciudad): `dist_embajada` −0,30, `dist_cbd` −0,29, `dist_cerros` −0,13.
  - Las de embajadas, oficinas, hoteles y clubes son experimentales: casi equivalen a una dummy de localidad.
- Entorno: esta sesión corrió en un Windows con R 4.5.2 (`"/c/Program Files/R/R-4.5.2/bin/Rscript.exe"`). Se instalaron `ranger`, `sp` y `stargazer`; `xgboost` no está instalado.

---

## 2026-11-19 · Sesión 6: librerías con pacman

- Todas las librerías se cargan ahora con `pacman::p_load()` al inicio de cada script, justo después de los `source()` (ya no hay `library()`). `01_setup.R` instala pacman si falta. Se mantuvo el orden de carga, así que los conflictos de nombres se resuelven igual. La convención quedó en `CLAUDE.md`.
- La columna de texto original (`title`, `description`) está en `data/raw/*.csv` y en `base_enriquecida.csv`, pero no en `base_modelo.rds`. Para TF-IDF hay que unirla por `property_id`.
- Verificación: todos los scripts se leen sin errores de sintaxis y `check_validacion.R` pasa. No cambió ningún modelo.
- Limpieza del código (auditoría de sobreingeniería):
  - Nueva función `arma_objetivos()` en `utils_modelos.R`: arma los objetivos log(precio) y log(precio por m²). Reemplaza cuatro versiones repetidas en 04, 04b, 05b y 07; en 07, m05 la usa con `quita_area = FALSE` para conservar `log_area` entre las variables.
  - `topes` en 02b con un solo `summarise`.
  - Las carpetas de `01_setup.R` se crean en una sola línea.
  - Se borró el alias sin uso `broom_like` (02).
  - Pendientes de esa auditoría (no aplicados): borrar los `.rds`/`.ubj` de modelos que nadie lee, mover los parámetros de XGBoost y `RONDAS` (repetidos en 06 y 07) a utils, y quitar argumentos que nunca se cambian.
- **Texto en Python con ConTexto (D11):** nuevos `03c_texto.py` (preprocesamiento, n-gramas y nubes) y `03d_tfidf.py` (TF-IDF). Entorno: `.venv` con Python 3.11 creado con uv; se instala `contexto --no-deps` porque sus dependencias fijadas de 2021 no compilan en arm64. ConTexto necesita el parche `collections.Iterable`.
  - Problemas encontrados en los datos:
    - En cerca de 1/4 de los anuncios se perdieron las tildes y la ñ (`baos`, `usaqun`). Se reparan insertando una vocal o una `n`: 1.317 palabras, 2,6% del texto.
    - Unas 8.800 entidades HTML llegaron partidas (`ba ntilde o`). Se vuelven a pegar.
  - Problemas encontrados en ConTexto:
    - `remover_stopwords(lista_expresiones=)` borra subcadenas, no palabras completas. Por eso los lugares se quitan con código propio.
    - `Corrector` con `dict` arma listas del tamaño de cada frecuencia y tardaba unos 15 min. Con una lista tarda 4 s.
    - `lematizar_texto` carga el modelo en cada llamada, así que el lematizador se crea una sola vez.
  - Problema encontrado en OSM: Overpass responde 406 al user agent por defecto de httr. Se agregó uno genérico en `01b_osm_descarga.R`, que ahora también descarga los nombres de barrios (`barrios_nombres.csv`, 1.159 nombres; no cambia `servicios_puntos.csv`).
  - Resultado:
    - Se quitan los nombres de lugares: 3,9% del texto (`bogota`, `chico`, `santa barbara`, `cedritos`, `usaquen`, `chapinero`…).
    - Se corrigen 3.155 errores de tipeo raros (0,13%).
    - Stopwords: la lista de ConTexto sin `sin`/`no`, más `STOP_EXTRA` (verbos genéricos, venta/contacto, tipo de inmueble y números escritos).
    - Texto final: 1,85 M de palabras.
    - TF-IDF: 48.930 × 5.000 (3.499 bigramas), densidad de 1,08%, en `data/processed/tfidf.parquet` (17,7 MB, formato largo). Se lee desde R con `arrow`, y los ids coinciden con `base_modelo.rds`.
  - Nubes (f11 train, f12 test):
    - El test usa más `exclusivo`, `edificio`, `moderno`, `espectacular`, `bano servicio`, `zona social`, `parqueadero independiente`.
    - El train usa más `nivel`, `infantil`, `centro comercial`, `zona verde`, `parque infantil`, `transporte`.
    - Es decir, el texto del test describe un segmento más alto.
  - Nubes de caras (precio > p75 = 810 M) frente a baratas (< p25 = 415 M), dentro del train (f13, f14):
    - Las caras usan más `cuarto bano` (7,5×), `bano servicio` (7,1×), `parqueadero independiente` (3,4×), `chimenea`, `estudio` y `terraza`.
    - Las baratas usan más `laminado` (2,8×), `habitacion closet`, `parqueadero cubierto`, `ascensor`, `vigilancia`, `centro comercial` y `transporte`.
    - El patrón se parece al de test frente a train.
  - Al revisarlas se encontró que se filtraban barrios con nombres de palabras comunes (`santa ana`, `puente largo`, `polo club`, `santa paula`, `san patricio`). Ahora los nombres con 2+ palabras de contenido se borran siempre: lugares = 4,3% del texto; TF-IDF regenerado (17,6 MB).
- **PCA (`03e_pca.R`, D12).** Salidas en `data/processed`: `base_no_texto.csv`, `pca_no_texto.csv`, `base_texto.rds` (dgCMatrix) y `pca_texto.csv`. Los λ están en `tables/pca_varianza.csv`; las 8 cargas más altas de las 10 primeras componentes, en `tables/pca_top8_{no_texto,texto}.csv`; gráficas de varianza en `figures/m5_pca_varianza_*.png`.
  - No texto: 10 componentes con λ > 1. PC1 = centralidad hacia el nororiente (densidades y estrato frente a distancia al CBD), PC4 = tamaño, PC5 = año e imputación.
  - Texto: la varianza está muy repartida (50 componentes explican 19%). PC1 y PC2 son plantillas de inmobiliarias (`contactame`, `rentahouse`), PC3 = conjunto/parqueadero frente a "cerca a vías y centro comercial", PC4 = casa con servicio frente a edificio con amenidades.
  - Pendiente: decidir si se quitan las plantillas de inmobiliarias del texto, y probar el modelo sin lat/lon crudas para ver si las distancias generalizan mejor hacia Chapinero.
- **Elastic net sobre los PCA (`04c_elastic_net_pca.R`, m12).** Tres especificaciones × 2 objetivos, con la grilla ajustada (α × `lambda.min.ratio` ∈ {10⁻⁴, 10⁻⁵, 10⁻⁶}); tarda 2,7 min.
  - **m12_en_pca_nt_tx** (PCA no texto + PCA texto + no linealidades): 131,1 total / 149,7 Chapinero / 146,0 macro. Es el mejor individual en total y macro, y el segundo en Chapinero, detrás de m06 (148,5).
  - El texto aporta: frente a la misma especificación sin texto, baja 19,8 M en Chapinero. Frente a m02 (texto por regex), baja 5,0 M en Chapinero.
  - El texto solo: 204 M sobre el precio y 158 M sobre el m².
  - Falta volver a correr `90_comparacion.R` para que m12 entre al ensamble.
- **Kaggle: m12 quedó peor que m02b.** Diagnóstico con `04d_diagnostico_ubicacion.R`:
  - **Las coordenadas no son la causa.** Su contribución a la predicción es pequeña (desviación estándar de 0,01 a 0,04 en log, frente a 0,17–0,33 de la estructura) y solo suben el test entre 0,4% y 1,6%. Sin lat/lon, el MAE cambia menos de 3 M y la predicción media del test, cerca de 10 M.
  - **En Chapinero, la ventaja de m12 sobre m02b no era significativa:** −4,1 M con error estándar de 5,4 M (*t* = −0,76). La ventaja en el total sí lo es (*t* = −9,8), pero viene del resto de Bogotá, que no está en el test.
  - Los dos modelos predicen en promedio lo mismo en el test (782 frente a 784 M; correlación de 0,96). Difieren en cómo reparten el efecto: m12 sube el test por el texto (+5%) y m02b por la estructura (+16%).
  - Las componentes del texto se desplazan en el test (hasta 0,47 desviaciones estándar en pc_tx07).
  - Conclusión: con 307 anuncios del train en Chapinero, la validación no distingue modelos que difieren en menos de unos 10 M en esa localidad.
- **Scores públicos de Kaggle** (`models/kaggle_scores.csv`):

  | Modelo | Kaggle | MAE validación en Chapinero |
  |---|---:|---:|
  | m04_xgboost | 172,7 | 163,2 |
  | m02b_elastic_net_m2 | 172,7 | 153,8 |
  | m12_en_pca_nt_tx | 174,1 | 149,7 |
  | reg_ols_sin_loc | 183,7 | 155,5 |
  | m11_cart_m2_mse | 197,1 | 182,7 |

  - **La validación ordena mal los modelos para el test.** Correlación de Spearman con Kaggle: 0,3 para el MAE de Chapinero, 0,2 para el total y 0,5 para el promedio por localidad. Son solo 5 puntos, pero la señal es clara.
  - La distancia entre Kaggle y la validación de Chapinero va de 9,5 M (XGBoost) a 28 M (OLS).
  - Hipótesis: el fold de Chapinero quita *todos* los anuncios de Chapinero y su buffer, y eso exige extrapolar más que el test real, donde el modelo sí ve los 307 anuncios de Chapinero del train y a sus vecinos. Así, la validación castiga a los modelos locales (XGBoost) y premia de más a los lineales.
  - m12 y m02b empatan en Kaggle (diferencia de 1,4 M, 0,8%).
  - Otros dos envíos: m12_en_pca_tx_m2 (solo texto, subido por error al renombrar) = 209,2; m12_en_pca_nt_tx_m2 = 176,8, peor que m02b (172,7). El PCA del texto **no mejora en Kaggle**, aunque en la validación sí mejoraba.
  - Con 7 envíos, la correlación de Spearman con Kaggle es 0,46 para el total, 0,50 para Chapinero y 0,71 para el promedio por localidad.
  - **Hallazgo para la presentación: el PCA pierde la información específica de las amenidades.** El PCA truncado del texto (50 componentes) se queda con las direcciones de mayor varianza, y las palabras raras tienen poca varianza. Son justo las señales de lujo, y casi desaparecen.
    - % de la varianza de cada término que queda en las 50 componentes: `bano servicio` 80%, `servicio` 76%, `terraza` 63%, `chimenea` 54%, `piscina` 30%, `walk closet` 19%, `duplex` 18%, `estrenar` 11%, `cuarto servicio` 9%, **`penthouse` 5%**.
    - m02b tenía esa información completa como dummies (`tx_penthouse`, `tx_duplex`, `tx_piscina`…). m12 *reemplazó* las dummies por el PCA, y por eso pierde en el test, que es de alta gama (Chapinero).
    - Lección: el PCA no es supervisado, así que resume variación, no precio. Para el texto conviene *agregar* el PCA a las dummies, o usar un método supervisado (lasso sobre el TF-IDF).
  - **Segunda ronda de 04c** (7 especificaciones × 2 objetivos, 9,8 min). `m12_en_m02_m2` reproduce exactamente a m02b, así que la comparación es justa.

    | Especificación (objetivo m²) | Total | Chapinero | Promedio por localidad | Sesgo Chapinero | Predicción media test |
    |---|---:|---:|---:|---:|---:|
    | m02b (referencia) | 135,0 | 153,8 | 162,1 | −80 | 784 |
    | **m02 + PCA texto** | 131,2 | 150,4 | 158,3 | −83 | 788 |
    | PCA no texto sin área + PCA texto | 131,8 | 148,3 | 156,8 | **−75** | **802** |
    | PCA no texto (con área) + PCA texto (enviado: 176,8) | 131,7 | 152,6 | 150,1 | −93 | 769 |

    - **Agregar el PCA del texto a las dummies funciona mejor que reemplazarlas:** mejora a m02b en las tres métricas (−3,8 M en el total con *t* = −20; −3,4 M en Chapinero con *t* = −1,6).
    - **El área metida en las componentes era un problema en el objetivo m².** Sacar `log_area` del PCA de no texto sube la predicción media del test de 769 a 802 M y reduce el sesgo en Chapinero de −93 a −75. Para modelar el precio por m², el PCA de no texto debe hacerse sin el área.
    - Con objetivo precio, m02 + PCA texto obtiene el mejor MAE total de todos los modelos (128,9 / 146,9 / 144,8), pero los modelos con objetivo precio han salido peor en Kaggle.
- **Modelo STAR (2026-11-20; D13; informe §2.2c).** `08_xgb_star.R` (97 min) y `08b_en_star.R` (2,4 min).
  - **STAR (m13):** objetivo m² 133,0 / 155,3 / 154,8; objetivo precio 130,3 / 170,4 / 143,2. Las restricciones y las curvas ICE están verificadas.
  - **Para la presentación:** el mapa de la prima de ubicación (`figures/m6`) y el encoder de texto supervisado, que recupera `duplex` (puesto 21 de 1.000) y `penthouse` (puesto 59), que el PCA casi borraba.
  - **m14_en_enc_tx** (m02 + encoder de texto, objetivo precio): **el mejor en Chapinero (143,6) y el de menor sesgo (−64)** de todos los modelos, aunque no significativo frente a m02 + PCA texto (*t* = −0,74).
  - El encoder de ubicación solo, sin la ubicación lineal, empeora Chapinero: los árboles no extrapolan.
- **Candidatos para Kaggle:** m14_en_enc_tx (mejor validación en Chapinero) y m12_en_m02_pca_tx_m2 o m14_en_enc_tx_m2 (m02b + texto, objetivo m²).
  - **Hallazgo:** el score de Kaggle se correlaciona −0,79 con la predicción media del test: los modelos que predicen más alto salen mejor. Todos subpredicen Chapinero en la validación (sesgo de −80 a −142 M). Una corrección de nivel podría ayudar a todos, y es el pendiente de la subpredicción.

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
- Auditoría de complejidad: `PATRONES` y `num_txt()` en `01_setup.R`, sin la `hav()` duplicada, sin `sup_total_ok`, y `matriz_arboles` simplificada. Se verificó que `base_modelo.rds` queda idéntica.
- Nueva guía de variables (`docs/guia_variables.md`). El informe de modelos se reescribió para esta ronda.

---

## 2026-11-16 · Sesión 3: valores extremos y rangos de validez

- Nuevo script `code/02b_extremos.R` y nueva sección 7 del informe de descriptivas, con la figura f10 y 3 tablas. Las secciones 7–10 del informe pasan a ser 8–11.
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
- Se creó la estructura `data/ code/ models/ submissions/ reports/ docs/`, junto con `README.md`, `BITACORA.md`, `CLAUDE.md` y `docs/decisiones.md` (D1–D5).

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
