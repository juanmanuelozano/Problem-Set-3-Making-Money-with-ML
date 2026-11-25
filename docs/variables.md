# Variables de los modelos

Variables de los modelos finales: **m24** (NN STAR) y **m48** (m24 combinado con el XGB STAR m47). La **categoría** es el grupo del STAR. Las variables de un grupo pueden interactuar entre sí, pero nunca con las de otro grupo; la predicción es la suma de los tres (o cuatro) componentes.

**Objetivo:** log del precio por m². En la red, `log_area` sale de las entradas y queda como *offset*. En el XGB STAR (m43, m47) entra como variable de estructura, así que la elasticidad precio-área no queda fija en 1.

## Fuentes

| Fuente | Qué aporta | Script |
|---|---|---|
| **Properati** (anuncio) | Precio, área, habitaciones, baños, tipo, fecha, coordenadas, título y descripción | `data/raw/` |
| **Texto del anuncio** (expresiones regulares) | Piso, antigüedad, parqueaderos, estrato, área y 32 amenidades | `02_descriptivas.R`, `03_features.R` |
| **Imputación** (random forest) | Área, baños y estrato cuando faltan | `03_features.R` |
| **OpenStreetMap** | Distancias y conteos a 500 m de puntos de interés | `01b_osm_descarga.R`, `02_descriptivas.R` |
| **Catastro de Bogotá** (UAECD, SDP) | Valor de referencia del suelo y estrato oficial por manzana | `03f_catastro.R` |
| **Train** (vecinos) | Precio por m² de los anuncios más cercanos | `utils_comparables.R` |
| **Texto procesado** | 1.000 términos TF-IDF (lematizados, sin nombres de lugares) | `03c_texto.py`, `03d_tfidf.py` |

## Estructura (rama lineal en la red; un grupo por variable en el XGB STAR)

| Variable | Descripción | Fuente |
|---|---|---|
| `log_area` | Log del área (m²). Fuera de la red, dentro del XGB (m43, m47) | Properati → texto → imputada |
| `area_imputada`, `area_texto` | Indicadores de dónde salió el área | Construida |
| `bedrooms` | Habitaciones | Properati |
| `banos_final`, `banos_imputado` | Baños (imputados si faltan) e indicador | Properati + imputación |
| `es_apto` | Apartamento (1) o casa (0) | Properati |
| `piso_txt` | Piso del apartamento (1–40) | Texto |
| `antig_txt` | Antigüedad en años (0–60) | Texto |
| `parq_txt` | Número de parqueaderos (1–6) | Texto |
| `n_palabras` | Largo de la descripción | Texto |
| `year`, `month` | Fecha del anuncio | Properati |
| `tx_*` (32) | Amenidades: ascensor, terraza, balcón, chimenea, gimnasio, piscina, vigilancia, depósito, estudio, dúplex, penthouse, remodelado, para estrenar, vista, BBQ, conjunto, cuarto de servicio, *walk-in closet*, patio, jardín, exterior, parqueadero de visitantes, parque infantil, salón comunal, zonas verdes, terraza comunal, turco o sauna, squash, planta eléctrica, *club house*, jacuzzi, parqueadero | Texto |

## Ubicación (rama profunda + atajo lineal en la red; un solo grupo en el XGB STAR)

| Variable | Descripción | Fuente |
|---|---|---|
| `lat`, `lon`, `lat_rot1`, `lat_rot2` | Coordenadas y coordenadas rotadas (lat ± lon) | Properati |
| `estrato_final` | Estrato **oficial de la manzana**; si no hay, el del texto o el imputado | Catastro (SDP) → texto → imputado |
| `log_v_ref` | Log del valor de referencia del suelo por m² de la manzana (2026) | Catastro (UAECD) |
| `dist_cbd` | Distancia al CBD más cercano (Centro Internacional, calle 72 o parque 93) | OSM |
| `dist_*` (14) | Distancia a TransMilenio, parque, centro comercial, universidad, colegio, hospital, restaurante o bar, supermercado, policía, gimnasio, banco y a cada CBD (Centro Internacional, calle 72, parque 93) | OSM |
| `n500_*` (11) | Número de esos lugares a menos de 500 m | OSM |
| `comp5`, `comp20` | Log del precio por m² de los 5 y 20 vecinos del train del mismo tipo. Solo en m32, m38, m43 y m47 | Train (vecinos) |
| `comp_logdist5`, `comp_logdist20` | Distancia media a esos vecinos | Train (vecinos) |

## Texto (rama profunda + atajo lineal en la red; un solo grupo en el XGB STAR)

| Variable | Descripción | Fuente |
|---|---|---|
| `tf_*` (1.000) | Pesos TF-IDF de los 1.000 términos más frecuentes (palabras y bigramas), sin nombres de lugares (D10) | Título y descripción |

## Variables que se dejaron por fuera (y por qué)

| Variables | Motivo |
|---|---|
| Distancias y conteos de embajadas, oficinas, hoteles y clubes | Se concentran en Chapinero y Usaquén; al dejar Chapinero afuera no se transfieren y empeoran la predicción (D15, D19) |
| Cerros, vías principales, área verde y altura de los edificios a 500 m (contexto de OSM) | Restaban un poco en las redes (ablación de 08e) |
| Dummies de localidad | La localidad solo define los folds de validación (D10) |
| Pisos, sótanos y huella del edificio (catastro, `03h`) | Probados en m34: no mejoraron |
| Embeddings de oraciones (`03g`) | Probados en m35: no mejoraron en conjunto |
