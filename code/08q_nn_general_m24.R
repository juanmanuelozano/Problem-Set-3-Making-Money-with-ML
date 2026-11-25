# =============================================================================
# 08q_nn_general_m24.R - Red general (caja negra) comparable a m24, para la presentación, D17
# Misma comparación que m17 (NN STAR, Kaggle 158,3) frente a m18 (red general del mismo tamaño, 167,5), pero con los datos
# de m24: catastro valor_estrato, sin zona de lujo ni OSM. Lo único que cambia frente a m24 es la estructura: todas las
# variables (estructura + ubicación + texto) entran juntas a una red 64-32-16 ReLU (~72 mil parámetros, como m24), sin
# ramas separadas. Misma configuración de entrenamiento que m24: lr 1e-3, MSE, calibración simple, 1 semilla, épocas por
# MAE TWCV en la CV por localidad. La red general tiene un solo dropout: se prueban 0,1 (el de la ubicación de m24) y 0,3.
# Registro: m49_nn_general_m24_m2 (el dropout con mejor TWCV)
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R")); source(here::here("code", "utils_redes.R"))

W <- pesos_twcv(); y <- exp(Y)
usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = "valor_estrato"); d <- dims(BR$m2)
cat(sprintf("Parámetros: NN STAR (m24) %d | red general %d\n", count_params(red_star(d, .1, .5)$modelo), count_params(red_general(d, .1)$modelo)))
res <- map_dfr(c(.1, .3), function(p) {
  construye <- function(g, d) red_general(d, p)
  r <- cv_red(\(d) construye(NULL, d), "m2", EPOCAS, 1e-3, "mse", w = W)
  f <- ajusta_final(tibble(objetivo = "m2", epocas = r$epocas), construye, 1e-3, "mse")
  m <- evalua(r$oof)
  paso(sprintf("dropout %.1f | ép %d | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f | test %.1f", p, r$epocas, m$mae_total / 1e6,
               m$mae_chapinero / 1e6, m$mae_macro / 1e6, mae_w(r$oof, W) / 1e6, mean(recorta(exp(f$pred_te))) / 1e6))
  tibble(p = p, epocas = r$epocas) %>% bind_cols(m) %>% mutate(mae_twcv = mae_w(r$oof, W), oof = list(r$oof), pred_te = list(f$pred_te))
})
b <- slice_min(res, mae_twcv, n = 1, with_ties = FALSE)
if (!PRUEBA) registra("m49_nn_general_m24_m2",
  "Red general 64-32-16 (caja negra, todas las variables juntas) con los datos y la configuración de m24 (catastro valor_estrato, sin zona de lujo ni OSM), 08q; comparación STAR vs general; sobre log(precio por m2)",
  sprintf("capas=64-32-16; p=%g; lr=1e-3; pérdida=mse; calibración=simple; semillas=1; épocas=%d", b$p, b$epocas),
  select(b, starts_with("ma")), b$oof[[1]], b$pred_te[[1]])
paso("Listo.")
