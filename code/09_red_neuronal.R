# =============================================================================
# 09_red_neuronal.R - Red neuronal (perceptrón multicapa de una capa oculta, nnet) sobre log(precio por m2)
# Mismas variables que el elastic net (matriz_lineal + interacciones), sin variables de área: el precio se
# recupera sumando log(área), como en m02b. Entradas y objetivo se estandarizan con las medias y
# desviaciones del conjunto de análisis de cada fold (sin filtrar información del fold evaluado).
# Grilla: neuronas ocultas (size) × penalización L2 de los pesos (decay), validada dejando una localidad
# afuera con buffer (cv_oof, D9) y elegida con el MAE del Chapinero sintético (TWCV, D18). Usa la base sin las
# variables de embajadas, oficinas, hoteles y clubes (D19). Activación sigmoide y salida lineal (linout = TRUE).
# Tiempo estimado: ~1 hora (4 combinaciones × 18 folds). Correr en el servidor.
# Salidas: tables/red_grilla.csv, registro (m16_red_m2) y submissions/m16_red_m2.csv
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))

obj <- arma_objetivos(cbind(matriz_lineal(TR), interacciones(TR)), cbind(matriz_lineal(TE), interacciones(TE)))$m2
MAXIT <- 500   # iteraciones de BFGS

# Ajusta la red en (X, y) y predice en Xn (en log precio/m2). Estandariza con las filas de entrenamiento.
ajusta_red <- function(X, y, Xn, size, decay) {
  mu <- colMeans(X); s <- apply(X, 2, sd); s[s == 0] <- 1
  my <- mean(y); sy <- sd(y)
  set.seed(123)
  m <- nnet(scale(X, mu, s), (y - my) / sy, size = size, decay = decay, linout = TRUE,
            maxit = MAXIT, MaxNWts = 1e5, trace = FALSE)
  as.numeric(predict(m, scale(Xn, mu, s))) * sy + my
}

grilla <- expand_grid(size = c(5, 15), decay = c(0.1, 1))
res <- pmap_dfr(grilla, function(size, decay) {
  t0 <- Sys.time()
  p <- cv_oof(function(a, e) ajusta_red(obj$Xtr[a, ], obj$y[a], obj$Xtr[e, ], size, decay)) + obj$off_tr
  r <- tibble(size = size, decay = decay, oof = list(p)) %>% bind_cols(evalua(p))
  cat(sprintf("size=%d decay=%.1f -> MAE %.1f | Chap %.1f | TWCV %.1f (%.0f min)\n", size, decay, r$mae_total / 1e6,
              r$mae_chapinero / 1e6, r$mae_twcv / 1e6, as.numeric(difftime(Sys.time(), t0, units = "mins"))))
  r
})
write_csv(select(res, -oof), file.path(P$tab_mod, "red_grilla.csv"))

# Mejor combinación por MAE del Chapinero sintético (mae_twcv, D18 y D19): reajuste con todo el train,
# registro y envío. Sin pesos de entrenamiento: en el lasso (04e) no ayudaron.
best <- res %>% slice_min(mae_twcv, n = 1, with_ties = FALSE)
pred_te <- ajusta_red(obj$Xtr, obj$y, obj$Xte, best$size, best$decay) + obj$off_te
registra("m16_red_m2", "Red neuronal (nnet, 1 capa oculta, sigmoide) sobre log(precio/m2), variables del elastic net estandarizadas",
         sprintf("size=%d; decay=%.1f; maxit=%d", best$size, best$decay, MAXIT),
         best %>% select(starts_with("ma")), best$oof[[1]], pred_te)
