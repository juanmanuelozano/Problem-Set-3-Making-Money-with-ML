# =============================================================================
# 08_xgb_star.R - Modelo STAR con XGBoost y restricciones de interacción (Mayer, Bourassa, Hoesli y Scognamiglio,
#                 2022, JRFM 15: 193), y encoders supervisados de ubicación y de texto.
# Grupos (partición; cada árbol usa variables de un solo grupo):
#  - Estructura y tiempo: cada variable sola -> efectos ADITIVOS (área, habitaciones, baños, tipo, piso, antigüedad,
#    parqueaderos, indicadores, año, mes y las 22 dummies tx_*).
#  - Ubicación: lat, lon, rotadas, dist_*, n500_* y estrato_final (D13: el estrato es casi todo espacial) -> interactúan.
#  - Texto: los 1.000 términos TF-IDF más frecuentes (filtro no supervisado; conserva penthouse, duplex, cuarto
#    servicio...) -> interactúan. Su componente es un encoder de texto SUPERVISADO, a diferencia del PCA.
# Sin dummies de localidad (D10). Validación: una localidad afuera con buffer (cv_oof, D9).
# Grilla (el paper ajusta profundidad, L1, L2 y submuestreo con búsqueda aleatoria): dos búsquedas aleatorias de
# N_CONF configuraciones con objetivo m2 (pérdida cuadrática con eta 0,1 y tope de 1.000 rondas; absoluta con eta 0,2 y
# tope de 2.000), en el espacio ampliado. La primera candidata de cada búsqueda es la mejor configuración de la grilla
# de 2026-11-20. TODO se elige por MAE TWCV (rondas y configuraciones; D16, D17). Se registra el mejor de cada búsqueda;
# los encoders salen del mejor de los dos.
# Datos: base nueva (D14) sin zona de lujo (D15) y con o sin contexto de OSM según la ganadora del NN STAR (08f).
# Encoders (Algoritmo 1 del paper): se fijan las variables fuera del grupo y se predice; centrados con el train.
# Salidas: tables/star_{grilla,resumen,texto_terminos}.csv, figures/m6_star_mapa_ubicacion.png, m7_star_ice_banos.png,
#          data/processed/star_encoders.csv, models/star_encoders_folds.rds (para 08b),
#          registro m22_xgb_star_twcv_m2 (cuadrática) y m22_xgb_star_twcv_m2_mae (absoluta). Los m13 (base anterior)
#          no se tocan; los encoders y tablas de star_* se sobrescriben (la versión anterior queda en git).
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(xgboost, Matrix))
K_TXT <- 1000; N_CONF <- 10; PRUEBA <- nzchar(Sys.getenv("PRUEBA"))
RONDAS <- list("reg:squarederror" = seq(50, 1000, 50), "reg:absoluteerror" = seq(100, 2000, 100))   # el óptimo cuadrático nunca pasó de 750
if (PRUEBA) { N_CONF <- 2; RONDAS <- map(RONDAS, ~ .x[1:2]) }                                       # flujo completo en minutos
W <- pesos_twcv(); OSM <- osm_ganadora(); base$vars <- vars_sin(OSM)                                # sin zona de lujo; OSM según 08f
# CATASTRO=valor_estrato (D18): agrega log(valor de referencia del suelo) a la ubicación y usa el estrato oficial de la
# manzana; los modelos se registran como m27_* y las salidas llevan el sufijo _catastro (no pisan m22 ni sus encoders).
CATASTRO <- Sys.getenv("CATASTRO", "no"); SUF <- if (CATASTRO == "no") "" else "_catastro"
if (CATASTRO != "no") {
  ct <- lee_csv(file.path(P$processed, "catastro.csv")); k <- match(D$property_id, ct$property_id); stopifnot(!anyNA(k))
  D$log_v_ref <- ct$log_v_ref[k]
  if (CATASTRO == "valor_estrato") D$estrato_final <- ifelse(ct$estrato_oficial[k] > 0, ct$estrato_oficial[k], D$estrato_final)
  TR <- filter(D, muestra == "train"); TE <- filter(D, muestra == "test"); base$vars <- c(base$vars, "log_v_ref")
  stopifnot(identical(TR$property_id, base$datos$property_id[base$datos$muestra == "train"]))
}
cat("Catastro:", CATASTRO, "\n")
cat("Variables:", length(base$vars), "| contexto de OSM:", OSM, "\n")
T0 <- Sys.time(); paso <- function(msg) cat(sprintf("[%5.0f min] %s\n", as.numeric(difftime(Sys.time(), T0, units = "mins")), msg))

