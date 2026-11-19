# =============================================================================
# 04b_elastic_net.R - Regresión lineal penalizada (elastic net) sobre log(precio). OLS y mediana: 04_regresiones.R
# Validación: dejar una localidad afuera con buffer (cv_oof). Se eligen alpha y lambda por MAE out-of-fold.
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(library(glmnet))

Xtr <- matriz_lineal(TR); Xte <- matriz_lineal(TE)
cat("Dimensión X:", dim(Xtr), "\n")

# Elastic net: grilla de alpha; para cada alpha, todo el camino de lambda se valida con cv_oof
# (se elige lambda por MAE OOF mínimo; ya no se usa la regla 1se de cv.glmnet, que no admite buffer)
res <- map_dfr(c(0, .25, .5, .75, 1), function(a) {
  lam <- glmnet(Xtr, Y, alpha = a, standardize = TRUE)$lambda
  oof <- cv_oof(function(i, e) predict(glmnet(Xtr[i, ], Y[i], alpha = a, lambda = lam, standardize = TRUE), Xtr[e, ], s = lam))
  j <- mejor_columna(oof)
  tibble(alpha = a, lambda = lam[j], j = j, lam = list(lam), oof = list(oof[, j])) %>% bind_cols(evalua(oof[, j]))
})
print(res %>% select(alpha, lambda, j, mae_total, mae_chapinero, mae_macro) %>% mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1))))

best <- res %>% slice_min(mae_total, n = 1, with_ties = FALSE)
fit_en <- glmnet(Xtr, Y, alpha = best$alpha, lambda = best$lam[[1]], standardize = TRUE)
pred_te <- drop(predict(fit_en, Xte, s = best$lambda))
registra("m02_elastic_net", "Elastic net (cuadráticos, interacciones, dummies de localidad)",
         sprintf("alpha=%.2f; lambda=%.5f", best$alpha, best$lambda),
         best %>% select(starts_with("ma")), best$oof[[1]], pred_te)

# Coeficientes no nulos más grandes (estandarizados)
co <- coef(fit_en, s = best$lambda)[-1, 1]; sdx <- apply(Xtr, 2, sd)
top <- tibble(var = names(co), b_std = co * sdx) %>% filter(b_std != 0) %>% arrange(desc(abs(b_std)))
write_csv(top, file.path(P$rep_mod, "tables", "elastic_net_coeficientes.csv"))
cat("Coeficientes distintos de 0:", nrow(top), "de", length(co), "\n"); print(head(top, 15))
saveRDS(list(fit = fit_en, lambda = best$lambda, alpha = best$alpha), file.path(P$models, "m02_elastic_net.rds"))
