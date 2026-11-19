# Datos

| Carpeta | Contenido | ¿Se edita? |
|---|---|---|
| `raw/` | `train.csv` (38.644), `test.csv` (10.286), `submission_template.csv`, tal como se descargaron de Kaggle | **No** |
| `external/osm/` | Respuestas de la API Overpass (`*.json`, en caché) y sus versiones tabulares: `localidades_poligonos.csv` (19 localidades), `upz_poligonos.csv` (111 UPZ), `servicios_puntos.csv` (11 capas de servicios) | Se regenera con `scripts/01_osm_descarga.R` |
| `processed/` | `base_enriquecida.csv` (datos + texto + localidad/UPZ + distancias, de `02_descriptivas.R`); `base_modelo.rds` (variables finales, imputaciones y folds espaciales, de `03_features.R`) | Se regenera con los scripts |

## Diccionario de variables

Ver [`docs/guia_variables.md`](../docs/guia_variables.md): nombres, definiciones, fuentes, script de origen y uso en los modelos.
