# Guía de variables

Todas las variables del proyecto: nombre, definición, fuente y dónde se construyen. Última actualización: 2026-11-16.

**Bases**

- `data/raw/{train,test}.csv`: datos originales de Kaggle (anuncios de Properati).
- `data/processed/base_enriquecida.csv`: datos originales más variables del texto y de OSM. La genera [`02_descriptivas.R`](../code/02_descriptivas.R).
- `data/processed/base_modelo.rds`: variables finales, imputaciones y folds espaciales. La genera [`03_features.R`](../code/03_features.R).

**Fuentes**

| Código | Fuente |
|---|---|
| **Properati** | Columnas originales de Kaggle (`train.csv` y `test.csv`) |
| **Texto** | Expresiones regulares sobre `title + description` en minúsculas. El texto viene sin tildes y **sin puntos decimales**: "96.0 m2" aparece como "960 m2" (ver la sección 7 de [`informe_descriptivas.md`](../reports/01_descriptivas/informe_descriptivas.md)) |
| **OSM** | OpenStreetMap vía la API Overpass, descargado el 2026-11-14 con [`01b_osm_descarga.R`](../code/01b_osm_descarga.R). Es la foto *actual* de OSM, no la de 2019–2021 |
| **Construida** | Calculada a partir de otras variables |
| **Imputada (RF)** | Predicha con un random forest (`ranger`) entrenado con las filas que sí tienen el dato. Usa train y test, porque son covariables y no el precio |

**Columna "Modelos"**

- **L:** entra en la matriz lineal (`matriz_lineal()`: OLS y elastic net).
- **Á:** entra en la matriz de árboles (`matriz_arboles()`: random forest y XGBoost).
- **—:** no entra en los modelos.

Las 66 variables de `base$vars` entran en ambas matrices.

---

## 1. Identificador, objetivo y organización

| Variable | Definición | Fuente | Script | Modelos |
|---|---|---|---|---|
| `property_id` | Identificador del anuncio. Es la llave del envío a Kaggle | Properati | — | — |
| `price` | Precio de venta en pesos. Solo existe en el train y está acotado en [300, 1.650] millones | Properati | — | Objetivo |
| `log_precio` | `log(price)`. Los modelos predicen `log(price)` y luego aplican `exp` y recortan a [300, 1.650] M (D2) | Construida | 02 | Objetivo |
| `precio_m2` | `price / area`, solo para las descriptivas. Usa el área sin filtro de coherencia, así que tiene colas falsas | Construida | 02 | — |
| `muestra` | `"train"` o `"test"` | Construida | 02 | — |
| `fold` | Fold espacial de validación (1–5), por k-means sobre las coordenadas del train (en km). NA en el test (D1) | Construida | 03 | — |

## 2. Variables originales de Properati

| Variable | Definición | Faltantes (train) | Tratamiento | Modelos |
|---|---|---:|---|---|
| `city` | Ciudad. Siempre Bogotá D.C. | 0% | Constante, se ignora | — |
| `operation_type` | Tipo de operación. Siempre venta | 0% | Constante, se ignora | — |
| `property_type` | `Apartamento` o `Casa` | 0% | Se recodifica como `es_apto` | — |
| `month`, `year` | Mes y año del anuncio (abr-2019 a ago-2021) | 0% | Se usan directamente | L, Á |
| `lat`, `lon` | Coordenadas del anuncio (grados) | 0% | Se usan directamente | L, Á |
| `surface_total` | Área total en m² | 79,7% | Se combina en `sup_obs` | — |
| `surface_covered` | Área construida en m² | 77,8% | Se combina en `sup_obs` | — |
| `rooms` | Número de ambientes | 47% | **Descartada**: correlación de 0,99 con `bedrooms` (D5) | — |
| `bedrooms` | Número de habitaciones (0–11) | 0% | Se usa directamente. Ojo: 186 anuncios tienen 0 y 97 tienen 11 | L, Á |
| `bathrooms` | Número de baños | 26% | Se combina en `banos` | — |
| `title`, `description` | Título y descripción del anuncio | — | Fuente de todas las variables del texto | — |

## 3. Variables extraídas del texto

Los valores fuera del rango se vuelven NA. El porqué de cada rango está en la sección 7.1 del [informe de descriptivas](../reports/01_descriptivas/informe_descriptivas.md).

