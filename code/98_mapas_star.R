# =============================================================================
# 98_mapas_star.R - Componente de ubicación de los dos modelos de la
# combinación STAR final (moraleja 2, presentación)
# m48_star_nn_xgbsq_area_m2 (Kaggle 153,3) = 60% NN STAR m24 + 40% XGB STAR
# m47, promedio en log. Los dos son aditivos por grupos, así que su componente
# de ubicación es una función exacta de las variables de ubicación (Mayer et
# al., 2022, figura 11): se puede pintar sobre el mapa.
#  - NN STAR m24: salida de la rama de ubicación (coordenadas, estrato,
#    catastro), configuración de 96_texto_modelos.R.
#  - XGB STAR m47: suma de las contribuciones TreeSHAP del grupo de ubicación
#    (coordenadas, estrato, catastro y comparables), configuración de 08p con
#    VARIANTE=area_sq y 2.800 rondas.
# Las dos componentes se centran con la media del train y están en
# log(precio por m2).
# Salida: output/tables/03_presentacion/mapas_ubicacion.csv (la grafica 95)
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))
source(here::here("code", "utils_redes.R"))
source(here::here("code", "utils_comparables.R"))

tp <- lee_csv(file.path(P$models, "test_predicciones.csv"))
repro <- \(p, m) cor(p, tp[[m]][match(TE$property_id, tp$property_id)])

# ---- NN STAR m24 ----
usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = "valor_estrato")
f <- ajusta_final(
  tibble(objetivo = "m2", epocas = 3), \(g, d) red_star(d, .1, .5), 1e-3, "mse"
)
rama <- \(x) drop(predict(f$red$ramas, x, batch_size = 8192, verbose = 0)[[2]])
nn <- c(rama(f$xtr), rama(f$xte))
cat(sprintf(
  "NN STAR: correlación con el test de m24 %.3f\n",
  repro(f$pred_te, "m24_nn_star_catastro_m2")
))

# ---- XGB STAR m47 (como 08p, VARIANTE=area_sq) ----
base$vars <- vars_sin(FALSE)
ct <- lee_csv(file.path(P$processed, "catastro.csv"))
k <- match(D$property_id, ct$property_id)
stopifnot(!anyNA(k))
D$log_v_ref <- ct$log_v_ref[k]
D$estrato_final <- ifelse(ct$estrato_oficial[k] > 0, ct$estrato_oficial[k], D$estrato_final)
TR <- filter(D, muestra == "train")
TE <- filter(D, muestra == "test")
base$vars <- c(base$vars, "log_v_ref")

Xt <- readRDS(file.path(P$processed, "base_texto.rds"))
Xt <- Xt[, order(-colSums(Xt != 0))[1:1000]]
colnames(Xt) <- paste0("tf_", colnames(Xt))
mat <- function(df) {
  cbind(Matrix(matriz_arboles(df), sparse = TRUE), Xt[match(df$property_id, rownames(Xt)), ])
}
o <- arma_objetivos(mat(TR), mat(TE), quita_area = FALSE)$m2
CMP <- prepara_comparables(k_max = 60)
CMP$r_tr <- rep(0, nrow(TR))
Xtr <- cbind(o$Xtr, comparables_train(CMP))
Xte <- cbind(o$Xte, comparables_test(CMP))
cn <- colnames(Xtr)

es_loc <- function(cn) {
  cn %in% c("lat", "lon", "lat_rot1", "lat_rot2", "estrato_final", "log_v_ref") |
    grepl("^(dist|n500)_", cn) | grepl("500$", cn) | startsWith(cn, "comp")
}
es_txt <- function(cn) startsWith(cn, "tf_")
i <- seq_along(cn) - 1L
pr <- list(
  objective = "reg:squarederror", max_bin = 64, nthread = 8, seed = 123,
  interaction_constraints = c(
    as.list(i[!es_loc(cn) & !es_txt(cn)]), list(i[es_loc(cn)], i[es_txt(cn)])
  ),
  max_depth = 4, min_child_weight = 3, subsample = .8, colsample_bytree = .7,
  lambda = 1, alpha = 0, eta = .05
)
fit <- xgb.train(
  params = pr, data = xgb.DMatrix(Xtr, label = o$y, nthread = 8),
  nrounds = 2800, verbose = 0
)
cat(sprintf(
  "XGB STAR: correlación con el test de m47 %.3f\n",
  repro(predict(fit, xgb.DMatrix(Xte)) + o$off_te, "m47_xgb_star_comparables_area_sq_m2")
))
ubi_x <- function(X) {
  cb <- predict(fit, xgb.DMatrix(X), predcontrib = TRUE)
  rowSums(cb[, es_loc(colnames(cb)), drop = FALSE])
}
xg <- c(ubi_x(Xtr), ubi_x(Xte))

# ---- Salida ----
tr <- seq_len(nrow(TR))
out <- tibble(
  property_id = c(TR$property_id, TE$property_id),
  muestra = rep(c("train", "test"), c(nrow(TR), nrow(TE))),
  lat = c(TR$lat, TE$lat), lon = c(TR$lon, TE$lon),
  nn = nn - mean(nn[tr]), xgb = xg - mean(xg[tr])
)
cat(sprintf(
  "Desv. est. de la ubicación (log): NN %.3f | XGB %.3f | correlación %.2f\n",
  sd(out$nn), sd(out$xgb), cor(out$nn, out$xgb)
))
write_csv(out, file.path(P$tab_pres, "mapas_ubicacion.csv"))
