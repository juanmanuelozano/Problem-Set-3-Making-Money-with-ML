# =============================================================================
# 02b_extremos.R - Valores extremos: rangos de validez de las variables,
#                  extremos del precio y del precio por m2.
# Entradas: data/processed/base_enriquecida.csv (de 02_descriptivas.R)
#           data/processed/base_modelo.rds      (de 03_features.R, para el área final)
# Salidas:  reports/01_descriptivas/tables/{rangos_validez,precio_topes,precio_m2_extremos}.csv
#           reports/01_descriptivas/figures/f10_precio_m2_extremos.png
# =============================================================================
source("scripts/00_config.R")

d  <- lee_csv(file.path(P$processed, "base_enriquecida.csv"))
dm <- readRDS(file.path(P$processed, "base_modelo.rds"))$datos   # mismas filas y orden que d
stopifnot(nrow(d) == nrow(dm), isTRUE(all.equal(d$price, dm$price)), identical(as.character(d$muestra), as.character(dm$muestra)))
txt <- str_to_lower(paste(d$title, d$description))
num_txt <- function(x, pat) as.numeric(str_replace(str_match(x, pat)[, 2], ",", "."))

# ---- 1. Rangos de validez: cuántos valores crudos quedan fuera y cuáles son ----
crudos <- list(
  `Área cubierta / total (variable)` = list(coalesce(d$surface_covered, d$surface_total), 20, 1500),
  `surface_total (03, sin uso)`       = list(d$surface_total, 20, 2000),
  `Área (texto)`        = list(num_txt(txt, "(\\d{2,4}(?:[\\.,]\\d+)?)\\s?(?:m2|mts2|mt2|mts|metros cuadrados|metros|mt)\\b"), 20, 1000),
  `Baños (texto)`       = list(num_txt(txt, "(\\d)\\s?(?:banos|bano)\\b"), 1, 8),
  `bathrooms (variable)` = list(d$bathrooms, 1, 8),
  `Estrato (texto)`     = list(num_txt(txt, "estrato\\s?(\\d)"), 1, 6),
  `Piso (texto)`        = list(num_txt(txt, "(?:piso|nivel)\\s?(\\d{1,2})\\b"), 1, 40),
  `Antigüedad (texto)`  = list(coalesce(num_txt(txt, "(\\d{1,2})\\s?anos? de (?:construid|antiguedad)"),
                                        num_txt(txt, "antiguedad (?:de )?(\\d{1,2})")), 0, 60),
  `Parqueaderos (texto)` = list(num_txt(txt, "(\\d)\\s?(?:parqueaderos|garajes|parqueadero|garaje)"), 1, 6),
  `bedrooms (variable)` = list(d$bedrooms, 1, 10))
rangos <- imap_dfr(crudos, function(v, nm) {
  x <- v[[1]][!is.na(v[[1]])]; f <- x[x < v[[2]] | x > v[[3]]]
  tibble(variable = nm, rango = paste0("[", v[[2]], ", ", v[[3]], "]"), n_con_dato = length(x),
         n_bajo = sum(x < v[[2]]), n_sobre = sum(x > v[[3]]),
         valores_fuera_frecuentes = paste(head(names(sort(table(f), decreasing = TRUE)), 6), collapse = ", "))
})
write_csv(rangos, file.path(P$rep_desc, "tables", "rangos_validez.csv")); print(rangos, width = 200)

# Evidencia de que el texto perdió los puntos decimales ("4.0 habitaciones 96.0 m2" -> "40 habitaciones 960 m2")
m <- str_match(str_to_lower(d$title), "(\\d+) habitaciones (\\d+) m2")
cat("\nTítulos 'N habitaciones M m2':", sum(!is.na(m[, 1])),
    "| N = 10 x bedrooms:", sum(as.numeric(m[, 2]) == 10 * d$bedrooms, na.rm = TRUE), "\n")