| Variable | Definición | Patrón (regex) | Rango válido | Script | Modelos |
|---|---|---|---|---|---|
| `area_txt` | Área en m² mencionada en el texto (primera coincidencia) | `NN(N)(N) m2 / mts / mt2 / metros / metros cuadrados` | 20–1.000 | 02 | — |
| `banos_txt` | Número de baños | `N bano(s)` | 1–8 | 02 | — |
| `estrato_txt` | Estrato socioeconómico | `estrato N` | 1–6 | 02 | — |
| `piso_txt` | Piso del apartamento | `piso N` / `nivel N` | 1–40, solo apartamentos | 03 | L, Á |
| `antig_txt` | Antigüedad en años | `N años de construido/antigüedad`, `antigüedad (de) N` | 0–60 | 03 | L, Á |
| `parq_txt` | Número de parqueaderos | `N parqueadero(s) / garaje(s)` | 1–6 | 03 | L, Á |
| `n_palabras` | Número de palabras de la descripción | — | — | 03 | L, Á |

`piso_txt`, `antig_txt` y `parq_txt` se dejan como NA cuando faltan. En la matriz lineal se imputan con la mediana del train y se agrega el indicador `na_<var>`. En la de árboles, NA pasa a −1 y también se agrega `na_<var>`.

### Amenidades (`tx_*`, 22 indicadores 0/1)

Valen 1 si el texto contiene el patrón. Fuente: Texto. Script: 02. Modelos: L, Á.

| Variable | Patrón | Variable | Patrón |
|---|---|---|---|
| `tx_parqueadero` | `parqueader\|garaje` | `tx_duplex` | `duplex` |
| `tx_ascensor` | `ascensor` | `tx_penthouse` | `penthouse\|pent house` |
| `tx_terraza` | `terraza` | `tx_remodelado` | `remodelad` |
| `tx_balcon` | `balcon` | `tx_estrenar` | `estrenar` |
| `tx_chimenea` | `chimenea` | `tx_vista` | `vista` |
| `tx_gimnasio` | `gimnasio\|gym` | `tx_bbq` | `bbq` |
| `tx_piscina` | `piscina` | `tx_conjunto` | `conjunto` |
| `tx_vigilancia` | `vigilancia\|porteria\|seguridad 24` | `tx_servicio` | `alcoba/cuarto de servicio` |
| `tx_deposito` | `deposito\|bodega` | `tx_walk_in` | `walk in` |
| `tx_estudio` | `estudio` | `tx_patio` | `patio` |
| `tx_jardin` | `jardin` | `tx_exterior` | `exterior` |

## 4. Atributos estructurales finales (con imputación)

| Variable | Definición | Fuente | Script | Modelos |
|---|---|---|---|---|
| `sup_obs` | `coalesce(surface_covered, surface_total)`, válida en 20–1.500 m² | Properati | 02 | — |
| `area` | `coalesce(sup_obs, area_txt)`. Es el área de las descriptivas, sin filtro de coherencia | Construida | 02 | — |
| `fuente_area` | Fuente de `area`: variable observada, texto o faltante | Construida | 02 | — |
| `area_pred` | Área predicha por un RF (R² OOB 0,83). Se entrena con `log(sup_obs)` y usa `bedrooms`, `es_apto`, `lat`, `lon`, `n_palabras`, `dist_cbd`, `tx_*` y baños (−1 si faltan) | Imputada (RF) | 03 | — |
| `area_final` | Jerarquía D3: `sup_obs`; si falta, `area_txt` cuando está entre 0,5 y 2 veces `area_pred`; si no, `area_pred` | Construida | 03 | — |
| `log_area` | `log(area_final)` | Construida | 03 | L, Á |
| `area_imputada` | 1 si `area_final` viene de `area_pred` | Construida | 03 | L, Á |
| `area_texto` | 1 si `area_final` viene del texto | Construida | 03 | L, Á |
| `banos` | `coalesce(bathrooms, banos_txt)` | Properati / Texto | 02 | — |
| `banos_final` | `banos`; si falta, un RF con `bedrooms`, `es_apto`, `log_area`, `lat`, `lon`, `n_palabras` y `dist_cbd`, redondeado a 1 decimal | Imputada (RF) | 03 | L, Á |
| `banos_imputado` | 1 si `banos_final` es imputado | Construida | 03 | L, Á |
| `estrato_pred` | Estrato predicho por un RF espacial (R² OOB 0,79) con `lat`, `lon`, coordenadas rotadas, `dist_cbd`, `dist_transmilenio`, `n500_restaurante_bar`, `n500_banco` y `es_apto` | Imputada (RF) | 03 | — |
| `estrato_final` | `coalesce(estrato_txt, estrato_pred)`. Es continua en la parte imputada (D4) | Construida | 03 | L, Á |
| `es_apto` | 1 si `property_type == "Apartamento"` | Construida | 03 | L, Á |