# ---- Matrices: variables de árboles + TF-IDF (dispersa) ----
Xt <- readRDS(file.path(P$processed, "base_texto.rds"))
Xt <- Xt[, order(-colSums(Xt != 0))[1:K_TXT]]; colnames(Xt) <- paste0("tf_", colnames(Xt))
mat <- function(df) cbind(Matrix(matriz_arboles(df), sparse = TRUE), Xt[match(df$property_id, rownames(Xt)), ])
objetivos <- arma_objetivos(mat(TR), mat(TE))   # m2: sin log_area, precio = predicción × m2
es_loc <- function(cn) cn %in% c("lat", "lon", "lat_rot1", "lat_rot2", "estrato_final", "log_v_ref") | grepl("^(dist|n500)_", cn) |
  grepl("500$", cn)   # area_verde500, pisos_prom500 (D15)
es_txt <- function(cn) startsWith(cn, "tf_")
grupos <- function(cn) {   # índices desde 0: una lista por variable aditiva + ubicación + texto
  i <- seq_along(cn) - 1L
  c(as.list(i[!es_loc(cn) & !es_txt(cn)]), list(i[es_loc(cn)], i[es_txt(cn)]))
}

# ---- Búsquedas aleatorias en el espacio ampliado: m2 cuadrática, m2 absoluta y precio cuadrática ----
espacio <- expand_grid(max_depth = 2:5, min_child_weight = c(1, 3, 5, 10), subsample = c(.8, .9, 1),
                       colsample_bytree = c(.7, .8, .9, 1), lambda = c(0, .5, 1, 3), alpha = c(0, 1, 3, 10))
anterior <- tibble(max_depth = 3, min_child_weight = 3, subsample = .9, colsample_bytree = .8, lambda = 1, alpha = 1, eta = .1)
candidatas <- function(tasa) {   # la mejor configuración anterior + N_CONF - 1 al azar
  e <- expand_grid(espacio, eta = tasa); set.seed(123)
  bind_rows(mutate(anterior, eta = tasa), e[sample(nrow(e), N_CONF - 1), ])
}
pr_de <- function(cfg, obj, loss)
  c(list(objective = loss, max_bin = 64, nthread = 8, seed = 123,
         interaction_constraints = grupos(colnames(objetivos[[obj]]$Xtr))), as.list(cfg))
corre <- function(pr, obj, rondas) {
  o <- objetivos[[obj]]
  oof <- cv_oof(function(a, e) xgb_rondas(pr, o$Xtr[a, ], o$y[a], o$Xtr[e, ], rondas)) + o$off_tr
  j <- mejor_columna(oof, W); list(nrounds = rondas[j], oof = oof[, j], borde = j == length(rondas))   # rondas por TWCV
}
f_grilla <- file.path(P$rep_mod, "tables", paste0("star_grilla", SUF, ".csv"))
busquedas <- list(c("m2", "reg:squarederror"), c("m2", "reg:absoluteerror"))
res <- list()
for (x in busquedas) {
  cand <- candidatas(if (x[2] == "reg:absoluteerror") .2 else .1)   # la MAE avanza más lento: eta más alto
  for (k in seq_len(nrow(cand))) {
    r <- corre(pr_de(cand[k, ], x[1], x[2]), x[1], RONDAS[[x[2]]])
    res[[length(res) + 1]] <- cand[k, ] %>%
      mutate(busqueda = paste(x, collapse = "/"), objetivo = x[1], perdida = x[2], nrounds = r$nrounds, borde = r$borde) %>%
      bind_cols(evalua(r$oof)) %>% mutate(mae_twcv = mae_w(r$oof, W), oof = list(r$oof))
    write_csv(select(bind_rows(res), -oof), f_grilla)   # se guarda a medida que avanza
    paso(sprintf("%s/%s %d/%d: depth %d, mcw %g, eta %g | rondas %d%s | MAE %.1f | Chap %.1f | TWCV %.1f", x[1], x[2], k, nrow(cand),
                 cand$max_depth[k], cand$min_child_weight[k], cand$eta[k], r$nrounds, if (r$borde) " (borde)" else "",
                 evalua(r$oof)$mae_total / 1e6, evalua(r$oof)$mae_chapinero / 1e6, mae_w(r$oof, W) / 1e6))
  }
}
tab <- bind_rows(res)

