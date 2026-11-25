# =============================================================================
# 97_shap_ensamble.R - Valores SHAP (Lundberg y Lee, 2017) de los modelos del
# ensamble ganador y del ensamble
# Ensamble m24_ens_optimo (Kaggle 152,3) = 53,4% NN STAR m17 + 39,9% XGB con
# comparables m22 + 6,6% elastic net m14. Los modelos no quedaron guardados: se
# reentrenan con su configuración y su base originales.
#  - NN STAR m17: base del 18/11 (commit 87b076a), lr 1e-3, p_u 0,1, p_t 0,5,
#    MSE, 3 épocas. Es aditiva por ramas, así que su SHAP se descompone exacto
#    por rama: estructura (lineal: w_j (z_j - media)), ubicación (Shapley exacto
#    entre 3 grupos: estrato, coordenadas y entorno, con 100 anuncios del train
#    de fondo) y texto (salida de la rama menos su media).
#  - XGB m22 (María José): base de su rama (VALIDACION_SINTETICA), comparables
#    de 5 y 20 vecinos del mismo tipo, profundidad 6, mcw 10, eta 0,03,
#    subsample 0,8, colsample 0,6, 2.500 rondas, objetivo log(precio/m2) con
#    log_area como variable. TreeSHAP exacto.
#  - Elastic net: m14 usaba un encoder de texto que ya se sobrescribió; se usa
#    m54 (mismo modelo, encoder actual). SHAP lineal.
# En m17 y m22 el objetivo es log(precio/m2): el offset log_area se suma al
# grupo "Área". Todo en log del precio.
# Ensamble: suma ponderada de los SHAP en log (aproxima el promedio de
# precios). Se explican 2.000 anuncios del test.
# Salidas (output/tables/03_presentacion/): shap_grupos.csv y
# shap_top_variables.csv
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))
source(here::here("code", "utils_redes.R"))
source(here::here("code", "utils_comparables.R"))

# Último commit de la rama validacion-sintetica que se usó (fijo, para que la
# corrida no cambie si la rama avanza)
VALIDACION_SINTETICA <- "b4948f0"
cur <- list(base = base, D = D, TR = TR, TE = TE)
set.seed(123)
S <- sort(sample(nrow(TE), 2000))
W_ENS <- c(nn = .534, xgb = .399, en = .066)
W_ENS <- W_ENS / sum(W_ENS)

# ---- Grupos de datos ----
parte <- c(apto = "es_apto", estrato = "estrato_final")
grupo1 <- function(v) {
  v <- sub("_2$", "", v)
  v <- ifelse(v %in% names(parte), parte[v], v)
  case_when(
    startsWith(v, "comp") ~ "Comparables (precio de vecinos)",
    v %in% c("log_area", "area_imputada", "area_texto") ~ "Área",
    grepl("^(bedrooms|banos)", v) ~ "Habitaciones y baños",
    v == "es_apto" ~ "Tipo de inmueble",
    startsWith(v, "estrato") ~ "Estrato",
    grepl("^(lat|lon)", v) ~ "Coordenadas",
    grepl("^(dist_|n500_)|500$", v) ~ "Entorno (OSM)",
    grepl("^tx_|piso_txt|antig_txt|parq_txt|n_palabras|^na_", v) ~ "Texto: dummies y números",
    v %in% c("txt", "enc_texto") | startsWith(v, "tf_") ~ "Texto: TF-IDF o encoder",
    v %in% c("year", "month") ~ "Fecha",
    TRUE ~ "Otras"
  )
}
# Columnas = variables; las interacciones x_y se reparten 50/50 entre los dos
# grupos
a_grupos <- function(Phi) {
  out <- list()
  for (j in seq_len(ncol(Phi))) {
    cn <- colnames(Phi)[j]
    ps <- if (grepl("_x_", cn)) strsplit(cn, "_x_")[[1]] else cn
    for (p in ps) {
      g <- grupo1(p)
      out[[g]] <- (if (is.null(out[[g]])) 0 else out[[g]]) + Phi[, j] / length(ps)
    }
  }
  as.data.frame(out, check.names = FALSE)
}

