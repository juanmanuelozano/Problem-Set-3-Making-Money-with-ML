# =============================================================================
# 08f2_nn_star_twcv_3sem.R - Registra la ganadora de 08f promediando 3 semillas (etapa D de 08f), D17
# En 08f la versión de 3 semillas no quedó registrada porque su TWCV fue 0,2 M peor (ruido), pero es la más estable y
# la única con diferencia significativa frente a m17 en Chapinero (−5,5 M, t −2,2). Misma configuración que m20:
# texto 64-32-16, sin área en m2, pérdida MAE, calibración TWCV, sin OSM, lr 1e-4, p_u 0,15, p_t 0,6; épocas por TWCV.
# Registro: m20b_nn_star_twcv_3sem_m2
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R"); source("scripts/utils_redes.R")

W <- pesos_twcv(); SEM3 <- c(123, 124, 125)
EP60 <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 60, 5))
cfg <- tibble(objetivo = "m2", p_u = .15, p_t = .6)
construye <- function(g, d) red_star(d, g$p_u, g$p_t)
usa_bloques(area_m2 = FALSE, osm = FALSE)
r <- cv_red(\(d) construye(cfg, d), "m2", EP60, 1e-4, "mae", w = W, w_cal = W, semillas = SEM3)
f <- ajusta_final(mutate(cfg, epocas = r$epocas), construye, 1e-4, "mae", W, SEM3)
m <- evalua(r$oof)
paso(sprintf("épocas %d | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f | test %.1f", r$epocas, m$mae_total / 1e6,
             m$mae_chapinero / 1e6, m$mae_macro / 1e6, mae_w(r$oof, W) / 1e6, mean(recorta(exp(f$pred_te))) / 1e6))
if (!PRUEBA) registra("m20b_nn_star_twcv_3sem_m2",
  "NN STAR elegido por TWCV (08f), promedio de 3 semillas: texto 64-32-16, base D14 sin zona de lujo ni OSM; sobre log(precio por m2)",
  sprintf("lr=1e-4; p_u=0.15; p_t=0.6; pérdida=mae; calibración=twcv; semillas=3; épocas=%d; batch=%d; l2=%g", r$epocas, BATCH, L2),
  m, r$oof, f$pred_te)
