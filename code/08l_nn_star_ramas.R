# =============================================================================
# 08l_nn_star_ramas.R - Diagnóstico de las ramas del NN STAR (configuración de m24), D17
# Motivo: la pendiente de log(precio real) sobre log(predicción) es 0,89 en m24 (OOF de Chapinero y re-publicaciones del
# test): las predicciones varían más de lo que deberían. ¿Qué rama mete ese ruido? Hipótesis: la de texto (66 mil
# parámetros sobre 1.000 términos TF-IDF, frente a ~5 mil de la de ubicación).
# Reproduce m24 (CV por localidad con buffer, 3 épocas, lr 1e-3, MSE, calibración simple, catastro valor_estrato, sin
# zona de lujo ni OSM) y guarda la salida de cada rama en la evaluación. Luego:
#  1. Desviación estándar de cada rama y su pendiente: log(precio/m2) - calibración ~ est + ubi + txt
#     (pendiente < 1: la rama sobrerreacciona; > 1: se queda corta). En todo el train y en Chapinero.
#  2. Ablación: MAE con la rama de texto reemplazada por su media.
#  3. Pendientes estimadas dejando una localidad afuera y aplicadas a ella (sin reusar la localidad evaluada).
# No registra modelos. Salida: tables/nn_star_ramas.csv
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R")); source(here::here("code", "utils_redes.R"))

usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = "valor_estrato")
B <- BR$m2; ym2 <- YR$m2; EP <- if (PRUEBA) 1 else 3
R <- matrix(NA_real_, nrow(TR), 3, dimnames = list(NULL, c("est", "ubi", "txt"))); corr <- p_oof <- rep(NA_real_, nrow(TR))
for (f in FOLDS) {
  a <- f$analisis; e <- f$evaluacion; esc <- ajusta_escala(sub_b(B, a))
  set_random_seed(123); red <- red_star(dims(B), .1, .5)
  xa <- a_keras(esc(sub_b(B, a)), "star"); xe <- a_keras(esc(sub_b(B, e)), "star")
  p <- entrena(red, xa, ym2[a], xe, EP, 1e-3, "mse")
  R[e, ] <- sapply(predict(red$ramas, xe, batch_size = 8192, verbose = 0), drop); corr[e] <- attr(p, "corr"); p_oof[e] <- p[, 1]
}
stopifnot(max(abs(rowSums(R) + corr - p_oof)) < 1e-3)   # la predicción es la suma de las ramas más la calibración
oof <- p_oof + OFF$m2$tr; y <- exp(Y)
paso(sprintf("Reproducción de m24: MAE %.1f / Chap %.1f (registrado: 132,0 / 139,2)", evalua(oof)$mae_total / 1e6, evalua(oof)$mae_chapinero / 1e6))

z <- ym2 - corr; d <- as_tibble(R) %>% mutate(z = z)
pend <- function(s) { m <- lm(z ~ est + ubi + txt, data = d[s, ]); cf <- summary(m)$coefficients
  tibble(rama = c("est", "ubi", "txt"), pendiente = cf[-1, 1], ee = cf[-1, 2]) }
tab <- bind_rows(pend(TRUE) %>% mutate(muestra = "train"), pend(ES_CHAP) %>% mutate(muestra = "Chapinero")) %>%
  left_join(tibble(rama = c("est", "ubi", "txt"), sd_rama = apply(R, 2, sd), sd_rama_chap = apply(R[ES_CHAP, ], 2, sd)), by = "rama")
print(as.data.frame(mutate(tab, across(where(is.double), ~ round(.x, 3)))))

# Ablación: texto apagado (reemplazado por su media)
sin_txt <- oof - R[, "txt"] + mean(R[, "txt"])
# Pendientes dejando una localidad afuera: se estiman con las demás y se aplican a la evaluada
loo <- rep(NA_real_, nrow(TR))
for (g in unique(GRUPO)) { s <- GRUPO == g; m <- lm(z ~ est + ubi + txt, data = d[!s, ]); loo[s] <- predict(m, d[s, ]) + corr[s] + OFF$m2$tr[s] }
res <- tibble(variante = c("m24 reproducida", "sin texto", "pendientes por rama (fuera de la localidad)"), oof = list(oof, sin_txt, loo)) %>%
  mutate(map_dfr(oof, evalua), pred_media_chap = map_dbl(oof, ~ mean(recorta(exp(.x[ES_CHAP])))), sesgo_chap = pred_media_chap - mean(y[ES_CHAP]))
print(as.data.frame(select(res, -oof) %>% mutate(across(where(is.double), ~ round(.x / 1e6, 1)))))
write_csv(bind_rows(tab %>% mutate(tipo = "pendiente"), select(res, -oof) %>% mutate(tipo = "variante")), file.path(P$tab_mod, "nn_star_ramas.csv"))
paso("Listo.")
