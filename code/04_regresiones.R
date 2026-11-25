# =============================================================================
# 04_regresiones.R - Regresiones lineales sin penalización (OLS) sobre log(precio)
#  0. m00: mediana del train (referencia trivial)
#  1. Especificaciones hedónicas acumulativas: estructural -> + ubicación -> + texto -> + no linealidades.
#     Solo van a una tabla (no al registro). Nada lleva dummies de localidad (D10).
#  2. m01: OLS con la especificación completa (se registra y entra al ensamble)
#  3. reg_ols_sin_loc y m08: m01 + habitaciones × distancia a cada CBD, por OLS y por regresión de mediana
#  4. m09 y m10: las mismas dos regresiones sobre el precio por m2 (sin variables de área)
# Validación: dejar una localidad afuera con buffer (cv_oof, D9).
# Salidas: output/tables/02_modelos/ols_especificaciones.csv, models/registro_modelos.csv
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))

Xtr <- matriz_lineal(TR); Xte <- matriz_lineal(TE)
v <- colnames(Xtr)

# ---- 0. Referencia trivial: mediana del train ----
registra("m00_mediana", "Mediana del precio del train (referencia)", "-",
         evalua(rep(median(Y), length(Y))), rep(median(Y), length(Y)), rep(median(Y), nrow(TE)))

# ---- 1. Bloques de variables (columnas de matriz_lineal) ----
# Para probar otra especificación: agregar un bloque aquí (el orden define la acumulación).
no_lineal <- grep("_2$|_x_", v, value = TRUE)
bloques <- list(
  estructural = c("log_area", "area_imputada", "area_texto", "bedrooms", "banos_final", "banos_imputado", "es_apto",
                  "estrato_final", "piso_txt", "antig_txt", "parq_txt", grep("^na_", v, value = TRUE),
                  "n_palabras", "year", "month"),
  ubicacion   = setdiff(c("lat", "lon", "lat_rot1", "lat_rot2", grep("^(dist|n500)_", v, value = TRUE)), no_lineal),
  texto       = grep("^tx_", v, value = TRUE),
  no_lineal   = no_lineal)
stopifnot(!anyDuplicated(unlist(bloques)), setequal(unlist(bloques), v))   # cada columna en un solo bloque

# ---- 2. OLS con validación cruzada ----
ols_oof  <- function(X) drop(cv_oof(function(a, e) cbind(1, X[e, , drop = FALSE]) %*% ols_coef(X, a)))

specs <- set_names(accumulate(names(bloques), c),
                   c("1. Estructural", "2. + Ubicación", "3. + Texto", "4. + No linealidades"))
tabla <- imap_dfr(specs, function(b, nombre) {
  cols <- unlist(bloques[b]); p <- ols_oof(Xtr[, cols])
  tibble(especificacion = nombre, n_variables = length(cols),
         r2_oof = 1 - sum((Y - p)^2) / sum((Y - mean(Y))^2), oof = list(p)) %>% bind_cols(evalua(p))
})
print(tabla %>% select(-oof) %>% mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1)), across(c(r2_oof, mape_chapinero), ~ round(.x, 3))))
write_csv(select(tabla, -oof), file.path(P$tab_mod, "ols_especificaciones.csv"))

# ---- 3. Registro de la especificación completa ----
registra("m01_ols", "OLS con variables estructurales, ubicación, texto y no linealidades", "-",
         evalua(last(tabla$oof)), last(tabla$oof), drop(cbind(1, Xte) %*% ols_coef(Xtr, seq_along(Y))))

# ---- 4. Especificación completa + habitaciones × distancia a cada CBD: OLS y LAD ----
Ztr <- cbind(Xtr, interacciones(TR)); Zte <- cbind(Xte, interacciones(TE))

oof_z <- ols_oof(Ztr)
registra("reg_ols_sin_loc", "OLS sin dummies de localidad + habitaciones × distancia a cada CBD", "-",
         evalua(oof_z), oof_z, drop(cbind(1, Zte) %*% ols_coef(Ztr, seq_along(Y))))

# Regresión de mediana (LAD): minimiza el error absoluto, la misma pérdida de la competencia. Se resuelve por
# mínimos cuadrados reponderados con pesos 1/|residuo| (IRLS); exp() de la mediana del log es la mediana del precio.
# ponytail: IRLS aproxima la solución exacta; quantreg::rq(method = "fn") si hiciera falta exactitud
lad_coef <- function(X, a, y = Y, iter = 50) {
  Xa <- cbind(1, X[a, , drop = FALSE]); w <- rep(1, length(a))
  for (i in seq_len(iter)) {
    b <- lm.wfit(Xa, y[a], w)$coefficients; b[is.na(b)] <- 0
    w <- 1 / pmax(abs(drop(y[a] - Xa %*% b)), 1e-4)
  }
  b
}
oof_lad <- drop(cv_oof(function(a, e) cbind(1, Ztr[e, , drop = FALSE]) %*% lad_coef(Ztr, a)))
registra("m08_lad_sin_loc", "Regresión de mediana (pérdida MAE), mismas variables que reg_ols_sin_loc", "IRLS, 50 iteraciones",
         evalua(oof_lad), oof_lad, drop(cbind(1, Zte) %*% lad_coef(Ztr, seq_along(Y))))

# ---- 5. Precio por m2: las mismas dos regresiones sobre log(precio / área) ----
# Se excluyen el área y sus términos derivados (log_area, log_area_2, log_area_x_apto, log_area_x_estrato); se
# conservan los indicadores de la fuente del área. Precio predicho = precio por m2 predicho × m2, es decir,
# en log: log(precio/m2) + log(área). Así se evalúa en la CV y así se arma el envío.
o <- arma_objetivos(Ztr, Zte)$m2
for (m in list(list("m09_ols_m2", "OLS", ols_coef), list("m10_lad_m2", "Regresión de mediana (IRLS)", lad_coef))) {
  oof <- drop(cv_oof(function(a, e) cbind(1, o$Xtr[e, , drop = FALSE]) %*% m[[3]](o$Xtr, a, o$y))) + o$off_tr
  registra(m[[1]], paste(m[[2]], "sobre log(precio por m2), sin variables de área; precio = predicción × m2"), "-",
           evalua(oof), oof, drop(cbind(1, o$Xte) %*% m[[3]](o$Xtr, seq_along(Y), o$y)) + o$off_te)
}
