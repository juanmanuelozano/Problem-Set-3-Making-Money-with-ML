# =============================================================================
# 08h_nn_star_catastro.R - Mini corrida: ¿aportan las variables catastrales (03f, D18) al NN STAR?
# Configuración de m17 (la que mantiene el nivel en el test): lr 1e-3, p_u 0,1, p_t 0,5, MSE, calibración simple,
# texto 64-32-16, sin área en m2; base D14 sin zona de lujo ni contexto de OSM. Épocas elegidas por TWCV (D16).
# Tres variantes: sin catastro | + log(valor de referencia del suelo) en ubicación | + valor y estrato oficial.
# No registra modelos: es para decidir si vale una corrida completa. Cada fila: MAE total / Chapinero / macro / TWCV,
# épocas, sesgo en Chapinero, predicción media del test y prueba pareada frente a m17_nn_star_m2 (Kaggle 158,3).
# Salida: tables/nn_star_catastro.csv
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R"); source("scripts/utils_redes.R")

REF <- "m17_nn_star_m2"; W <- pesos_twcv()
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv"))
ref <- oofs[[REF]][match(TR$property_id, oofs$property_id)]
y <- exp(Y); err <- \(p) abs(y - recorta(exp(p)))
cfg <- tibble(objetivo = "m2", p_u = .1, p_t = .5)
construye <- function(g, d) red_star(d, g$p_u, g$p_t)

res <- map_dfr(c("no", "valor", "valor_estrato"), function(cat_v) {
  usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = cat_v)
  r <- cv_red(\(d) construye(cfg, d), "m2", w = W)
  f <- ajusta_final(mutate(cfg, epocas = r$epocas), construye)
  d <- err(r$oof) - err(ref)
  fila <- tibble(catastro = cat_v, entradas = paste(dims(BR$m2), collapse = "/"), epocas = r$epocas, borde = r$borde) %>%
    bind_cols(evalua(r$oof)) %>%
    mutate(mae_twcv = mae_w(r$oof, W), sesgo_chap = mean(recorta(exp(r$oof[ES_CHAP])) - y[ES_CHAP]),
           pred_test = mean(recorta(exp(f$pred_te))), dif_chap = mean(d[ES_CHAP]), t_chap = unname(t.test(d[ES_CHAP])$statistic),
           dif_total = mean(d), t_total = unname(t.test(d)$statistic))
  paso(sprintf("%-13s ent %s | ép %d%s | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f | sesgo %.1f | test %.1f | vs m17: Chap %+.1f (t %.2f), total %+.1f (t %.2f)",
               cat_v, fila$entradas, r$epocas, if (r$borde) " (BORDE)" else "", fila$mae_total / 1e6, fila$mae_chapinero / 1e6,
               fila$mae_macro / 1e6, fila$mae_twcv / 1e6, fila$sesgo_chap / 1e6, fila$pred_test / 1e6,
               fila$dif_chap / 1e6, fila$t_chap, fila$dif_total / 1e6, fila$t_total))
  write_csv(fila, file.path(P$rep_mod, "tables", "nn_star_catastro.csv"), append = cat_v != "no")
  fila
})
paso("Listo.")
