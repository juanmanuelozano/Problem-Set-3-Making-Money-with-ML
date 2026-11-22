# =============================================================================
# 04e_elastic_net_pesos.R - Lasso por m2 entrenado con pesos hacia el test ("Chapinero sintético", D19)
# Misma especificación que m02b (04b_elastic_net.R): log(precio/m2), matriz_lineal + habitaciones × distancia
# a cada CBD, alpha = 1 (el mejor de la grilla de 04b), camino de 100 lambdas con lambda.min.ratio = 1e-3.
# Cambio: cada anuncio del train pesa según qué tanto se parece al test (importance weighting, Shimodaira 2000;
# Brenning y Suesse 2026). Los pesos solo usan las variables del test, no su precio: no hay fuga.
# Los pesos están muy concentrados (tamaño efectivo de ~3-5%), así que se suavizan: w^gamma, con gamma = 0
# (sin pesos) a 1 (pesos completos). Fuente de los pesos: IWCV (logit test vs train) o TWCV (raking).
# Lambda y la mejor combinación se eligen con el MAE del Chapinero sintético (mae_twcv), no con el total.
# Usa la base nueva (D14, D15). Salidas: tables/en_pesos_grilla.csv, registro (m20_en_sin_pesos_m2, m20_en_pesos_m2)
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(glmnet))

o <- arma_objetivos(cbind(matriz_lineal(TR), interacciones(TR)), cbind(matriz_lineal(TE), interacciones(TE)))$m2

# Pesos de entrenamiento sin encoger (el encogimiento del 20% es para evaluar), con media 1
base_w <- list(iwcv = pesos_iwcv(), twcv = pesos_twcv()) %>% map(~ .x / mean(.x))
grilla <- bind_rows(tibble(fuente = "ninguna", gamma = 0),
                    expand_grid(fuente = c("iwcv", "twcv"), gamma = c(.25, .5, 1)))

res <- pmap_dfr(grilla, function(fuente, gamma) {
  t0 <- Sys.time()
  w <- if (fuente == "ninguna") rep(1, nrow(TR)) else base_w[[fuente]]^gamma
  w <- w / mean(w)
  lam <- glmnet(o$Xtr, o$y, alpha = 1, nlambda = 100, lambda.min.ratio = 1e-3, weights = w)$lambda
  oof <- cv_oof(function(a, e) predict(glmnet(o$Xtr[a, ], o$y[a], alpha = 1, lambda = lam, weights = w[a]),
                                       o$Xtr[e, ], s = lam)) + o$off_tr
  j <- which.min(apply(oof, 2, function(p) evalua(p)$mae_twcv))          # lambda por MAE sintético
  r <- tibble(fuente, gamma, ess_entreno = ess(w) / length(w), lambda = lam[j], en_borde = j %in% c(1, length(lam)),
              lam = list(lam), w = list(w), oof = list(oof[, j])) %>% bind_cols(evalua(oof[, j]))
  cat(sprintf("%-7s gamma=%.2f -> total %.1f | Chap %.1f | TWCV %.1f | IWCV %.1f (ESS %.0f%%, %.0fs)\n", fuente, gamma,
              r$mae_total / 1e6, r$mae_chapinero / 1e6, r$mae_twcv / 1e6, r$mae_iwcv / 1e6, 100 * r$ess_entreno,
              as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  r
})
write_csv(select(res, -lam, -w, -oof), file.path(P$rep_mod, "tables", "en_pesos_grilla.csv"))

# Registro: sin pesos (referencia, base nueva) y la mejor combinación con pesos (por MAE TWCV)
ajusta_registra <- function(b, nombre, desc) {
  fit <- glmnet(o$Xtr, o$y, alpha = 1, lambda = b$lam[[1]], weights = b$w[[1]])
  registra(nombre, desc, sprintf("alpha=1; lambda=%.2g; pesos=%s; gamma=%.2f", b$lambda, b$fuente, b$gamma),
           select(b, starts_with("ma")), b$oof[[1]], drop(predict(fit, o$Xte, s = b$lambda)) + o$off_te)
  if (b$en_borde) cat("Aviso:", nombre, "eligió un extremo del camino de lambda\n")
}
ajusta_registra(filter(res, fuente == "ninguna"), "m20_en_sin_pesos_m2",
                "Lasso sobre log(precio/m2), base nueva (D14, D15), sin pesos; lambda por MAE TWCV")
ajusta_registra(res %>% filter(fuente != "ninguna") %>% slice_min(mae_twcv, n = 1, with_ties = FALSE), "m20_en_pesos_m2",
                "Lasso sobre log(precio/m2), base nueva, entrenado con pesos hacia el test (D19); lambda y gamma por MAE TWCV")
