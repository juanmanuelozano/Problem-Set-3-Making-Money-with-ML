# =============================================================================
# 08f_nn_star_twcv.R - NN STAR elegido con la validación ponderada hacia el test (TWCV, D16), objetivo m2, D17
# Todo se elige por MAE TWCV (épocas y configuraciones). Base nueva (D14) sin zona de lujo; el contexto de OSM se
# mide primero sin y al final con. Fijo, por lo aprendido en 08e: lr 1e-4, p_u 0,15, p_t 0,6, épocas hasta 60.
#  A. Grilla de arquitectura: rama de texto {64-32-16, 32-16} × área en m2 {no, sí} × pérdida {MSE, MAE}.
#     Área en m2: log_area entra en la rama lineal (desviación de la elasticidad precio-área frente a 1).
#  B. Calibración del nivel ponderada por TWCV frente a la simple, en la ganadora.
#  C. Con y sin contexto de OSM, en la ganadora.
#  D. Promedio de 3 semillas, en la ganadora.
# Cada fila: MAE total / Chapinero / macro / TWCV, épocas (borde), sesgo en Chapinero, predicción media del test y
# prueba pareada frente a m17_nn_star_m2 (Kaggle 158,3).
# Salidas: tables/nn_star_twcv.csv (se guarda a medida que avanza), tables/nn_star_twcv_ganadora.csv (la leen 08g,
#          08 y 08b para seguir la decisión de OSM); registro m20_nn_star_twcv_m2
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R")); source(here::here("code", "utils_redes.R"))

REF <- "m17_nn_star_m2"; W <- pesos_twcv()
EP60 <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 60, 5))
SEM3 <- c(123, 124, 125)
f_tab <- file.path(P$tab_mod, "nn_star_twcv.csv")
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv")); tst <- lee_csv(file.path(P$models, "test_predicciones.csv"))
ref <- oofs[[REF]][match(TR$property_id, oofs$property_id)]
y <- exp(Y); err <- \(p) abs(y - recorta(exp(p)))
pareada <- function(p) {
  d <- err(p) - err(ref)
  c(dif_chap = mean(d[ES_CHAP]), t_chap = unname(t.test(d[ES_CHAP])$statistic), dif_total = mean(d), t_total = unname(t.test(d)$statistic))
}
cat(sprintf("Referencia %s: MAE %.1f / Chap %.1f / TWCV %.1f | predicción media del test %.1f (millones)\n", REF,
            mean(err(ref)) / 1e6, mean(err(ref)[ES_CHAP]) / 1e6, mae_w(ref, W) / 1e6, mean(recorta(exp(tst[[REF]]))) / 1e6))

capas_de <- function(texto) as.integer(strsplit(texto, "-")[[1]])
construye <- function(g, d) red_star(d, g$p_u, g$p_t, capas_t = capas_de(g$texto))
res <- list()
corre <- function(etapa, cfg) {   # cfg: texto, area_m2, perdida, cal, osm, n_sem (+ lr, p_u, p_t)
  usa_bloques(cfg$area_m2, cfg$osm)
  w_cal <- if (cfg$cal == "twcv") W else NULL; sem <- if (cfg$n_sem == 3) SEM3 else 123
  r <- cv_red(\(d) construye(cfg, d), "m2", EP60, cfg$lr, cfg$perdida, w = W, w_cal = w_cal, semillas = sem)
  f <- ajusta_final(mutate(cfg, objetivo = "m2", epocas = r$epocas), construye, cfg$lr, cfg$perdida, w_cal, sem)
  fila <- cfg %>% mutate(etapa = etapa, parametros = count_params(f$red$modelo), entradas = paste(dims(BR$m2), collapse = "/"),
                         epocas = r$epocas, borde = r$borde) %>% bind_cols(evalua(r$oof)) %>%
    mutate(mae_twcv = mae_w(r$oof, W), sesgo_chap = mean(recorta(exp(r$oof[ES_CHAP])) - y[ES_CHAP]),
           pred_test = mean(recorta(exp(f$pred_te)))) %>%
    bind_cols(as_tibble_row(pareada(r$oof))) %>% mutate(oof = list(r$oof), pred_te = list(f$pred_te))
  res[[length(res) + 1]] <<- fila
  write_csv(select(bind_rows(res), -oof, -pred_te), f_tab)
  paso(sprintf(paste("%s | texto %s, área %s, %s, cal %s, osm %s, %d sem | ép %d%s | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f |",
                     "sesgo %.1f | test %.1f | vs m17: Chap %+.1f (t %.2f), total %+.1f (t %.2f)"),
               etapa, cfg$texto, cfg$area_m2, cfg$perdida, cfg$cal, cfg$osm, cfg$n_sem, r$epocas, if (r$borde) " (BORDE)" else "",
               fila$mae_total / 1e6, fila$mae_chapinero / 1e6, fila$mae_macro / 1e6, fila$mae_twcv / 1e6, fila$sesgo_chap / 1e6,
               fila$pred_test / 1e6, fila$dif_chap / 1e6, fila$t_chap, fila$dif_total / 1e6, fila$t_total))
  fila
}
mejor <- \(...) bind_rows(...) %>% slice_min(mae_twcv, n = 1, with_ties = FALSE)
base_cfg <- tibble(lr = 1e-4, p_u = .15, p_t = .6, cal = "simple", osm = FALSE, n_sem = 1)

