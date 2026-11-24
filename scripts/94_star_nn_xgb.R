# =============================================================================
# 94_star_nn_xgb.R - Combinaciones STAR: NN STAR (m24) + XGB STAR, promedio en log con peso fijo, D26
# Los modelos tienen la misma estructura aditiva por grupos (estructura + ubicación + texto) y los mismos datos de base
# (catastro valor_estrato, sin zona de lujo ni OSM). El promedio en log de modelos aditivos sigue siendo aditivo: cada
# componente (prima de ubicación, efecto del texto, estructura) es el promedio ponderado de los componentes, así que el
# modelo combinado se interpreta igual que un STAR. Aprovecha que una red y unos árboles se equivocan distinto (la razón
# por la que el ensamble del equipo, NN STAR + XGB con comparables, ganó 6 M en Kaggle).
#  m37: m24 + m27_mae (XGB STAR sin comparables), 50/50 fijado de antemano. Validación por localidad: 131,0 / 139,2
#       (m24: 132,0 / 139,2). Kaggle 156,8 (m24 156,3): m27 se equivoca casi igual que la red (correlación 0,983).
#  m39: m24 + m38 (XGB STAR con comparables en la ubicación, 08p), 70/30. En la CV por edificio (08p): 119,2 / 144,2 frente
#       a 122,6 / 146,4 de la red sola (60/40 daba 118,7 / 143,9). Se eligió 70/30 y no 60/40 para dar menos peso al único
#       modelo sin puntaje de Kaggle: cota por convexidad 0,7*156,3 + 0,3*MAE(m38). m38 difiere más de m24 (0,967, 80 M).
#  m40: m24 + m32 + m38, 35/35/30. En la CV por edificio: 118,8 / 142,8 / 142,6 (igual total que m39, mejor Chapinero y
#       macro). Menos riesgo: 70% del peso en dos redes con puntaje de Kaggle (156,3 y 156,5) y 30% en m38 (sin puntaje).
#       Cota por convexidad (promedio de precios): 0,35*156,3 + 0,35*156,5 + 0,3*MAE(m38).
#  m44: m24 + m43 (m38 con log(área) en la estructura), 60/40. m24 y m38 sobrepredecían los inmuebles de más de 200 m2
#       (+7,3% y +6,4% en el OOF) por la elasticidad precio-área fija en 1 (en el train ~0,67); m43 corrige (+2,4%) y mejora
#       la CV por edificio (117,7 / 142,2 vs 123,1 / 150,1). Con la red m24: 70/30 117,2 / 142,4; 50/50 115,5 / 140,4.
#       La red con área (m42) sobrecorrigió (sobrepredice los pequeños, Chapinero +5,4) y no se usa. Peso 60/40: intermedio
#       entre la CV (0,4-0,5) y el óptimo estimado de m39 con un XGB peor (0,69).
#  m46: m24 + m43, 70/30 = m39 con el XGB corregido por área y el mismo peso. La CV sobreestima al XGB frente a la red
#       (m38: 123,1 vs 122,6 en la CV por edificio; ~163 vs 156,3 en Kaggle), así que el peso se toma del óptimo
#       estimado con los puntajes de Kaggle (0,69 para m39) y no de la CV (0,4-0,5).
#  m48: m24 + m47, 60/40. m47 = m43 con la configuración cuadrática de m41 (profundidad 4, eta 0,05): CV por edificio
#       114,8 / 137,9 (m43: 117,7 / 142,2) y más distinto de m24 en el test (88 M frente a 79 M por anuncio).
# PROCESSED=<carpeta> en el entorno: lee base_modelo.rds de otra carpeta (copia de git cuando iCloud no lo descarga).
# =============================================================================
source("scripts/00_config.R")
if (nzchar(Sys.getenv("PROCESSED"))) P$processed <- Sys.getenv("PROCESSED")
source("scripts/utils_modelos.R")

combos <- tribble(~nombre, ~pesos, ~desc,
  "m37_star_nn_xgb_m2",     c(m24_nn_star_catastro_m2 = .5, m27_xgb_star_catastro_m2_mae = .5), "NN STAR m24 y XGB STAR m27_mae (sin comparables)",
  "m39_star_nn_xgbcomp_m2", c(m24_nn_star_catastro_m2 = .7, m38_xgb_star_comparables_m2_mae = .3), "NN STAR m24 y XGB STAR m38 (con comparables; su OOF es de la CV por edificio)",
  "m40_star_2nn_xgbcomp_m2", c(m24_nn_star_catastro_m2 = .35, m32_nn_star_comparables_m2 = .35, m38_xgb_star_comparables_m2_mae = .3),
    "NN STAR m24, NN STAR m32 y XGB STAR m38 (m32 y m38 con comparables; sus OOF son de la CV por edificio)",
  "m44_star_nn_xgbcomp_area_m2", c(m24_nn_star_catastro_m2 = .6, m43_xgb_star_comparables_area_m2_mae = .4),
    "NN STAR m24 y XGB STAR m43 (como m38, con log(área) en la estructura: elasticidad precio-área libre)",
  "m48_star_nn_xgbsq_area_m2", c(m24_nn_star_catastro_m2 = .6, m47_xgb_star_comparables_area_sq_m2 = .4),
    "NN STAR m24 y XGB STAR m47 (catastro + comparables + log(área), pérdida cuadrática, profundidad 4)",
  "m46_star_nn_xgbcomp_area_7030_m2", c(m24_nn_star_catastro_m2 = .7, m43_xgb_star_comparables_area_m2_mae = .3),
    "NN STAR m24 y XGB STAR m43, 70/30: m39 con un solo cambio (XGB corregido por área) y el mismo peso, el óptimo estimado con Kaggle para m39")
if (nzchar(Sys.getenv("SOLO"))) combos <- filter(combos, nombre == Sys.getenv("SOLO"))
o <- lee_csv(file.path(P$models, "oof_predicciones.csv")); t <- lee_csv(file.path(P$models, "test_predicciones.csv"))
po <- \(m) o[[m]][match(TR$property_id, o$property_id)]; pt <- \(m) t[[m]][match(TE$property_id, t$property_id)]
for (k in seq_len(nrow(combos))) {
  cb <- combos[k, ]
  w <- cb$pesos[[1]]; stopifnot(abs(sum(w) - 1) < 1e-9)
  oof <- Reduce(`+`, map2(names(w), w, \(m, a) a * po(m))); pte <- Reduce(`+`, map2(names(w), w, \(m, a) a * pt(m)))
  stopifnot(!anyNA(oof), !anyNA(pte))
  registra(cb$nombre, paste0("Combinación STAR: promedio en log de ", cb$desc, "; sigue siendo aditivo por grupos (94)"),
           paste(sprintf("%s=%.2f", names(w), w), collapse = "; "), evalua(oof), oof, pte)
  cat(sprintf("%s: predicción media del test %.1f M\n", cb$nombre, mean(recorta(exp(pte))) / 1e6))
}
