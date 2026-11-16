# =============================================================================
# 04_elastic_net.R - Baseline: regresión lineal penalizada (elastic net) sobre log(precio)
# Validación: folds espaciales (cv.glmnet con foldid). Se elige alpha por MAE out-of-fold.
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(library(glmnet))

Xtr <- matriz_lineal(TR); Xte <- matriz_lineal(TE)
cat("Dimensión X:", dim(Xtr), "\n")

# 0. Referencia trivial: mediana del train
registra("m00_mediana", "Mediana del precio del train (referencia)", "-",
         evalua(rep(median(Y), length(Y))), rep(median(Y), length(Y)), rep(median(Y), nrow(TE)))

# 1. OLS con las mismas variables (sin penalización)
ols_oof <- numeric(length(Y))
for (k in sort(unique(FOLD))) {
  fit <- lm.fit(cbind(1, Xtr[FOLD != k, ]), Y[FOLD != k]); b <- fit$coefficients; b[is.na(b)] <- 0
  ols_oof[FOLD == k] <- cbind(1, Xtr[FOLD == k, ]) %*% b
}
fit <- lm.fit(cbind(1, Xtr), Y); b <- fit$coefficients; b[is.na(b)] <- 0
registra("m01_ols", "OLS con variables estructurales, ubicación, texto y localidad", "-",
         evalua(ols_oof), ols_oof, drop(cbind(1, Xte) %*% b))

# 2. Elastic net: grilla de alpha, lambda por CV espacial
res <- map_dfr(c(0, .25, .5, .75, 1), function(a) {
  cv <- cv.glmnet(Xtr, Y, alpha = a, foldid = FOLD, keep = TRUE, type.measure = "mae", standardize = TRUE)
  map_dfr(c("lambda.min", "lambda.1se"), function(l) {
    j <- which(cv$lambda == cv[[l]])
    tibble(alpha = a, regla = l, lambda = cv[[l]], cv = list(cv), j = j) %>% bind_cols(evalua(cv$fit.preval[, j]))
  })
})
print(res %>% select(alpha, regla, lambda, mae_total, mae_chapinero, mae_fold2) %>% mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1))))

best <- res %>% slice_min(mae_total, n = 1, with_ties = FALSE)
cv <- best$cv[[1]]
fit_en <- glmnet(Xtr, Y, alpha = best$alpha, lambda = cv$lambda, standardize = TRUE)
pred_te <- drop(predict(fit_en, Xte, s = best$lambda))
registra("m02_elastic_net", "Elastic net (cuadráticos, interacciones, dummies de localidad)",
         sprintf("alpha=%.2f; lambda=%.5f (%s)", best$alpha, best$lambda, best$regla),
         best %>% select(starts_with("ma")), cv$fit.preval[, best$j], pred_te)

# Coeficientes no nulos más grandes (estandarizados)
co <- coef(fit_en, s = best$lambda)[-1, 1]; sdx <- apply(Xtr, 2, sd)
top <- tibble(var = names(co), b_std = co * sdx) %>% filter(b_std != 0) %>% arrange(desc(abs(b_std)))
write_csv(top, file.path(P$rep_mod, "tables", "elastic_net_coeficientes.csv"))
cat("Coeficientes distintos de 0:", nrow(top), "de", length(co), "\n"); print(head(top, 15))
saveRDS(list(fit = fit_en, lambda = best$lambda, alpha = best$alpha), file.path(P$models, "m02_elastic_net.rds"))
