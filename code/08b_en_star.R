# =============================================================================
# 08b_en_star.R - Elastic net con los encoders del STAR (paso 2 del paper: "OLS with XGB loc"), frente al EN con PCA
# Encoders: de 08_xgb_star.R. En la validación se usan los del STAR ajustado en las filas de análisis de cada fold
# (models/star_encoders_folds.rds): las filas evaluadas nunca entran al ajuste del encoder. Para el test, los del
# STAR ajustado con todo el train (data/processed/star_encoders.csv).
# Especificaciones (todas sobre las variables de m02/m02b: matriz_lineal + habitaciones × distancia a cada CBD):
#  - enc_tx: m02 + encoder de texto                      -> comparar con m02 + PCA texto (04c: m12_en_m02_pca_tx)
#  - enc:    m02 sin el bloque de ubicación + encoder de ubicación + encoder de texto + log_area × encoder de ubicación
#  - enc_b:  enc + distancias lineales (dist_*): la parte lineal puede extrapolar hacia Chapinero
# Objetivos log(precio) y log(precio por m2) (sin columnas de área; en m2 tampoco entra log_area × encoder).
# Grilla de 04c: alpha en {0, .1, .25, .5, .75, .9, 1} × lambda.min.ratio en {1e-4, 1e-5, 1e-6}, nlambda = 100.
# Versión TWCV (2026-11-22): base D14 sin zona de lujo y OSM según 08f (vars_sin), encoders del XGB STAR m22, lambda
# y alpha (y la mejor configuración) elegidos por MAE TWCV (D16). Los m14 (base anterior) no se tocan.
# Salidas: tables/elastic_net_star_twcv_{grilla,resumen,coef_encoders}.csv; registro m23_en_<spec>[_m2]
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))
PRUEBA <- nzchar(Sys.getenv("PRUEBA")); W <- pesos_twcv(); base$vars <- vars_sin(osm_ganadora())

encs <- readRDS(file.path(P$models, "star_encoders_folds.rds"))
ef <- lee_csv(file.path(P$processed, "star_encoders.csv"))
E <- function(df) as.matrix(ef[match(df$property_id, ef$property_id), c("enc_ubicacion", "enc_texto")])
B_tr <- cbind(matriz_lineal(TR), interacciones(TR)); B_te <- cbind(matriz_lineal(TE), interacciones(TE))
cn <- colnames(B_tr)
ubic <- grepl("^(lat|lon)", cn) | grepl("estrato|^dist_|^n500_|_x_dist|dist_cbd_x", cn)   # bloque de ubicación de m02
dist_lin <- grepl("^dist_", cn) & !grepl("_2$|_x_", cn)
specs <- list(
  enc_tx = list(desc = "variables de m02/m02b + encoder de texto del STAR",
                f = function(B, En) cbind(B, enc_texto = En[, 2])),
  enc    = list(desc = "m02 sin ubicación + encoders de ubicación y texto del STAR + log_area × encoder de ubicación",
                f = function(B, En) cbind(B[, !ubic], enc_ubicacion = En[, 1], enc_texto = En[, 2], log_area_x_enc_ubic = B[, "log_area"] * En[, 1])),
  enc_b  = list(desc = "como enc + distancias lineales (dist_*)",
                f = function(B, En) cbind(B[, !ubic | dist_lin], enc_ubicacion = En[, 1], enc_texto = En[, 2],
                                          log_area_x_enc_ubic = B[, "log_area"] * En[, 1])))
prep <- function(X, obj) if (obj == "m2") X[, !grepl("log_area", colnames(X)), drop = FALSE] else X
y_obj <- list(precio = Y, m2 = Y - TR$log_area)
off <- list(precio = list(tr = 0, te = 0), m2 = list(tr = TR$log_area, te = TE$log_area))
fold_de <- function(e) which(map_lgl(encs, ~ .x$evaluacion[1] == e[1]))   # encoders del fold que evalúa `e`

# ---- Grilla con validación cruzada (encoders por fold) ----
grilla <- expand_grid(spec = names(specs), objetivo = c("precio", "m2"), alpha = c(0, .1, .25, .5, .75, .9, 1),
                      lambda.min.ratio = c(1e-4, 1e-5, 1e-6))
