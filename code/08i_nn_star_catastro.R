# =============================================================================
# 08i_nn_star_catastro.R - NN STAR con catastro (valor del suelo + estrato oficial, D18): registro y afinación, D17
# Base: D14 sin zona de lujo ni contexto de OSM; catastro "valor_estrato" (ganó la mini corrida de 08h: 132,0 / 139,2,
# TWCV 138,2, predicción del test 841 frente a 826 de m17). Todo se elige por MAE TWCV (D16).
#  0. Configuración de m17 (lr 1e-3, p_u 0,1, p_t 0,5, MSE, calibración simple): se registra como m24_nn_star_catastro_m2
#     (la versión menos entrenada, que en 08h mantuvo el nivel del test).
#  A. Grilla: lr {1e-3, 3e-4, 1e-4} × pérdida {MSE, MAE} × p_t {0,5; 0,7}, con p_u 0,1 y texto 64-32-16 (12 celdas;
#     la de la etapa 0 no se repite). Las épocas van hasta 80 con lr 1e-3 y hasta 60 con tasas menores.
#  B. Calibración ponderada por TWCV frente a la simple, en la ganadora.
#  C. Promedio de 3 semillas, en la ganadora.
# La ganadora se registra como m25_nn_star_catastro_afinada_m2 y se escribe en tables/nn_star_catastro_ganadora.csv
# (la lee 08g con GANADORA= para entrenar la red general del mismo tamaño y con los mismos datos).
# Salidas: tables/nn_star_catastro_afinacion.csv (se guarda a medida que avanza)
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R")); source(here::here("code", "utils_redes.R"))

REF <- "m17_nn_star_m2"; W <- pesos_twcv(); CAT_V <- "valor_estrato"; SEM3 <- c(123, 124, 125)
EP60 <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 60, 5))
f_tab <- file.path(P$tab_mod, "nn_star_catastro_afinacion.csv")
f_gan <- file.path(P$tab_mod, "nn_star_catastro_ganadora.csv")
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv"))
ref <- oofs[[REF]][match(TR$property_id, oofs$property_id)]
y <- exp(Y); err <- \(p) abs(y - recorta(exp(p)))
usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = CAT_V)
cat("Entradas (m2):", paste(names(dims(BR$m2)), dims(BR$m2), collapse = " | "), "\n")

construye <- function(g, d) red_star(d, g$p_u, g$p_t)
res <- list()
corre <- function(etapa, cfg) {   # cfg: lr, p_u, p_t, perdida, cal, n_sem
  ep <- if (cfg$lr >= 1e-3) EPOCAS else EP60
  w_cal <- if (cfg$cal == "twcv") W else NULL; sem <- if (cfg$n_sem == 3) SEM3 else 123
  r <- cv_red(\(d) construye(cfg, d), "m2", ep, cfg$lr, cfg$perdida, w = W, w_cal = w_cal, semillas = sem)
  f <- ajusta_final(mutate(cfg, objetivo = "m2", epocas = r$epocas), construye, cfg$lr, cfg$perdida, w_cal, sem)
  d <- err(r$oof) - err(ref)
  fila <- cfg %>% mutate(etapa = etapa, parametros = count_params(f$red$modelo), epocas = r$epocas, borde = r$borde) %>%
    bind_cols(evalua(r$oof)) %>%
    mutate(mae_twcv = mae_w(r$oof, W), sesgo_chap = mean(recorta(exp(r$oof[ES_CHAP])) - y[ES_CHAP]),
           pred_test = mean(recorta(exp(f$pred_te))), dif_chap = mean(d[ES_CHAP]), t_chap = unname(t.test(d[ES_CHAP])$statistic),
           dif_total = mean(d), t_total = unname(t.test(d)$statistic), oof = list(r$oof), pred_te = list(f$pred_te))
  res[[length(res) + 1]] <<- fila
  write_csv(select(bind_rows(res), -oof, -pred_te), f_tab)
  paso(sprintf(paste("%s | lr %g, p_t %g, %s, cal %s, %d sem | ép %d%s | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f |",
                     "sesgo %.1f | test %.1f | vs m17: Chap %+.1f (t %.2f), total %+.1f (t %.2f)"),
               etapa, cfg$lr, cfg$p_t, cfg$perdida, cfg$cal, cfg$n_sem, r$epocas, if (r$borde) " (BORDE)" else "",
               fila$mae_total / 1e6, fila$mae_chapinero / 1e6, fila$mae_macro / 1e6, fila$mae_twcv / 1e6, fila$sesgo_chap / 1e6,
               fila$pred_test / 1e6, fila$dif_chap / 1e6, fila$t_chap, fila$dif_total / 1e6, fila$t_total))
  fila
}
mejor <- \(...) bind_rows(...) %>% slice_min(mae_twcv, n = 1, with_ties = FALSE)
sel <- \(x) select(x, lr, p_u, p_t, perdida, cal, n_sem)
reg <- function(nombre, b, desc) if (!PRUEBA) registra(nombre,
  paste0("NN STAR con catastro (valor del suelo + estrato oficial, D18), ", desc, "; base D14 sin zona de lujo ni OSM; sobre log(precio por m2)"),
  sprintf("lr=%g; p_u=%g; p_t=%g; pérdida=%s; calibración=%s; semillas=%d; épocas=%d; batch=%d; l2=%g",
          b$lr, b$p_u, b$p_t, b$perdida, b$cal, b$n_sem, b$epocas, BATCH, L2),
  select(b, starts_with("ma")), b$oof[[1]], b$pred_te[[1]])

