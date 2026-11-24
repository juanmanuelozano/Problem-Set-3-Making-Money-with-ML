# =============================================================================
# utils_modelos.R - Funciones comunes para entrenar, evaluar y registrar modelos
# Uso: source("scripts/00_config.R"); source("scripts/utils_modelos.R")
# =============================================================================
base <- readRDS(file.path(P$processed, "base_modelo.rds"))
D  <- base$datos
TR <- D %>% filter(muestra == "train")
TE <- D %>% filter(muestra == "test")
Y  <- log(TR$price)
GRUPO <- TR$grupo   # localidad usada como fold de validación
ES_CHAP <- TR$localidad %in% "Chapinero"

# ---- Validación: dejar una localidad afuera, con buffer (D9) ----
# Equivale a spatialsample::spatial_leave_location_out_cv(group = localidad, buffer = b): cada localidad es un
# fold de evaluación, y del conjunto de análisis se quitan los anuncios a menos de b metros de algún anuncio evaluado.
BUFFER_M <- 500
folds_localidad <- function(buffer = BUFFER_M) {
  map(set_names(colnames(base$dist_loc)), function(g)
    list(analisis = which(GRUPO != g & base$dist_loc[, g] >= buffer), evaluacion = which(GRUPO == g)))
}
FOLDS <- folds_localidad()

# Validación cruzada genérica, para cualquier modelo. ajusta_predice(analisis, evaluacion) recibe índices de filas
# del train, ajusta con `analisis` y devuelve predicciones (en log) para `evaluacion`: un vector o una matriz con
# una columna por hiperparámetro (todo el camino de lambda, varias rondas de boosting...). Devuelve las OOF.
cv_oof <- function(ajusta_predice, folds = FOLDS) {
  pred <- NULL
  for (f in folds) {
    q <- as.matrix(ajusta_predice(f$analisis, f$evaluacion))
    if (is.null(pred)) pred <- matrix(NA_real_, length(Y), ncol(q), dimnames = list(NULL, colnames(q)))
    pred[f$evaluacion, ] <- q
  }
  if (ncol(pred) == 1) pred[, 1] else pred
}
# Coeficientes OLS (con intercepto) ajustados en las filas `a` de X; los coeficientes no identificados quedan en 0
ols_coef <- function(X, a, y = Y) { b <- lm.fit(cbind(1, X[a, , drop = FALSE]), y[a])$coefficients; b[is.na(b)] <- 0; b }

# Columna de una matriz de predicciones OOF con menor MAE total (elige lambda, rondas, etc.). Con pesos `w` (que
# suman 1, p. ej. los de TWCV de 91_validacion_sintetica.R, D16), elige por MAE ponderado.
mejor_columna <- function(pred, w = NULL) which.min(apply(pred, 2, function(p)
  if (is.null(w)) evalua(p)$mae_total else sum(w * abs(exp(Y) - recorta(exp(p))))))

# XGBoost: ajusta max(rondas) rondas y predice con las primeras r rondas para cada r -> matriz (columna = r).
# Reemplaza el early stopping de xgb.cv, que no admite buffer; las rondas se eligen con mejor_columna().
xgb_rondas <- function(pr, Xa, ya, Xe, rondas, ma = NULL, me = NULL) {
  fit <- xgb.train(params = pr, data = xgb.DMatrix(Xa, label = ya, base_margin = ma, nthread = pr$nthread),
                   nrounds = max(rondas), verbose = 0)
  de <- xgb.DMatrix(Xe, base_margin = me, nthread = pr$nthread)
  `colnames<-`(sapply(rondas, function(r) predict(fit, de, iterationrange = c(1, r))), rondas)
}

# Matriz para árboles: NA -> -1 más indicador de faltante
matriz_arboles <- function(df, vars = base$vars) {
  na <- sapply(c("piso_txt", "antig_txt", "parq_txt"), \(v) as.integer(is.na(df[[v]])))
  X <- cbind(as.matrix(df[vars]), `colnames<-`(na, paste0("na_", colnames(na))))
  X[is.na(X)] <- -1
  X
}

