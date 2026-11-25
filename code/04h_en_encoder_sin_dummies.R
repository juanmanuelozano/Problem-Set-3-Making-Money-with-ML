# =============================================================================
# 04h_en_encoder_sin_dummies.R - ¿Las dummies del texto aportan algo que el
# encoder de texto no? (moraleja 1)
# El encoder de texto del STAR resume el TF-IDF, y la limpieza del texto (03c)
# quita los números: el encoder no puede ver el piso, la antigüedad ni el número
# de parqueaderos, que sí extraen las expresiones regulares (piso_txt,
# antig_txt, parq_txt), ni las negaciones que manejan las dummies
# ("sin ascensor").
# Dos elastic net con el encoder de texto (encoders por fold de 08: las filas
# evaluadas nunca entran a su ajuste):
#   m54_en_enc_tx_dummies: variables de m02 + encoder de texto (como m14/m23,
#     con la base y los encoders actuales)
#   m55_en_enc_tx_sin_dummies: lo mismo SIN las variables derivadas del texto
#     (tx_*, piso, antigüedad, parqueaderos, largo)
# Configuración de m14: alpha = 1, nlambda = 100, lambda.min.ratio = 1e-6,
# lambda por MAE total; objetivo log(precio).
# Requiere models/star_encoders_folds.rds (08_xgb_star.R, CATASTRO=no).
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))

base$vars <- vars_sin(osm_ganadora()) # misma base que 08b (m23)
W <- pesos_twcv()

encs <- readRDS(file.path(P$models, "star_encoders_folds.rds"))
ef <- lee_csv(file.path(P$processed, "star_encoders.csv"))
enc_tr <- ef$enc_texto[match(TR$property_id, ef$property_id)]
enc_te <- ef$enc_texto[match(TE$property_id, ef$property_id)]
B_tr <- cbind(matriz_lineal(TR), interacciones(TR))
B_te <- cbind(matriz_lineal(TE), interacciones(TE))
# Columnas derivadas del texto, incluidos sus na_* y cuadrados
txt <- grepl("^tx_|piso_txt|antig_txt|parq_txt|n_palabras|area_texto", colnames(B_tr))
cat("Columnas derivadas del texto que se quitan:", sum(txt), "de", ncol(B_tr), "\n")

fold_de <- function(e) which(map_lgl(encs, ~ .x$evaluacion[1] == e[1]))

corre <- function(nombre, cols, desc) {
  X <- B_tr[, cols]
  Xte <- cbind(B_te[, cols], enc_texto = enc_te)
  X_todo <- cbind(X, enc_texto = enc_tr)
  lam <- glmnet(X_todo, Y, alpha = 1, nlambda = 100, lambda.min.ratio = 1e-6)$lambda
  oof <- cv_oof(function(a, e) {
    k <- fold_de(e)
    fit <- glmnet(cbind(X[a, ], enc_texto = encs[[k]]$ea[, 2]), Y[a], alpha = 1, lambda = lam)
    predict(fit, cbind(X[e, ], enc_texto = encs[[k]]$ee[, 2]), s = lam)
  })
  j <- mejor_columna(oof)
  m <- evalua(oof[, j])
  fit <- glmnet(X_todo, Y, alpha = 1, lambda = lam)
  cat(sprintf(
    "%s: MAE %.1f / Chap %.1f / TWCV %.1f\n", nombre,
    m$mae_total / 1e6, m$mae_chapinero / 1e6, mae_w(oof[, j], W) / 1e6
  ))
  registra(
    nombre, desc,
    sprintf("alpha=1; lambda=%.2g; nlambda=100; lambda.min.ratio=1e-06", lam[j]),
    m, oof[, j], drop(predict(fit, Xte, s = lam[j]))
  )
}

corre(
  "m54_en_enc_tx_dummies", rep(TRUE, ncol(B_tr)),
  paste(
    "Elastic net: variables de m02 (con las dummies del texto) + encoder de",
    "texto del STAR (encoders de 08b); 04h; sobre log(precio)"
  )
)
corre(
  "m55_en_enc_tx_sin_dummies", !txt,
  paste(
    "Elastic net: variables de m02 SIN las derivadas del texto + encoder de",
    "texto del STAR (encoders de 08b); 04h; sobre log(precio)"
  )
)