# ---- 0. Configuración de m17 con catastro (registro) ----
cfg0 <- tibble(lr = 1e-3, p_u = .1, p_t = .5, perdida = "mse", cal = "simple", n_sem = 1)
e0 <- corre("0_config_m17", cfg0)
reg("m24_nn_star_catastro_m2", e0, "configuración de m17 (08i, etapa 0)")

# ---- A. Grilla: tasa × pérdida × dropout del texto ----
gA <- expand_grid(lr = c(1e-3, 3e-4, 1e-4), perdida = c("mse", "mae"), p_t = c(.5, .7)) %>%
  filter(!(lr == 1e-3 & perdida == "mse" & p_t == .5))
if (PRUEBA) gA <- gA[c(1, nrow(gA)), ]
eA <- map(seq_len(nrow(gA)), \(k) corre("A_grilla", tibble(lr = gA$lr[k], p_u = .1, p_t = gA$p_t[k], perdida = gA$perdida[k],
                                                          cal = "simple", n_sem = 1)))
b <- mejor(e0, eA)
# ---- B. Calibración ponderada ----
b <- mejor(b, corre("B_calibracion", mutate(sel(b), cal = "twcv")))
# ---- C. Tres semillas ----
fin <- mejor(b, corre("C_semillas", mutate(sel(b), n_sem = 3)))

cat(sprintf("\nGanadora: lr %g, p_t %g, %s, calibración %s, %d semillas, %d épocas\n", fin$lr, fin$p_t, fin$perdida, fin$cal, fin$n_sem, fin$epocas))
write_csv(select(fin, -oof, -pred_te) %>% mutate(texto = "64-32-16", area_m2 = FALSE, osm = FALSE, catastro = CAT_V), f_gan)
reg("m25_nn_star_catastro_afinada_m2", fin, "afinado por TWCV (08i)")
print(as.data.frame(select(bind_rows(res), etapa, lr, p_t, perdida, cal, n_sem, epocas, borde, mae_total, mae_chapinero, mae_macro,
                           mae_twcv, sesgo_chap, pred_test, dif_chap, t_chap, dif_total, t_total) %>%
  mutate(across(c(mae_total, mae_chapinero, mae_macro, mae_twcv, sesgo_chap, pred_test, dif_chap, dif_total), ~ round(.x / 1e6, 1)),
         across(c(t_chap, t_total), ~ round(.x, 2)))))
paso("Listo.")
