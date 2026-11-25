# =============================================================================
# 04g_en_sin_texto.R - Elastic net SIN variables de texto
# Comparable con m12_en_m02 (dummies), m12_en_m02_pca_tx y m14_en_enc_tx.
# Para la tabla de la moraleja 1 (95_presentacion.R): mide cuánto aportan las
# dummies extraídas del texto.
# Usa la base de esa fecha (commit 87b076a, la de m12 y m14) y la misma
# configuración (alpha = 1, nlambda = 100, lambda.min.ratio = 1e-6; lambda por
# MAE total con la CV por localidad, como 04c). Primero reproduce m12_en_m02.
# Variables de texto que se quitan (criterio de 03e_pca.R): area_texto,
# piso_txt, antig_txt, parq_txt, n_palabras y tx_*.
# Registro: m53_en_sin_texto (se subió a Kaggle como m51_en_sin_texto.csv)
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))

# MAE de m12_en_m02 con la base del 18/11, como se subió a Kaggle. El registro
# actual tiene otro valor porque 00_main.R lo volvió a entrenar con la base
# nueva (D27).
REF_M12 <- 132163918

b_old <- readRDS(desde_git("87b076a", "data/processed/base_modelo.rds"))
TR_old <- filter(b_old$datos, muestra == "train")
TE_old <- filter(b_old$datos, muestra == "test")
# Mismas filas y en el mismo orden que la base actual
stopifnot(
  identical(TR_old$property_id, TR$property_id),
  identical(TE_old$property_id, TE$property_id)
)

v_txt <- c(
  "area_texto", "piso_txt", "antig_txt", "parq_txt", "n_palabras",
  grep("^tx_", b_old$vars, value = TRUE)
)

# matriz_lineal() + interacciones() de m02, sin las variables de texto ni sus
# indicadores de faltante
sin_texto <- function(df) {
  X <- df[setdiff(b_old$vars, v_txt)]
  cuadrados <- c(
    "log_area", "bedrooms", "banos_final", "estrato_final", "dist_cbd",
    "dist_transmilenio", "lat", "lon"
  )
  for (v in cuadrados) X[[paste0(v, "_2")]] <- X[[v]]^2
  X$log_area_x_apto <- X$log_area * X$es_apto
  X$log_area_x_estrato <- X$log_area * X$estrato_final
  X$dist_cbd_x_apto <- X$dist_cbd * X$es_apto
  cbind(as.matrix(X), interacciones(df))
}

con_texto <- function(df) {
  cbind(matriz_lineal(df, ref = TR_old, vars = b_old$vars), interacciones(df))
}

en <- function(Xtr, Xte) {
  lam <- glmnet(Xtr, Y, alpha = 1, nlambda = 100, lambda.min.ratio = 1e-6)$lambda
  oof <- cv_oof(function(a, e) {
    fit <- glmnet(Xtr[a, ], Y[a], alpha = 1, lambda = lam)
    predict(fit, Xtr[e, ], s = lam)
  })
  j <- mejor_columna(oof)
  fit <- glmnet(Xtr, Y, alpha = 1, lambda = lam)
  list(
    lambda = lam[j],
    oof = oof[, j],
    pred_te = drop(predict(fit, Xte, s = lam[j])),
    m = evalua(oof[, j])
  )
}

con <- en(con_texto(TR_old), con_texto(TE_old))
sin <- en(sin_texto(TR_old), sin_texto(TE_old))
cat(sprintf(
  "Reproducción de m12_en_m02: %.1f (registrado %.1f) | sin texto: %.1f / Chap %.1f\n",
  con$m$mae_total / 1e6, REF_M12 / 1e6,
  sin$m$mae_total / 1e6, sin$m$mae_chapinero / 1e6
))
stopifnot(abs(con$m$mae_total - REF_M12) < 5e5)

registra(
  "m53_en_sin_texto",
  paste(
    "Elastic net con las variables de m02 SIN las derivadas del texto",
    "(base del 18/11, como m12_en_m02); sobre log(precio)"
  ),
  sprintf("alpha=1; lambda=%.2g; nlambda=100; lambda.min.ratio=1e-06", sin$lambda),
  sin$m, sin$oof, sin$pred_te
)
