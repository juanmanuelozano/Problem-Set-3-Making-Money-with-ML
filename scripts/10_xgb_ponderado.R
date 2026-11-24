# =============================================================================
# 10_xgb_ponderado.R - XGBoost con pérdida ponderada hacia el test y separación casas / apartamentos (D16b)
#
# Motivación: el test es Chapinero y 97% apartamentos; el train tiene 24,5% de casas (casi todas lejos de Chapinero)
# y solo 307 anuncios en Chapinero. Con pesos iguales, el modelo dedica buena parte de su capacidad a zonas y tipos
# que el test casi no tiene. Corrección clásica por cambio de covariables: ponderar cada fila del train por
# w(x) = p_test(x) / p_train(x) (Shimodaira, 2000; Sugiyama et al., 2007).
#
# Pesos que se comparan (sin usar el precio, así que no hay fuga):
#  - tipo:   razón de proporciones casa / apartamento entre test y train.
#  - dist:   núcleo exponencial en la distancia al anuncio del test más cercano, exp(-d / h), con piso.
#  - razon:  razón de densidades estimada con un clasificador train-vs-test (XGBoost, cross-fitting),
#            atenuada con un exponente gamma y recortada (pesos extremos -> varianza alta).
# Separación por tipo: un modelo solo con apartamentos predice los apartamentos; las casas se predicen con el
# modelo de todas las filas de la misma configuración de pesos.
#
# Métrica para elegir rondas y comparar: MAE en la "zona objetivo" = Chapinero + anuncios a <= 1 km de Chapinero
# (unos 3.900, menos ruidosa que los 307 de Chapinero). Se reportan también Chapinero, total y macro.
# Hiperparámetros del árbol: los de m04 (depth 4, mcw 3, eta 0,03). Pesos normalizados a media 1 para que
# min_child_weight conserve su escala.
# Validación: una localidad afuera con buffer de 500 m (cv_oof, D9).
# Salidas: reports/02_modelos/tables/ponderados_{pesos,resultados}.csv, models/ponderados_oof.rds,
#          registro m17_xgb_ponderado
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(xgboost))
T0 <- Sys.time(); paso <- function(msg) cat(sprintf("[%5.1f min] %s\n", as.numeric(difftime(Sys.time(), T0, units = "mins")), msg))

Xtr <- matriz_arboles(TR); Xte <- matriz_arboles(TE)
RONDAS <- seq(50, 1500, 50)
PR <- list(objective = "reg:squarederror", eta = 0.03, max_depth = 4, min_child_weight = 3, subsample = 0.8,
           colsample_bytree = 0.6, lambda = 1, nthread = 8, seed = 123)
APTO <- TR$es_apto == 1
ZONA <- ES_CHAP | base$dist_loc[, "Chapinero"] <= 1000
cat("Zona objetivo:", sum(ZONA), "anuncios (", sum(ZONA & APTO), "apartamentos )\n")

# Métricas: las de evalua() más la zona objetivo
metricas <- function(p_log) {
  p <- recorta(exp(p_log)); y <- TR$price
  evalua(p_log) %>% mutate(mae_zona = mae(y[ZONA], p[ZONA]), mae_zona_apto = mae(y[ZONA & APTO], p[ZONA & APTO]),
                           sesgo_chapinero = mean(p[ES_CHAP] - y[ES_CHAP]))
}
mae_zona_cols <- function(pred) apply(pred, 2, function(p) mae(TR$price[ZONA], recorta(exp(p[ZONA]))))

# ---- 1. Pesos ----
norm1 <- function(w) w / mean(w)
ess <- function(w) sum(w)^2 / sum(w^2)   # tamaño de muestra efectivo de Kish

# (a) tipo
p_te <- mean(TE$es_apto == 1); p_tr <- mean(APTO)
w_tipo <- ifelse(APTO, p_te / p_tr, (1 - p_te) / (1 - p_tr))

# (b) distancia al anuncio del test más cercano
d_test <- dist_min(TR$lat, TR$lon, TE$lat, TE$lon)
w_dist <- function(h, piso = 0.05) pmax(exp(-d_test / h), piso)

# (c) razón de densidades con un clasificador train (0) vs. test (1), predicciones out-of-fold para el train
vars_clf <- setdiff(colnames(Xtr), c("year", "month", "area_imputada", "area_texto", "banos_imputado",
                                     grep("^na_", colnames(Xtr), value = TRUE)))
Xc <- rbind(Xtr[, vars_clf], Xte[, vars_clf]); yc <- rep(0:1, c(nrow(Xtr), nrow(Xte)))
set.seed(123); kc <- sample(rep(1:5, length.out = nrow(Xc)))
pc <- numeric(nrow(Xc))
prc <- list(objective = "binary:logistic", eta = 0.1, max_depth = 4, min_child_weight = 10, subsample = 0.8,
            colsample_bytree = 0.6, nthread = 8, seed = 123)
for (k in 1:5) {
  fit_c <- xgb.train(params = prc, data = xgb.DMatrix(Xc[kc != k, ], label = yc[kc != k]), nrounds = 300, verbose = 0)
  pc[kc == k] <- predict(fit_c, xgb.DMatrix(Xc[kc == k, ]))
}
auc <- function(s, y) { r <- rank(s); (sum(r[y == 1]) - sum(y == 1) * (sum(y == 1) + 1) / 2) / (sum(y == 1) * sum(y == 0)) }
cat(sprintf("Clasificador train vs. test: AUC out-of-fold = %.3f\n", auc(pc, yc)))
p_tr_c <- pmin(pmax(pc[yc == 0], 1e-4), 1 - 1e-4)
razon <- p_tr_c / (1 - p_tr_c) * nrow(Xtr) / nrow(Xte)
w_razon <- function(gamma, tope = 0.99) { w <- razon^gamma; pmin(w, quantile(w, tope)) }
imp_c <- xgb.importance(model = fit_c); cat("Variables que más separan train y test:\n"); print(head(imp_c[, 1:2], 10))

