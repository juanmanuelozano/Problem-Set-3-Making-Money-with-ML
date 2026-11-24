# =============================================================================
# 03h_construcciones.R - Características del edificio y de la manzana desde el catastro (UAECD, Datos Abiertos), D24
# Del anuncio solo se sabe el piso y la antigüedad cuando el texto los menciona; el catastro trae, para cada edificio,
# el número de pisos, sótanos, semisótano y área de la huella (CONALTURA no es la altura en metros: su mediana es
# negativa; se descarta). En Chapinero una torre nueva y una casa vieja en
# la misma manzana valen muy distinto, y eso no lo ven ni el valor del suelo por manzana (03f) ni las coordenadas.
#  - Edificio (capa Construcción, 10/2026): el que contiene al anuncio; si cae fuera (vía, andén, geocodificación al
#    frente), el más cercano a menos de 30 m; si no hay, NA (la red imputa la mediana y agrega el indicador).
#  - Manzana (capa Número de pisos ponderado por manzana, 2026; campo altura): la que contiene al anuncio o la más cercana.
# Las variables del edificio van a la rama de estructura; los pisos de la manzana, a la de ubicación (utils_redes.R).
# Descarga (una vez, desde la raíz; no está en git por tamaño; el .zip de construcciones se puede borrar después):
#   https://datosabiertos.bogota.gov.co/dataset/397ccbd8-e2c5-4700-b90e-b68d101ab0c5/resource/2e619105-f07a-45c9-944b-ecc8ee206ef1/download/const.gpkg.10.26.zip
#   https://datosabiertos.bogota.gov.co/dataset/780d9d1d-bafa-4956-8cdc-eda5063e72b2/resource/c6825a12-2252-418c-ae75-14f7d78c0e31/download/pisos2026.zip
#   descomprimir en data/external/catastro/construccion/ y data/external/catastro/pisos/
# Salida: data/processed/construcciones.csv
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(sf))
sf_use_s2(FALSE)

dir_c <- file.path("data", "external", "catastro")
pts <- st_as_sf(select(D, property_id, lat, lon), coords = c("lon", "lat"), crs = 4326) %>% st_transform(3116)   # metros

# ---- Edificio ----
f_gpkg <- list.files(file.path(dir_c, "construccion"), pattern = "gpkg$", recursive = TRUE, full.names = TRUE)[1]
crs_c <- st_layers(f_gpkg)$crs[[1]]   # se leen solo las construcciones dentro del rectángulo de los anuncios
caja <- st_as_text(st_as_sfc(st_bbox(st_transform(st_buffer(st_as_sfc(st_bbox(pts)), 100), crs_c))))
cons <- st_read(f_gpkg, quiet = TRUE, wkt_filter = caja) %>%
  st_transform(3116) %>% st_make_valid() %>% transmute(edif_pisos = CONNPISOS, edif_sotanos = CONNSOTANO, edif_semisotano = CONTSEMIS,
                                                         edif_huella = as.numeric(st_area(.)))
paso <- function(msg) cat(sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), msg))
paso(sprintf("Construcciones leídas: %d", nrow(cons)))
dentro <- st_join(pts, cons, join = st_within) %>% st_drop_geometry() %>% distinct(property_id, .keep_all = TRUE)
falta <- is.na(dentro$edif_pisos); k <- st_nearest_feature(pts[falta, ], cons)
dist <- as.numeric(st_distance(pts[falta, ], cons[k, ], by_element = TRUE))
cerca <- st_drop_geometry(cons[k, ]); cerca[dist > 30, ] <- NA
dentro[falta, names(cerca)] <- cerca
dentro$edif_dist <- 0; dentro$edif_dist[falta] <- pmin(dist, 30)
paso(sprintf("Edificio: dentro %.0f%% | a <30 m %.0f%% | sin edificio %.0f%%", 100 * mean(!falta), 100 * sum(dist <= 30) / length(falta), 100 * sum(dist > 30) / length(falta)))

# ---- Manzana: pisos ponderados ----
pis <- st_read(file.path(dir_c, "pisos", "pisos2026.shp"), quiet = TRUE) %>% st_transform(3116) %>% st_make_valid() %>% select(pisos_manzana = altura)
jm <- st_join(pts, pis, join = st_within) %>% st_drop_geometry() %>% distinct(property_id, .keep_all = TRUE)
fm <- is.na(jm$pisos_manzana); jm$pisos_manzana[fm] <- pis$pisos_manzana[st_nearest_feature(pts[fm, ], pis)]

out <- dentro %>% left_join(jm, by = "property_id") %>%
  mutate(log_edif_huella = log1p(edif_huella), across(c(edif_semisotano), ~ as.numeric(.x > 0))) %>%
  select(property_id, edif_pisos, edif_sotanos, edif_semisotano, log_edif_huella, edif_dist, pisos_manzana)
stopifnot(nrow(out) == nrow(D), setequal(out$property_id, D$property_id))
write_csv(out, file.path(P$processed, "construcciones.csv"))
m <- match(out$property_id, D$property_id)
print(out %>% mutate(muestra = D$muestra[m], chap = D$localidad[m] %in% "Chapinero") %>% group_by(muestra, chap) %>%
        summarise(n = n(), pisos = median(edif_pisos, na.rm = TRUE), sotanos = mean(edif_sotanos > 0, na.rm = TRUE),
                  huella = median(exp(log_edif_huella), na.rm = TRUE), pisos_manzana = median(pisos_manzana), sin_edif = mean(is.na(edif_pisos)), .groups = "drop"))
paso("Listo: data/processed/construcciones.csv")
