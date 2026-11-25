# =============================================================================
# 90_comparacion.R - Compara los modelos registrados, arma un ensamble simple y genera figuras
# Entradas: models/registro_modelos.csv, models/oof_predicciones.csv, models/test_predicciones.csv
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))

oof <- lee_csv(file.path(P$models, "oof_predicciones.csv"))
tst <- lee_csv(file.path(P$models, "test_predicciones.csv"))
modelos <- setdiff(names(oof), c("property_id", "log_price", "grupo", "chapinero", "m00_mediana", "m90_ensamble"))
modelos <- setdiff(modelos, grep("^m9", modelos, value = TRUE))

# ---- Ensamble: pesos no negativos que minimizan el MAE OOF ----
# Selección codiciosa con reemplazo (Caruana et al., 2004): en cada uno de 20 pasos se suma el modelo que más baja
# el MAE. Da pesos múltiplos de 0,05 como la grilla anterior, pero crece lineal (no 21^k) con el número de modelos.
M <- as.matrix(oof[modelos]); Mt <- as.matrix(tst[modelos])
cuenta <- setNames(numeric(length(modelos)), modelos); actual <- 0
for (paso in 1:20) {
  k <- which.min(apply(M, 2, function(m) mae(exp(Y), recorta(exp((actual * (paso - 1) + m) / paso)))))
  cuenta[k] <- cuenta[k] + 1; actual <- (actual * (paso - 1) + M[, k]) / paso
}
w <- cuenta / 20
cat("Pesos del ensamble:\n"); print(round(w, 2))
registra("m90_ensamble", "Promedio ponderado (en log) de los modelos; pesos que minimizan el MAE OOF",
         paste(sprintf("%s=%.2f", modelos, w), collapse = "; "), evalua(drop(M %*% w)), drop(M %*% w), drop(Mt %*% w))
cat("Nota: los pesos se eligen con las mismas predicciones OOF, así que su MAE es levemente optimista.\n")

reg <- lee_csv(file.path(P$models, "registro_modelos.csv"))
print(reg %>% select(modelo, mae_total, mae_chapinero, mae_macro) %>% mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1))))

# ---- MAE por fold (localidad), al estilo de collect_metrics() de tidymodels ----
# mae_ponderado = promedio de los folds ponderado por sus anuncios del train (= mae_total);
# mae_promedio = promedio simple de los folds (= mae_macro); std_err = sd de los MAE de los folds / sqrt(folds)
oof$m90_ensamble <- drop(M %*% w)
por_fold <- map_dfr(c(modelos, "m90_ensamble"), \(m) tibble(modelo = m, localidad = oof$grupo, err = abs(exp(Y) - recorta(exp(oof[[m]]))))) %>%
  group_by(modelo, localidad) %>% summarise(n = n(), mae = mean(err), .groups = "drop")
write_csv(por_fold, file.path(P$tab_mod, "mae_por_fold.csv"))
resumen_cv <- por_fold %>% group_by(modelo) %>%
  summarise(folds = n(), mae_ponderado = weighted.mean(mae, n), mae_promedio = mean(mae), std_err = sd(mae) / sqrt(n())) %>%
  arrange(mae_ponderado)
write_csv(resumen_cv, file.path(P$tab_mod, "resumen_cv.csv"))
print(as.data.frame(mutate(resumen_cv, across(-c(modelo, folds), ~ round(.x / 1e6, 1)))))

# ---- Figura 1: comparación de MAE ----
g1 <- reg %>% select(modelo, `Todo el train` = mae_total, `Train en Chapinero` = mae_chapinero) %>%
  pivot_longer(-modelo) %>% mutate(modelo = fct_reorder(modelo, -value, .fun = max)) %>%
  ggplot(aes(value / 1e6, modelo, fill = name)) +
  geom_col(position = position_dodge(width = .75), width = .7, color = "#fcfcfb", linewidth = .5) +
  geom_text(aes(label = round(value / 1e6)), position = position_dodge(width = .75), hjust = -.15, size = 3, color = c_ink2) +
  scale_fill_manual(values = c(`Todo el train` = c_train, `Train en Chapinero` = c_test), name = NULL) +
  scale_x_continuous(expand = expansion(mult = c(0, .1))) +
  labs(title = "Error de predicción por modelo", subtitle = sprintf("MAE out-of-fold dejando una localidad afuera, buffer de %s m (millones de COP)", BUFFER_M),
       x = "MAE (millones COP)", y = NULL, caption = fuente)
