# =============================================================================
# 04f_lasso_comparables.R - Lasso por m2 con "comparables": un control sintético para cada anuncio (D20)
# Idea (la de un avaluador): para cada anuncio, el precio por m2 de los anuncios del train más cercanos del
# mismo tipo (apartamento/casa), con más peso a los más cercanos. Es el rezago espacial que estaba pendiente.
# Por qué: el 99% del test tiene un anuncio del train a menos de 500 m (mediana 96 m; ver D16), pero la
# validación con buffer de 500 m no deja ningún vecino cerca. Los modelos predecían Chapinero "desde lejos".
# Sin fuga de información (funciones en utils_comparables_d20.R):
#  - en cada fold, los comparables de un anuncio salen solo del conjunto de análisis, y nunca él mismo;
#  - no se usan como comparables los anuncios con la MISMA descripción (el mismo inmueble publicado dos veces:
#    8.078 descripciones repetidas en el train y 200 compartidas con el test).
# Validación: la CV aleatoria (10 folds) se parece al test en la distancia a los vecinos; la de localidad con
# buffer (D9) los quita todos, así que castiga la variable. Se reportan las dos, con y sin comparables.
# Lambda se elige con el MAE del Chapinero sintético (mae_twcv) en la CV aleatoria. Base de D19 (81 variables).
# Kaggle: 167,1 M (frente a 171,6 M del mismo lasso sin comparables, m20).
# Salidas: tables/en_comparables_cv.csv, registro (m21_en_comparables_m2) con OOF de la CV por localidad.
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))
source(here::here("code", "utils_comparables_d20.R"))

V <- vars_sin()
o <- arma_objetivos(
  cbind(matriz_lineal(TR, vars = V), interacciones(TR)),
  cbind(matriz_lineal(TE, vars = V), interacciones(TE))
)$m2
CMP <- prepara_comparables()
C_full <- comparables_train(CMP)
C_te <- comparables_test(CMP)
cat(sprintf(
  "Distancia media a los 5 comparables (mediana, m): train %.0f | test %.0f\n",
  median(expm1(C_full[, "comp_logdist5"])), median(expm1(C_te[, "comp_logdist5"]))
))
cat(sprintf("Correlación de comp5 con log(precio/m2) en el train: %.2f\n", cor(C_full[, "comp5"], o$y)))

# ---- Validación: CV aleatoria (10 folds) y CV por localidad con buffer, con y sin comparables ----
X_full <- cbind(o$Xtr, C_full)
lam <- list(
  sin = glmnet(o$Xtr, o$y, alpha = 1, nlambda = 100, lambda.min.ratio = 1e-3)$lambda,
  con = glmnet(X_full, o$y, alpha = 1, nlambda = 100, lambda.min.ratio = 1e-3)$lambda
)
corre_cv <- function(folds, con) {
  cv_oof(function(a, e) {
    if (con) {
      Xa <- cbind(o$Xtr[a, ], comparables_fold(CMP, a, a))
      Xe <- cbind(o$Xtr[e, ], comparables_fold(CMP, a, e))
    } else {
      Xa <- o$Xtr[a, ]
      Xe <- o$Xtr[e, ]
    }
    l <- lam[[if (con) "con" else "sin"]]
    predict(glmnet(Xa, o$y[a], alpha = 1, lambda = l), Xe, s = l)
  }, folds) + o$off_tr
}

res <- list()
for (cv in c("aleatoria", "localidad_buffer")) {
  for (con in c(FALSE, TRUE)) {
    t0 <- Sys.time()
    folds <- if (cv == "aleatoria") FOLDS_ALEAT else FOLDS
    res[[paste(cv, con)]] <- list(cv = cv, con = con, oof = corre_cv(folds, con))
    cat(sprintf(
      "CV %-16s %-16s listo (%.0fs)\n", cv, if (con) "con comparables" else "sin comparables",
      as.numeric(difftime(Sys.time(), t0, units = "secs"))
    ))
  }
}

# Lambda: el de menor MAE TWCV en la CV aleatoria (la que se parece al test); se aplica igual en las dos CV
j <- map_int(c(sin = FALSE, con = TRUE), function(con) {
  which.min(apply(res[[paste("aleatoria", con)]]$oof, 2, \(p) evalua(p)$mae_twcv))
})
tabla <- map_dfr(res, function(r) {
  jj <- j[[if (r$con) "con" else "sin"]]
  tibble(cv = r$cv, comparables = r$con, lambda = lam[[if (r$con) "con" else "sin"]][jj]) %>%
    bind_cols(evalua(r$oof[, jj]))
})
write_csv(tabla, file.path(P$tab_mod, "en_comparables_cv.csv"))
tabla %>%
  mutate(across(starts_with("ma"), ~ round(.x / 1e6, 1))) %>%
  select(-mape_chapinero) %>%
  print()

# ---- Modelo final: entrenado con todo el train; comparables del test con todo el train ----
l <- lam$con
fit <- glmnet(X_full, o$y, alpha = 1, lambda = l)
co <- coef(fit, s = l[j[["con"]]])[, 1]
cat("Coeficientes de comparables:", round(co[colnames(C_full)], 3), "\n")
oof_loc <- res[["localidad_buffer TRUE"]]$oof[, j[["con"]]]
registra(
  "m21_en_comparables_m2",
  paste(
    "Lasso sobre log(precio/m2) + precio por m2 de los comparables (5 y 20 vecinos del mismo tipo,",
    "sin duplicados); OOF de la CV por localidad con buffer (castiga la variable; ver en_comparables_cv.csv)"
  ),
  sprintf(
    "alpha=1; lambda=%.2g (por MAE TWCV en CV aleatoria); K=%s; D0=%d m",
    l[j[["con"]]], paste(CMP$ks, collapse = "/"), CMP$d0
  ),
  evalua(oof_loc), oof_loc,
  drop(predict(fit, cbind(o$Xte, C_te), s = l[j[["con"]]])) + o$off_te
)
