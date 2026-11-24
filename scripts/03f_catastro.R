# =============================================================================
# 03f_catastro.R - Variables catastrales por manzana (Datos Abiertos Bogotá), D18
#  - Valor de referencia del terreno por m2, 2026 (UAECD: "Mediana del valor comercial por metro cuadrado de terreno
#    por manzana"; campo V_REF, en pesos por m2 de terreno). Cubre todo Bogotá, incluido Chapinero, y no se aprende del
#    train: da al modelo el NIVEL de precio de la manzana, que es lo que no logra extrapolar.
#  - Estrato oficial por manzana (SDP, decreto 532 de 2025; campo ESTRATO, 0 = sin estrato).
# Asignación: la manzana que contiene al anuncio; si cae en vía o andén, la manzana más cercana (mediana 5 m).
# Descarga (una vez, desde la raíz; no está en git por tamaño):
#   https://datosabiertos.bogota.gov.co/dataset/a0ad3bf4-1e97-4cf9-b853-76558158036f/resource/a98d3bf3-46d0-4b26-8c3d-d6102e6e57f0/download/valor_ref_2026.zip
#   https://datosabiertos.bogota.gov.co/dataset/55467552-0af4-4524-a390-a2956035744e/resource/63dfac38-e729-4c7c-9935-fece39f176ea/download/manzanaestratificacion.zip
#   descomprimir en data/external/catastro/valor_ref_2026/ y data/external/catastro/estratificacion/
# Salida: data/processed/catastro.csv (property_id, v_ref, log_v_ref, estrato_oficial, catastro_cercana)
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(sf))
sf_use_s2(FALSE)

dir_c <- file.path("data", "external", "catastro")
v <- st_read(file.path(dir_c, "valor_ref_2026", "SHP_Valor_Ref_2026", "Valor_Ref_M_2026.shp"), quiet = TRUE) %>% st_make_valid()
e <- st_read(file.path(dir_c, "estratificacion", "ManzanaEstratificacion.shp"), quiet = TRUE) %>% st_transform(4326) %>% st_make_valid()
pts <- st_as_sf(select(D, property_id, lat, lon), coords = c("lon", "lat"), crs = 4326)

# Manzana que contiene al punto; si no hay (vía, andén), la más cercana
asigna <- function(capa, campo) {
  j <- st_join(pts, capa[campo], join = st_within) %>% st_drop_geometry() %>% distinct(property_id, .keep_all = TRUE)
  fuera <- which(is.na(j[[campo]]))
  if (length(fuera)) j[[campo]][fuera] <- capa[[campo]][st_nearest_feature(pts[fuera, ], capa)]
  list(valor = j[[campo]], cercana = seq_len(nrow(j)) %in% fuera)
}
vr <- asigna(v, "V_REF"); es <- asigna(e, "ESTRATO")
cat <- tibble(property_id = D$property_id, v_ref = vr$valor, log_v_ref = log(vr$valor),
              estrato_oficial = es$valor, catastro_cercana = as.integer(vr$cercana))
stopifnot(nrow(cat) == nrow(D), !anyNA(cat$v_ref), !anyNA(cat$estrato_oficial))
write_csv(cat, file.path(P$processed, "catastro.csv"))
cat(sprintf("Anuncios: %d | dentro de una manzana: %.1f%% | V_REF mediana %.2f M/m2\n", nrow(cat),
            100 * mean(!vr$cercana), median(cat$v_ref) / 1e6))