# ---- A. Grilla de arquitectura ----
gA <- expand_grid(texto = c("64-32-16", "32-16"), area_m2 = c(FALSE, TRUE), perdida = c("mse", "mae"))
if (PRUEBA) gA <- gA[c(1, 8), ]
eA <- map(seq_len(nrow(gA)), \(k) corre("A_arquitectura", bind_cols(gA[k, ], base_cfg)))
b <- mejor(eA)
sel <- \(x) select(x, lr, p_u, p_t, texto, area_m2, perdida, cal, osm, n_sem)

# ---- B. Calibración ponderada por TWCV ----
b <- mejor(b, corre("B_calibracion", mutate(sel(b), cal = "twcv")))
# ---- C. Con contexto de OSM ----
b <- mejor(b, corre("C_osm", mutate(sel(b), osm = TRUE)))
# ---- D. Promedio de 3 semillas ----
fin <- mejor(b, corre("D_semillas", mutate(sel(b), n_sem = 3)))

# ---- Ganadora: registro y archivo para los demás scripts ----
cat(sprintf("\nGanadora: texto %s, área en m2 %s, pérdida %s, calibración %s, OSM %s, %d semillas, %d épocas, %d parámetros\n",
            fin$texto, fin$area_m2, fin$perdida, fin$cal, fin$osm, fin$n_sem, fin$epocas, fin$parametros))
write_csv(select(fin, -oof, -pred_te), F_GANADORA_NN)
if (!PRUEBA) registra("m20_nn_star_twcv_m2",
  paste0("NN STAR elegido por TWCV (08f): texto ", fin$texto, if (fin$area_m2) ", log_area en la rama lineal" else "",
         ", base D14 sin zona de lujo", if (fin$osm) " con" else " sin", " contexto de OSM; sobre log(precio por m2)"),
  sprintf("lr=%g; p_u=%g; p_t=%g; pérdida=%s; calibración=%s; semillas=%d; épocas=%d; batch=%d; l2=%g",
          fin$lr, fin$p_u, fin$p_t, fin$perdida, fin$cal, fin$n_sem, fin$epocas, BATCH, L2),
  select(fin, starts_with("ma")), fin$oof[[1]], fin$pred_te[[1]])

cat("\nNN STAR por TWCV (millones; dif = error del modelo − error de", REF, "por anuncio):\n")
print(as.data.frame(select(bind_rows(res), etapa, texto, area_m2, perdida, cal, osm, n_sem, parametros, epocas, borde,
                           mae_total, mae_chapinero, mae_macro, mae_twcv, sesgo_chap, pred_test, dif_chap, t_chap, dif_total, t_total) %>%
  mutate(across(c(mae_total, mae_chapinero, mae_macro, mae_twcv, sesgo_chap, pred_test, dif_chap, dif_total), ~ round(.x / 1e6, 1)),
         across(c(t_chap, t_total), ~ round(.x, 2)))))
paso("Listo.")
