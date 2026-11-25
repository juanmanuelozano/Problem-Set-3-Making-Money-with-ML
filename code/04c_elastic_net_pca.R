# =============================================================================
# 04c_elastic_net_pca.R - Elastic net (glmnet) sobre las componentes principales de 03e_pca.R
# Tres especificaciones (el TF-IDF completo no entra):
#  (a) pca_nt:    PCA de las variables que no son de texto (37) + no linealidades de m02
#  (b) pca_tx:    PCA del texto (50 componentes), sin nada más: modelo solo de texto
#  (c) pca_nt_tx: (a) + (b)
# No linealidades = las de m02: cuadrados, área × estrato y tipo, distancia al CBD × tipo y habitaciones × distancia a
# cada CBD. Las componentes ya contienen la parte lineal de las variables originales; estos términos no.
# Dos objetivos, como en 04b: log(precio) y log(precio por m2) (este último sin las columnas de log_area;
# las componentes de no texto sí contienen el área, porque son combinaciones de todas las variables).
# Grilla: alpha en {0, .1, .25, .5, .75, .9, 1} (Zou y Hastie, 2005); nlambda = 100 y lambda.min.ratio en
# {1e-4, 1e-5, 1e-6} (Friedman, Hastie y Tibshirani, 2010; en m02 nlambda no movió el MAE y lambda quedó en el borde
# inferior, así que se extiende ese borde). Validación: una localidad afuera con buffer (cv_oof, D9).
# Salidas: tables/elastic_net_pca_{grilla,resumen,coeficientes}.csv; registro m12_en_<spec>[_m2]
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))

# ---- Matrices ----
pnt <- lee_csv(file.path(P$processed, "pca_no_texto.csv")); ptx <- lee_csv(file.path(P$processed, "pca_texto.csv"))
pcs <- function(df, p) {   # componentes en el orden de filas de df
  X <- as.matrix(p[match(df$property_id, p$property_id), grep("^pc_", names(p))]); stopifnot(!anyNA(X)); X
}
nolin <- function(df) { M <- cbind(matriz_lineal(df), interacciones(df)); M[, grep("_2$|_x_", colnames(M))] }
m02 <- function(df) cbind(matriz_lineal(df), interacciones(df))   # columnas de m02 / m02b
# PCA de no texto rehecho SIN log_area: el área entra como columna aparte, así el objetivo m2 la deja fuera como en m02b
nt <- lee_csv(file.path(P$processed, "base_no_texto.csv"))
p_sa <- prcomp(select(nt, -property_id, -muestra, -log_area), center = TRUE, scale. = TRUE)
pcs_sa <- function(df) {
  S <- predict(p_sa, nt[match(df$property_id, nt$property_id), ]); colnames(S) <- sprintf("pc_sa%02d", seq_len(ncol(S)))
  cbind(S, log_area = df$log_area)
}
specs <- list(
  m02           = list(desc = "variables de m02/m02b (misma grilla que m12, como referencia)", tr = m02(TR), te = m02(TE)),
  m02_pca_tx    = list(desc = "variables de m02/m02b + PCA texto (50)",
                       tr = cbind(m02(TR), pcs(TR, ptx)), te = cbind(m02(TE), pcs(TE, ptx))),
  m02_pca_nt_tx = list(desc = "variables de m02/m02b + PCA no texto (37) + PCA texto (50)",
                       tr = cbind(m02(TR), pcs(TR, pnt), pcs(TR, ptx)), te = cbind(m02(TE), pcs(TE, pnt), pcs(TE, ptx))),
  pca_nt_tx_sa  = list(desc = "PCA no texto sin log_area (36) + log_area + PCA texto (50) + no linealidades de m02",
                       tr = cbind(pcs_sa(TR), pcs(TR, ptx), nolin(TR)), te = cbind(pcs_sa(TE), pcs(TE, ptx), nolin(TE))),
  pca_nt    = list(desc = "PCA de variables no texto (37) + no linealidades de m02",
                   tr = cbind(pcs(TR, pnt), nolin(TR)), te = cbind(pcs(TE, pnt), nolin(TE))),
  pca_tx    = list(desc = "PCA del texto (50 componentes), solo texto",
                   tr = pcs(TR, ptx), te = pcs(TE, ptx)),
  pca_nt_tx = list(desc = "PCA no texto (37) + PCA texto (50) + no linealidades de m02",
                   tr = cbind(pcs(TR, pnt), pcs(TR, ptx), nolin(TR)), te = cbind(pcs(TE, pnt), pcs(TE, ptx), nolin(TE))))
objetivos <- map(specs, ~ arma_objetivos(.x$tr, .x$te))
iwalk(specs, ~ cat(sprintf("%-10s %3d columnas (precio) | %3d (m2)\n", .y, ncol(.x$tr), ncol(objetivos[[.y]]$m2$Xtr))))

# ---- Grilla con validación cruzada ----
grilla <- expand_grid(spec = names(specs), objetivo = c("precio", "m2"), alpha = c(0, .1, .25, .5, .75, .9, 1),
                      nlambda = 100, lambda.min.ratio = c(1e-4, 1e-5, 1e-6))