# ---- 1. NN STAR m17 (base del 18/11) ----
b_old <- readRDS(desde_git("87b076a", "data/processed/base_modelo.rds"))
base <- b_old
D <- b_old$datos
TR <- filter(D, muestra == "train")
TE <- filter(D, muestra == "test")
stopifnot(
  identical(TR$property_id, cur$TR$property_id),
  identical(TE$property_id, cur$TE$property_id)
)
YR <- list(m2 = Y - TR$log_area)
OFF <- list(m2 = list(tr = TR$log_area, te = TE$log_area))
usa_bloques(area_m2 = FALSE, osm = TRUE, catastro = "no")
f <- ajusta_final(
  tibble(objetivo = "m2", epocas = 3), \(g, d) red_star(d, .1, .5), 1e-3, "mse"
)
Xe <- lapply(f$xte, reticulate::py_to_r)
Xr <- lapply(f$xtr, reticulate::py_to_r)
sub_m <- \(k) keras_model(f$red$ramas$inputs[[k]], f$red$ramas$outputs[[k]])
pr <- function(m, x) {
  drop(predict(m, reticulate::np_array(x, dtype = "float32"), batch_size = 65536, verbose = 0))
}

# Estructura (lineal): pesos por sondeo de la rama con la matriz identidad
m_est <- sub_m(1)
pe <- ncol(Xe[[1]])
w_est <- pr(m_est, diag(pe)) - pr(m_est, matrix(0, 1, pe))
Phi_est <- sweep(sweep(Xe[[1]][S, ], 2, colMeans(Xr[[1]])), 2, w_est, "*")
colnames(Phi_est) <- colnames(BR$m2$est)

# Ubicación: Shapley exacto entre 3 grupos (2^3 coaliciones), fondo de 100
# anuncios del train
m_ubi <- sub_m(2)
cu <- colnames(BR$m2$ubi)
gu <- case_when(
  startsWith(sub("_2$", "", cu), "estrato") ~ 1L,
  grepl("^(lat|lon)", cu) ~ 2L,
  TRUE ~ 3L
)
set.seed(123)
bg <- Xr[[2]][sample(nrow(Xr[[2]]), 100), ]
xs <- Xe[[2]][S, ]
# Valor de la coalición: promedio sobre el fondo, con las columnas de la
# coalición fijas en x
v <- function(coal) {
  M <- bg[rep(seq_len(nrow(bg)), times = nrow(xs)), ]
  idx <- rep(seq_len(nrow(xs)), each = nrow(bg))
  cols <- which(gu %in% coal)
  if (length(cols)) M[, cols] <- xs[idx, cols]
  colMeans(matrix(pr(m_ubi, M), nrow = nrow(bg)))
}
coals <- list(integer(0), 1L, 2L, 3L, c(1L, 2L), c(1L, 3L), c(2L, 3L), 1:3)
key <- \(s) if (length(s)) paste(sort(s), collapse = ",") else "vacia"
V <- setNames(lapply(coals, v), map_chr(coals, key))
shap_g <- sapply(1:3, function(i) {
  otros <- setdiff(1:3, i)
  tot <- 0
  for (k in 0:2) {
    for (s in combn(otros, k, simplify = FALSE)) {
      s <- as.integer(unlist(s))
      peso <- factorial(length(s)) * factorial(3 - length(s) - 1) / factorial(3)
      tot <- tot + peso * (V[[key(c(s, i))]] - V[[key(s)]])
    }
  }
  tot
})
colnames(shap_g) <- c("estrato_final", "lat", "dist_cbd") # un nombre por grupo

# Texto: la rama completa como un grupo
m_txt <- sub_m(3)
Phi_txt <- cbind(txt = pr(m_txt, Xe[[3]][S, ]) - mean(pr(m_txt, Xr[[3]])))
off_nn <- cbind(log_area = TE$log_area[S] - mean(TR$log_area))
G_nn <- a_grupos(cbind(Phi_est, shap_g, Phi_txt, off_nn))
top_nn <- colMeans(abs(cbind(Phi_est, Phi_txt, off_nn)))
cat("NN STAR m17 listo\n")

