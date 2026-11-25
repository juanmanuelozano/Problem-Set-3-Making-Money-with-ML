# =============================================================================
# 96_texto_modelos.R - ¿Dos modelos leen el mismo texto de forma distinta?
# (moraleja 1, presentación)
# Compara la componente de texto de la NN STAR (salida de la rama de texto,
# configuración de m24) con la del XGB STAR (encoder de texto,
# data/processed/star_encoders.csv, Algoritmo 1 de Mayer et al.). Las dos están
# en log(precio): un valor de 0,05 significa que el texto sube la predicción
# ~5%. No registra modelos.
# Salidas (output/tables/03_presentacion/): texto_terminos.csv (términos que
# más mueven cada componente), texto_componentes.csv y texto_comparacion.csv
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))
source(here::here("code", "utils_redes.R"))

# ---- Componentes de texto de los dos modelos ----
usa_bloques(area_m2 = FALSE, osm = FALSE, catastro = "valor_estrato")
f <- ajusta_final( # configuración de m24
  tibble(objetivo = "m2", epocas = 3), \(g, d) red_star(d, .1, .5), 1e-3, "mse"
)
rama <- \(x) drop(predict(f$red$ramas, x, batch_size = 8192, verbose = 0)[[3]])
ids <- c(TR$property_id, TE$property_id)
nn <- c(rama(f$xtr), rama(f$xte))
ef <- lee_csv(file.path(P$processed, "star_encoders.csv"))
xg <- ef$enc_texto[match(ids, ef$property_id)]
tr <- seq_len(nrow(TR))
nn <- nn - mean(nn[tr]) # centradas con el train
xg <- xg - mean(xg[tr])

cat(sprintf(
  "Desv. est. de la componente de texto (log precio): NN STAR %.3f | XGB STAR %.3f\n",
  sd(nn), sd(xg)
))
cat(sprintf(
  "Correlación entre las dos: todo %.2f | train %.2f | test %.2f\n",
  cor(nn, xg), cor(nn[tr], xg[tr]), cor(nn[-tr], xg[-tr])
))
# ¿Qué tan seguido el texto empuja en sentidos opuestos (uno sube, el otro
# baja, ambos más de 2%)?
op <- (nn > .02 & xg < -.02) | (nn < -.02 & xg > .02)
cat(sprintf(
  "Anuncios donde el texto empuja en sentidos opuestos (más de 2%% cada uno): %.1f%%\n",
  100 * mean(op)
))

# ---- Términos que más se asocian con cada componente ----
# Correlación de cada componente con el TF-IDF del término, en todos los anuncios
X <- XT[match(ids, rownames(XT)), ]
cr <- function(z) {
  zc <- z - mean(z)
  Xc <- sweep(as.matrix(X), 2, colMeans(X))
  drop(crossprod(Xc, zc)) / (sqrt(colSums(Xc^2)) * sqrt(sum(zc^2)))
}
c_nn <- cr(nn)
c_xg <- cr(xg)
tab <- tibble(termino = colnames(X), cor_nn = c_nn, cor_xgb = c_xg) %>%
  mutate(dif = cor_nn - cor_xgb)
top <- function(v, n = 8, des = TRUE) {
  tab %>%
    arrange(if (des) desc(.data[[v]]) else .data[[v]]) %>%
    slice_head(n = n)
}
muestra <- function(d) {
  print(as.data.frame(mutate(d, across(where(is.double), ~ round(.x, 2)))))
}
cat("\nSuben el precio según la NN:\n")
muestra(top("cor_nn"))
cat("\nSuben el precio según el XGB:\n")
muestra(top("cor_xgb"))
cat("\nBajan el precio según la NN:\n")
muestra(top("cor_nn", des = FALSE))
cat("\nBajan el precio según el XGB:\n")
muestra(top("cor_xgb", des = FALSE))
cat("\nMás desacuerdo (la NN los valora más que el XGB / al revés):\n")
muestra(bind_rows(top("dif", 6), top("dif", 6, FALSE)))
cat(sprintf(
  "\nCorrelación entre los dos perfiles de términos (1.000 términos): %.2f\n",
  cor(c_nn, c_xg)
))

# ---- Salidas ----
write_csv(tab, file.path(P$tab_pres, "texto_terminos.csv"))
write_csv( # para el gráfico de dispersión (95)
  tibble(
    property_id = ids,
    muestra = rep(c("train", "test"), c(nrow(TR), nrow(TE))),
    nn = nn, xgb = xg
  ),
  file.path(P$tab_pres, "texto_componentes.csv")
)
write_csv(
  tibble(
    cor_componentes = cor(nn, xg), cor_terminos = cor(c_nn, c_xg),
    pct_opuestos = mean(op)
  ),
  file.path(P$tab_pres, "texto_comparacion.csv")
)
