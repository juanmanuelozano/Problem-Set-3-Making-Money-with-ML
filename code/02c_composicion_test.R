# =============================================================================
# 02c_composicion_test.R - Composición del test frente al train: tipo de inmueble, estrato, habitaciones,
#                          área y cercanía a los centros de empleo; perfil de casas y apartamentos.
# Entradas: data/processed/base_modelo.rds (de 03_features.R; usa el área y el estrato finales)
# Salidas:  output/tables/01_descriptivas/composicion_train_test.csv, perfil_tipo_inmueble.csv,
#           cercania_train_test.csv
#           output/figures/01_descriptivas/f15_composicion_train_test.png
# =============================================================================
source(here::here("code", "01_setup.R"))

base <- readRDS(file.path(P$processed, "base_modelo.rds"))
d <- base$datos %>%
  mutate(chap = localidad %in% "Chapinero",
         grupo_m = case_when(muestra == "test" ~ "Test",
                             chap ~ "Train: Chapinero",
                             TRUE ~ "Train: resto"),
         area = exp(log_area))

# ---- 1. Composición por dimensión ----
dims <- d %>% transmute(
  grupo_m, muestra,
  `Tipo de inmueble` = if_else(es_apto == 1, "Apartamento", "Casa"),
  `Estrato` = if_else(round(estrato_final) <= 2, "1–2", as.character(pmin(round(estrato_final), 6))),
  `Habitaciones` = cut(bedrooms, c(-Inf, 1, 2, 3, Inf), labels = c("1 o menos", "2", "3", "4 o más")),
  `Área (m²)` = cut(area, c(0, 60, 90, 120, 180, Inf), labels = c("< 60", "60–90", "90–120", "120–180", "> 180")),
  `Distancia al CBD más cercano (km)` = cut(dist_cbd / 1000, c(-Inf, 0.5, 1, 2, 5, Inf),
                                            labels = c("< 0,5", "0,5–1", "1–2", "2–5", "> 5"))) %>%
  mutate(across(-c(grupo_m, muestra), as.character))

prop_por <- function(df, col) df %>% count(categoria = .data[[col]]) %>% mutate(p = n / sum(n)) %>% select(-n)
comp <- map_dfr(setdiff(names(dims), c("grupo_m", "muestra")), function(v) {
  bind_rows(prop_por(filter(dims, muestra == "train"), v) %>% mutate(grupo = "Train (total)"),
            prop_por(filter(dims, grupo_m == "Train: Chapinero"), v) %>% mutate(grupo = "Train: Chapinero"),
            prop_por(filter(dims, muestra == "test"), v) %>% mutate(grupo = "Test")) %>%
    mutate(dimension = v)
}) %>% pivot_wider(names_from = grupo, values_from = p, values_fill = 0) %>%
  mutate(razon_test_train = Test / `Train (total)`)
orden <- list(`Tipo de inmueble` = c("Apartamento", "Casa"), Estrato = c("1–2", as.character(3:6)),
              Habitaciones = c("1 o menos", "2", "3", "4 o más"), `Área (m²)` = c("< 60", "60–90", "90–120", "120–180", "> 180"),
              `Distancia al CBD más cercano (km)` = c("< 0,5", "0,5–1", "1–2", "2–5", "> 5"))
comp <- comp %>% mutate(pos = map2_int(dimension, categoria, ~ match(.y, orden[[.x]])),
                        dimension = factor(dimension, names(orden))) %>%
  arrange(dimension, pos) %>% select(-pos)
write_csv(comp, file.path(P$tab_desc, "composicion_train_test.csv"))
cat("Composición (proporciones):\n")
print(comp %>% mutate(across(where(is.double), ~ round(.x, 3))), n = Inf)
for (s in c("train", "test")) {
  x <- d$dist_cbd[d$muestra == s] / 1000
  cat(sprintf("Distancia al CBD, %s: mediana %.2f km | p90 %.2f | máximo %.2f | < 1 km %.1f%% | < 2 km %.1f%%\n",
              s, median(x), quantile(x, .9), max(x), 100 * mean(x < 1), 100 * mean(x < 2)))
}