# ---- Modelos finales (mejor de cada búsqueda), registro y envío ----
finales <- tab %>% group_by(busqueda) %>% slice_min(mae_twcv, n = 1, with_ties = FALSE) %>% ungroup()
en_borde <- function(b) { v <- names(espacio); v <- v[map_lgl(v, ~ b[[.x]] %in% range(espacio[[.x]]))]
  if (length(v)) paste(v, collapse = ", ") else "ninguno" }
nombres <- if (CATASTRO == "no") c("m2/reg:squarederror" = "m22_xgb_star_twcv_m2", "m2/reg:absoluteerror" = "m22_xgb_star_twcv_m2_mae") else
  c("m2/reg:squarederror" = "m27_xgb_star_catastro_m2", "m2/reg:absoluteerror" = "m27_xgb_star_catastro_m2_mae")
fits <- list()
for (k in seq_len(nrow(finales))) {
  b <- finales[k, ]; o <- objetivos[[b$objetivo]]; pr <- pr_de(select(b, max_depth:eta), b$objetivo, b$perdida)
  cat(sprintf("%s: parámetros en el borde del espacio ampliado: %s%s\n", b$busqueda, en_borde(b),
              if (b$borde) "; rondas en el tope" else ""))
  fit <- xgb.train(params = pr, data = xgb.DMatrix(o$Xtr, label = o$y, nthread = 8), nrounds = b$nrounds, verbose = 0)
  fits[[b$busqueda]] <- list(fit = fit, pr = pr, nrounds = b$nrounds)
  if (!PRUEBA) registra(nombres[[b$busqueda]], paste("XGBoost STAR elegido por TWCV: estructura aditiva, ubicación y texto TF-IDF como grupos; base D14 sin zona de lujo,",
                         if (OSM) "con contexto de OSM;" else "sin contexto de OSM;",
                         if (CATASTRO != "no") paste0("catastro ", CATASTRO, ";") else "",
                         if (b$objetivo == "m2") "sobre log(precio por m2), precio = predicción × m2" else "sobre log(precio)"),
           sprintf("%s; depth=%d; mcw=%g; subsample=%.1f; colsample=%.1f; lambda=%g; alpha=%g; eta=%g; nrounds=%d",
                   b$perdida, b$max_depth, b$min_child_weight, b$subsample, b$colsample_bytree, b$lambda, b$alpha, b$eta, b$nrounds),
           select(b, starts_with("ma")), b$oof[[1]], predict(fit, xgb.DMatrix(o$Xte)) + o$off_te)
  # Verificación: ningún árbol mezcla variables de grupos distintos
  dt <- xgb.model.dt.tree(model = fit); g <- function(f) ifelse(es_txt(f), "texto", ifelse(es_loc(f), "ubicacion", f))
  mezcla <- dt %>% filter(Feature != "Leaf") %>% group_by(Tree) %>% summarise(n = n_distinct(g(Feature))) %>% filter(n > 1)
  stopifnot(nrow(mezcla) == 0)
}
paso("modelos finales registrados; restricciones verificadas")

