# =============================================================================
# 08d_nn_general.R - Red general (sin estructura), referencia del NN STAR (08c), D17
# Todas las variables (estructura + ubicación + TF-IDF) entran mezcladas desde la primera capa:
#   Dense(64, ReLU) -> Dropout(p) -> Dense(32, ReLU) -> Dropout(p) -> Dense(16, ReLU) -> Dense(1)
# Tiene casi los mismos parámetros que el NN STAR (≈71,5 mil frente a ≈72,8 mil): la comparación aísla el efecto de
# la estructura aditiva, como m04 frente a m13 en el boosting. Mismo entrenamiento, validación y calibración.
# Afinación: p en {0, .1, .2, .3, .5} con objetivo m2; con la mejor, también objetivo precio.
# Salidas: tables/nn_general_dropout.csv, tables/nn_resumen.csv, registro m18_nn_64_m2 y m18_nn_64
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R")); source(here::here("code", "utils_redes.R"))

grilla <- tibble(p = c(0, .1, .2, .3, .5)); if (PRUEBA) grilla <- grilla[1, ]
construye <- function(g, d) red_general(d, g$p)
cat("Parámetros (objetivo m2): red general", count_params(red_general(dims(BR$m2), 0)$modelo),
    "| NN STAR", count_params(red_star(dims(BR$m2), 0, 0)$modelo), "\n")

tab <- busca_red(grilla, construye, file.path(P$tab_mod, "nn_general_dropout.csv"))

finales <- tab %>% group_by(objetivo) %>% slice_min(mae_total, n = 1, with_ties = FALSE) %>% ungroup()
for (k in seq_len(nrow(finales))) {
  b <- finales[k, ]; f <- ajusta_final(b, construye)
  if (!PRUEBA) registra(paste0("m18_nn_64", if (b$objetivo == "m2") "_m2"),
    paste("Red general (Keras) 64-32-16 ReLU con dropout, todas las variables mezcladas, nivel calibrado;",
          if (b$objetivo == "m2") "sobre log(precio por m2), precio = predicción × m2" else "sobre log(precio)"),
    sprintf("p=%g; épocas=%d; lr=%g; batch=%d; l2=%g; mse", b$p, b$epocas, LR, BATCH, L2),
    select(b, starts_with("ma")), b$oof[[1]], f$pred_te)
}
cat("\nAfinación del dropout (MAE OOF, millones):\n")
print(as.data.frame(select(tab, -oof) %>% mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1)))))

# ---- Resumen: redes frente a los STAR de boosting y las referencias (sesgo en Chapinero y predicción de test) ----
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv")); tst <- lee_csv(file.path(P$models, "test_predicciones.csv"))
reg <- lee_csv(file.path(P$models, "registro_modelos.csv")); kag <- lee_csv(file.path(P$models, "kaggle_scores.csv"))
mods <- c("m17_nn_star_m2", "m17_nn_star", "m18_nn_64_m2", "m18_nn_64", "m13_xgb_star_m2", "m13_xgb_star",
          "m14_en_enc_tx", "m14_en_enc_tx_m2", "m04_xgboost", "m02b_elastic_net_m2")
resumen <- reg %>% filter(modelo %in% mods) %>% select(modelo, mae_total, mae_chapinero, mae_macro) %>%
  mutate(sesgo_chap = map_dbl(modelo, ~ mean(recorta(exp(oofs[[.x]][oofs$chapinero])) - exp(oofs$log_price[oofs$chapinero]))),
         pred_test = map_dbl(modelo, ~ mean(recorta(exp(tst[[.x]]))))) %>%
  left_join(select(kag, modelo, kaggle = public_score), by = "modelo") %>%
  mutate(across(where(is.numeric), ~ round(.x / 1e6, 1))) %>% arrange(match(modelo, mods))
write_csv(resumen, file.path(P$tab_mod, "nn_resumen.csv"))
cat("\nValidación cruzada (MAE OOF, millones; una localidad afuera, buffer de", BUFFER_M, "m):\n")
print(as.data.frame(resumen))
paso("Listo.")
