# =============================================================================
# 08m_criterio_twcv_edif.R - ¿Sirve el MAE TWCV calculado con la CV agrupada por edificio para elegir redes? D17
# El TWCV con la CV por localidad (D16) eligió mal 3 de 3 veces entre NN STAR (m19, m20, m25 < m17/m24 en Kaggle):
# en esa CV Chapinero se evalúa sin vecinos en el train (en el test, el más cercano está a 96 m), así que no ve el
# error de nivel. Aquí se recalcula con FOLDS_EDIF (utils_comparables.R), donde los evaluados sí tienen vecinos.
# Prueba con dos pares de configuraciones de resultado conocido en Kaggle (las épocas se eligen por este criterio):
#   con catastro: m24 (lr 1e-3, MSE, calibración simple) 156,3  vs  m25 (lr 1e-4, MAE, calibración TWCV, 3 semillas) 160,6
#   sin catastro: m17 (igual que m24)                    158,3  vs  m20 (lr 1e-4, p_u 0,15, p_t 0,6, MAE, cal. TWCV) 162,1
# (m17 y m20 se reproducen sobre la base actual sin zona de lujo ni OSM; m17 original usaba la base anterior.)
# El criterio pasa si prefiere m24 y m17. No registra modelos. Salida: tables/criterio_twcv_edif.csv
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R"); source("scripts/utils_redes.R")
source("scripts/utils_comparables.R")

W <- pesos_twcv(); y <- exp(Y); SEM3 <- c(123, 124, 125)
EP60 <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 60, 5))
cfgs <- tribble(~config, ~catastro, ~lr, ~p_u, ~p_t, ~perdida, ~cal, ~n_sem, ~kaggle,
  "m24", "valor_estrato", 1e-3, .1,  .5, "mse", "simple", 1, 156.3,
  "m25", "valor_estrato", 1e-4, .1,  .5, "mae", "twcv",   3, 160.6,
  "m17", "no",            1e-3, .1,  .5, "mse", "simple", 1, 158.3,
  "m20", "no",            1e-4, .15, .6, "mae", "twcv",   1, 162.1)
if (PRUEBA) cfgs$n_sem <- 1

res <- list()
for (k in seq_len(nrow(cfgs))) {
  g <- cfgs[k, ]; usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = g$catastro)
  construye <- function(b, d) red_star(d, g$p_u, g$p_t)
  w_cal <- if (g$cal == "twcv") W else NULL; sem <- if (g$n_sem == 3) SEM3 else 123
  r <- cv_red(\(d) construye(NULL, d), "m2", if (g$lr >= 1e-3) EPOCAS else EP60, g$lr, g$perdida, w = W, w_cal = w_cal,
              semillas = sem, folds = FOLDS_EDIF)
  f <- ajusta_final(tibble(objetivo = "m2", epocas = r$epocas), construye, g$lr, g$perdida, w_cal, sem)
  res[[g$config]] <- g %>% mutate(epocas = r$epocas, borde = r$borde) %>% bind_cols(evalua(r$oof)) %>%
    mutate(mae_twcv = mae_w(r$oof, W), sesgo_chap = mean(recorta(exp(r$oof[ES_CHAP])) - y[ES_CHAP]),
           pred_test = mean(recorta(exp(f$pred_te))), oof = list(r$oof))
  x <- res[[g$config]]
  paso(sprintf("%s | ép %d%s | TWCV %.1f | MAE %.1f / Chap %.1f / macro %.1f | sesgo Chap %.1f | test %.1f | Kaggle %.1f",
               g$config, r$epocas, if (r$borde) " (BORDE)" else "", x$mae_twcv / 1e6, x$mae_total / 1e6, x$mae_chapinero / 1e6,
               x$mae_macro / 1e6, x$sesgo_chap / 1e6, x$pred_test / 1e6, g$kaggle))
}
todo <- bind_rows(res)
write_csv(select(todo, -oof), file.path(P$rep_mod, "tables", "criterio_twcv_edif.csv"))

# Diferencias pareadas ponderadas (TWCV) dentro de cada par, con su error estándar
err <- \(c) abs(y - recorta(exp(todo$oof[[which(todo$config == c)]])))
for (par in list(c("m24", "m25"), c("m17", "m20"))) {
  d <- err(par[1]) - err(par[2]); m <- sum(W * d); se <- sqrt(sum(W^2 * (d - m)^2))
  paso(sprintf("%s - %s: TWCV %+.1f M (EE %.1f, t %.2f) -> el criterio prefiere %s; Kaggle prefiere %s",
               par[1], par[2], m / 1e6, se / 1e6, m / se, if (m < 0) par[1] else par[2], par[1]))
}
paso("Listo.")