# ---- Encoders (Algoritmo 1): se fijan las variables fuera del grupo y se predice; centrados con el train ----
encoders <- function(fit, Xr, X) {   # Xr: filas de referencia (train) para centrar; devuelve n x 2 (ubicacion, texto)
  cn <- colnames(X); jd <- which(!es_txt(cn)); jt <- which(es_txt(cn))   # bloque denso (primero) y TF-IDF (al final)
  ref <- as.numeric(Xr[1, jd])                                           # valores fijos arbitrarios: la primera fila
  arma <- function(M, grupo) {   # deja variar solo las columnas del grupo; el resto queda fijo (texto fijo en 0)
    Dm <- as.matrix(M[, jd]); fijas <- if (grupo == "ubicacion") !es_loc(cn[jd]) else rep(TRUE, length(jd))
    Dm[, fijas] <- matrix(ref[fijas], nrow(Dm), sum(fijas), byrow = TRUE)
    Tm <- if (grupo == "texto") M[, jt] else Matrix(0, nrow(M), length(jt), sparse = TRUE)
    out <- cbind(Matrix(Dm, sparse = TRUE), Tm); colnames(out) <- cn; out
  }
  sapply(c(ubicacion = "ubicacion", texto = "texto"), function(gr)
    predict(fit, xgb.DMatrix(arma(X, gr))) - mean(predict(fit, xgb.DMatrix(arma(Xr, gr)))))
}
b_m2 <- finales %>% slice_min(mae_twcv, n = 1, with_ties = FALSE)   # cuadrática o absoluta
cat("Encoders a partir de:", b_m2$busqueda, "\n")
fm <- fits[[b_m2$busqueda]]; o <- objetivos$m2
enc_tr <- encoders(fm$fit, o$Xtr, o$Xtr); enc_te <- encoders(fm$fit, o$Xtr, o$Xte)
# Chequeo: Algoritmo 1 = suma de predcontrib del grupo (en una muestra)
set.seed(123); s <- sample(nrow(o$Xtr), 500)
sh <- predict(fm$fit, xgb.DMatrix(o$Xtr[s, ]), predcontrib = TRUE)
d_ub <- rowSums(sh[, which(es_loc(colnames(o$Xtr)))]); d_ub <- d_ub - mean(d_ub)
cat("Encoder de ubicación: dif. máx. con predcontrib =", signif(max(abs((enc_tr[s, 1] - mean(enc_tr[s, 1])) - d_ub)), 3), "\n")
enc <- bind_rows(tibble(property_id = TR$property_id, muestra = "train", enc_ubicacion = enc_tr[, 1], enc_texto = enc_tr[, 2]),
                 tibble(property_id = TE$property_id, muestra = "test",  enc_ubicacion = enc_te[, 1], enc_texto = enc_te[, 2]))
write_csv(enc, file.path(P$processed, paste0("star_encoders", SUF, ".csv")))
cat("Encoders (media test - media train): ubicación", round(mean(enc_te[, 1]), 3), "| texto", round(mean(enc_te[, 2]), 3), "\n")

# ---- Encoders por fold (para 08b): STAR ajustado en las filas de análisis de cada fold ----
encs_fold <- map(FOLDS, function(f) {
  fit <- xgb.train(params = fm$pr, data = xgb.DMatrix(o$Xtr[f$analisis, ], label = o$y[f$analisis], nthread = 8),
                   nrounds = fm$nrounds, verbose = 0)
  list(analisis = f$analisis, evaluacion = f$evaluacion,
       ea = encoders(fit, o$Xtr[f$analisis, ], o$Xtr[f$analisis, ]), ee = encoders(fit, o$Xtr[f$analisis, ], o$Xtr[f$evaluacion, ]))
})
saveRDS(encs_fold, file.path(P$models, paste0("star_encoders_folds", SUF, ".rds")))
paso("encoders por fold guardados")