# ---- 2. XGB con comparables m22 (base de la rama de María José) ----
b_el <- readRDS(desde_git(VALIDACION_SINTETICA, "data/processed/base_modelo.rds"))
base <- b_el
D <- b_el$datos
TR <- filter(D, muestra == "train")
TE <- filter(D, muestra == "test")
stopifnot(identical(TR$property_id, cur$TR$property_id))
CMP <- prepara_comparables(k_max = 60)
CMP$r_tr <- rep(0, nrow(TR)) # como en su rama: sin radio mínimo
o <- arma_objetivos(
  cbind(matriz_arboles(TR, vars = b_el$vars), comparables_train(CMP)),
  cbind(matriz_arboles(TE, vars = b_el$vars), comparables_test(CMP)),
  quita_area = FALSE
)$m2
pr_x <- list(
  objective = "reg:squarederror", eta = .03, max_depth = 6, min_child_weight = 10,
  subsample = .8, colsample_bytree = .6, lambda = 1, nthread = 8, seed = 123
)
fit <- xgb.train(
  params = pr_x, data = xgb.DMatrix(o$Xtr, label = o$y, nthread = 8),
  nrounds = 2500, verbose = 0
)
cb <- predict(fit, xgb.DMatrix(o$Xte[S, ]), predcontrib = TRUE)
cb <- cb[, !colnames(cb) %in% c("BIAS", "(Intercept)")]
off_x <- cbind(log_area = TE$log_area[S] - mean(TR$log_area))
# log_area: variable + offset en una sola columna
cbx <- t(rowsum(t(cbind(cb, off_x)), colnames(cbind(cb, off_x))))
G_xgb <- a_grupos(cbx)
top_xgb <- colMeans(abs(cbx))
cat("XGB m22 listo\n")

# ---- 3. Elastic net con encoder (m54 en lugar de m14) ----
base <- cur$base
D <- cur$D
TR <- cur$TR
TE <- cur$TE
base$vars <- vars_sin(osm_ganadora())
ef <- lee_csv(file.path(P$processed, "star_encoders.csv"))
matriz_en <- function(df) {
  cbind(
    matriz_lineal(df), interacciones(df),
    enc_texto = ef$enc_texto[match(df$property_id, ef$property_id)]
  )
}
Xtr_en <- matriz_en(TR)
Xte_en <- matriz_en(TE)
b_en <- as.matrix(coef(glmnet(Xtr_en, Y, alpha = 1, lambda = .00014)))[-1, 1]
Phi_en <- sweep(sweep(Xte_en[S, ], 2, colMeans(Xtr_en)), 2, b_en, "*")
G_en <- a_grupos(Phi_en)
top_en <- colMeans(abs(Phi_en))
cat("Elastic net listo\n")

# ---- 4. Ensamble y resúmenes ----
grupos <- union(union(names(G_nn), names(G_xgb)), names(G_en))
completa <- function(G) {
  for (g in setdiff(grupos, names(G))) G[[g]] <- 0
  as.matrix(G[grupos])
}
Gs <- list(nn = completa(G_nn), xgb = completa(G_xgb), en = completa(G_en))
Gs$ens <- W_ENS["nn"] * Gs$nn + W_ENS["xgb"] * Gs$xgb + W_ENS["en"] * Gs$en
res <- imap_dfr(Gs, \(G, m) tibble(modelo = m, grupo = colnames(G), shap_abs = colMeans(abs(G))))
print(as.data.frame(
  res %>%
    mutate(shap_abs = round(100 * shap_abs, 1)) %>%
    pivot_wider(names_from = modelo, values_from = shap_abs) %>%
    arrange(desc(ens))
))
write_csv(res, file.path(P$tab_pres, "shap_grupos.csv"))

tops <- imap_dfr(list(nn = top_nn, xgb = top_xgb, en = top_en), function(t, m) {
  tibble(
    modelo = m, variable = names(t), shap_abs = t,
    grupo = ifelse(grepl("_x_", names(t)), "Interacción", grupo1(names(t)))
  ) %>%
    arrange(desc(shap_abs)) %>%
    slice_head(n = 10)
})
write_csv(tops, file.path(P$tab_pres, "shap_top_variables.csv"))
print(as.data.frame(tops %>% mutate(shap_abs = round(100 * shap_abs, 1))))
