# =============================================================================
# 08e_nn_star_afinacion.R - Afinación por etapas del NN STAR (misma arquitectura que 08c), objetivo m2, D16
# Referencia: m17_nn_star_m2 (08c; se llamaba m15_nn_star_m2 antes del merge; Kaggle 158,3). No se toca ni se
# sobrescribe. Cada etapa parte de la ganadora de la anterior, elegida por MAE total:
#  0. Datos nuevos (D14, D15) sin la zona de lujo (LUJO en utils_redes.R): la configuración de m17 (lr 1e-3, p_u 0,1,
#     p_t 0,5, MSE) con la base nueva. Separa el efecto de los datos del de la afinación y es el punto de lr = 1e-3
#     de la etapa 1. Ablación previa (misma configuración): base nueva completa 137,0 / 166,5; sin lujo 133,6 / 148,8;
#     sin lujo ni OSM 131,9 / 148,3; base vieja 131,4 / 146,9 (= m17, control del código).
#  1. Tasa de aprendizaje: {3e-4, 1e-4}, con épocas hasta 150 (con lr 1e-3, hasta 80).
#  2. Dropouts: p_u en {0,1; 0,15} × p_t en {0,5; 0,6; 0,7}, con la tasa ganadora.
#  3. Pérdida absoluta (MAE) frente a MSE, con la mejor configuración.
# Cada fila: MAE total / Chapinero / macro, épocas (y si quedan en el borde), sesgo en Chapinero, predicción media
# del test y prueba pareada (error absoluto por anuncio) frente a m17_nn_star_m2.
# Salidas: tables/nn_star_afinacion.csv (se guarda a medida que avanza); registro m19_nn_star_afinada_m2 (ganadora)
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R"); source("scripts/utils_redes.R")

REF <- "m17_nn_star_m2"
EP_LARGAS <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 100, 5), seq(110, 150, 10))
f_tab <- file.path(P$rep_mod, "tables", "nn_star_afinacion.csv")
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv")); tst <- lee_csv(file.path(P$models, "test_predicciones.csv"))
ref <- oofs[[REF]][match(TR$property_id, oofs$property_id)]
y <- exp(Y); err <- \(p) abs(y - recorta(exp(p)))
pareada <- function(p) {
  d <- err(p) - err(ref)
  c(dif_chap = mean(d[ES_CHAP]), t_chap = unname(t.test(d[ES_CHAP])$statistic), dif_total = mean(d), t_total = unname(t.test(d)$statistic))
}
cat(sprintf("Referencia %s: MAE %.1f / Chap %.1f | sesgo Chap %.1f | predicción media del test %.1f (millones)\n", REF,
            mean(err(ref)) / 1e6, mean(err(ref)[ES_CHAP]) / 1e6, mean(recorta(exp(ref[ES_CHAP])) - y[ES_CHAP]) / 1e6,
            mean(recorta(exp(tst[[REF]]))) / 1e6))
cat("Entradas (m2):", paste(names(dims(BR$m2)), dims(BR$m2), collapse = " | "), "\n")

