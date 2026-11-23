# =============================================================================
# utils_modelos.R - Funciones comunes para entrenar, evaluar y registrar modelos
# Uso: source("scripts/00_config.R"); source("scripts/utils_modelos.R")
# =============================================================================
base <- readRDS(file.path(P$processed, "base_modelo.rds"))
D  <- base$datos
TR <- D %>% filter(muestra == "train")
TE <- D %>% filter(muestra == "test")
Y  <- log(TR$price)
GRUPO <- TR$grupo   # localidad usada como fold de validación
ES_CHAP <- TR$localidad %in% "Chapinero"

# ---- Validación: dejar una localidad afuera, con buffer (D9) ----
# Equivale a spatialsample::spatial_leave_location_out_cv(group = localidad, buffer = b): cada localidad es un
# fold de evaluación, y del conjunto de análisis se quitan los anuncios a menos de b metros de algún anuncio evaluado.
BUFFER_M <- 500
folds_localidad <- function(buffer = BUFFER_M) {
  map(set_names(colnames(base$dist_loc)), function(g)
    list(analisis = which(GRUPO != g & base$dist_loc[, g] >= buffer), evaluacion = which(GRUPO == g)))
}
FOLDS <- folds_localidad()

# ---- "Chapinero sintético": pesos que acercan el train al test (D18, Brenning y Suesse 2026) ----
# Solo usan las VARIABLES del test, nunca su precio. Sirven para evaluar (mae_twcv, mae_iwcv en evalua()) y
# para entrenar con pesos (D19). Variables de balanceo: estrato, apartamento, habitaciones, área y distancia al CBD.
encoge <- function(w, lambda = 0.2) { w1 <- (1 - lambda) * length(w) * w + lambda; w1 / sum(w1) }  # hacia pesos iguales
ess <- function(w) sum(w)^2 / sum(w^2)                                                         # tamaño efectivo
vars_balanceo <- function() {
  corta <- function(x_tr, x_te) {   # quintiles del test
    br <- unique(quantile(x_te, 0:5 / 5, na.rm = TRUE)); br[1] <- -Inf; br[length(br)] <- Inf
    list(tr = cut(x_tr, br), te = cut(x_te, br))
  }
  fija <- function(x_tr, x_te, f) list(tr = f(x_tr), te = f(x_te))
  list(estrato  = fija(TR$estrato_final, TE$estrato_final, \(x) factor(pmin(pmax(round(x), 1), 6), 1:6)),
       apto     = fija(TR$es_apto, TE$es_apto, \(x) factor(x, 0:1)),
       habit    = fija(TR$bedrooms, TE$bedrooms, \(x) cut(x, c(-Inf, 1, 2, 3, Inf))),
       area     = corta(TR$log_area, TE$log_area),
       dist_cbd = corta(TR$dist_cbd, TE$dist_cbd))
}
# TWCV: raking (ajuste proporcional iterativo) hasta igualar las proporciones de cada variable a las del test
pesos_twcv <- function(vars = vars_balanceo(), maxit = 500, tol = 1e-10) {
  w <- rep(1 / length(TR$price), length(TR$price))
  objetivo <- map(vars, ~ prop.table(table(.x$te)))
  for (it in seq_len(maxit)) {
    for (nm in names(vars)) {
      f <- vars[[nm]]$tr; s <- tapply(w, f, sum); s[is.na(s)] <- 0
      w <- w * as.vector(objetivo[[nm]][f] / s[f])
    }
    dif <- max(map_dbl(names(vars), \(nm) max(abs(tapply(w, vars[[nm]]$tr, sum) - objetivo[[nm]]), na.rm = TRUE)))
    if (dif < tol) break
  }
  w / sum(w)
}
# IWCV: p/(1 - p) de un logit que distingue test de train, con las mismas variables en continuo
pesos_iwcv <- function() {
  pool <- bind_rows(TR %>% mutate(es_test = 0), TE %>% mutate(es_test = 1))
  m <- glm(es_test ~ estrato_final + I(estrato_final^2) + log_area + I(log_area^2) + es_apto + bedrooms +
             log(dist_cbd) + I(log(dist_cbd)^2), data = pool, family = binomial)
  p <- predict(m, TR, type = "response"); (p / (1 - p)) / sum(p / (1 - p))
}
W_TWCV <- encoge(pesos_twcv())   # para evaluar (encogidos 20%, como en el artículo)
W_IWCV <- encoge(pesos_iwcv())