# ---- 2. Perfil de casas y apartamentos ----
perfil <- d %>% mutate(tipo = if_else(es_apto == 1, "Apartamento", "Casa")) %>%
  group_by(grupo_m, tipo) %>%
  summarise(n = n(),
            precio_mediano_M = median(price, na.rm = TRUE) / 1e6,
            precio_m2_mediano_M = median(price / area, na.rm = TRUE) / 1e6,
            area_mediana = median(area), habitaciones = mean(bedrooms), banos = mean(banos_final),
            estrato_medio = mean(estrato_final), piso_mediano = median(piso_txt, na.rm = TRUE),
            pct_ascensor = mean(tx_ascensor), pct_terraza = mean(tx_terraza), pct_patio_jardin = mean(tx_patio | tx_jardin),
            dist_cbd_mediana_km = median(dist_cbd) / 1000, .groups = "drop") %>%
  mutate(grupo_m = factor(grupo_m, c("Train: resto", "Train: Chapinero", "Test"))) %>% arrange(tipo, grupo_m)
write_csv(perfil, file.path(P$tab_desc, "perfil_tipo_inmueble.csv"))
cat("\nPerfil por tipo de inmueble:\n"); print(perfil %>% mutate(across(where(is.double), ~ round(.x, 2))), width = 220)

# ---- 3. Cercanía: distancia de cada anuncio del train al anuncio del test más cercano ----
tr <- d %>% filter(muestra == "train"); te <- d %>% filter(muestra == "test")
tr$d_test <- dist_min(tr$lat, tr$lon, te$lat, te$lon)
cerc <- tr %>% mutate(banda = cut(d_test, c(-Inf, 500, 1000, 2000, 5000, Inf),
                                  labels = c("< 0,5 km", "0,5–1 km", "1–2 km", "2–5 km", "> 5 km"))) %>%
  group_by(banda) %>%
  summarise(n = n(), pct_train = n / nrow(tr), pct_casas = mean(es_apto == 0),
            estrato_medio = mean(estrato_final), precio_mediano_M = median(price) / 1e6, .groups = "drop")
write_csv(cerc, file.path(P$tab_desc, "cercania_train_test.csv"))
cat("\nTrain según su distancia al anuncio del test más cercano:\n"); print(cerc %>% mutate(across(where(is.double), ~ round(.x, 3))))

# ---- 4. Figura: composición del train y del test ----
# Clave única por panel ("dimensión|categoría") para fijar el orden dentro de cada faceta; la etiqueta muestra
# solo la categoría. Niveles de `muestra` invertidos para que, en barras horizontales, Train quede arriba.
niveles <- rev(unlist(imap(orden, ~ paste(.y, .x, sep = "|"))))
fig <- comp %>% select(dimension, categoria, Train = `Train (total)`, Test) %>%
  pivot_longer(c(Train, Test), names_to = "muestra", values_to = "p") %>%
  mutate(muestra = factor(muestra, c("Test", "Train")),
         clave = factor(paste(dimension, categoria, sep = "|"), niveles))
g <- ggplot(fig, aes(p, clave, fill = muestra)) +
  geom_col(position = position_dodge(width = .8), width = .72, color = "#fcfcfb", linewidth = .4) +
  facet_wrap(~ dimension, scales = "free_y", ncol = 2) +
  scale_y_discrete(labels = function(x) sub("^.*\\|", "", x)) +
  scale_x_continuous(labels = percent_format(accuracy = 1), limits = c(0, 1), breaks = seq(0, 1, .25),
                     expand = expansion(mult = c(0, .04))) +
  scale_fill_manual(values = c(Train = c_train, Test = c_test), name = NULL, breaks = c("Train", "Test"),
                    labels = c(Train = "Entrenamiento (n = 38.644)", Test = "Prueba (n = 10.286)")) +
  labs(title = "Composición de las muestras de entrenamiento y prueba",
       subtitle = "Proporción de anuncios en cada categoría",
       x = NULL, y = NULL,
       caption = paste0(fuente, "\nÁrea y estrato: valor observado o, si falta, imputado (03_features.R).")) +
  theme(panel.grid.major.y = element_blank(), strip.text = element_text(face = "bold", hjust = 0, color = c_ink),
        plot.margin = margin(10, 18, 8, 10), panel.spacing.x = unit(1.4, "lines"))
ggsave(file.path(P$fig_desc, "f15_composicion_train_test.png"), g, width = 8.5, height = 8.5, dpi = 250)
cat("Listo.\n")