CONFIGS <- list(
  base          = rep(1, length(Y)),
  tipo          = w_tipo,
  dist2km       = w_dist(2000),
  tipo_dist2km  = w_tipo * w_dist(2000),
  tipo_dist5km  = w_tipo * w_dist(5000),
  razon_g05     = w_razon(0.5),
  razon_g1      = w_razon(1)
) %>% map(norm1)

resumen_pesos <- imap_dfr(CONFIGS, function(w, n) tibble(
  config = n, ess = ess(w), ess_pct = ess(w) / length(w),
  peso_medio_chapinero = mean(w[ES_CHAP]), peso_medio_zona = mean(w[ZONA]), peso_medio_lejos = mean(w[!ZONA]),
  peso_medio_casa = mean(w[!APTO]), peso_medio_apto = mean(w[APTO]), pct_peso_zona = sum(w[ZONA]) / sum(w)))
cat("\nResumen de los pesos:\n"); print(resumen_pesos %>% mutate(across(where(is.double), ~ round(.x, 3))), width = 200)
write_csv(resumen_pesos, file.path(P$rep_mod, "tables", "ponderados_pesos.csv"))
paso("pesos listos")

# ---- 2. Validación con buffer: todas las filas y solo apartamentos ----
corre <- function(w, solo_apto = FALSE) {
  cv_oof(function(a, e) {
    if (solo_apto) { a <- a[APTO[a]] }
    xgb_rondas(PR, Xtr[a, ], Y[a], Xtr[e, ], RONDAS, wa = w[a])
  })
}
elige <- function(m, n) {
  j <- which.min(mae_zona_cols(m))
  if (j == length(RONDAS)) warning(n, ": las rondas quedaron en el tope de la grilla")
  tibble(config = n, rondas = RONDAS[j], oof = list(m[, j])) %>% bind_cols(metricas(m[, j]))
}
oof_mat <- list(); res <- NULL
for (n in names(CONFIGS)) {
  oof_mat[[n]] <- corre(CONFIGS[[n]]); res <- bind_rows(res, elige(oof_mat[[n]], n)); paso(paste("todas las filas:", n))
}
for (n in c("base", "dist2km", "razon_g05")) {
  m <- corre(CONFIGS[[n]], solo_apto = TRUE)
  m[!APTO, ] <- res$oof[[which(res$config == n)]][!APTO]   # casas: modelo de todas las filas, con sus mejores rondas
  oof_mat[[paste0("apto_", n)]] <- m; res <- bind_rows(res, elige(m, paste0("apto_", n)))
  paso(paste("solo apartamentos:", n))
}
# En las separadas, `rondas` es la del modelo de apartamentos; las casas usan las de su configuración de todas las filas.
tabla <- res %>% select(-oof) %>% arrange(mae_zona)
cat("\nResultados (millones de COP), ordenados por MAE en la zona objetivo:\n")
print(tabla %>% mutate(across(c(starts_with("mae"), sesgo_chapinero), ~ round(.x / 1e6, 1)), mape_chapinero = round(mape_chapinero, 3)), width = 200)
write_csv(tabla, file.path(P$rep_mod, "tables", "ponderados_resultados.csv"))
saveRDS(list(oof = oof_mat, rondas = RONDAS, pesos = CONFIGS, d_test = d_test, razon = razon),
        file.path(P$models, "ponderados_oof.rds"))

# ---- 3. Modelos finales ----
# m17: la mejor configuración (no base) por MAE en la zona objetivo, el criterio fijado antes de correr.
# m17b: tipo_dist2km, la mejor en Chapinero (-13,5 M frente a la base, pareado t = -3,2). Se registra para
#       comparar en Kaggle; elegirla por Chapinero entre 9 variantes es una selección a posteriori.
registra_config <- function(nombre, config) {
  fila <- res %>% filter(config == !!config)
  n_w <- sub("^apto_", "", config); w <- CONFIGS[[n_w]]
  ajusta <- function(filas, r) xgb.train(params = PR, data = xgb.DMatrix(Xtr[filas, ], label = Y[filas], weight = w[filas]),
                                       nrounds = r, verbose = 0)
  r_todas <- res$rondas[res$config == n_w]
  pred_te <- predict(ajusta(seq_along(Y), r_todas), xgb.DMatrix(Xte))
  separa <- startsWith(config, "apto_")
  if (separa) {
    ap_te <- TE$es_apto == 1
    pred_te[ap_te] <- predict(ajusta(which(APTO), fila$rondas), xgb.DMatrix(Xte[ap_te, ]))
  }
  registra(nombre,
           sprintf("XGBoost log(precio), pérdida ponderada hacia el test (%s)%s", n_w,
                   if (separa) "; modelo solo de apartamentos para los apartamentos" else ""),
           sprintf("pesos=%s; eta=0.03; max_depth=4; mcw=3; nrounds=%d%s; rondas por MAE en la zona objetivo",
                   n_w, fila$rondas, if (separa) sprintf(" (casas: %d)", r_todas) else ""),
           fila %>% select(starts_with("ma")), fila$oof[[1]], pred_te)
}
mejor <- res %>% filter(config != "base") %>% slice_min(mae_zona, n = 1, with_ties = FALSE)
paso(paste("mejor configuración por zona objetivo:", mejor$config))
registra_config("m17_xgb_ponderado", mejor$config)
registra_config("m17b_xgb_tipo_dist", "tipo_dist2km")
paso("listo")