# Matriz lineal: imputación por mediana del train + indicadores y términos cuadráticos.
# Sin dummies de localidad (D10): con la validación por localidad no se pueden estimar para la localidad evaluada.
matriz_lineal <- function(df, ref = TR, vars = base$vars) {
  X <- df[vars]
  for (v in c("piso_txt", "antig_txt", "parq_txt")) {
    X[[paste0("na_", v)]] <- as.integer(is.na(X[[v]]))
    X[[v]][is.na(X[[v]])] <- median(ref[[v]], na.rm = TRUE)
  }
  for (v in c("log_area", "bedrooms", "banos_final", "estrato_final", "dist_cbd", "dist_transmilenio", "lat", "lon"))
    X[[paste0(v, "_2")]] <- X[[v]]^2
  X$log_area_x_apto <- X$log_area * X$es_apto
  X$log_area_x_estrato <- X$log_area * X$estrato_final
  X$dist_cbd_x_apto <- X$dist_cbd * X$es_apto
  as.matrix(X)
}

# Habitaciones × distancia (km) a cada CBD; se pegan a matriz_lineal() en las regresiones (04, 04b)
interacciones <- function(df) {
  h <- c("centro_internacional", "calle72", "parque93")
  `colnames<-`(sapply(h, \(x) df$bedrooms * df[[paste0("dist_", x)]] / 1000), paste0("bedrooms_x_dist_", h))
}

# Dos objetivos: log(precio) y log(precio por m2). En el de m2 se quitan las columnas de área (salvo quita_area = FALSE)
# y el precio se recupera sumando log(área): off_tr / off_te se suman a la predicción (04, 04b, 05b, 07).
arma_objetivos <- function(Xtr, Xte, quita_area = TRUE) {
  k <- !(quita_area & grepl("log_area", colnames(Xtr)))
  list(precio = list(Xtr = Xtr, Xte = Xte, y = Y, off_tr = 0, off_te = 0),
       m2     = list(Xtr = Xtr[, k], Xte = Xte[, k], y = Y - TR$log_area, off_tr = TR$log_area, off_te = TE$log_area))
}

# Métricas sobre predicciones out-of-fold (en log) -> MAE en pesos con recorte al soporte
evalua <- function(pred_log, y_log = Y) {
  p <- recorta(exp(pred_log)); y <- exp(y_log)
  tibble(mae_total = mae(y, p), mae_chapinero = mae(y[ES_CHAP], p[ES_CHAP]),
         mae_macro = mean(tapply(abs(y - p), GRUPO, mean)),   # promedio simple entre localidades
         mape_chapinero = mean(abs(y[ES_CHAP] - p[ES_CHAP]) / y[ES_CHAP]))
}

# Registro acumulado de modelos (un renglón por modelo y versión)
registra <- function(nombre, descripcion, params, metr, pred_oof_log, pred_test_log) {
  reg_f <- file.path(P$models, "registro_modelos.csv")
  metr <- select(metr, any_of(c("mae_total", "mae_chapinero", "mae_macro", "mape_chapinero")))
  fila <- tibble(fecha = as.character(Sys.Date()), modelo = nombre, descripcion = descripcion, params = params) %>% bind_cols(metr)
  reg <- if (file.exists(reg_f)) read_csv(reg_f, col_types = cols(.default = "c"), num_threads = 1) %>%
    mutate(across(starts_with("ma"), as.numeric)) %>% filter(modelo != nombre) else NULL
  write_csv(bind_rows(reg, fila), reg_f)
  # predicciones out-of-fold (para ensamblar) y envío a Kaggle
  oof_f <- file.path(P$models, "oof_predicciones.csv")
  oof <- if (file.exists(oof_f)) lee_csv(oof_f) else tibble(property_id = TR$property_id, log_price = Y, grupo = GRUPO, chapinero = ES_CHAP)
  oof[[nombre]] <- pred_oof_log; write_csv(oof, oof_f)
  tst_f <- file.path(P$models, "test_predicciones.csv")
  tst <- if (file.exists(tst_f)) lee_csv(tst_f) else tibble(property_id = TE$property_id)
  tst[[nombre]] <- pred_test_log; write_csv(tst, tst_f)
  sub <- tibble(property_id = TE$property_id, price = round(recorta(exp(pred_test_log))))
  stopifnot(nrow(sub) == nrow(TE), !anyDuplicated(sub$property_id), !anyNA(sub$price))   # formato de Kaggle
  write_csv(sub, file.path(P$subs, paste0(nombre, ".csv")))
  cat(sprintf("[%s] MAE OOF total: %s | Chapinero: %s | macro localidades: %s\n", nombre,
              comma(metr$mae_total / 1e6, .1), comma(metr$mae_chapinero / 1e6, .1), comma(metr$mae_macro / 1e6, .1)))
}

