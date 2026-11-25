# =============================================================================
# 08p_xgb_star_comparables.R - XGB STAR con catastro + comparables en el grupo de ubicación, para combinar con m24, D26
# m37 (m24 + XGB STAR m27_mae, 50/50) no mejoró a m24 en Kaggle (156,8 vs 156,3): el XGB STAR se equivoca casi igual
# que la red (correlación de errores estimada 0,915). El XGB del equipo con comparables sí es distinto (0,94 en las
# predicciones, ~94 M por anuncio) y por eso su ensamble ganó 6 M. A los árboles los comparables les sirven (-10 M al
# XGB del equipo); a la red no (m32 = m24). Aquí: el XGB STAR de m27_mae (misma configuración, sin volver a buscar) con
# los comparables de m32 (5 y 20 vecinos del mismo tipo, sin radio, sin descripciones idénticas) en el grupo de
# ubicación. Las restricciones de interacción por grupos se mantienen: sigue siendo un STAR, y su promedio con m24 también.
# Validación: CV agrupada por edificio (FOLDS_EDIF) con los comparables recalculados en cada fold; rondas por MAE total.
# El peso de la combinación se elige en esa misma CV con la red de la configuración de m24 (nn_star_comparables.rds,
# variante sin_comparables, 08k), que tiene OOF en los mismos folds.
# Registro: m38_xgb_star_comparables_m2_mae (OOF de la CV por edificio; no comparable con la CV por localidad)
# VARIANTE=distinto: XGB STAR más distinto de la red (m24 tiene catastro): SIN catastro, árboles de profundidad 4, pérdida
#   cuadrática, eta 0,05 (como el XGB con comparables del equipo, que tiene correlación de errores 0,83 con m24 frente a
#   0,89 de m38). Registro: m41_xgb_star_comparables_distinto_m2.
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R")); source(here::here("code", "utils_comparables.R"))
PRUEBA <- nzchar(Sys.getenv("PRUEBA")); VAR <- Sys.getenv("VARIANTE")
GENERAL <- VAR == "area_sq_general"   # VARIANTE=area_sq_general: m47 SIN restricciones de interacción (XGB general, registro m50)
DISTINTO <- VAR == "distinto"; AREA <- VAR %in% c("area", "area_sq", "area_sq_general"); SQ <- VAR %in% c("distinto", "area_sq", "area_sq_general")
# VARIANTE=area_sq: catastro + comparables + log(área) con la configuración cuadrática de m41 (profundidad 4, eta 0,05),
#   que fue más precisa que la de m27_mae en la CV por edificio (registro m47)
# VARIANTE=area: m38 con log(área) entre las variables de estructura (elasticidad precio-área libre; registro m43)
RONDAS <- if (PRUEBA) c(100, 200) else if (SQ) seq(200, 4000, 200) else seq(200, 5000, 200)   # con tope de 2.000 quedó en el borde
T0 <- Sys.time(); paso <- function(msg) cat(sprintf("[%5.0f min] %s\n", as.numeric(difftime(Sys.time(), T0, units = "mins")), msg))

# ---- Datos como m27: sin zona de lujo ni OSM, catastro valor_estrato ----
base$vars <- vars_sin(FALSE)
if (!DISTINTO) {
ct <- lee_csv(file.path(P$processed, "catastro.csv")); k <- match(D$property_id, ct$property_id); stopifnot(!anyNA(k))
D$log_v_ref <- ct$log_v_ref[k]; D$estrato_final <- ifelse(ct$estrato_oficial[k] > 0, ct$estrato_oficial[k], D$estrato_final)
TR <- filter(D, muestra == "train"); TE <- filter(D, muestra == "test"); base$vars <- c(base$vars, "log_v_ref")
}
Xt <- readRDS(file.path(P$processed, "base_texto.rds"))
Xt <- Xt[, order(-colSums(Xt != 0))[1:1000]]; colnames(Xt) <- paste0("tf_", colnames(Xt))
mat <- function(df) cbind(Matrix(matriz_arboles(df), sparse = TRUE), Xt[match(df$property_id, rownames(Xt)), ])
o <- arma_objetivos(mat(TR), mat(TE), quita_area = !AREA)$m2

