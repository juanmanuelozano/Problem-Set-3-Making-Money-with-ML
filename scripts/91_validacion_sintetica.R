# =============================================================================
# 91_validacion_sintetica.R - "Chapinero sintético": validación ponderada hacia el test (D18)
# Basado en Brenning y Suesse (2026), "Aligning Validation with Deployment: Target-Weighted Cross-Validation
# for Spatial Prediction" (arXiv 2603.29981).
# Idea: la validación (una localidad afuera, con buffer) promedia errores de anuncios que se parecen poco al
# test (Chapinero: más caro, más estrato 6). No se cambian los folds: se REPONDERAN los errores out-of-fold ya
# guardados, para que los anuncios validados se parezcan, en promedio, a los del test.
#  - TWCV (target-weighted CV): pesos por calibración (raking) que igualan las proporciones de unas pocas
#    variables discretizadas a las del test. Encogimiento del 20% hacia pesos iguales (lambda = 0,2).
#  - IWCV (importance-weighted CV): pesos p/(1 - p) de un logit que distingue test de train (comparación).
# Los pesos (W_TWCV, W_IWCV) y sus funciones están en utils_modelos.R, para que cualquier modelo los use.
# Solo se usan las VARIABLES del test, nunca su precio: no hay fuga de información.
# El error es el absoluto (Kaggle mide MAE). Se compara con los scores públicos de Kaggle.
# Salidas: tables/validacion_sintetica.csv, tables/vs_pesos_localidad.csv, figures/m6_validacion_sintetica.png
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")

# ---- 1. Errores out-of-fold de todos los modelos registrados ----
oof <- lee_csv(file.path(P$models, "oof_predicciones.csv"))
stopifnot(identical(oof$property_id, TR$property_id))           # mismo orden que el train de la base
modelos <- setdiff(names(oof), c("property_id", "log_price", "grupo", "chapinero"))
y <- exp(oof$log_price)
err <- sapply(modelos, function(m) abs(y - recorta(exp(oof[[m]]))))   # n_train × modelos, en pesos

# ---- 2. Variables de balanceo (discretizadas con los quintiles del test) y cobertura ----
# Toda categoría que aparece en el test debe tener anuncios en el train (si no, no hay pesos posibles)
v <- vars_balanceo()
for (nm in names(v)) {
  tab <- tibble(cat = levels(v[[nm]]$te), test = as.vector(prop.table(table(v[[nm]]$te))),
                train = as.vector(prop.table(table(v[[nm]]$tr))), n_train = as.vector(table(v[[nm]]$tr)))
  cat("\n", nm, "\n"); print(tab %>% mutate(across(c(test, train), ~ round(.x, 3))))
  stopifnot(all(tab$n_train[tab$test > 0] > 0))
}

# ---- 3. Pesos (de utils_modelos.R) y tamaño efectivo de muestra ----
w_tw <- W_TWCV; w_iw <- W_IWCV
cat(sprintf("\nTamaño efectivo de muestra (ESS): TWCV %.0f (%.1f%%) | IWCV %.0f (%.1f%%) de %d anuncios\n",
            ess(w_tw), 100 * ess(w_tw) / nrow(TR), ess(w_iw), 100 * ess(w_iw) / nrow(TR), nrow(TR)))

# Composición del "Chapinero sintético": peso total de cada localidad del train
comp <- tibble(localidad = GRUPO, twcv = w_tw, iwcv = w_iw) %>% group_by(localidad) %>%
  summarise(n = n(), peso_sin_ponderar = n / nrow(TR), twcv = sum(twcv), iwcv = sum(iwcv)) %>%
  arrange(desc(twcv))
write_csv(comp, file.path(P$rep_mod, "tables", "vs_pesos_localidad.csv"))
print(comp %>% mutate(across(c(peso_sin_ponderar, twcv, iwcv), ~ round(100 * .x, 1))), n = 25)

