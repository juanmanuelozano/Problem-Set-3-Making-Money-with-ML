# =============================================================================
# 08n_nn_star_dropout_ramas.R - m24 con un solo cambio de dropout, según el diagnóstico de las ramas (08l), D17
# 08l: la rama de ubicación exagera (pendiente 0,84; 0,58 en Chapinero) y la de texto se queda corta (1,43).
# La validación no distingue diferencias de 2-4 M entre variantes de la red (error ~5 M frente a Kaggle, 08m), así que
# cada hipótesis se fija de antemano y se juzga en Kaggle (gana solo si mejora a m24, 156,3, en más de ~1,5 M):
#   m30_nn_star_pu03_m2   dropout de ubicación 0,1 -> 0,3 (frenar la sobrerreacción)
#   m31_nn_star_pt025_m2  dropout de texto 0,5 -> 0,25 (dejar que use más el texto)
#   m33_nn_star_tanh_ubi_m2  tanh en la rama profunda de ubicación (ReLU no tiene tope; tanh satura y debería comprimir
#                            los extremos caros que el ensamble corrige hacia abajo); el atajo lineal queda igual
# SOLO=<nombre> en el entorno corre solo esa variante.
# Todo lo demás como m24: catastro valor_estrato, sin zona de lujo ni OSM, lr 1e-3, MSE, calibración simple, 1 semilla,
# épocas elegidas por MAE TWCV en la CV por localidad.
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R")); source(here::here("code", "utils_redes.R"))

W <- pesos_twcv(); y <- exp(Y)
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv")); ref <- oofs$m24_nn_star_catastro_m2[match(TR$property_id, oofs$property_id)]
err <- \(p) abs(y - recorta(exp(p)))
usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = "valor_estrato")
variantes <- tribble(~nombre, ~p_u, ~p_t, ~act_u, ~desc,
  "m30_nn_star_pu03_m2",     .3, .5,  "relu", "dropout de ubicación 0,3 (m24 tenía 0,1)",
  "m31_nn_star_pt025_m2",    .1, .25, "relu", "dropout de texto 0,25 (m24 tenía 0,5)",
  "m33_nn_star_tanh_ubi_m2", .1, .5,  "tanh", "tanh en la rama profunda de ubicación (m24 tenía ReLU)")
if (nzchar(Sys.getenv("SOLO"))) variantes <- filter(variantes, nombre == Sys.getenv("SOLO"))
for (k in seq_len(nrow(variantes))) {
  v <- variantes[k, ]; construye <- function(g, d) red_star(d, v$p_u, v$p_t, act_u = v$act_u)
  r <- cv_red(\(d) construye(NULL, d), "m2", EPOCAS, 1e-3, "mse", w = W)
  f <- ajusta_final(tibble(objetivo = "m2", epocas = r$epocas), construye, 1e-3, "mse")
  m <- evalua(r$oof); d <- err(r$oof) - err(ref); dw <- sum(W * d); se <- sqrt(sum(W^2 * (d - dw)^2))
  paso(sprintf("%s | ép %d%s | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f | test %.1f | vs m24: TWCV %+.1f (EE %.1f), Chap %+.1f",
               v$nombre, r$epocas, if (r$borde) " (BORDE)" else "", m$mae_total / 1e6, m$mae_chapinero / 1e6, m$mae_macro / 1e6,
               mae_w(r$oof, W) / 1e6, mean(recorta(exp(f$pred_te))) / 1e6, dw / 1e6, se / 1e6, mean(d[ES_CHAP]) / 1e6))
  if (!PRUEBA) registra(v$nombre,
    paste0("NN STAR como m24 (catastro valor_estrato, sin zona de lujo ni OSM) con ", v$desc, " (08n); sobre log(precio por m2)"),
    sprintf("lr=1e-3; p_u=%g; p_t=%g; activación ubicación=%s; pérdida=mse; calibración=simple; semillas=1; épocas=%d; batch=%d; l2=%g", v$p_u, v$p_t, v$act_u, r$epocas, BATCH, L2),
    m, r$oof, f$pred_te)
}
paso("Listo.")