# ---- Comparables (como m32) y grupos de interacción ----
CMP <- prepara_comparables(k_max = 60); CMP$r_tr <- rep(0, nrow(TR))
C_tr <- comparables_train(CMP); C_te <- comparables_test(CMP)
cn <- c(colnames(o$Xtr), colnames(C_tr))
es_loc <- function(cn) cn %in% c("lat", "lon", "lat_rot1", "lat_rot2", "estrato_final", "log_v_ref") | grepl("^(dist|n500)_", cn) |
  grepl("500$", cn) | startsWith(cn, "comp")
es_txt <- function(cn) startsWith(cn, "tf_")
grupos <- function(cn) { i <- seq_along(cn) - 1L; c(as.list(i[!es_loc(cn) & !es_txt(cn)]), list(i[es_loc(cn)], i[es_txt(cn)])) }
paso(sprintf("Columnas: %d (ubicación %d, texto %d)", length(cn), sum(es_loc(cn)), sum(es_txt(cn))))

# Configuración ganadora de m27_mae (star_resumen_catastro.csv), sin volver a buscar
pr <- list(objective = "reg:absoluteerror", max_bin = 64, nthread = 8, seed = 123, interaction_constraints = grupos(cn),
           max_depth = 2, min_child_weight = 3, subsample = .8, colsample_bytree = .7, lambda = 0, alpha = 3, eta = .2)
if (SQ) pr <- modifyList(pr, list(objective = "reg:squarederror", max_depth = 4, lambda = 1, alpha = 0, eta = .05))
if (GENERAL) pr$interaction_constraints <- NULL

# ---- CV por edificio ----
oof_m <- cv_oof(function(a, e) xgb_rondas(pr, cbind(o$Xtr[a, ], comparables_fold(CMP, a, a)), o$y[a],
                                          cbind(o$Xtr[e, ], comparables_fold(CMP, a, e)), RONDAS), FOLDS_EDIF) + o$off_tr
j <- mejor_columna(oof_m); oof <- oof_m[, j]; m <- evalua(oof)
paso(sprintf("CV por edificio: rondas %d%s | MAE %.1f / Chap %.1f / macro %.1f | TWCV %.1f", RONDAS[j], if (j == length(RONDAS)) " (BORDE)" else "",
             m$mae_total / 1e6, m$mae_chapinero / 1e6, m$mae_macro / 1e6, mae_w(oof, pesos_twcv()) / 1e6))

# ---- Ajuste final y registro ----
fit <- xgb.train(params = pr, data = xgb.DMatrix(cbind(o$Xtr, C_tr), label = o$y, nthread = 8), nrounds = RONDAS[j], verbose = 0)
pte <- predict(fit, xgb.DMatrix(cbind(o$Xte, C_te))) + o$off_te
dt <- xgb.model.dt.tree(model = fit); g <- function(f) ifelse(es_txt(f), "texto", ifelse(es_loc(f), "ubicacion", f))
mezcla <- as.data.frame(dt) %>% filter(Feature != "Leaf") %>% group_by(Tree) %>% summarise(n = n_distinct(g(Feature))) %>% filter(n > 1)
if (!GENERAL) stopifnot(nrow(mezcla) == 0) else paso(sprintf("XGB general: %.0f%% de los árboles mezclan grupos", 100 * nrow(mezcla) / n_distinct(dt$Tree)))   # STAR: ninguno
if (!PRUEBA && GENERAL) registra("m50_xgb_general_comparables_area_sq_m2",
  "XGBoost GENERAL (sin restricciones de interacción) con los datos y la configuración de m47: catastro + comparables + log(área), cuadrática, profundidad 4 (08p, VARIANTE=area_sq_general); comparación STAR vs general; OOF de la CV por edificio",
  sprintf("reg:squarederror; depth=4; mcw=3; subsample=0.8; colsample=0.7; lambda=1; alpha=0; eta=0.05; nrounds=%d; sin restricciones", RONDAS[j]), m, oof, pte)