# Mapa de una prima de ubicación (encoder en log, centrado): mediana por celda de ~500 m (08, 08c; figura 11 del paper)
mapa_prima <- function(enc, titulo, subtitulo, archivo) {
  loc_poly <- lee_csv(file.path(P$osm, "localidades_poligonos.csv"))
  mp <- D %>% select(property_id, lat, lon) %>% inner_join(enc, by = "property_id")
  g <- ggplot(mp, aes(lon, lat, z = enc_ubicacion)) +
    geom_polygon(data = loc_poly, aes(lon, lat, group = interaction(nombre, ring)), fill = NA, color = c_muted, linewidth = .25, inherit.aes = FALSE) +
    stat_summary_2d(fun = median, binwidth = c(.0045, .0045), alpha = .95) +
    scale_fill_gradient2(low = c_train, mid = "#f4f4f2", high = c_test, midpoint = 0, labels = \(x) percent(exp(x) - 1),
                         name = "Prima de ubicación sobre el precio por m2") +
    coord_quickmap(xlim = c(-74.19, -74.015), ylim = c(4.565, 4.775)) +
    guides(fill = guide_colorbar(barwidth = 14, barheight = .5, title.position = "top")) +
    labs(title = titulo, subtitle = subtitulo, x = NULL, y = NULL, caption = fuente) +
    theme(axis.text = element_blank(), panel.grid.major = element_blank())
  ggsave(file.path(P$rep_mod, "figures", archivo), g, width = 6.5, height = 7.4, dpi = 250)
}

# ---- Variables excluidas y validación ponderada (D15, D16, D17) ----
# Zona de lujo de D15: casi una dummy de Chapinero, empeora mucho la validación (siempre fuera). Contexto de OSM de D15:
# se decide con la NN STAR (08f mide primero sin y luego con); los demás modelos siguen esa decisión (osm_ganadora()).
LUJO    <- "^(dist|n500)_(embajada|oficina|hotel|club)$"
OSM_CTX <- "^(dist_cerros|dist_via_principal|area_verde500|pisos_prom500|n500_edif_pisos)$"
vars_sin <- function(osm = TRUE, vars = base$vars) vars[!grepl(LUJO, vars) & (osm | !grepl(OSM_CTX, vars))]
F_GANADORA_NN <- file.path(P$rep_mod, "tables", "nn_star_twcv_ganadora.csv")
osm_ganadora <- function() if (file.exists(F_GANADORA_NN)) as.logical(read_csv(F_GANADORA_NN, show_col_types = FALSE)$osm[1]) else FALSE
# Pesos TWCV por anuncio del train (suman 1), de 91_validacion_sintetica.R; MAE ponderado hacia el test
pesos_twcv <- function() {
  pw <- lee_csv(file.path(P$processed, "pesos_validacion.csv")); w <- pw$w_twcv[match(TR$property_id, pw$property_id)]
  stopifnot(!anyNA(w), abs(sum(w) - 1) < 1e-8); w
}
mae_w <- function(pred_log, w) sum(w * abs(exp(Y) - recorta(exp(pred_log))))