res <- pmap_dfr(grilla, function(spec, objetivo, alpha, lambda.min.ratio) {
  f <- specs[[spec]]$f; y <- y_obj[[objetivo]]
  lam <- glmnet(prep(f(B_tr, E(TR)), objetivo), y, alpha = alpha, nlambda = 100, lambda.min.ratio = lambda.min.ratio)$lambda
  oof <- cv_oof(function(a, e) {
    k <- fold_de(e)
    fit <- glmnet(prep(f(B_tr[a, ], encs[[k]]$ea), objetivo), y[a], alpha = alpha, lambda = lam)
    predict(fit, prep(f(B_tr[e, ], encs[[k]]$ee), objetivo), s = lam)
  }) + off[[objetivo]]$tr
  j <- mejor_columna(oof, W)
  tibble(spec, objetivo, alpha, lambda.min.ratio, lambda = lam[j], en_borde = j == length(lam), lam = list(lam), oof = list(oof[, j])) %>%
    bind_cols(evalua(oof[, j])) %>% mutate(mae_twcv = mae_w(.env$oof[, j], W))
})
write_csv(select(res, -lam, -oof), file.path(P$tab_mod, "elastic_net_star_twcv_grilla.csv"))

# ---- Mejor configuración por especificación y objetivo: ajuste final, registro y envío ----
mejores <- res %>% group_by(spec, objetivo) %>% slice_min(mae_twcv, n = 1, with_ties = FALSE) %>% ungroup()
coefs <- list()
for (k in seq_len(nrow(mejores))) {
  b <- mejores[k, ]; f <- specs[[b$spec]]$f
  fit <- glmnet(prep(f(B_tr, E(TR)), b$objetivo), y_obj[[b$objetivo]], alpha = b$alpha, lambda = b$lam[[1]])
  modelo <- paste0("m23_en_", b$spec, if (b$objetivo == "m2") "_m2")
  if (!PRUEBA) registra(modelo, paste("Elastic net:", specs[[b$spec]]$desc,
                         if (b$objetivo == "m2") "; sobre log(precio por m2), precio = predicción × m2" else "; sobre log(precio)"),
           sprintf("alpha=%.2f; lambda=%.2g; lambda.min.ratio=%g", b$alpha, b$lambda, b$lambda.min.ratio),
           select(b, starts_with("ma")), b$oof[[1]],
           drop(predict(fit, prep(f(B_te, E(TE)), b$objetivo), s = b$lambda)) + off[[b$objetivo]]$te)
  co <- coef(fit, s = b$lambda)[, 1]
  coefs[[modelo]] <- tibble(modelo, termino = names(co), coef = co) %>% filter(str_detect(termino, "enc"))
}
coefs <- bind_rows(coefs)
write_csv(coefs, file.path(P$tab_mod, "elastic_net_star_twcv_coef_encoders.csv"))
cat("\nCoeficientes de los encoders (≈ 1 si el encoder está bien calibrado):\n")
print(as.data.frame(coefs %>% mutate(coef = round(coef, 3))))

# ---- Resumen: encoders frente a PCA (04c), STAR (08) y referencias, con sesgo, predicción de test y Kaggle ----
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv")); tst <- lee_csv(file.path(P$models, "test_predicciones.csv"))
reg <- lee_csv(file.path(P$models, "registro_modelos.csv")); kag <- lee_csv(file.path(P$models, "kaggle_scores.csv"))
mods <- c(paste0("m23_en_", c("enc_tx", "enc", "enc_b")), paste0("m23_en_", c("enc_tx", "enc", "enc_b"), "_m2"),
          "m22_xgb_star_twcv_m2", "m22_xgb_star_twcv_m2_mae", "m20_nn_star_twcv_m2", "m21_nn_general_twcv_m2",
          "m14_en_enc_tx", "m17_nn_star_m2", "m02b_elastic_net_m2", "m04_xgboost")
resumen <- reg %>% filter(modelo %in% mods, modelo %in% names(oofs)) %>% select(modelo, mae_total, mae_chapinero, mae_macro) %>%
  mutate(mae_twcv = map_dbl(modelo, ~ mae_w(oofs[[.x]][match(TR$property_id, oofs$property_id)], W))) %>%
  mutate(sesgo_chap = map_dbl(modelo, ~ mean(recorta(exp(oofs[[.x]][oofs$chapinero])) - exp(oofs$log_price[oofs$chapinero]))),
         pred_test = map_dbl(modelo, ~ mean(recorta(exp(tst[[.x]]))))) %>%
  left_join(select(kag, modelo, kaggle = public_score), by = "modelo") %>%
  mutate(across(where(is.numeric), ~ round(.x / 1e6, 1))) %>% arrange(match(modelo, mods))
write_csv(resumen, file.path(P$tab_mod, "elastic_net_star_twcv_resumen.csv"))
cat("\nValidación cruzada (MAE OOF, millones; una localidad afuera, buffer de", BUFFER_M, "m):\n")
print(as.data.frame(resumen))
