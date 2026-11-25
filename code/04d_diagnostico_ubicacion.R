# =============================================================================
# 04d_diagnostico_ubicacion.R - ¿Cuánto pesan las coordenadas? m12 (EN sobre PCA) frente a m02b (EN por m2)
#  1. Contribución de cada grupo de variables a la predicción (en log): dispersión en el train y desplazamiento
#     medio test - train. Las componentes de no texto se reexpresan en las variables originales: si
#     pc = z %*% R, la contribución de la variable j es z_j * (R %*% beta)_j.
#  2. Ablación: la misma validación cruzada sin lat, lon ni sus cuadrados (el PCA de no texto se rehace sin ellas).
#  3. Predicciones de test de cada modelo.
# Salidas: tables/diagnostico_ubicacion_{contribuciones,ablacion}.csv
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))

grupo <- function(v) case_when(
  v %in% c("lat", "lon", "lat_2", "lon_2") ~ "1. coordenadas",
  str_detect(v, "^dist_|_x_dist") ~ "2. distancias",
  str_detect(v, "^n500_") ~ "3. densidades",
  str_detect(v, "^pc_tx|^tx_|_txt$|n_palabras|area_texto|^na_") ~ "5. texto",
  v %in% c("year", "month") ~ "6. fecha",
  TRUE ~ "4. estructura (área, habitaciones, baños, estrato, tipo)")

# ---- Matrices (las mismas de 04b y 04c) ----
nt <- lee_csv(file.path(P$processed, "base_no_texto.csv")); ptx <- lee_csv(file.path(P$processed, "pca_texto.csv"))
fila <- function(df, b) match(df$property_id, b$property_id)
v_nt <- setdiff(names(nt), c("property_id", "muestra"))
nolin <- function(df) { M <- cbind(matriz_lineal(df), interacciones(df)); M[, grep("_2$|_x_", colnames(M))] }
TX <- function(df) as.matrix(ptx[fila(df, ptx), grep("^pc_", names(ptx))])
pca_nt <- readRDS(file.path(P$models, "pca_no_texto.rds"))
Z <- function(df) scale(as.matrix(nt[fila(df, nt), v_nt]), pca_nt$center, pca_nt$scale)   # originales estandarizadas
m12 <- function(df, quita = character()) {   # PCA no texto (rehecho sin `quita`) + PCA texto + no linealidades
  v <- setdiff(v_nt, quita); p <- prcomp(nt[v], center = TRUE, scale. = TRUE)
  S <- predict(p, nt[fila(df, nt), v]); colnames(S) <- sprintf("pc_nt%02d", seq_len(ncol(S)))
  N <- nolin(df); cbind(S, TX(df), N[, !colnames(N) %in% paste0(quita, "_2")])
}
m02 <- function(df, quita = character()) { M <- cbind(matriz_lineal(df), interacciones(df)); M[, !colnames(M) %in% c(quita, paste0(quita, "_2"))] }

# Especificaciones: matrices, objetivo y alpha/lambda elegidos en 04b y 04c (registro)
mods <- list(
  m12_en_pca_nt_tx    = list(f = m12, obj = "precio", alpha = 1,   lambda = 1.4418673e-4),
  m12_en_pca_nt_tx_m2 = list(f = m12, obj = "m2",     alpha = 0.1, lambda = 0.02315913),
  m02b_elastic_net_m2 = list(f = m02, obj = "m2",     alpha = 1,   lambda = 0.0017))
COORD <- c("lat", "lon")

# ---- 1. Contribuciones por grupo ----
contrib <- imap_dfr(mods, function(m, nm) {
  o <- arma_objetivos(m$f(TR), m$f(TE))[[m$obj]]
  fit <- glmnet(o$Xtr, o$y, alpha = m$alpha, lambda = m$lambda)
  b <- coef(fit)[-1, 1]
  cc <- function(X, Zs) {   # contribución por variable original (n x variables)
    C <- sweep(X, 2, b[colnames(X)], `*`)
    pc <- grep("^pc_nt", colnames(X))
    if (length(pc)) C <- cbind(C[, -pc], Zs %*% diag(drop(pca_nt$rotation[, seq_along(pc)] %*% b[colnames(X)[pc]])) %>% `colnames<-`(v_nt))
    C
  }
  Ctr <- cc(o$Xtr, Z(TR)); Cte <- cc(o$Xte, Z(TE))
  g <- grupo(colnames(Ctr))
  map_dfr(unique(g), function(k) {
    a <- rowSums(Ctr[, g == k, drop = FALSE]); e <- rowSums(Cte[, g == k, drop = FALSE])
    tibble(modelo = nm, grupo = k, sd_train = sd(a), desplazamiento_test = mean(e) - mean(a),
           desplazamiento_test_vs_chap_train = mean(e) - mean(a[ES_CHAP]))
  })
}) %>% arrange(modelo, grupo)
write_csv(contrib, file.path(P$tab_mod, "diagnostico_ubicacion_contribuciones.csv"))
cat("\nContribución por grupo (log): dispersión en el train y desplazamiento medio del test frente al train\n")
print(as.data.frame(mutate(contrib, across(where(is.numeric), ~ round(.x, 3)))))

# ---- 2. Ablación: sin coordenadas ----
abl <- imap_dfr(mods, function(m, nm) map_dfr(list(con = character(), sin = COORD), function(q) {
  o <- arma_objetivos(m$f(TR, q), m$f(TE, q))[[m$obj]]
  lam <- glmnet(o$Xtr, o$y, alpha = m$alpha, nlambda = 100, lambda.min.ratio = 1e-5)$lambda
  oof <- cv_oof(function(a, e) predict(glmnet(o$Xtr[a, ], o$y[a], alpha = m$alpha, lambda = lam), o$Xtr[e, ], s = lam)) + o$off_tr
  j <- mejor_columna(oof)
  pt <- exp(drop(predict(glmnet(o$Xtr, o$y, alpha = m$alpha, lambda = lam), o$Xte, s = lam[j])) + o$off_te)
  evalua(oof[, j]) %>% mutate(modelo = nm, coordenadas = if (length(q)) "sin" else "con", .before = 1) %>%
    mutate(pred_test_media = mean(recorta(pt)), pred_test_mediana = median(recorta(pt)))
}, .id = NULL))
write_csv(abl, file.path(P$tab_mod, "diagnostico_ubicacion_ablacion.csv"))
cat("\nAblación (MAE OOF y predicción media del test, millones):\n")
print(as.data.frame(abl %>% select(-mape_chapinero) %>% mutate(across(where(is.numeric), ~ round(.x / 1e6, 1)))))

# ---- 3. Predicciones de test registradas ----
tst <- lee_csv(file.path(P$models, "test_predicciones.csv"))
pr <- sapply(names(mods), \(m) recorta(exp(tst[[m]])) / 1e6)
cat("\nPredicción de test (millones): media, cuartiles y % por encima de 1.000 M\n")
print(round(rbind(media = colMeans(pr), apply(pr, 2, quantile, c(.25, .5, .75)), pct_mayor_1000 = 100 * colMeans(pr > 1000)), 1))
cat("Precio del train: media", round(mean(exp(Y)) / 1e6), "| en Chapinero:", round(mean(exp(Y[ES_CHAP])) / 1e6), "\n")
cat("Correlación de las predicciones de test:\n"); print(round(cor(pr), 3))