## 5. Ubicación

| Variable | Definición | Fuente | Script | Modelos |
|---|---|---|---|---|
| `localidad` | Localidad (19 urbanas), asignada por punto en polígono (`sp::point.in.polygon`) con relaciones de OSM de `admin_level=8`. Define los folds de validación; **no entra en ningún modelo** (D10) | OSM | 02 | — |
| `upz` | UPZ (111), asignada por punto en polígono con `admin_level=9` | OSM | 02 | — |
| `lat_rot1`, `lat_rot2` | `lat + lon` y `lat − lon`: coordenadas rotadas 45°, que ayudan a los árboles a hacer cortes diagonales | Construida | 03 | L, Á |

### Distancias y densidades de servicios

Para cada una de las 11 capas hay dos variables:

- `dist_<capa>`: distancia haversine en metros al elemento más cercano.
- `n500_<capa>`: número de elementos a menos de 500 m.

Las calcula el script 02 y todas entran en los modelos (L, Á). Los nodos, vías y relaciones de OSM (`nwr`) se reducen a un punto.

| `<capa>` | Etiqueta de OSM |
|---|---|
| `transmilenio` | `public_transport=station` y `network~TransMilenio` |
| `parque` | `leisure=park` |
| `centro_comercial` | `shop=mall` |
| `universidad` | `amenity=university` |
| `colegio` | `amenity=school` |
| `hospital` | `amenity~hospital\|clinic` |
| `restaurante_bar` | `amenity~restaurant\|bar\|cafe\|pub` |
| `supermercado` | `shop=supermarket` |
| `policia` | `amenity=police` |
| `gimnasio` | `leisure=fitness_centre` |
| `banco` | `amenity=bank` |

### Hitos de empleo (CBD)

Coordenadas fijadas a mano en el script 02. Fuente: Construida. Modelos: L, Á.

| Variable | Definición |
|---|---|
| `dist_centro_internacional` | Distancia en metros al Centro Internacional (4,6148; −74,0697) |
| `dist_calle72` | Distancia en metros a la Calle 72 (4,6573; −74,0585) |
| `dist_parque93` | Distancia en metros al Parque de la 93 (4,6766; −74,0484) |
| `dist_cbd` | Mínimo de las tres anteriores |

## 6. Variables que solo existen dentro de las matrices de modelación

Se crean al vuelo en [`utils_modelos.R`](../code/utils_modelos.R). No están guardadas en ninguna base.

| Variable | Definición | Matriz |
|---|---|---|
| `na_piso_txt`, `na_antig_txt`, `na_parq_txt` | Indicadores de faltante | L, Á |
| `<var>_2` | Cuadrado de `log_area`, `bedrooms`, `banos_final`, `estrato_final`, `dist_cbd`, `dist_transmilenio`, `lat` y `lon` | L |
| `log_area_x_apto`, `log_area_x_estrato`, `dist_cbd_x_apto` | Interacciones | L |

El híbrido (`07_hibridos.R`) usa además el margen del lasso como `base_margin` de XGBoost. No es una columna, sino un desplazamiento inicial de las predicciones.

## 7. Texto procesado (Python, D11)

Se generan con [`03c_texto.py`](../code/03c_texto.py) y [`03d_tfidf.py`](../code/03d_tfidf.py). Se unen a las demás bases por `property_id`.

| Archivo | Contenido |
|---|---|
| `data/processed/texto_limpio.csv` | `property_id`, `muestra`, `texto`. El texto es `title + description` después de: reparar tildes y ñ perdidas, quitar nombres de lugares, corregir errores de tipeo raros, lematizar, quitar stopwords (se conservan `sin` y `no`) y quitar palabras de menos de 3 letras |
| `data/processed/tfidf.parquet` | Formato largo y disperso: `property_id`, `termino` (unigrama o bigrama), `tfidf` (float32). Solo las celdas distintas de 0; vocabulario de hasta 5.000 términos presentes en al menos 20 anuncios |
| `data/external/lugares_texto.csv` | Nombres de lugares borrados del texto, con la regla que los capturó y cuántas veces aparecieron |
| `data/external/dict_lemas.json` | Lemas propios del dominio (unifica sinónimos: `garaje` → `parqueadero`, `alcoba` → `habitacion`) |
