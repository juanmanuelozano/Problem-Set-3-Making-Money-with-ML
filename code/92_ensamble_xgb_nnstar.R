# =============================================================================
# 92_ensamble_xgb_nnstar.R - Ensamble: XGBoost con comparables (m22) + NN STAR (m17_nn_star_m2), D21
# Los dos modelos se equivocan distinto (árboles + comparables frente a red con texto), así que el promedio
# suele ganarle a cada uno. Kaggle: m22 = 162,9 M; NN STAR = 158,3 M.
# Promedio ARITMÉTICO del precio: como el valor absoluto es convexo, el MAE del promedio nunca supera el promedio de
# los MAE, así que en el test de Kaggle el peor caso está acotado (p. ej., con 70% NN: <= 0,7×158,3 + 0,3×162,9 =
# 159,7 M). Los pesos NO se estiman con validación (ni con TWCV): las OOF de los dos modelos vienen de CV distintas
# (aleatoria y por localidad) y la aleatoria está inflada en árboles. Con un solo envío disponible se sube 70% NN.
# Entradas (D28): los envíos tal como se calificaron en Kaggle, leídos de commits fijos con desde_git(), para que
# el resultado no cambie si se vuelven a entrenar m22 (06b) o m17 (08c).
# Salidas: submissions/m23_ens_xgbcomp_nnstar_50.csv y m23_ens_xgbcomp_nnstar_70nn.csv
# =============================================================================
source(here::here("code", "01_setup.R"))

ENVIOS_MJ <- "589aff9"    # validacion-sintetica: m22 (y los demás envíos de 93)
ENVIOS_REDES <- "f5786a2" # redes-neuronales: m17 y m18, los calificados en Kaggle

xgb <- lee_csv_git(ENVIOS_MJ, "submissions/m22_xgb_comparables_m2.csv")
nn <- lee_csv_git(ENVIOS_REDES, "submissions/m17_nn_star_m2.csv")
d <- inner_join(xgb, nn, by = "property_id", suffix = c("_xgb", "_nn"))
stopifnot(nrow(d) == nrow(xgb), nrow(d) == nrow(nn), !anyNA(d))
cat(sprintf(
  "Correlación de log(precio) entre los dos modelos: %.3f | diferencia media en log: %.3f | MAD: %.1f M\n",
  cor(log(d$price_xgb), log(d$price_nn)), mean(log(d$price_nn) - log(d$price_xgb)),
  mean(abs(d$price_nn - d$price_xgb)) / 1e6
))

for (w_nn in c(.5, .7)) {
  sub <- tibble(
    property_id = d$property_id,
    price = round(recorta((1 - w_nn) * d$price_xgb + w_nn * d$price_nn))
  )
  f <- file.path(P$subs, sprintf("m23_ens_xgbcomp_nnstar_%s.csv", if (w_nn == .5) "50" else "70nn"))
  write_csv(sub, f)
  cat("Escrito:", f, "\n")
}
