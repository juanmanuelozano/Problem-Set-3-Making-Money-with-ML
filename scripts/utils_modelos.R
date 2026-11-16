# =============================================================================
# utils_modelos.R - Funciones comunes para entrenar, evaluar y registrar modelos
# Uso: source("scripts/00_config.R"); source("scripts/utils_modelos.R")
# =============================================================================
base <- readRDS(file.path(P$processed, "base_modelo.rds"))
D  <- base$datos
TR <- D %>% filter(muestra == "train")
TE <- D %>% filter(muestra == "test")
Y  <- log(TR$price)
FOLD <- TR$fold
ES_CHAP <- TR$localidad %in% "Chapinero"

# Matriz para árboles: NA -> -1 más indicador de faltante
matriz_arboles <- function(df, vars = base$vars) {
  X <- as.matrix(df[vars])
  for (v in c("piso_txt", "antig_txt", "parq_txt")) {
    X <- cbind(X, setNames(as.integer(is.na(df[[v]])), paste0("na_", v)) |> as.matrix() |> `colnames<-`(paste0("na_", v)))
  }
  X[is.na(X)] <- -1
  X
}

# Matriz lineal: imputación por mediana del train + indicadores, términos cuadráticos y dummies de localidad
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
  locs <- c("Chapinero", "Usaquén", "Suba", "Teusaquillo", "Barrios Unidos", "Santa Fé", "Fontibón", "Engativá", "Kennedy")
  for (l in locs) X[[paste0("loc_", make.names(l))]] <- as.integer(df$localidad %in% l)
  as.matrix(X)
}

# Métricas sobre predicciones out-of-fold (en log) -> MAE en pesos con recorte al soporte
evalua <- function(pred_log, y_log = Y) {
  p <- recorta(exp(pred_log)); y <- exp(y_log)
  tibble(mae_total = mae(y, p), mae_chapinero = mae(y[ES_CHAP], p[ES_CHAP]),
         mae_fold2 = mae(y[FOLD == 2], p[FOLD == 2]),
         mape_chapinero = mean(abs(y[ES_CHAP] - p[ES_CHAP]) / y[ES_CHAP]))
}

# Registro acumulado de modelos (un renglón por modelo y versión)
registra <- function(nombre, descripcion, params, metr, pred_oof_log, pred_test_log) {
  reg_f <- file.path(P$models, "registro_modelos.csv")
  metr <- select(metr, any_of(c("mae_total", "mae_chapinero", "mae_fold2", "mape_chapinero")))
  fila <- tibble(fecha = as.character(Sys.Date()), modelo = nombre, descripcion = descripcion, params = params) %>% bind_cols(metr)
  reg <- if (file.exists(reg_f)) read_csv(reg_f, col_types = cols(.default = "c"), num_threads = 1) %>%
    mutate(across(starts_with("ma"), as.numeric)) %>% filter(modelo != nombre) else NULL
  write_csv(bind_rows(reg, fila), reg_f)
  # predicciones out-of-fold (para ensamblar) y envío a Kaggle
  oof_f <- file.path(P$models, "oof_predicciones.csv")
  oof <- if (file.exists(oof_f)) lee_csv(oof_f) else tibble(property_id = TR$property_id, log_price = Y, fold = FOLD, chapinero = ES_CHAP)
  oof[[nombre]] <- pred_oof_log; write_csv(oof, oof_f)
  tst_f <- file.path(P$models, "test_predicciones.csv")
  tst <- if (file.exists(tst_f)) lee_csv(tst_f) else tibble(property_id = TE$property_id)
  tst[[nombre]] <- pred_test_log; write_csv(tst, tst_f)
  sub <- tibble(property_id = TE$property_id, price = round(recorta(exp(pred_test_log))))
  write_csv(sub, file.path(P$subs, paste0(nombre, ".csv")))
  cat(sprintf("[%s] MAE OOF total: %s | Chapinero: %s | fold 2: %s\n", nombre,
              comma(metr$mae_total / 1e6, .1), comma(metr$mae_chapinero / 1e6, .1), comma(metr$mae_fold2 / 1e6, .1)))
}