# Componentes por grupo en el test (para comparar con las ramas de la red, ramas_m24_test.csv de 08l; todavía no las
# usa ningún script)
if (!PRUEBA && VAR == "area_sq") {
  cb <- predict(fit, xgb.DMatrix(cbind(o$Xte, C_te)), predcontrib = TRUE)
  cnb <- colnames(cb)
  comp_te <- tibble(
    property_id = TE$property_id,
    est = rowSums(cb[, !es_loc(cnb) & !es_txt(cnb) & cnb != "BIAS"]),
    ubi = rowSums(cb[, es_loc(cnb)]),
    txt = rowSums(cb[, es_txt(cnb)]),
    cte = cb[, "BIAS"],
    offset = o$off_te
  )
  suma <- comp_te$est + comp_te$ubi + comp_te$txt + comp_te$cte + comp_te$offset
  stopifnot(max(abs(suma - pte)) < 1e-4) # la descomposición suma exacto
  write_csv(comp_te, file.path(P$processed, "ramas_m47_test.csv"))
}
if (!PRUEBA && VAR == "area_sq") registra("m47_xgb_star_comparables_area_sq_m2",
  "XGB STAR con catastro + comparables + log(área), configuración cuadrática de m41 (08p, VARIANTE=area_sq); OOF de la CV agrupada por edificio; sobre log(precio por m2)",
  sprintf("reg:squarederror; depth=4; mcw=3; subsample=0.8; colsample=0.7; lambda=1; alpha=0; eta=0.05; nrounds=%d", RONDAS[j]), m, oof, pte)
if (!PRUEBA && VAR == "area") registra("m43_xgb_star_comparables_area_m2_mae",
  "XGB STAR como m38 (catastro + comparables en la ubicación) con log(área) en la estructura (08p, VARIANTE=area); OOF de la CV agrupada por edificio; sobre log(precio por m2)",
  sprintf("reg:absoluteerror; depth=2; mcw=3; subsample=0.8; colsample=0.7; lambda=0; alpha=3; eta=0.2; nrounds=%d", RONDAS[j]), m, oof, pte)
if (!PRUEBA && !DISTINTO && !AREA) registra("m38_xgb_star_comparables_m2_mae",
  "XGB STAR (configuración de m27_mae) con catastro valor_estrato + comparables de m32 en el grupo de ubicación (08p); OOF de la CV agrupada por edificio, NO de la CV por localidad; sobre log(precio por m2)",
  sprintf("reg:absoluteerror; depth=2; mcw=3; subsample=0.8; colsample=0.7; lambda=0; alpha=3; eta=0.2; nrounds=%d", RONDAS[j]), m, oof, pte)
if (!PRUEBA && DISTINTO) registra("m41_xgb_star_comparables_distinto_m2",
  "XGB STAR SIN catastro + comparables de m32 en el grupo de ubicación, profundidad 4, pérdida cuadrática (08p, VARIANTE=distinto): más distinto de m24; OOF de la CV agrupada por edificio; sobre log(precio por m2)",
  sprintf("reg:squarederror; depth=4; mcw=3; subsample=0.8; colsample=0.7; lambda=1; alpha=0; eta=0.05; nrounds=%d", RONDAS[j]), m, oof, pte)
if (DISTINTO || VAR == "area_sq") {   # comparación con m38 en el test: queremos que se aleje más de m24 sin perder precisión
  t38 <- lee_csv(file.path(P$models, "test_predicciones.csv")); t38 <- t38$m38_xgb_star_comparables_m2_mae[match(TE$property_id, t38$property_id)]
  paso(sprintf("Test: correlación log con m38 %.3f | diferencia media con m38 %.0f M", cor(pte, t38), mean(abs(exp(pte) - exp(t38))) / 1e6))
}

# ---- Diversidad frente a m24 y peso de la combinación (en la misma CV por edificio) ----
t24 <- lee_csv(file.path(P$models, "test_predicciones.csv")); t24 <- t24$m24_nn_star_catastro_m2[match(TE$property_id, t24$property_id)]
paso(sprintf("Test: correlación log con m24 %.3f | diferencia media %.0f M | predicción media %.1f M (m24 %.1f)",
             cor(pte, t24), mean(abs(exp(pte) - exp(t24))) / 1e6, mean(recorta(exp(pte))) / 1e6, mean(recorta(exp(t24))) / 1e6))
r <- readRDS(file.path(P$models, "nn_star_comparables.rds")); nn <- r$oof[[which(r$variante == "sin_comparables")]]
for (w in c(1, .8, .7, .6, .5, .4, 0)) { p <- w * nn + (1 - w) * oof; e <- evalua(p)
  paso(sprintf("  CV por edificio, peso red %.1f: MAE %.1f / Chap %.1f / macro %.1f", w, e$mae_total / 1e6, e$mae_chapinero / 1e6, e$mae_macro / 1e6)) }
paso("Listo.")
