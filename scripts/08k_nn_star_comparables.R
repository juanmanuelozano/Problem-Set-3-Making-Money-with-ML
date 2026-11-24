# =============================================================================
# 08k_nn_star_comparables.R - NN STAR (configuración de m24) con comparables en la rama de ubicación, D23
# Comparables (utils_comparables.R): log(precio/m2) de los 5 y 20 vecinos del train del mismo tipo, ponderados por
# 1/(distancia + 30 m), y la distancia media a ellos. Validación: CV de 5 folds agrupada por edificio (FOLDS_EDIF),
# con los comparables recalculados en cada fold solo con el conjunto de análisis. Las épocas se eligen por MAE total
# en esa CV; lr, dropout, pérdida y calibración quedan como m24 (afinar por TWCV empeoró Kaggle 3 veces).
# Variantes, todas en la misma CV:
#   sin_comparables  m24 tal cual (referencia en esta CV)
#   comp_radio       comparables con el radio mínimo emparejado con el test (la propuesta)
#   comp_sin_radio   comparables sin radio (como en la rama de María José): para ver si el radio importa
# Control externo: MAE en los 85 anuncios del test que son re-publicaciones de un anuncio del train (misma
# descripción, a <100 m, área ±5%, mismo tipo); el 83% de las re-publicaciones del train repite el precio exacto.
# No registra modelos ni escribe envíos. Salidas: tables/nn_star_comparables.csv; models/nn_star_comparables.rds
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R"); source("scripts/utils_redes.R")
source("scripts/utils_comparables.R")

W <- pesos_twcv(); y <- exp(Y)
usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = "valor_estrato")
CMP <- prepara_comparables(); CMP0 <- modifyList(CMP, list(r_tr = rep(0, nrow(TR))))
d5 <- \(C) round(median(expm1(C[, "comp_logdist5"])))
f1 <- FOLDS_EDIF[[1]]
paso(sprintf("Distancia media a los 5 comparables (mediana): test %d m | train con radio %d m | train sin radio %d m | evaluación de un fold con radio %d m",
             d5(comparables_test(CMP)), d5(comparables_train(CMP)), d5(comparables_train(CMP0)), d5(comparables_fold(CMP, f1$analisis, f1$evaluacion))))

# Re-publicaciones del test: precio del mismo inmueble en el train
dup <- local({
  cl <- \(cmp_cl, ids) tibble(property_id = ids, clave = cmp_cl)
  a <- cl(CMP$cl_te, TE$property_id) %>% mutate(i = row_number()) %>% filter(nchar(clave) >= 50)
  b <- cl(CMP$cl_tr, TR$property_id) %>% mutate(j = row_number()) %>% filter(nchar(clave) >= 50)
  inner_join(a, b, by = "clave", relationship = "many-to-many") %>%
    mutate(dist = sqrt(((TE$lat[i] - TR$lat[j]) * 110574)^2 + ((TE$lon[i] - TR$lon[j]) * 110985)^2)) %>%
    filter(dist < 100, abs(TE$log_area[i] - TR$log_area[j]) < .05, TE$es_apto[i] == TR$es_apto[j]) %>%
    group_by(i) %>% summarise(precio = median(y[j]), .groups = "drop")
})
paso(sprintf("Re-publicaciones en el test: %d", nrow(dup)))

construye <- function(g, d) red_star(d, .1, .5)
extra_de <- \(cmp) function(a, e) list(a = comparables_fold(cmp, a, a), e = comparables_fold(cmp, a, e))
res <- list()
corre <- function(nombre, cmp = NULL) {
  r <- cv_red(\(d) construye(NULL, d), "m2", EPOCAS, 1e-3, "mse", folds = FOLDS_EDIF, extra = if (is.null(cmp)) NULL else extra_de(cmp))
  BR0 <- BR; BTE0 <- BTE
  if (!is.null(cmp)) { BR$m2$ubi <<- cbind(BR$m2$ubi, comparables_train(cmp)); BTE$m2$ubi <<- cbind(BTE$m2$ubi, comparables_test(cmp)) }
  f <- ajusta_final(tibble(objetivo = "m2", epocas = r$epocas), construye, 1e-3, "mse")
  BR <<- BR0; BTE <<- BTE0
  pt <- recorta(exp(f$pred_te))
  fila <- tibble(variante = nombre, epocas = r$epocas, borde = r$borde) %>% bind_cols(evalua(r$oof)) %>%
    mutate(mae_twcv = mae_w(r$oof, W), sesgo_chap = mean(recorta(exp(r$oof[ES_CHAP])) - y[ES_CHAP]), pred_test = mean(pt),
           mae_dup = mean(abs(pt[dup$i] - dup$precio)), sesgo_dup = mean(pt[dup$i] - dup$precio), oof = list(r$oof), pred_te = list(f$pred_te))
  res[[nombre]] <<- fila
  write_csv(select(bind_rows(res), -oof, -pred_te), file.path(P$rep_mod, "tables", "nn_star_comparables.csv"))
  saveRDS(bind_rows(res), file.path(P$models, "nn_star_comparables.rds"))
  paso(sprintf("%-15s ép %d%s | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f | sesgo Chap %.1f | test %.1f | re-publicaciones: MAE %.1f, sesgo %.1f",
               nombre, r$epocas, if (r$borde) " (BORDE)" else "", fila$mae_total / 1e6, fila$mae_chapinero / 1e6, fila$mae_macro / 1e6,
               fila$mae_twcv / 1e6, fila$sesgo_chap / 1e6, fila$pred_test / 1e6, fila$mae_dup / 1e6, fila$sesgo_dup / 1e6))
}
corre("sin_comparables")
corre("comp_radio", CMP)
corre("comp_sin_radio", CMP0)
print(as.data.frame(select(bind_rows(res), variante, epocas, borde, mae_total, mae_chapinero, mae_macro, mae_twcv, sesgo_chap, pred_test, mae_dup, sesgo_dup) %>%
  mutate(across(c(starts_with("mae"), starts_with("sesgo"), pred_test), ~ round(.x / 1e6, 1)))))
paso("Listo.")
