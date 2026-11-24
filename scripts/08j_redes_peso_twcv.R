# =============================================================================
# 08j_redes_peso_twcv.R - NN STAR y red general ENTRENADAS con los pesos TWCV (pérdida ponderada), D17
# Hasta 08i los pesos TWCV (91_validacion_sintetica.R, D16) solo elegían épocas y calibraban el nivel. Aquí además
# ponderan la pérdida: la red le da más importancia a los anuncios parecidos al test (Chapinero).
# Los pesos crudos tienen tamaño efectivo de muestra de ~1.160 de 38.644 (3%) y un máximo de 156 veces la media:
# se atenúan como w^alfa, alfa {0,5; 1} (alfa = 0 son m24, m25 y m26, ya registrados). La calibración usa los
# mismos pesos de entrenamiento (con la simple se desharía el efecto sobre el nivel).
# Configuraciones base (datos de 08i: catastro valor_estrato, sin zona de lujo ni OSM, texto 64-32-16):
#   star_m24: lr 1e-3, p_u 0,1, p_t 0,5, MSE, 1 semilla      star_m25: lr 1e-4, MAE, 3 semillas
#   general_m26: 64-32-16, lr 1e-4, p 0,3, MAE, 3 semillas
# Todo se elige por MAE TWCV. Registro: m28_nn_star_peso_twcv_m2 y m29_nn_general_peso_twcv_m2 (la mejor de cada red).
# Salidas: tables/redes_peso_twcv.csv; models/redes_peso_twcv.rds (OOF y test de todas, para registrar otras después)
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R"); source("scripts/utils_redes.R")

REF <- "m17_nn_star_m2"; W <- pesos_twcv(); SEM3 <- c(123, 124, 125)
EP60 <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 60, 5))
f_tab <- file.path(P$rep_mod, "tables", "redes_peso_twcv.csv")
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv"))
ref <- oofs[[REF]][match(TR$property_id, oofs$property_id)]
y <- exp(Y); err <- \(p) abs(y - recorta(exp(p)))
usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = "valor_estrato")

base <- tribble(~red, ~lr, ~p_u, ~p_t, ~perdida, ~n_sem,
  "star_m24",    1e-3, .1, .5, "mse", 1,
  "star_m25",    1e-4, .1, .5, "mae", 3,
  "general_m26", 1e-4, .3, NA, "mae", 3)
grilla <- expand_grid(base, alfa = c(.5, 1))
if (PRUEBA) grilla <- grilla[c(1, 6), ] %>% mutate(n_sem = 1)

construye <- function(g, d) if (startsWith(g$red, "star")) red_star(d, g$p_u, g$p_t) else red_general(d, g$p_u)
res <- list()
for (k in seq_len(nrow(grilla))) {
  cfg <- grilla[k, ]; wf <- W^cfg$alfa; wf <- wf / mean(wf)
  ep <- if (cfg$lr >= 1e-3) EPOCAS else EP60; sem <- if (cfg$n_sem == 3) SEM3 else 123
  r <- cv_red(\(d) construye(cfg, d), "m2", ep, cfg$lr, cfg$perdida, w = W, w_cal = wf, semillas = sem, w_fit = wf)
  f <- ajusta_final(mutate(cfg, objetivo = "m2", epocas = r$epocas), construye, cfg$lr, cfg$perdida, wf, sem, wf)
  d <- err(r$oof) - err(ref)
  fila <- cfg %>% mutate(epocas = r$epocas, borde = r$borde) %>% bind_cols(evalua(r$oof)) %>%
    mutate(mae_twcv = mae_w(r$oof, W), sesgo_chap = mean(recorta(exp(r$oof[ES_CHAP])) - y[ES_CHAP]),
           pred_test = mean(recorta(exp(f$pred_te))), dif_chap = mean(d[ES_CHAP]), t_chap = unname(t.test(d[ES_CHAP])$statistic),
           oof = list(r$oof), pred_te = list(f$pred_te))
  res[[k]] <- fila
  write_csv(select(bind_rows(res), -oof, -pred_te), f_tab)
  if (!PRUEBA) saveRDS(bind_rows(res), file.path(P$models, "redes_peso_twcv.rds"))
  paso(sprintf("%-11s alfa %.1f | ép %d%s | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f | sesgo %.1f | test %.1f | vs m17 Chap %+.1f (t %.2f)",
               cfg$red, cfg$alfa, r$epocas, if (r$borde) " (BORDE)" else "", fila$mae_total / 1e6, fila$mae_chapinero / 1e6,
               fila$mae_macro / 1e6, fila$mae_twcv / 1e6, fila$sesgo_chap / 1e6, fila$pred_test / 1e6, fila$dif_chap / 1e6, fila$t_chap))
}

todo <- bind_rows(res)
reg <- function(nombre, b, desc) if (!PRUEBA) registra(nombre,
  paste0(desc, " entrenada con pesos TWCV^", b$alfa, " (pérdida y calibración ponderadas, 08j); catastro valor_estrato, sin zona de lujo ni OSM; sobre log(precio por m2)"),
  sprintf("alfa=%g; lr=%g; dropout=%g/%g; pérdida=%s; semillas=%d; épocas=%d; batch=%d; l2=%g",
          b$alfa, b$lr, b$p_u, b$p_t, b$perdida, b$n_sem, b$epocas, BATCH, L2),
  select(b, starts_with("ma")), b$oof[[1]], b$pred_te[[1]])
mejor <- \(x) slice_min(x, mae_twcv, n = 1, with_ties = FALSE)
reg("m28_nn_star_peso_twcv_m2", mejor(filter(todo, startsWith(red, "star"))), "NN STAR")
reg("m29_nn_general_peso_twcv_m2", mejor(filter(todo, red == "general_m26")), "Red general 64-32-16")
print(as.data.frame(select(todo, red, alfa, epocas, borde, mae_total, mae_chapinero, mae_macro, mae_twcv, sesgo_chap, pred_test, dif_chap, t_chap) %>%
  mutate(across(c(starts_with("mae"), sesgo_chap, pred_test, dif_chap), ~ round(.x / 1e6, 1)), t_chap = round(t_chap, 2))))
paso("Listo.")