# ---- Comparables: precio por m2 de los vecinos del train, un "control sintético" por anuncio (D20) ----
# Uso: el script carga RANN (pacman::p_load(RANN)) y llama a prepara_comparables(); dentro de cada fold,
# comparables(CMP$V_tr, filas, en_ref, propio, CMP$cl_tr[filas], CMP) con en_ref = conjunto de análisis.
FOLDS_ALEAT <- local({   # CV aleatoria de 10 folds: se parece al test en la distancia a los vecinos (D20)
  set.seed(123); g <- sample(rep(1:10, length.out = nrow(TR)))
  map(1:10, ~ list(analisis = which(g != .x), evaluacion = which(g == .x)))
})
prepara_comparables <- function(k_max = 60, ks = c(5, 20), d0 = 30, usa_duplicados = FALSE) {
  m_lon <- 111320 * cos(4.65 * pi / 180); m_lat <- 110574
  xy <- function(df) cbind(df$lon * m_lon, df$lat * m_lat)     # coordenadas planas en metros
  # Claves de descripción: el mismo inmueble publicado dos veces no puede ser su propio comparable
  raw <- bind_rows(lee_csv(file.path(P$raw, "train.csv")), lee_csv(file.path(P$raw, "test.csv"))) %>%
    transmute(property_id, clave = str_squish(str_to_lower(coalesce(description, ""))))
  clave <- raw$clave[match(c(TR$property_id, TE$property_id), raw$property_id)]
  clave[clave == "" | usa_duplicados] <- NA
  # Vecinos candidatos: los k_max anuncios del train más cercanos y del mismo tipo (apartamento/casa)
  vecinos <- function(q, q_apto) {
    idx <- matrix(NA_integer_, nrow(q), k_max); d <- matrix(NA_real_, nrow(q), k_max)
    for (t in 0:1) {
      pool <- which(TR$es_apto == t); qi <- which(q_apto == t)
      if (!length(qi)) next
      nn <- RANN::nn2(xy(TR)[pool, ], q[qi, , drop = FALSE], k = min(k_max, length(pool)))
      idx[qi, seq_len(ncol(nn$nn.idx))] <- pool[nn$nn.idx]; d[qi, seq_len(ncol(nn$nn.idx))] <- nn$nn.dists
    }
    list(idx = idx, d = d)
  }
  list(V_tr = vecinos(xy(TR), TR$es_apto), V_te = vecinos(xy(TE), TE$es_apto),
       cl_tr = clave[seq_len(nrow(TR))], cl_te = clave[nrow(TR) + seq_len(nrow(TE))],
       ym2 = Y - TR$log_area, ks = ks, d0 = d0)
}
# Variables de comparables para unas filas, con referencia solo en el train marcado en en_ref (lógico).
# propio: índice en el train de cada fila (para excluirse a sí misma); NULL para el test.
comparables <- function(V, filas, en_ref, propio, cl_q, cmp) {
  idx <- V$idx[filas, , drop = FALSE]; d <- V$d[filas, , drop = FALSE]; K <- ncol(idx)
  idx1 <- replace(idx, is.na(idx), 1L)
  ok <- !is.na(idx) & en_ref[idx1]
  if (!is.null(propio)) ok <- ok & idx != rep(propio, K)
  dup <- cmp$cl_tr[idx1] == rep(cl_q, K); ok <- ok & !(!is.na(dup) & dup)
  ok[is.na(ok)] <- FALSE
  rango <- t(apply(ok, 1, cumsum))                          # posición del vecino entre los válidos
  yv <- matrix(cmp$ym2[idx1], nrow(idx)); d[is.na(d)] <- 0
  out <- list(); ref_media <- mean(cmp$ym2[en_ref])
  for (k in cmp$ks) {
    sel <- ok & rango <= k; w <- sel / (d + cmp$d0); s <- rowSums(w)
    m <- rowSums(w * yv) / s; m[s == 0] <- ref_media           # sin comparables válidos: media de referencia
    dist_k <- rowSums(sel * d) / pmax(rowSums(sel), 1); dist_k[s == 0] <- 5000
    out[[paste0("comp", k)]] <- m; out[[paste0("comp_logdist", k)]] <- log1p(dist_k)
  }
  do.call(cbind, out)
}
# Atajos: variables de comparables del train completo (cada uno sin sí mismo), del test, y de un fold
comparables_train <- function(cmp) comparables(cmp$V_tr, seq_len(nrow(TR)), rep(TRUE, nrow(TR)), seq_len(nrow(TR)), cmp$cl_tr, cmp)
comparables_test  <- function(cmp) comparables(cmp$V_te, seq_len(nrow(TE)), rep(TRUE, nrow(TR)), NULL, cmp$cl_te, cmp)
comparables_fold  <- function(cmp, a, filas) { en <- logical(nrow(TR)); en[a] <- TRUE
  comparables(cmp$V_tr, filas, en, filas, cmp$cl_tr[filas], cmp) }

