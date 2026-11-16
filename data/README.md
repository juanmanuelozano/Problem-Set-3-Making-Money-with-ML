# Datos

| Carpeta | Contenido | ¿Se edita? |
|---|---|---|
| `raw/` | `train.csv` (38.644), `test.csv` (10.286), `submission_template.csv`, tal como se descargaron de Kaggle | **No** |
| `external/osm/` | Respuestas de la API Overpass (`*.json`, en caché) y sus versiones tabulares: `localidades_poligonos.csv` (19 localidades), `upz_poligonos.csv` (111 UPZ), `servicios_puntos.csv` (11 capas de servicios) | Se regenera con `scripts/01_osm_descarga.R` |
| `processed/` | `base_enriquecida.csv` (datos + texto + localidad/UPZ + distancias, de `02_descriptivas.R`); `base_modelo.rds` (variables finales, imputaciones y folds espaciales, de `03_features.R`) | Se regenera con los scripts |

## Diccionario de las variables construidas (principales)

| Variable | Descripción |
|---|---|
| `area_final`, `log_area` | Área en m²: observada (`surface_covered` o `surface_total`) → extraída del texto si es coherente (0,5–2 veces la predicción) → imputada con random forest |
| `area_imputada`, `area_texto` | Indicadores de la fuente del área |
| `banos_final`, `banos_imputado` | Baños: observados → texto → imputados con random forest |
| `estrato_final` | Estrato mencionado en el texto; si no aparece, predicción espacial con random forest (R² OOB 0,79) |
| `piso_txt`, `antig_txt`, `parq_txt` | Piso (solo apartamentos), antigüedad en años y número de parqueaderos, extraídos del texto (NA si no aparece) |
| `tx_*` | 22 indicadores de mención de amenidades en el título o la descripción |
| `localidad`, `upz` | Localidad y UPZ (punto en polígono de OSM) |
| `dist_<capa>` | Distancia en metros al servicio más cercano de cada capa de OSM |
| `n500_<capa>` | Número de servicios de la capa a menos de 500 m |
| `dist_cbd` | Distancia al más cercano de: Centro Internacional, Calle 72 y Parque de la 93 |
| `lat_rot1`, `lat_rot2` | Coordenadas rotadas 45° (lat ± lon), útiles para los árboles |
| `fold` | Fold espacial (1–5, k-means sobre coordenadas del train) |
