# =============================================================================
# 08c_nn_star.R - NN STAR (Mayer, Bourassa, Hoesli y Scognamiglio, 2022, sección 3.2) con ReLU, D17
# Salida = suma de tres ramas que nunca se mezclan (cada una es un rubro interpretable):
#  - Estructura: Dense(1) lineal -> un coeficiente por variable (efectos aditivos, ICE paralelas).
#  - Ubicación: 64-32-16 ReLU con dropout p_u + atajo lineal (para extrapolar hacia Chapinero) -> encoder de ubicación.
#  - Texto (TF-IDF, 1.000 términos): 64-32-16 ReLU con dropout p_t + atajo lineal (peso por palabra) -> encoder de texto.
# Nivel calibrado (Remark 6 del paper). Sin dummies de localidad (D10); validación cv_oof con buffer (D9).
# Afinación: p_u en {0, .1, .2} × p_t en {0, .25, .5} con objetivo m2; con la mejor pareja, también objetivo precio.
# Salidas: tables/nn_star_dropout.csv, data/processed/nn_star_encoders.csv, figures/m8_nn_star_mapa_ubicacion.png,
#          registro m17_nn_star_m2 y m17_nn_star
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R")); source(here::here("code", "utils_redes.R"))

grilla <- expand_grid(p_u = c(0, .1, .2), p_t = c(0, .25, .5)); if (PRUEBA) grilla <- grilla[1, ]
construye <- function(g, d) red_star(d, g$p_u, g$p_t)
cat("Entradas (m2):", paste(names(dims(BR$m2)), dims(BR$m2), collapse = " | "),
    "| parámetros:", count_params(red_star(dims(BR$m2), 0, 0)$modelo), "\n")

tab <- busca_red(grilla, construye, file.path(P$tab_mod, "nn_star_dropout.csv"))

# ---- Modelos finales (mejor configuración por objetivo), registro y envío ----
finales <- tab %>% group_by(objetivo) %>% slice_min(mae_total, n = 1, with_ties = FALSE) %>% ungroup()
for (k in seq_len(nrow(finales))) {
  b <- finales[k, ]; f <- ajusta_final(b, construye)
  if (!PRUEBA) registra(paste0("m17_nn_star", if (b$objetivo == "m2") "_m2"),
    paste("NN STAR (Keras): estructura lineal + ubicación y texto 64-32-16 ReLU con atajo lineal, ramas sumadas, nivel calibrado;",
          if (b$objetivo == "m2") "sobre log(precio por m2), precio = predicción × m2" else "sobre log(precio)"),
    sprintf("p_u=%g; p_t=%g; épocas=%d; lr=%g; batch=%d; l2=%g; mse", b$p_u, b$p_t, b$epocas, LR, BATCH, L2),
    select(b, starts_with("ma")), b$oof[[1]], f$pred_te)
  if (b$objetivo == "m2") fm <- f
}
paso("modelos finales ajustados")

# ---- Verificaciones (objetivo m2) ----
pr <- \(m, x) predict(m, x, batch_size = 8192, verbose = 0)
r_tr <- map(pr(fm$red$ramas, fm$xtr), drop); tot <- drop(pr(fm$red$modelo, fm$xtr))
d_suma <- max(abs(Reduce(`+`, r_tr) - tot)); cat("Suma de las ramas - predicción: dif. máx. =", signif(d_suma, 3), "\n")
stopifnot(d_suma < 1e-3)
cat("Media de los residuos del train tras calibrar =", signif(mean(YR$m2 - tot - fm$corr), 3), "\n")
Bs <- ajusta_escala(BR$m2)(BR$m2); set.seed(123); s <- sample(nrow(TR), 150)
ice <- sapply(c(-1, 1), function(v) { B1 <- sub_b(Bs, s); B1$est[, "bedrooms"] <- v; drop(pr(fm$red$modelo, a_keras(B1, "star"))) })
cat("ICE de habitaciones: desv. est. del efecto entre anuncios =", signif(sd(ice[, 2] - ice[, 1]), 3), "(0 = paralelas)\n")

# ---- Encoders = salidas de las ramas de ubicación y de texto, centradas con el train ----
r_te <- map(pr(fm$red$ramas, fm$xte), drop)
cen <- \(x, ref) x - mean(ref)
enc <- bind_rows(
  tibble(property_id = TR$property_id, muestra = "train", enc_ubicacion = cen(r_tr[[2]], r_tr[[2]]), enc_texto = cen(r_tr[[3]], r_tr[[3]])),
  tibble(property_id = TE$property_id, muestra = "test",  enc_ubicacion = cen(r_te[[2]], r_tr[[2]]), enc_texto = cen(r_te[[3]], r_tr[[3]])))
write_csv(enc, file.path(P$processed, "nn_star_encoders.csv"))
star <- lee_csv(file.path(P$processed, "star_encoders.csv"))
cmp <- inner_join(enc, star, by = c("property_id", "muestra"), suffix = c("_nn", "_xgb"))
cat("Correlación con los encoders del XGB STAR: ubicación", round(cor(cmp$enc_ubicacion_nn, cmp$enc_ubicacion_xgb), 3),
    "| texto", round(cor(cmp$enc_texto_nn, cmp$enc_texto_xgb), 3), "\n")
cat("Encoders (media test - media train): ubicación", round(mean(enc$enc_ubicacion[enc$muestra == "test"]), 3),
    "| texto", round(mean(enc$enc_texto[enc$muestra == "test"]), 3), "\n")
mapa_prima(enc, "Prima de ubicación aprendida por el NN STAR",
           "Salida de la rama de ubicación (mediana por celda de ~500 m; train y test)", "m8_nn_star_mapa_ubicacion.png")

cat("\nAfinación del dropout (MAE OOF, millones):\n")
print(as.data.frame(select(tab, -oof) %>% mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1)))))
paso("Listo.")