# Validación cruzada genérica, para cualquier modelo. ajusta_predice(analisis, evaluacion) recibe índices de filas
# del train, ajusta con `analisis` y devuelve predicciones (en log) para `evaluacion`: un vector o una matriz con
# una columna por hiperparámetro (todo el camino de lambda, varias rondas de boosting...). Devuelve las OOF.
cv_oof <- function(ajusta_predice, folds = FOLDS) {
  pred <- NULL
  for (f in folds) {
    q <- as.matrix(ajusta_predice(f$analisis, f$evaluacion))
    if (is.null(pred)) pred <- matrix(NA_real_, length(Y), ncol(q), dimnames = list(NULL, colnames(q)))
    pred[f$evaluacion, ] <- q
  }
  if (ncol(pred) == 1) pred[, 1] else pred
}
# Coeficientes OLS (con intercepto) ajustados en las filas `a` de X; los coeficientes no identificados quedan en 0
ols_coef <- function(X, a, y = Y) { b <- lm.fit(cbind(1, X[a, , drop = FALSE]), y[a])$coefficients; b[is.na(b)] <- 0; b }

# Columna de una matriz de predicciones OOF con menor MAE total (elige lambda, rondas, etc.)
mejor_columna <- function(pred) which.min(apply(pred, 2, function(p) evalua(p)$mae_total))

# XGBoost: ajusta max(rondas) rondas y predice con las primeras r rondas para cada r -> matriz (columna = r).
# Reemplaza el early stopping de xgb.cv, que no admite buffer; las rondas se eligen con mejor_columna().
xgb_rondas <- function(pr, Xa, ya, Xe, rondas, ma = NULL, me = NULL) {
  fit <- xgb.train(params = pr, data = xgb.DMatrix(Xa, label = ya, base_margin = ma, nthread = pr$nthread),
                   nrounds = max(rondas), verbose = 0)
  de <- xgb.DMatrix(Xe, base_margin = me, nthread = pr$nthread)
  `colnames<-`(sapply(rondas, function(r) predict(fit, de, iterationrange = c(1, r))), rondas)
}

# Matriz para árboles: NA -> -1 más indicador de faltante
matriz_arboles <- function(df, vars = base$vars) {
  na <- sapply(c("piso_txt", "antig_txt", "parq_txt"), \(v) as.integer(is.na(df[[v]])))
  X <- cbind(as.matrix(df[vars]), `colnames<-`(na, paste0("na_", colnames(na))))
  X[is.na(X)] <- -1
  X
}

# Matriz lineal: imputación por mediana del train + indicadores y términos cuadráticos.
# Sin dummies de localidad (D10): con la validación por localidad no se pueden estimar para la localidad evaluada.
matriz_lineal <- function(df, ref = TR, vars = base$vars) {
  X <- df[vars]
  for (v in c("piso_txt", "antig_txt", "parq_txt")) {
    X[[paste0("na_", v)]] <- as.integer(is.na(X[[v]]))
    X[[v]][is.na(X[[v]])] <- median(ref[[v]], na.rm = TRUE)
  }
  for (v in c("log_area", "bedrooms", "banos_final", "estrato_final", "dist_cbd", "dist_transmilenio", "lat", "lon"))
    X[[paste0(v, "_2")]] <- X[[v]]^2
  X$log_area_x_apto <- X$log_area * X$es_apto
  X$log_area_x_estrato <- X$log_area * X$estrato_final
  X$dist_cbd_x_apto <- X$dist_cbd * X$es_apto
  as.matrix(X)
}

