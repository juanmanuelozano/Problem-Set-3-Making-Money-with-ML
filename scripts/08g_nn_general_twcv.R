# =============================================================================
# 08g_nn_general_twcv.R - Red general (todo mezclado) elegida por TWCV, referencia de m20 (08f), D17
# Usa los mismos datos, área en m2, calibración y semillas que la ganadora del NN STAR (tables/nn_star_twcv_ganadora.csv)
# y su mismo número de parámetros: si la rama de texto de la ganadora es 64-32-16, la red general es 64-32-16; si es
# 32-16, la red general es c(w, 16), con w elegido para igualar los parámetros. Así la comparación aísla la estructura.
# Grilla: dropout {0,1; 0,3} × pérdida {MSE, MAE}, lr 1e-4, épocas hasta 60, todo elegido por MAE TWCV. La ganadora
# se reajusta con las semillas de la ganadora del NN STAR.
# Salidas: tables/nn_general_twcv.csv; registro m21_nn_general_twcv_m2
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R"); source("scripts/utils_redes.R")

# GANADORA=catastro: usa la ganadora de 08i (catastro, D18) y registra m26_nn_general_catastro_m2; por defecto, la de 08f (m21).
GAN <- Sys.getenv("GANADORA", "twcv")
W <- pesos_twcv(); g0 <- read_csv(if (GAN == "catastro") file.path(P$rep_mod, "tables", "nn_star_catastro_ganadora.csv") else F_GANADORA_NN,
                                 show_col_types = FALSE)
CAT_V <- if ("catastro" %in% names(g0)) g0$catastro else "no"
LRS <- if (GAN == "catastro") c(1e-3, 1e-4) else 1e-4   # con catastro también se prueba la tasa de m17
NOMBRE <- if (GAN == "catastro") "m26_nn_general_catastro_m2" else "m21_nn_general_twcv_m2"
F_TAB <- file.path(P$rep_mod, "tables", if (GAN == "catastro") "nn_general_catastro.csv" else "nn_general_twcv.csv")
EP60 <- if (PRUEBA) c(1, 2) else c(1:10, seq(12, 30, 2), seq(35, 60, 5))
usa_bloques(g0$area_m2, g0$osm, CAT_V); d <- dims(BR$m2); n_in <- sum(d)
capas_g <- if (g0$texto == "64-32-16") c(64, 32, 16) else c(round((g0$parametros - 16 - 17) / (n_in + 1 + 16)), 16)
cat(sprintf("Ganadora del NN STAR: texto %s, área en m2 %s, OSM %s, calibración %s, %d semillas, %d parámetros\n",
            g0$texto, g0$area_m2, g0$osm, g0$cal, g0$n_sem, g0$parametros))
cat("Red general:", paste(capas_g, collapse = "-"), "| parámetros:", count_params(red_general(d, 0, capas = capas_g)$modelo), "\n")

y <- exp(Y); w_cal <- if (g0$cal == "twcv") W else NULL
construye <- function(g, d) red_general(d, g$p, capas = capas_g)
res <- list()
corre <- function(etapa, cfg, sem = 123) {
  ep <- if (cfg$lr >= 1e-3) EPOCAS else EP60
  r <- cv_red(\(d) construye(cfg, d), "m2", ep, cfg$lr, cfg$perdida, w = W, w_cal = w_cal, semillas = sem)
  f <- ajusta_final(mutate(cfg, objetivo = "m2", epocas = r$epocas), construye, cfg$lr, cfg$perdida, w_cal, sem)
  fila <- cfg %>% mutate(etapa = etapa, n_sem = length(sem), epocas = r$epocas, borde = r$borde) %>% bind_cols(evalua(r$oof)) %>%
    mutate(mae_twcv = mae_w(r$oof, W), sesgo_chap = mean(recorta(exp(r$oof[ES_CHAP])) - y[ES_CHAP]),
           pred_test = mean(recorta(exp(f$pred_te))), oof = list(r$oof), pred_te = list(f$pred_te))
  res[[length(res) + 1]] <<- fila
  write_csv(select(bind_rows(res), -oof, -pred_te), F_TAB)
  paso(sprintf("%s | lr %g, p %g, %s, %d sem | ép %d%s | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f | sesgo %.1f | test %.1f",
               etapa, cfg$lr, cfg$p, cfg$perdida, length(sem), r$epocas, if (r$borde) " (BORDE)" else "", fila$mae_total / 1e6,
               fila$mae_chapinero / 1e6, fila$mae_macro / 1e6, fila$mae_twcv / 1e6, fila$sesgo_chap / 1e6, fila$pred_test / 1e6))
  fila
}
gr <- expand_grid(lr = LRS, p = c(.1, .3), perdida = c("mse", "mae")); if (PRUEBA) gr <- gr[1, ]
b <- map(seq_len(nrow(gr)), \(k) corre("grilla", gr[k, ])) %>% bind_rows() %>% slice_min(mae_twcv, n = 1, with_ties = FALSE)
fin <- if (g0$n_sem == 3) corre("semillas", select(b, lr, p, perdida), c(123, 124, 125)) else b

if (!PRUEBA) registra(NOMBRE,
  paste0("Red general (Keras) ", paste(capas_g, collapse = "-"), " elegida por TWCV (08g), mismos datos y tamaño que ", if (GAN == "catastro") "m25 (con catastro)" else "m20", "; sobre log(precio por m2)"),
  sprintf("capas=%s; p=%g; pérdida=%s; lr=%g; calibración=%s; semillas=%d; épocas=%d", paste(capas_g, collapse = "-"),
          fin$p, fin$perdida, fin$lr, g0$cal, fin$n_sem, fin$epocas),
  select(fin, starts_with("ma")), fin$oof[[1]], fin$pred_te[[1]])
print(as.data.frame(select(bind_rows(res), etapa, lr, p, perdida, n_sem, epocas, borde, mae_total, mae_chapinero, mae_macro, mae_twcv,
                           sesgo_chap, pred_test) %>% mutate(across(c(starts_with("mae"), sesgo_chap, pred_test), ~ round(.x / 1e6, 1)))))
paso("Listo.")
