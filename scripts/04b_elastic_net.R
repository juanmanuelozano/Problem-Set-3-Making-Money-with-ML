# =============================================================================
# 04b_elastic_net.R - Elastic net (glmnet, pérdida cuadrática) sobre log(precio) y log(precio por m2)
# Mismas variables que reg_ols_sin_loc (04_regresiones.R): matriz_lineal + habitaciones × distancia a cada CBD.
# Grilla (respaldo en la literatura):
#  - alpha: mezcla ridge/lasso. Zou y Hastie (2005, JRSS-B) cruzan una grilla de la penalización L2 con todo el
#    camino de la L1; aquí, en la parametrización de glmnet, alpha en {0, .1, .25, .5, .75, .9, 1}.
#  - camino de lambda: Friedman, Hastie y Tibshirani (2010, JSS) recomiendan K = 100 valores en escala log
#    desde lambda_max hasta eps·lambda_max, con eps = 0,001. Se prueban nlambda en {50, 100, 200} y
#    lambda.min.ratio en {1e-3 (artículo), 1e-4 (por defecto en glmnet con n > p), 1e-5 (extensión: la primera
#    ronda eligió el borde del camino)}.
# Cada camino se valida entero con cv_oof (una localidad afuera, buffer, D9); lambda por MAE OOF mínimo.
# Precio por m2: sin variables de área; precio = predicción por m2 × m2 (en log: + log_area), como m09.
# Salidas: tables/elastic_net_grilla.csv, tables/elastic_net_coeficientes.csv, registro (m02, m02b)
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(glmnet))

Ztr <- cbind(matriz_lineal(TR), interacciones(TR)); Zte <- cbind(matriz_lineal(TE), interacciones(TE))
W <- !grepl("log_area", colnames(Ztr))
objetivos <- list(
  precio = list(Xtr = Ztr, Xte = Zte, y = Y, off_tr = 0, off_te = 0),
  m2     = list(Xtr = Ztr[, W], Xte = Zte[, W], y = Y - TR$log_area, off_tr = TR$log_area, off_te = TE$log_area))

grilla <- expand_grid(objetivo = names(objetivos), alpha = c(0, .1, .25, .5, .75, .9, 1),
                      nlambda = c(50, 100, 200), lambda.min.ratio = c(1e-3, 1e-4, 1e-5))

# El camino de lambda se fija con todo el train para que las columnas OOF de los folds coincidan
res <- pmap_dfr(grilla, function(objetivo, alpha, nlambda, lambda.min.ratio) {
  o <- objetivos[[objetivo]]
  lam <- glmnet(o$Xtr, o$y, alpha = alpha, nlambda = nlambda, lambda.min.ratio = lambda.min.ratio)$lambda
  oof <- cv_oof(function(a, e) predict(glmnet(o$Xtr[a, ], o$y[a], alpha = alpha, lambda = lam), o$Xtr[e, ], s = lam)) + o$off_tr
  j <- mejor_columna(oof)
  tibble(objetivo, alpha, nlambda, lambda.min.ratio, lambda = lam[j], en_borde = j == length(lam),
         lam = list(lam), oof = list(oof[, j])) %>% bind_cols(evalua(oof[, j]))
})
tabla <- res %>% select(-lam, -oof)
write_csv(tabla, file.path(P$rep_mod, "tables", "elastic_net_grilla.csv"))
print(tabla %>% mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1))) %>% arrange(objetivo, mae_total), n = Inf)

# ---- Mejor configuración por objetivo: reajuste con todo el train, registro y envío ----
for (nm in names(objetivos)) {
  b <- res %>% filter(objetivo == nm) %>% slice_min(mae_total, n = 1, with_ties = FALSE); o <- objetivos[[nm]]
  fit <- glmnet(o$Xtr, o$y, alpha = b$alpha, lambda = b$lam[[1]])
  modelo <- c(precio = "m02_elastic_net", m2 = "m02b_elastic_net_m2")[[nm]]
  registra(modelo, paste("Elastic net sobre", c(precio = "log(precio)", m2 = "log(precio por m2), sin variables de área; precio = predicción × m2")[[nm]],
                         "+ habitaciones × distancia a cada CBD, sin dummies de localidad"),
           sprintf("alpha=%.2f; lambda=%.2g; nlambda=%d; lambda.min.ratio=%g", b$alpha, b$lambda, b$nlambda, b$lambda.min.ratio),
           select(b, starts_with("ma")), b$oof[[1]], drop(predict(fit, o$Xte, s = b$lambda)) + o$off_te)
  if (b$en_borde) cat("Aviso:", modelo, "eligió el menor lambda del camino (borde de la grilla)\n")
  if (nm == "precio") {   # coeficientes estandarizados distintos de 0
    co <- coef(fit, s = b$lambda)[-1, 1]
    top <- tibble(var = names(co), b_std = co * apply(o$Xtr, 2, sd)) %>% filter(b_std != 0) %>% arrange(desc(abs(b_std)))
    write_csv(top, file.path(P$rep_mod, "tables", "elastic_net_coeficientes.csv"))
    cat("Coeficientes distintos de 0:", nrow(top), "de", length(co), "\n")
    saveRDS(list(fit = fit, lambda = b$lambda, alpha = b$alpha), file.path(P$models, "m02_elastic_net.rds"))
  }
}


