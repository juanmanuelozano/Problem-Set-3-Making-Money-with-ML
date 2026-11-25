# =============================================================================
# check_validacion.R - Verificación de la validación cruzada (folds por localidad con buffer y cv_oof).
# Uso: Rscript code/check_validacion.R   (falla con error si algo no se cumple)
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))
ev <- unlist(map(FOLDS, "evaluacion"))
stopifnot(length(ev) == length(Y), all(sort(ev) == seq_along(Y)))
cat("Folds:", length(FOLDS), "| tamaño mínimo:", min(lengths(map(FOLDS, "evaluacion"))), "\n")
# Buffer: distancia mínima recalculada desde cero para tres folds
for (g in c("Chapinero", "Bosa", "Teusaquillo")) {
  f <- folds_localidad(BUFFER_M)[[g]]
  dmin <- dist_min(TR$lat[f$analisis], TR$lon[f$analisis], TR$lat[f$evaluacion], TR$lon[f$evaluacion])
  excl <- setdiff(which(GRUPO != g), f$analisis)
  dexc <- dist_min(TR$lat[excl], TR$lon[excl], TR$lat[f$evaluacion], TR$lon[f$evaluacion])
  stopifnot(min(dmin) >= BUFFER_M, all(dexc < BUFFER_M), !any(f$analisis %in% f$evaluacion))
  cat(g, ": análisis", length(f$analisis), "| excluidos", length(excl), "| dist. mínima", round(min(dmin)), "m\n")
}
# cv_oof == ciclo manual (buffer 0, OLS) y salida matricial
L <- matriz_lineal(TR); fo <- folds_localidad(0)
co <- function(a) ols_coef(L, a)
p1 <- cv_oof(function(a, e) cbind(1, L[e, ]) %*% co(a), fo)
p2 <- numeric(length(Y)); for (g in unique(GRUPO)) p2[GRUPO == g] <- cbind(1, L[GRUPO == g, ]) %*% co(which(GRUPO != g))
stopifnot(isTRUE(all.equal(unname(drop(p1)), p2)))
pm <- cv_oof(function(a, e) cbind(a = cbind(1, L[e, ]) %*% co(a), b = 0), fo)
stopifnot(is.matrix(pm), ncol(pm) == 2, isTRUE(all.equal(unname(pm[, 1]), p2)), mejor_columna(pm) == 1)
cat("OK: partición, buffer y cv_oof verificados\n")
