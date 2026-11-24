# =============================================================================
# 08o_nn_star_datos_nuevos.R - m24 con una sola fuente de información nueva por variante, D17
# Lo único que ha mejorado la red en Kaggle es información nueva (catastro: 158,3 -> 156,3); los cambios de forma
# (dropout, tanh, pesos, tasa) no. Cada variante agrega una fuente y deja todo lo demás como m24 (catastro valor_estrato,
# sin zona de lujo ni OSM, lr 1e-3, p_u 0,1, p_t 0,5, MSE, calibración simple, 1 semilla):
#   m34_nn_star_construccion_m2  + edificio (pisos, sótanos, semisótano, altura, huella; estructura) y pisos de la
#                                manzana (ubicación), del catastro (03h, D24). CV por localidad, épocas por TWCV, como m24.
#   m35_nn_star_embeddings_m2    + embeddings del texto (multilingual-e5-small, 384 dim., sin lugares; 03g, D25) en la
#                                rama de texto. CV por localidad, épocas por TWCV, como m24.
#   m36_nn_star_vecinos_m2       + comparables "limpios" en una 4.a rama aditiva (vecinos): de cualquier tipo (no mezclan
#                                es_apto), ponderados por similitud del texto (embeddings) y sin los casi idénticos
#                                (similitud > 0,95: re-publicaciones del mismo inmueble), sin radio como m32. La rama de
#                                ubicación queda pura. CV agrupada por edificio (FOLDS_EDIF), épocas por MAE total, como m32.
# El juez es Kaggle (gana si mejora a m24, 156,3, en más de ~1,5 M). SOLO=<nombre> corre solo esa variante.
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R"); source("scripts/utils_redes.R")
source("scripts/utils_comparables.R")

W <- pesos_twcv(); y <- exp(Y)
oofs <- lee_csv(file.path(P$models, "oof_predicciones.csv")); ref <- oofs$m24_nn_star_catastro_m2[match(TR$property_id, oofs$property_id)]
err <- \(p) abs(y - recorta(exp(p)))
variantes <- tribble(~nombre, ~construccion, ~emb, ~vecinos, ~area, ~desc,
  "m34_nn_star_construccion_m2", TRUE,  FALSE, FALSE, FALSE, "+ edificio y pisos de la manzana del catastro (03h)",
  "m35_nn_star_embeddings_m2",   FALSE, TRUE,  FALSE, FALSE, "+ embeddings del texto (03g) en la rama de texto",
  "m36_nn_star_vecinos_m2",      FALSE, FALSE, TRUE,  FALSE, "+ rama de vecinos: comparables de cualquier tipo ponderados por similitud del texto, sin casi idénticos (OOF de la CV por edificio)",
  # m24 sobrepredice los inmuebles grandes (>200 m2: +7,3% en el OOF) y subpredice los pequeños: sin log_area en la rama
  # lineal, la elasticidad precio-área queda fija en 1 (en el train es ~0,67). Con area=TRUE su coeficiente es elasticidad - 1.
  "m42_nn_star_area_m2",         FALSE, FALSE, FALSE, TRUE,  "+ log(área) en la rama lineal de estructura (elasticidad precio-área libre)",
  # m42 sobrecorrigió (3 épocas no alcanzan para estimar el coeficiente). Alternativa: fijar la elasticidad en el objetivo,
  # log(precio / área^e), con e de una regresión hedónica en el train (log precio ~ log área + baños + habitaciones +
  # estrato + lat + lon + tipo). Con e = 1 es el objetivo de siempre (m24).
  "m45_nn_star_elasticidad_m2",  FALSE, FALSE, FALSE, NA,    "con objetivo log(precio / área^e), e = elasticidad precio-área hedónica del train")
if (nzchar(Sys.getenv("SOLO"))) variantes <- filter(variantes, nombre == Sys.getenv("SOLO"))

for (k in seq_len(nrow(variantes))) {
  v <- variantes[k, ]
  ELAST <- is.na(v$area); if (ELAST) v$area <- FALSE
  usa_bloques(area_m2 = v$area, osm = FALSE, catastro = "valor_estrato", construccion = v$construccion, emb = v$emb)
  if (ELAST) {   # objetivo log(precio) - e log(área); el área sigue fuera de las entradas (como m24)
    e <- unname(coef(lm(Y ~ log_area + banos_final + bedrooms + estrato_final + lat + lon + es_apto, data = TR))["log_area"])
    YR$m2 <- Y - e * TR$log_area; OFF$m2 <- list(tr = e * TR$log_area, te = e * TE$log_area)
    paso(sprintf("Elasticidad precio-área hedónica del train: %.3f", e))
  }
  construye <- function(g, d) red_star(d, .1, .5)
  if (v$vecinos) {
    if (is.null(EMB)) EMB <- lee_emb()
    E <- EMB[c(TR$property_id, TE$property_id), ]; E <- E / sqrt(rowSums(E^2))   # cosenos sobre vectores normalizados
    CMP <- prepara_comparables(k_max = 60, por_tipo = FALSE, emb = E); CMP$r_tr <- rep(0, nrow(TR))
    s1 <- CMP$V_te$S[, 1]; paso(sprintf("Similitud con el vecino más cercano (test): mediana %.2f | > 0,95: %.1f%%", median(s1, na.rm = TRUE), 100 * mean(s1 > .95, na.rm = TRUE)))
    r <- cv_red(\(d) construye(NULL, d), "m2", EPOCAS, 1e-3, "mse", folds = FOLDS_EDIF, bloque_extra = "vec",
                extra = function(a, e) list(a = comparables_fold(CMP, a, a), e = comparables_fold(CMP, a, e)))
    BR$m2$vec <- comparables_train(CMP); BTE$m2$vec <- comparables_test(CMP)
  } else r <- cv_red(\(d) construye(NULL, d), "m2", EPOCAS, 1e-3, "mse", w = W)
  f <- ajusta_final(tibble(objetivo = "m2", epocas = r$epocas), construye, 1e-3, "mse")
  m <- evalua(r$oof); d <- err(r$oof) - err(ref); dw <- sum(W * d); se <- sqrt(sum(W^2 * (d - dw)^2))
  paso(sprintf("%s | entradas %s | ép %d%s | MAE %.1f / Chap %.1f / macro %.1f / TWCV %.1f | test %.1f | vs m24: TWCV %+.1f (EE %.1f), Chap %+.1f%s",
               v$nombre, paste(dims(BR$m2), collapse = "/"), r$epocas, if (r$borde) " (BORDE)" else "", m$mae_total / 1e6,
               m$mae_chapinero / 1e6, m$mae_macro / 1e6, mae_w(r$oof, W) / 1e6, mean(recorta(exp(f$pred_te))) / 1e6, dw / 1e6, se / 1e6,
               mean(d[ES_CHAP]) / 1e6, if (v$vecinos) " (OOF de otra CV: no comparable)" else ""))
  if (!PRUEBA) registra(v$nombre,
    paste0("NN STAR como m24 (catastro valor_estrato, sin zona de lujo ni OSM) ", v$desc, " (08o); sobre log(precio por m2)"),
    sprintf("lr=1e-3; p_u=0.1; p_t=0.5; pérdida=mse; calibración=simple; semillas=1; épocas=%d; batch=%d; l2=%g; cv=%s",
            r$epocas, BATCH, L2, if (v$vecinos) "edificio" else "localidad"),
    m, r$oof, f$pred_te)
}
paso("Listo.")
