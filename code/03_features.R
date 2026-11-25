# =============================================================================
# 03_features.R - Base de modelación: variables adicionales del texto, imputación
#                 de área / baños / estrato y grupos de validación (localidades).
# Entradas: data/processed/base_enriquecida.csv (de 02_descriptivas.R)
# Salidas:  data/processed/base_modelo.rds  (lista: datos, vars, dist_loc)
# =============================================================================
source(here::here("code", "01_setup.R"))

d <- lee_csv(file.path(P$processed, "base_enriquecida.csv"))
d <- d %>% mutate(txt = str_to_lower(paste(title, description)))

# ---- 1. Variables adicionales del texto ----
d <- d %>% mutate(
  n_palabras   = str_count(coalesce(description, ""), "\\S+"),
  piso_txt     = num_txt(txt, PATRONES$piso),
  piso_txt     = if_else(property_type == "Apartamento" & between(piso_txt, 1, 40), piso_txt, NA_real_),
  antig_txt    = coalesce(num_txt(txt, PATRONES$antig), num_txt(txt, PATRONES$antig2)),
  antig_txt    = if_else(between(antig_txt, 0, 60), antig_txt, NA_real_),
  parq_txt     = num_txt(txt, PATRONES$parq),
  parq_txt     = if_else(between(parq_txt, 1, 6), parq_txt, NA_real_),
  es_apto      = as.integer(property_type == "Apartamento"),
  lat_rot1     = lat + lon, lat_rot2 = lat - lon   # coordenadas rotadas: ayudan a los árboles
)

# ---- 2. Imputación del área (log) con random forest ----
# Se entrena solo con el área observada en las variables originales (más confiable que la del texto).
# Usar las filas de test aquí NO es fuga: el área es una covariable, no el precio.
pred_area_vars <- c("bedrooms", "es_apto", "lat", "lon", "n_palabras", "dist_cbd",
                    grep("^tx_", names(d), value = TRUE))
d$banos_aux <- coalesce(d$banos, -1)
f_area <- as.formula(paste("log(sup_obs) ~", paste(c(pred_area_vars, "banos_aux"), collapse = " + ")))
rf_area <- ranger(f_area, data = filter(d, !is.na(sup_obs)), num.trees = 300, num.threads = 8, seed = 123)
cat("Imputación área - R2 OOB:", round(rf_area$r.squared, 3), "\n")
d$area_pred <- exp(predict(rf_area, d, num.threads = 8)$predictions)

# El área del texto se acepta solo si es coherente con la predicción (entre 0,5x y 2x)
d <- d %>% mutate(
  ratio_txt  = area_txt / area_pred,
  area_final = case_when(!is.na(sup_obs) ~ sup_obs,
                         !is.na(area_txt) & between(ratio_txt, .5, 2) ~ area_txt,
                         TRUE ~ area_pred),
  area_fuente = case_when(!is.na(sup_obs) ~ "observada",
                          !is.na(area_txt) & between(ratio_txt, .5, 2) ~ "texto", TRUE ~ "imputada"),
  area_imputada = as.integer(area_fuente == "imputada"),
  area_texto    = as.integer(area_fuente == "texto"),
  log_area   = log(area_final))
print(count(d, muestra, area_fuente) %>% group_by(muestra) %>% mutate(p = round(n / sum(n), 3)))

# ---- 3. Imputación de baños ----
rf_banos <- ranger(banos ~ bedrooms + es_apto + log_area + lat + lon + n_palabras + dist_cbd,
                   data = filter(d, !is.na(banos)), num.trees = 200, num.threads = 8, seed = 123)
d <- d %>% mutate(banos_imputado = as.integer(is.na(banos)),
                  banos_final = if_else(is.na(banos), round(predict(rf_banos, d, num.threads = 8)$predictions, 1), banos))

# ---- 4. Imputación del estrato (proxy espacial del nivel socioeconómico) ----
# El estrato es fundamentalmente espacial: se predice con coordenadas y entorno, entrenando con las ~3.800 menciones.
f_est <- estrato_txt ~ lat + lon + lat_rot1 + lat_rot2 + dist_cbd + dist_transmilenio + n500_restaurante_bar + n500_banco + es_apto
rf_est <- ranger(f_est, data = filter(d, !is.na(estrato_txt)), num.trees = 300, num.threads = 8, seed = 123)
cat("Imputación estrato - R2 OOB:", round(rf_est$r.squared, 3), "\n")
d$estrato_pred <- predict(rf_est, d, num.threads = 8)$predictions
d$estrato_final <- coalesce(d$estrato_txt, d$estrato_pred)
print(d %>% group_by(muestra, chap = localidad %in% "Chapinero") %>% summarise(estrato_medio = mean(estrato_final), .groups = "drop"))

# ---- 5. Grupos de validación: una localidad por fold (D9) ----
# El único anuncio del train sin localidad (fuera de los polígonos) toma la de su vecino más cercano.
tr_idx <- which(d$muestra == "train")
d$grupo <- d$localidad
sin <- tr_idx[is.na(d$grupo[tr_idx])]; con <- setdiff(tr_idx, sin)
for (i in sin) d$grupo[i] <- d$grupo[con][which.min(hav(d$lat[i], d$lon[i], d$lat[con], d$lon[con]))]
d$grupo[-tr_idx] <- NA
print(count(d[tr_idx, ], grupo, sort = TRUE), n = 25)

# Distancia (m) de cada anuncio del train al anuncio más cercano de cada localidad (0 en la suya).
# Con esto, los folds con buffer se arman al instante para cualquier distancia (utils_modelos.R).
grupos <- sort(unique(d$grupo[tr_idx]))
dist_loc <- sapply(grupos, function(g) { j <- tr_idx[d$grupo[tr_idx] == g]; dist_min(d$lat[tr_idx], d$lon[tr_idx], d$lat[j], d$lon[j]) })

# ---- 6. Conjunto de variables para los modelos ----
vars_num <- c("log_area", "area_imputada", "area_texto", "bedrooms", "banos_final", "banos_imputado", "es_apto",
              "estrato_final", "piso_txt", "antig_txt", "parq_txt", "n_palabras",
              "lat", "lon", "lat_rot1", "lat_rot2", "year", "month",
              grep("^dist_", names(d), value = TRUE), grep("^n500_", names(d), value = TRUE),
              "area_verde500", "pisos_prom500",                         # contexto (D15)
              grep("^tx_", names(d), value = TRUE))
base <- list(datos = select(d, property_id, muestra, price, localidad, upz, grupo, all_of(vars_num)),
             vars = vars_num, dist_loc = dist_loc)
saveRDS(base, file.path(P$processed, "base_modelo.rds"))
cat("Variables:", length(vars_num), " | NA restantes (se tratan en cada modelo):\n")
print(sort(colSums(is.na(base$datos[vars_num])))[colSums(is.na(base$datos[vars_num])) > 0])
cat("Listo.\n")