# ---- 4. Diagnóstico: distancia de predicción d (al anuncio de entrenamiento más cercano) ----
# En la validación, d se mide contra el conjunto de análisis de su fold; en el test, contra todo el train.
d_val <- numeric(nrow(TR))
for (f in FOLDS) d_val[f$evaluacion] <- dist_min(TR$lat[f$evaluacion], TR$lon[f$evaluacion],
                                                 TR$lat[f$analisis], TR$lon[f$analisis], bloque = 300)
d_test <- dist_min(TE$lat, TE$lon, TR$lat, TR$lon, bloque = 300)
q <- c(.1, .25, .5, .75, .9)
cat("\nDistancia de predicción d (m), cuantiles 10/25/50/75/90:\n")
cat("  validación:", round(quantile(d_val, q)), "\n  test:      ", round(quantile(d_test, q)), "\n")
cat(sprintf("  test con d < 500 m: %.1f%% | validación con d < 500 m: %.1f%%\n", 100 * mean(d_test < 500), 100 * mean(d_val < 500)))

# ---- 5. MAE por modelo: validación actual, TWCV, IWCV y Kaggle ----
kaggle <- lee_csv(file.path(P$models, "kaggle_scores.csv")) %>% group_by(modelo) %>%
  summarise(kaggle = min(public_score))
res <- tibble(modelo = modelos,
              mae_total = colMeans(err),
              mae_chapinero = colMeans(err[ES_CHAP, , drop = FALSE]),
              mae_twcv = as.vector(crossprod(w_tw, err)),
              mae_iwcv = as.vector(crossprod(w_iw, err))) %>%
  left_join(kaggle, by = "modelo") %>% arrange(mae_twcv)
write_csv(res, file.path(P$rep_mod, "tables", "validacion_sintetica.csv"))
print(res %>% mutate(across(where(is.numeric), ~ round(.x / 1e6, 1))), n = Inf)

# ¿Qué validación se parece más a Kaggle? (solo modelos con score público)
k <- filter(res, !is.na(kaggle))
cmp <- map_dfr(c("mae_total", "mae_chapinero", "mae_twcv", "mae_iwcv"), function(cn) tibble(
  validacion = cn, n_modelos = nrow(k),
  sesgo_medio_M = mean(k[[cn]] - k$kaggle) / 1e6,                       # negativo = optimista
  error_abs_medio_M = mean(abs(k[[cn]] - k$kaggle)) / 1e6,
  spearman = cor(k[[cn]], k$kaggle, method = "spearman")))               # ¿ordena los modelos como Kaggle?
cat("\nComparación con Kaggle:\n"); print(cmp %>% mutate(across(where(is.numeric), ~ round(.x, 2))))
write_csv(cmp, file.path(P$rep_mod, "tables", "validacion_sintetica_vs_kaggle.csv"))

# ---- 6. Figura: cada validación contra el score de Kaggle ----
etq <- c(mae_total = "CV por localidad (total)", mae_chapinero = "CV: solo Chapinero del train",
         mae_twcv = "Chapinero sintético (TWCV)", mae_iwcv = "Chapinero sintético (IWCV)")
g <- k %>% pivot_longer(c(mae_total, mae_chapinero, mae_twcv, mae_iwcv), names_to = "validacion", values_to = "mae") %>%
  mutate(validacion = factor(etq[validacion], etq)) %>%
  ggplot(aes(kaggle / 1e6, mae / 1e6)) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = c_muted) +
  geom_point(color = c_train, size = 2.5) +
  facet_wrap(~ validacion, nrow = 1) +
  labs(title = "¿Qué validación anticipa el score de Kaggle?",
       subtitle = "Cada punto es un modelo enviado. Sobre la diagonal, la validación acierta; debajo, es optimista",
       x = "MAE público en Kaggle (millones de COP)", y = "MAE estimado en la validación (millones)", caption = fuente)
ggsave(file.path(P$rep_mod, "figures", "m6_validacion_sintetica.png"), g, width = 11, height = 4, dpi = 300)
cat("Listo.\n")