ggsave(file.path(P$fig_mod, "m1_comparacion_mae.png"), g1, width = 7.5, height = 4.5, dpi = 250)

# ---- Figura 2: error por localidad del mejor modelo individual ----
mejor <- reg %>% filter(modelo %in% modelos) %>% slice_min(mae_total, n = 1) %>% pull(modelo)
err_loc <- TR %>% mutate(pred = recorta(exp(oof[[mejor]])), err = abs(price - pred), sesgo = pred - price) %>%
  group_by(localidad) %>% filter(n() >= 100) %>%
  summarise(n = n(), mae = mean(err) / 1e6, sesgo = mean(sesgo) / 1e6, mape = mean(err / price), .groups = "drop") %>%
  mutate(localidad = fct_reorder(paste0(localidad, " (n=", format(n, big.mark = ".", trim = TRUE), ")"), mae),
         es_chap = str_starts(localidad, "Chapinero"))
write_csv(err_loc, file.path(P$tab_mod, "error_por_localidad.csv"))
g2 <- ggplot(err_loc, aes(mae, localidad, fill = es_chap)) + geom_col(width = .65) +
  geom_text(aes(label = sprintf("%.0f", mae)), hjust = -.2, size = 3, color = c_ink2) +
  scale_fill_manual(values = c(`FALSE` = "#86b6ef", `TRUE` = c_test), guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, .12))) +
  labs(title = "Chapinero está entre las localidades con mayor error",
       subtitle = sprintf("MAE out-of-fold por localidad, modelo %s (millones COP)", mejor), x = "MAE (millones COP)", y = NULL, caption = fuente)
ggsave(file.path(P$fig_mod, "m2_error_localidad.png"), g2, width = 7, height = 4.8, dpi = 250)

# ---- Figura 3: predicho vs observado en Chapinero ----
g3 <- tibble(obs = exp(Y[ES_CHAP]) / 1e6, pred = recorta(exp(oof[[mejor]][ES_CHAP])) / 1e6) %>%
  ggplot(aes(obs, pred)) + geom_abline(color = c_muted, linetype = 2) +
  geom_point(color = c_test, alpha = .6, size = 1.6) + coord_equal(xlim = c(300, 1650), ylim = c(300, 1650)) +
  labs(title = "Predicho vs. observado en Chapinero", subtitle = sprintf("Predicciones out-of-fold, %s (millones COP)", mejor),
       x = "Precio observado", y = "Precio predicho", caption = fuente)
ggsave(file.path(P$fig_mod, "m3_pred_obs_chapinero.png"), g3, width = 5.5, height = 5.8, dpi = 250)

# ---- Figura 4: importancia de variables (XGBoost, ganancia) ----
if (file.exists(file.path(P$tab_mod, "xgb_importancia.csv"))) {
  imp <- lee_csv(file.path(P$tab_mod, "xgb_importancia.csv")) %>% slice_max(Gain, n = 20) %>%
    mutate(Feature = fct_reorder(Feature, Gain))
  g4 <- ggplot(imp, aes(Gain, Feature)) + geom_col(fill = c_train, width = .65) +
    scale_x_continuous(labels = percent) +
    labs(title = "Variables más importantes (XGBoost)", subtitle = "Participación en la ganancia total de los árboles, top 20",
         x = "Ganancia", y = NULL, caption = fuente)
  ggsave(file.path(P$fig_mod, "m4_importancia_xgb.png"), g4, width = 7, height = 5.5, dpi = 250)
}
cat("Listo.\n")