# El camino de lambda se fija con todo el train para que las columnas OOF de los folds coincidan
res <- pmap_dfr(grilla, function(spec, objetivo, alpha, nlambda, lambda.min.ratio) {
  o <- objetivos[[spec]][[objetivo]]
  lam <- glmnet(o$Xtr, o$y, alpha = alpha, nlambda = nlambda, lambda.min.ratio = lambda.min.ratio)$lambda
  oof <- cv_oof(function(a, e) predict(glmnet(o$Xtr[a, ], o$y[a], alpha = alpha, lambda = lam), o$Xtr[e, ], s = lam)) + o$off_tr
  j <- mejor_columna(oof)
  tibble(spec, objetivo, alpha, nlambda, lambda.min.ratio, lambda = lam[j], en_borde = j == length(lam),
         lam = list(lam), oof = list(oof[, j])) %>% bind_cols(evalua(oof[, j]))
})
write_csv(select(res, -lam, -oof), file.path(P$tab_mod, "elastic_net_pca_grilla.csv"))

# ---- Mejor configuración por especificación y objetivo: reajuste con todo el train, registro y envío ----
mejores <- res %>% group_by(spec, objetivo) %>% slice_min(mae_total, n = 1, with_ties = FALSE) %>% ungroup() %>%
  mutate(n_coef = NA_integer_, n_var = NA_integer_, pred_test = NA_real_, sesgo_chap = NA_real_)
coefs <- list()
for (k in seq_len(nrow(mejores))) {
  b <- mejores[k, ]; o <- objetivos[[b$spec]][[b$objetivo]]
  fit <- glmnet(o$Xtr, o$y, alpha = b$alpha, lambda = b$lam[[1]])
  modelo <- paste0("m12_en_", b$spec, if (b$objetivo == "m2") "_m2")
  pt <- drop(predict(fit, o$Xte, s = b$lambda)) + o$off_te
  registra(modelo, paste("Elastic net:", specs[[b$spec]]$desc,
                         if (b$objetivo == "m2") "; sobre log(precio por m2), precio = predicción × m2" else "; sobre log(precio)"),
           sprintf("alpha=%.2f; lambda=%.2g; nlambda=%d; lambda.min.ratio=%g", b$alpha, b$lambda, b$nlambda, b$lambda.min.ratio),
           select(b, starts_with("ma")), b$oof[[1]], pt)
  # Predicción media del test (en Kaggle, los modelos que predicen más alto salen mejor) y sesgo OOF en Chapinero
  mejores$pred_test[k] <- mean(recorta(exp(pt)))
  mejores$sesgo_chap[k] <- mean(recorta(exp(b$oof[[1]][ES_CHAP])) - exp(Y[ES_CHAP]))
  if (b$en_borde) cat("Aviso:", modelo, "eligió el menor lambda del camino (borde de la grilla)\n")
  co <- coef(fit, s = b$lambda)[-1, 1]   # coeficientes estandarizados (beta × sd), distintos de 0
  coefs[[modelo]] <- tibble(modelo, var = names(co), b_std = co * apply(o$Xtr, 2, sd)) %>% filter(b_std != 0) %>%
    arrange(desc(abs(b_std)))
  mejores$n_coef[k] <- nrow(coefs[[modelo]]); mejores$n_var[k] <- length(co)
}
write_csv(bind_rows(coefs), file.path(P$tab_mod, "elastic_net_pca_coeficientes.csv"))

# ---- Resumen de la validación cruzada, junto a las referencias m02 / m02b (texto por regex y dummies tx_*) ----
reg <- lee_csv(file.path(P$models, "registro_modelos.csv"))
kag <- lee_csv(file.path(P$models, "kaggle_scores.csv")) %>% select(modelo, kaggle = public_score)
resumen <- bind_rows(
  mejores %>% transmute(modelo = paste0("m12_en_", spec, if_else(objetivo == "m2", "_m2", "")), spec, objetivo, alpha,
                        lambda, coef = sprintf("%d de %d", n_coef, n_var), mae_total, mae_chapinero, mae_macro,
                        sesgo_chap, pred_test),
  reg %>% filter(modelo %in% c("m02_elastic_net", "m02b_elastic_net_m2")) %>%
    transmute(modelo, spec = "referencia (04b)", objetivo = if_else(str_detect(modelo, "m2"), "m2", "precio"),
              mae_total, mae_chapinero, mae_macro)) %>%
  left_join(kag, by = "modelo") %>%
  mutate(across(c(starts_with("mae"), sesgo_chap, pred_test, kaggle), ~ round(.x / 1e6, 1)))
write_csv(resumen, file.path(P$tab_mod, "elastic_net_pca_resumen.csv"))
cat("\nValidación cruzada (MAE OOF, millones; una localidad afuera, buffer de", BUFFER_M, "m):\n")
print(as.data.frame(arrange(resumen, objetivo, mae_total)))
