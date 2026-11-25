# =============================================================================
# 99_negocio.R - Moraleja 5 de la presentación: ¿sirven estos modelos para
# hacer negocios?
# Usa las predicciones OOF de la CV por localidad con buffer (D9): cada
# localidad se predice sin haberla visto, como Chapinero en el test. Tres
# modelos, uno por familia: NN STAR m24, XGB STAR m27 (catastro) y ElasticNet
# m23 (encoder).
#  - Sesgo por localidad: (media de la predicción - media del precio) / media
#    del precio.
#  - k*: factor que minimiza el MAE al multiplicar todas las predicciones de la
#    localidad (k* > 1: subpredice).
#  - "Messis": anuncios de Chapinero con precio por m2 sobre el percentil 95 del
#    resto de la ciudad.
# Salidas: output/figures/03_presentacion/sesgo_localidades.pdf y
# output/tables/03_presentacion/numeros_negocio.tex
# =============================================================================
source(here::here("code", "01_setup.R"))

num <- function(x, d = 1) formatC(x, format = "f", digits = d, decimal.mark = ",")
FUENTE <- "NewCenturySchoolbook" # la de las diapositivas
o <- lee_csv(file.path(P$models, "oof_predicciones.csv"))
tr <- filter(readRDS(file.path(P$processed, "base_modelo.rds"))$datos, muestra == "train")
y <- exp(o$log_price)
m2 <- y / exp(tr$log_area[match(o$property_id, tr$property_id)])
ch <- o$chapinero == 1
MODS <- c(red = "m24_nn_star_catastro_m2", xgb = "m27_xgb_star_catastro_m2", en = "m23_en_enc_tx")
P_oof <- lapply(MODS, \(m) recorta(exp(o[[m]])))

# ---- Sesgo y k* por localidad ----
sesgo <- \(p, i) mean(p[i] - y[i]) / mean(y[i])
loc <- imap_dfr(P_oof, function(p, k) {
  tibble(grupo = o$grupo, y, p, m2) %>%
    group_by(grupo) %>%
    summarise(
      n = n(),
      m2 = median(m2) / 1e6,
      sesgo = mean(p - y) / mean(y),
      mape = median(abs(p / y - 1)),
      k_opt = optimize(\(k) mean(abs(recorta(k * p) - y)), c(.7, 1.4))$minimum,
      .groups = "drop"
    ) %>%
    mutate(modelo = k)
})
cor_loc <- loc %>%
  group_by(modelo) %>%
  summarise(r = cor(m2, sesgo))
print(as.data.frame(
  mutate(loc, across(where(is.double), ~ round(.x, 3))) %>% arrange(modelo, desc(m2))
))
print(cor_loc)

# ---- "Messis" de Chapinero ----
p95 <- quantile(m2[!ch], .95)
messi <- ch & m2 > p95
ses_messi <- sapply(P_oof, sesgo, i = messi)
ses_resto <- sapply(P_oof, sesgo, i = ch & !messi)
cat(sprintf(
  "p95 resto: %.1f M/m2 | Messis: %.0f%% de Chapinero\n",
  p95 / 1e6, 100 * mean(m2[ch] > p95)
))
print(round(rbind(messi = ses_messi, resto = ses_resto), 3))

# ---- Figura: sesgo por localidad frente a su precio por m2 (NN STAR m24) ----
fr <- filter(loc, modelo == "red")
etq <- filter(fr, grupo %in% c("Chapinero", "Usaquén", "Suba", "La Candelaria"))
g <- ggplot(fr, aes(m2, sesgo)) +
  geom_hline(yintercept = 0, colour = "#898781", linewidth = .4) +
  geom_smooth(
    method = "lm", formula = y ~ x, se = FALSE, colour = "#c3c2bd",
    linewidth = .6, mapping = aes(weight = NULL)
  ) +
  geom_point(aes(size = n), colour = "#1E5631", alpha = .85) +
  geom_text(
    data = etq, aes(label = grupo), nudge_y = .022, size = 3.6,
    family = FUENTE, colour = "#0b0b0b"
  ) +
  scale_size_area(max_size = 7, guide = "none") +
  scale_y_continuous(labels = \(x) paste0(ifelse(x > 0, "+", ""), num(100 * x, 0), " %")) +
  scale_x_continuous(labels = label_number(decimal.mark = ",")) +
  labs(x = "Precio mediano por m² de la localidad (millones)", y = "Sesgo de la predicción") +
  theme_minimal(base_size = 13, base_family = FUENTE) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(colour = "#ecebe8", linewidth = .4),
    axis.text = element_text(colour = "#52514e"),
    axis.title = element_text(colour = "#52514e", size = 11)
  )
ggsave(
  file.path(P$fig_pres, "sesgo_localidades.pdf"), g,
  width = 5, height = 3.4, device = "pdf", family = FUENTE
)

# ---- Cifras para el texto ----
L <- \(k, g, v) loc[[v]][loc$modelo == k & loc$grupo == g]
pc <- \(x, d = 0) num(100 * abs(x), d)
coma_mat <- \(x) sub(",", "{,}", num(x, 2)) # coma decimal dentro de $...$
k_chap <- sapply(names(MODS), L, g = "Chapinero", v = "k_opt")
mac <- c(
  sesgoChapRed = pc(L("red", "Chapinero", "sesgo")),
  sesgoChapXGB = pc(L("xgb", "Chapinero", "sesgo")),
  sesgoChapEN = pc(L("en", "Chapinero", "sesgo")),
  kChapMin = num(min(k_chap), 2),
  kChapMax = num(max(k_chap), 2),
  corLocRed = coma_mat(cor_loc$r[cor_loc$modelo == "red"]),
  corLocXGB = coma_mat(cor_loc$r[cor_loc$modelo == "xgb"]),
  corLocEN = coma_mat(cor_loc$r[cor_loc$modelo == "en"]),
  pNoventaCinco = num(unname(p95) / 1e6),
  pctMessi = num(100 * mean(m2[ch] > p95), 0),
  sesgoMessiRed = pc(ses_messi[["red"]]),
  sesgoMessiXGB = pc(ses_messi[["xgb"]]),
  sesgoRestoRed = pc(ses_resto[["red"]], 1),
  mapeChap = pc(L("red", "Chapinero", "mape")),
  dentroDiezChap = num(100 * mean(abs(P_oof$red[ch] / y[ch] - 1) < .1), 0),
  sesgoUsaquen = pc(L("red", "Usaquén", "sesgo"), 1),
  sesgoSuba = pc(L("red", "Suba", "sesgo"), 1),
  mapeUsaquen = pc(L("red", "Usaquén", "mape")),
  mapeSuba = pc(L("red", "Suba", "mape"))
)
writeLines(
  c(
    "% Generado por code/99_negocio.R: no editar a mano",
    sprintf("\\newcommand{\\%s}{%s}", names(mac), mac)
  ),
  file.path(P$tab_pres, "numeros_negocio.tex")
)