# ---- 2. Extremos del precio: masa en los topes y heaping ----
tr  <- d %>% filter(muestra == "train") %>% mutate(p = price / 1e6)
tmr <- dm %>% filter(muestra == "train")
topes <- tr %>% group_by(grupo = if_else(localidad %in% "Chapinero", "Chapinero", "Resto")) %>%
  summarise(n = n(), en_300 = sum(p == 300), pct_hasta_310 = mean(p <= 310), en_1650 = sum(p == 1650),
            pct_desde_1600 = mean(p >= 1600), pct_mult_10M = mean(p %% 10 == 0), pct_mult_50M = mean(p %% 50 == 0)) %>%
  bind_rows(tr %>% summarise(grupo = "Total", n = n(), en_300 = sum(p == 300), pct_hasta_310 = mean(p <= 310),
                             en_1650 = sum(p == 1650), pct_desde_1600 = mean(p >= 1600),
                             pct_mult_10M = mean(p %% 10 == 0), pct_mult_50M = mean(p %% 50 == 0)))
write_csv(topes, file.path(P$rep_desc, "tables", "precio_topes.csv")); print(topes)
frec <- sort(table(tr$p), decreasing = TRUE)
cat("\nPrecios más frecuentes:", paste0(names(frec)[1:8], " (", frec[1:8], ")", collapse = ", "), "\n")
cat("Bins 950-1000 vs 1000-1050:", sum(tr$p > 950 & tr$p <= 1000), "vs", sum(tr$p > 1000 & tr$p <= 1050), "\n")
cat("Inmuebles en exactamente 300 M vs resto: área mediana",
    median(tr$area[tr$p == 300], na.rm = TRUE), "vs", median(tr$area[tr$p != 300], na.rm = TRUE), "\n")

# ---- 3. Precio por m2: los extremos vienen del área, no del precio ----
# Dos versiones del área: la de las descriptivas (observada o, si falta, texto sin filtro)
# y la final de modelación (texto solo si es coherente con el RF; si no, imputada).
pm <- bind_rows(
  tr %>% filter(!is.na(area)) %>% transmute(version = "Área descriptiva", property_type,
                                           fuente = if_else(fuente_area == "Variable observada", "Observada", "Texto"), pm2 = price / area / 1e6),
  tmr %>% transmute(version = "Área final (modelo)", property_type = if_else(es_apto == 1, "Apartamento", "Casa"),
                    fuente = case_when(area_imputada == 1 ~ "Imputada", area_texto == 1 ~ "Texto", TRUE ~ "Observada"),
                    pm2 = price / exp(log_area) / 1e6)) %>%
  group_by(version, property_type) %>%
  mutate(z = (log(pm2) - median(log(pm2))) / mad(log(pm2))) %>% ungroup()   # z robusto en log, por tipo
ext <- pm %>% group_by(version, property_type, fuente) %>%
  summarise(n = n(), p01 = quantile(pm2, .01), mediana = median(pm2), p99 = quantile(pm2, .99),
            n_z_mayor_3 = sum(abs(z) > 3), pct_z_mayor_3 = mean(abs(z) > 3), .groups = "drop")
write_csv(ext, file.path(P$rep_desc, "tables", "precio_m2_extremos.csv")); print(ext, width = 200)

# F10. Distribución del precio por m2 según la fuente del área
g10 <- ggplot(pm, aes(pm2, fill = fuente)) +
  geom_histogram(bins = 80, position = "identity", alpha = .75, color = NA) +
  facet_grid(fuente ~ version, scales = "free_y") +
  scale_x_log10(breaks = c(.3, 1, 3, 10, 30), labels = label_number(decimal.mark = ",")) +
  scale_fill_manual(values = c(Observada = c_train, Texto = c_test, Imputada = c_aqua), guide = "none") +
  geom_vline(xintercept = c(2, 15), linetype = 2, color = c_ink2, linewidth = .3) +
  labs(title = "Los precios por m2 extremos vienen del área extraída del texto",
       subtitle = "Precio por m2 según la fuente del área (train, escala log). Líneas: 2 y 15 millones/m2",
       x = "Precio por m2 (millones COP, log)", y = "Inmuebles", caption = fuente) +
  theme(strip.text.y = element_text(angle = 0))
ggsave(file.path(P$rep_desc, "figures", "f10_precio_m2_extremos.png"), g10, width = 8, height = 5.5, dpi = 300)