# Habitaciones × distancia (km) a cada CBD; se pegan a matriz_lineal() en las regresiones (04, 04b)
interacciones <- function(df) {
  h <- c("centro_internacional", "calle72", "parque93")
  `colnames<-`(sapply(h, \(x) df$bedrooms * df[[paste0("dist_", x)]] / 1000), paste0("bedrooms_x_dist_", h))
}

# Dos objetivos: log(precio) y log(precio por m2). En el de m2 se quitan las columnas de área (salvo quita_area = FALSE)
# y el precio se recupera sumando log(área): off_tr / off_te se suman a la predicción (04, 04b, 05b, 07).
arma_objetivos <- function(Xtr, Xte, quita_area = TRUE) {
  k <- !(quita_area & grepl("log_area", colnames(Xtr)))
  list(precio = list(Xtr = Xtr, Xte = Xte, y = Y, off_tr = 0, off_te = 0),
       m2     = list(Xtr = Xtr[, k], Xte = Xte[, k], y = Y - TR$log_area, off_tr = TR$log_area, off_te = TE$log_area))
}

# Métricas sobre predicciones out-of-fold (en log) -> MAE en pesos con recorte al soporte
evalua <- function(pred_log, y_log = Y) {
  p <- recorta(exp(pred_log)); y <- exp(y_log)
  tibble(mae_total = mae(y, p), mae_chapinero = mae(y[ES_CHAP], p[ES_CHAP]),
         mae_macro = mean(tapply(abs(y - p), GRUPO, mean)),   # promedio simple entre localidades
         mape_chapinero = mean(abs(y[ES_CHAP] - p[ES_CHAP]) / y[ES_CHAP]),
         mae_twcv = sum(W_TWCV * abs(y - p)), mae_iwcv = sum(W_IWCV * abs(y - p)))   # Chapinero sintético (D18)
}

# Registro acumulado de modelos (un renglón por modelo y versión)
registra <- function(nombre, descripcion, params, metr, pred_oof_log, pred_test_log) {
  reg_f <- file.path(P$models, "registro_modelos.csv")
  metr <- select(metr, any_of(c("mae_total", "mae_chapinero", "mae_macro", "mape_chapinero", "mae_twcv", "mae_iwcv")))
  fila <- tibble(fecha = as.character(Sys.Date()), modelo = nombre, descripcion = descripcion, params = params) %>% bind_cols(metr)
  reg <- if (file.exists(reg_f)) read_csv(reg_f, col_types = cols(.default = "c"), num_threads = 1) %>%
    mutate(across(starts_with("ma"), as.numeric)) %>% filter(modelo != nombre) else NULL
  write_csv(bind_rows(reg, fila), reg_f)
  # predicciones out-of-fold (para ensamblar) y envío a Kaggle
  oof_f <- file.path(P$models, "oof_predicciones.csv")
  oof <- if (file.exists(oof_f)) lee_csv(oof_f) else tibble(property_id = TR$property_id, log_price = Y, grupo = GRUPO, chapinero = ES_CHAP)
  oof[[nombre]] <- pred_oof_log; write_csv(oof, oof_f)
  tst_f <- file.path(P$models, "test_predicciones.csv")
  tst <- if (file.exists(tst_f)) lee_csv(tst_f) else tibble(property_id = TE$property_id)
  tst[[nombre]] <- pred_test_log; write_csv(tst, tst_f)
  sub <- tibble(property_id = TE$property_id, price = round(recorta(exp(pred_test_log))))
  stopifnot(nrow(sub) == nrow(TE), !anyDuplicated(sub$property_id), !anyNA(sub$price))   # formato de Kaggle
  write_csv(sub, file.path(P$subs, paste0(nombre, ".csv")))
  cat(sprintf("[%s] MAE OOF total: %s | Chapinero: %s | macro localidades: %s\n", nombre,
              comma(metr$mae_total / 1e6, .1), comma(metr$mae_chapinero / 1e6, .1), comma(metr$mae_macro / 1e6, .1)))
}