# ---- Figura: mapa de la prima de ubicación (análogo a la figura 11 del paper) ----
mapa_prima(enc, "Prima de ubicación aprendida por el modelo STAR",
           "Encoder del grupo de ubicación (mediana por celda de ~500 m; train y test)", paste0("m6_star_mapa_ubicacion", SUF, ".png"))

# ---- Figura: curvas ICE de los baños en el STAR (m2; deben ser paralelas: efecto aditivo) ----
set.seed(123); s <- sample(nrow(o$Xtr), 150); jb <- which(colnames(o$Xtr) == "banos_final")
ice <- map_dfr(1:6, function(v) { M <- o$Xtr[s, ]; M[, jb] <- v
  tibble(id = s, banos = v, pred = predict(fm$fit, xgb.DMatrix(M))) })
g7 <- ggplot(ice, aes(banos, pred, group = id)) + geom_line(color = c_train, alpha = .25, linewidth = .3) +
  labs(title = "Efecto de los baños en el STAR: curvas paralelas (efecto aditivo)",
       subtitle = "Curvas ICE de 150 anuncios del train, objetivo log(precio por m2)", x = "Baños",
       y = "log(precio por m2) predicho", caption = fuente)
ggsave(file.path(P$rep_mod, "figures", paste0("m7_star_ice_banos", SUF, ".png")), g7, width = 7, height = 4.5, dpi = 250)
cat("ICE: desviación estándar entre anuncios de la pendiente =",
    signif(sd(ice %>% group_by(id) %>% summarise(p = diff(range(pred))) %>% pull(p)), 3), "(0 = paralelas)\n")

# ---- Términos del texto: importancia supervisada (SHAP) frente a la varianza que conservaba el PCA ----
set.seed(123); s <- sample(nrow(o$Xtr), 3000)
sh <- predict(fm$fit, xgb.DMatrix(o$Xtr[s, ]), predcontrib = TRUE)
jt <- which(es_txt(colnames(o$Xtr)))
imp <- tibble(termino = sub("^tf_", "", colnames(o$Xtr)[jt]), importancia = colMeans(abs(sh[, jt])))
pca_tx <- readRDS(file.path(P$models, "pca_texto.rds")); Xf <- readRDS(file.path(P$processed, "base_texto.rds"))
vj <- (colSums(Xf^2) - nrow(Xf) * colMeans(Xf)^2) / (nrow(Xf) - 1)
imp <- imp %>% mutate(pct_varianza_pca = map_dbl(termino, ~ sum(pca_tx$rotation[.x, ]^2 * pca_tx$sdev^2) / vj[.x]),
                      rango = rank(-importancia)) %>% arrange(rango)
write_csv(imp, file.path(P$rep_mod, "tables", paste0("star_texto_terminos", SUF, ".csv")))
cat("\nTérminos más importantes del encoder de texto:\n"); print(head(imp, 15))
cat("\nSeñales de lujo (rango de importancia de 1.000 / % de varianza en el PCA):\n")
print(filter(imp, termino %in% c("penthouse", "cuarto servicio", "duplex", "walk closet", "piscina", "bano servicio", "chimenea")))

# ---- Resumen ----
kag <- lee_csv(file.path(P$models, "kaggle_scores.csv")) %>% select(modelo, kaggle = public_score)
reg <- lee_csv(file.path(P$models, "registro_modelos.csv"))
resumen <- tab %>% select(busqueda, nrounds, borde, max_depth:eta, mae_total, mae_chapinero, mae_macro, mae_twcv) %>%
  bind_rows(reg %>% filter(modelo %in% c("m04_xgboost", "m02b_elastic_net_m2")) %>% select(busqueda = modelo, mae_total, mae_chapinero, mae_macro)) %>%
  mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1))) %>% arrange(mae_twcv)
write_csv(resumen, file.path(P$rep_mod, "tables", paste0("star_resumen", SUF, ".csv")))
cat("\nResumen (MAE OOF, millones):\n"); print(as.data.frame(resumen))
paso("Listo.")