construye <- function(g, d) red_star(d, g$p_u, g$p_t)
res <- list()
corre <- function(etapa, cfg) {   # cfg: lr, p_u, p_t, perdida
  ep <- if (cfg$lr >= 1e-3) EPOCAS else EP_LARGAS
  r <- cv_red(\(d) construye(cfg, d), "m2", ep, cfg$lr, cfg$perdida)
  f <- ajusta_final(mutate(cfg, objetivo = "m2", epocas = r$epocas), construye, cfg$lr, cfg$perdida)
  fila <- cfg %>% mutate(etapa = etapa, epocas = r$epocas, borde = r$borde) %>% bind_cols(evalua(r$oof)) %>%
    mutate(sesgo_chap = mean(recorta(exp(r$oof[ES_CHAP])) - y[ES_CHAP]), pred_test = mean(recorta(exp(f$pred_te)))) %>%
    bind_cols(as_tibble_row(pareada(r$oof))) %>% mutate(oof = list(r$oof), pred_te = list(f$pred_te))
  res[[length(res) + 1]] <<- fila
  write_csv(select(bind_rows(res), -oof, -pred_te), f_tab)
  paso(sprintf(paste("%s | lr %g, p_u %g, p_t %g, %s | épocas %d%s | MAE %.1f / Chap %.1f / macro %.1f | sesgo Chap %.1f |",
                     "test %.1f | frente a %s: Chap %+.1f (t %.2f), total %+.1f (t %.2f)"),
               etapa, cfg$lr, cfg$p_u, cfg$p_t, cfg$perdida, r$epocas, if (r$borde) " (BORDE)" else "",
               fila$mae_total / 1e6, fila$mae_chapinero / 1e6, fila$mae_macro / 1e6, fila$sesgo_chap / 1e6, fila$pred_test / 1e6,
               REF, fila$dif_chap / 1e6, fila$t_chap, fila$dif_total / 1e6, fila$t_total))
  fila
}
mejor <- \(...) bind_rows(...) %>% slice_min(mae_total, n = 1, with_ties = FALSE)

# ---- Etapa 0: datos nuevos con la configuración de m17 ----
cfg0 <- tibble(lr = 1e-3, p_u = .1, p_t = .5, perdida = "mse")
e0 <- corre("0_datos_nuevos", cfg0)

# ---- Etapa 1: tasa de aprendizaje ----
e1 <- map(if (PRUEBA) 3e-4 else c(3e-4, 1e-4), \(tasa) corre("1_tasa", mutate(cfg0, lr = tasa)))
b1 <- mejor(e0, e1)

# ---- Etapa 2: dropouts con la tasa ganadora ----
g2 <- expand_grid(p_u = c(.1, .15), p_t = c(.5, .6, .7)) %>% filter(!(p_u == b1$p_u & p_t == b1$p_t))
if (PRUEBA) g2 <- g2[1, ]
e2 <- map(seq_len(nrow(g2)), \(k) corre("2_dropout", tibble(lr = b1$lr, p_u = g2$p_u[k], p_t = g2$p_t[k], perdida = "mse")))
b2 <- mejor(b1, e2)

# ---- Etapa 3: pérdida absoluta frente a MSE ----
e3 <- corre("3_perdida", mutate(select(b2, lr, p_u, p_t), perdida = "mae"))
fin <- mejor(b2, e3)

# ---- Registro de la ganadora ----
cat(sprintf("\nGanadora: lr %g, p_u %g, p_t %g, pérdida %s, %d épocas\n", fin$lr, fin$p_u, fin$p_t, fin$perdida, fin$epocas))
if (!PRUEBA) registra("m19_nn_star_afinada_m2",
  "NN STAR afinado (08e): misma arquitectura que m17, base con D14 y D15 sin zona de lujo; sobre log(precio por m2), precio = predicción × m2",
  sprintf("lr=%g; p_u=%g; p_t=%g; pérdida=%s; épocas=%d; batch=%d; l2=%g", fin$lr, fin$p_u, fin$p_t, fin$perdida, fin$epocas, BATCH, L2),
  select(fin, starts_with("ma")), fin$oof[[1]], fin$pred_te[[1]])

cat("\nAfinación por etapas (millones; dif = error del modelo − error de", REF, "por anuncio):\n")
print(as.data.frame(select(bind_rows(res), etapa, lr, p_u, p_t, perdida, epocas, borde, mae_total, mae_chapinero, mae_macro,
                           sesgo_chap, pred_test, dif_chap, t_chap, dif_total, t_total) %>%
  mutate(across(c(mae_total, mae_chapinero, mae_macro, sesgo_chap, pred_test, dif_chap, dif_total), ~ round(.x / 1e6, 1)),
         across(c(t_chap, t_total), ~ round(.x, 2)))))
paso("Listo.")
