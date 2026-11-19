# =============================================================================
# Problem Set 3 - Estadísticas descriptivas y motivación espacial
# Entradas: data/raw/{train,test}.csv, data/external/osm/* (de 01_osm_descarga.R)
# Salidas:  data/processed/base_enriquecida.csv, reports/01_descriptivas/{figures,tables}/
# =============================================================================
source("scripts/00_config.R")
suppressMessages(pacman::p_load(sp, stargazer))

# ---- 1. Datos ----
tr <- lee_csv(file.path(P$raw, "train.csv"))
te <- lee_csv(file.path(P$raw, "test.csv"))
d <- bind_rows(tr %>% mutate(muestra = "train"), te %>% mutate(muestra = "test")) %>%
  mutate(muestra = factor(muestra, c("train", "test")),
         txt = str_to_lower(paste(title, description)),
         fecha = as.Date(sprintf("%d-%02d-01", year, month)))

# ---- 2. Variables extraídas del texto ----
d <- d %>% mutate(
  area_txt  = num_txt(txt, PATRONES$area),
  area_txt  = if_else(between(area_txt, 20, 1000), area_txt, NA_real_),
  banos_txt = num_txt(txt, PATRONES$banos),
  estrato_txt = num_txt(txt, PATRONES$estrato),
  estrato_txt = if_else(between(estrato_txt, 1, 6), estrato_txt, NA_real_),
  sup_obs   = coalesce(surface_covered, surface_total),
  sup_obs   = if_else(between(sup_obs, 20, 1500), sup_obs, NA_real_),
  area      = coalesce(sup_obs, area_txt),
  fuente_area = case_when(!is.na(sup_obs) ~ "Variable observada", !is.na(area_txt) ~ "Extraída del texto", TRUE ~ "Faltante"),
  banos     = coalesce(bathrooms, if_else(between(banos_txt, 1, 8), banos_txt, NA_real_)),
  log_precio = log(price), precio_m2 = price / area)

amen <- c(parqueadero = "parqueader|garaje", ascensor = "ascensor", terraza = "terraza", balcon = "balcon",
          chimenea = "chimenea", gimnasio = "gimnasio|\\bgym\\b", piscina = "piscina",
          vigilancia = "vigilancia|porteria|seguridad 24", deposito = "deposito|bodega", estudio = "estudio",
          duplex = "duplex", penthouse = "penthouse|pent house", remodelado = "remodelad", estrenar = "estrenar",
          vista = "vista", bbq = "\\bbbq\\b", conjunto = "conjunto", servicio = "alcoba de servicio|cuarto de servicio",
          walk_in = "walk in", patio = "patio", jardin = "jardin", exterior = "exterior")
for (k in names(amen)) d[[paste0("tx_", k)]] <- as.integer(str_detect(d$txt, amen[k]))

# ---- 3. Localidad y UPZ (punto en polígono con sp) ----
asigna_poly <- function(poly, lon, lat) {
  out <- rep(NA_character_, length(lon))
  for (g in split(poly, list(poly$nombre, poly$ring), drop = TRUE)) {
    inside <- point.in.polygon(lon, lat, g$lon, g$lat) > 0
    out[inside & is.na(out)] <- g$nombre[1]
  }
  out
}
loc_poly <- lee_csv(file.path(P$osm, "localidades_poligonos.csv"))
upz_poly <- lee_csv(file.path(P$osm, "upz_poligonos.csv"))
d$localidad <- asigna_poly(loc_poly, d$lon, d$lat)
d$upz <- asigna_poly(upz_poly, d$lon, d$lat)

# ---- 4. Distancias a servicios (haversine de 00_config.R, metros) ----
pts <- lee_csv(file.path(P$osm, "servicios_puntos.csv"))
chunks <- split(seq_len(nrow(d)), ceiling(seq_len(nrow(d)) / 1500))
for (cp in unique(pts$capa)) {
  p <- filter(pts, capa == cp); dist <- numeric(nrow(d)); n500 <- integer(nrow(d))
  for (ix in chunks) {
    m <- hav(d$lat[ix], d$lon[ix], p$lat, p$lon)
    dist[ix] <- apply(m, 1, min); n500[ix] <- rowSums(m <= 500)
  }
  d[[paste0("dist_", cp)]] <- dist; d[[paste0("n500_", cp)]] <- n500
}
# Distancia a hitos de empleo/comercio (CBD): Centro Internacional, Calle 72 y Parque de la 93
hitos <- tibble(h = c("centro_internacional", "calle72", "parque93"),
                lat = c(4.6148, 4.6573, 4.6766), lon = c(-74.0697, -74.0585, -74.0484))
for (i in seq_len(nrow(hitos))) d[[paste0("dist_", hitos$h[i])]] <- hav(d$lat, d$lon, hitos$lat[i], hitos$lon[i])[, 1]
d$dist_cbd <- pmin(d$dist_centro_internacional, d$dist_calle72, d$dist_parque93)

write_csv(select(d, -txt), file.path(P$processed, "base_enriquecida.csv"))

# ---- 5. Tablas ----
# 5a. Faltantes y recuperación desde el texto
falt <- d %>% group_by(muestra) %>% summarise(
  `Área (variable original)` = mean(is.na(sup_obs)), `Área (tras usar texto)` = mean(is.na(area)),
  `Baños (original)` = mean(is.na(bathrooms)), `Baños (tras usar texto)` = mean(is.na(banos)),
  `Cuartos (rooms)` = mean(is.na(rooms)), `Habitaciones (bedrooms)` = mean(is.na(bedrooms)),
  `Estrato (mencionado en texto)` = mean(!is.na(estrato_txt)))
write_csv(falt, file.path(P$rep_desc, "tables", "faltantes.csv")); print(falt %>% mutate(across(where(is.numeric), ~ round(.x, 3))))

# 5b. Descriptivas train vs test vs train-Chapinero
vars_desc <- c(price = "Precio (millones COP)", area = "Área (m2)", precio_m2 = "Precio por m2 (millones)",
               bedrooms = "Habitaciones", banos = "Baños", es_apto = "Apartamento (=1)",
               dist_transmilenio = "Dist. TransMilenio (m)", dist_parque = "Dist. parque (m)",
               dist_cbd = "Dist. CBD más cercano (m)", n500_restaurante_bar = "Restaurantes/bares a 500 m",
               tx_parqueadero = "Menciona parqueadero", tx_ascensor = "Menciona ascensor", tx_chimenea = "Menciona chimenea",
               tx_terraza = "Menciona terraza", tx_gimnasio = "Menciona gimnasio")
dd <- d %>% mutate(price = price / 1e6, precio_m2 = precio_m2 / 1e6, es_apto = as.integer(property_type == "Apartamento"),
                   grupo = case_when(muestra == "test" ~ "Test", localidad %in% "Chapinero" ~ "Train: Chapinero", TRUE ~ "Train: resto"))
desc <- map_dfr(names(vars_desc), function(v) dd %>% group_by(grupo) %>%
  summarise(media = mean(.data[[v]], na.rm = TRUE), mediana = median(.data[[v]], na.rm = TRUE), n = sum(!is.na(.data[[v]]))) %>%
  mutate(variable = vars_desc[v]))
tab_desc <- desc %>% mutate(val = sprintf("%s [%s]", comma(media, .01, big.mark = ".", decimal.mark = ","), comma(mediana, .01, big.mark = ".", decimal.mark = ","))) %>%
  select(variable, grupo, val) %>% pivot_wider(names_from = grupo, values_from = val)
write_csv(tab_desc, file.path(P$rep_desc, "tables", "descriptivas_grupos.csv")); print(tab_desc, n = 30)
print(count(dd, grupo))

stargazer(as.data.frame(dd %>% filter(muestra == "train") %>% select(all_of(names(vars_desc)))),
          type = "latex", title = "Estadísticas descriptivas - muestra de entrenamiento", digits = 2,
          covariate.labels = unname(vars_desc), out = file.path(P$rep_desc, "tables", "descriptivas_train.tex"), float = TRUE,
          summary.stat = c("n", "mean", "sd", "min", "p25", "median", "p75", "max"))

# 5c. Localidades
tab_loc <- d %>% group_by(localidad = coalesce(localidad, "Sin asignar")) %>%
  summarise(n_train = sum(muestra == "train"), n_test = sum(muestra == "test"),
            precio_med_mill = median(price[muestra == "train"]) / 1e6,
            precio_m2_med_mill = median(precio_m2[muestra == "train"], na.rm = TRUE) / 1e6,
            pct_apto_train = mean(property_type[muestra == "train"] == "Apartamento")) %>% arrange(desc(n_train + n_test))
write_csv(tab_loc, file.path(P$rep_desc, "tables", "localidades.csv")); print(tab_loc, n = 25)
cat("UPZ en test:", n_distinct(d$upz[d$muestra == "test"]), "\n")
print(d %>% filter(muestra == "test") %>% count(upz, sort = TRUE) %>% mutate(n_train = map_int(upz, ~ sum(d$upz[d$muestra == "train"] %in% .x))), n = 30)

# 5d. Regresión hedónica motivacional (log precio)
dr <- d %>% filter(muestra == "train", !is.na(area), !is.na(banos)) %>%
  mutate(localidad = relevel(factor(coalesce(localidad, "Otra")), ref = "Kennedy"), apto = property_type == "Apartamento",
         dist_tm_km = dist_transmilenio / 1000, dist_cbd_km = dist_cbd / 1000, dist_parque_100m = dist_parque / 100,
         log_rest500 = log1p(n500_restaurante_bar), anio = factor(year))
f1 <- log_precio ~ log(area) + bedrooms + banos + apto + anio
f2 <- update(f1, ~ . + dist_cbd_km + dist_tm_km + dist_parque_100m + log_rest500)
f3 <- update(f2, as.formula(paste("~ . +", paste(paste0("tx_", names(amen)), collapse = " + "))))
f4 <- update(f3, ~ . + localidad)
mods <- list(lm(f1, dr), lm(f2, dr), lm(f3, dr), lm(f4, dr))
stargazer(mods, type = "text", keep = c("area", "bedrooms", "banos", "apto", "dist_", "rest", "tx_"), omit.stat = c("f", "ser"),
          add.lines = list(c("Efectos fijos localidad", "No", "No", "No", "Sí")))
stargazer(mods, type = "latex", out = file.path(P$rep_desc, "tables", "hedonica_motivacional.tex"), keep = c("area", "bedrooms", "banos", "apto", "dist_", "rest", "tx_"),
          omit.stat = c("f", "ser"), title = "Regresión hedónica: log(precio)", dep.var.labels = "log(precio)",
          add.lines = list(c("Efectos fijos de año", "Sí", "Sí", "Sí", "Sí"), c("Efectos fijos de localidad", "No", "No", "No", "Sí")))

# ---- 6. Figuras ----
borde <- geom_polygon(data = loc_poly, aes(lon, lat, group = interaction(nombre, ring)), fill = NA, color = c_muted, linewidth = .25, inherit.aes = FALSE)
# Etiqueta en la mediana de los inmuebles de cada localidad (no en el centro del polígono, que incluye zona rural)
lab_loc <- d %>% filter(!is.na(localidad)) %>% group_by(nombre = localidad) %>% filter(n() > 150) %>%
  summarise(lon = median(lon), lat = median(lat)) %>%
  mutate(lon = if_else(nombre == "Chapinero", lon + .012, lon), lon = if_else(nombre == "Usaquén", lon - .004, lon))
lims <- coord_quickmap(xlim = c(-74.19, -74.015), ylim = c(4.565, 4.775))
etiquetas <- geom_label(data = lab_loc, aes(lon, lat, label = nombre), size = 2.6, color = c_ink, fill = "#fcfcfbcc",
                        label.size = 0, label.padding = unit(.12, "lines"), inherit.aes = FALSE)

# F1. Train vs test en el mapa
g1 <- ggplot(d %>% arrange(muestra), aes(lon, lat, color = muestra)) + borde +
  geom_point(size = .35, alpha = .45) + etiquetas + lims +
  scale_color_manual(values = c(train = c_train, test = c_test), labels = c("Entrenamiento (38.644)", "Prueba (10.286)"), name = NULL) +
  guides(color = guide_legend(override.aes = list(size = 3, alpha = 1))) +
  labs(title = "La muestra de prueba está concentrada en Chapinero",
       subtitle = "Ubicación de los inmuebles en venta, 2019-2021", x = NULL, y = NULL, caption = fuente) +
  theme(axis.text = element_blank(), panel.grid.major = element_blank())
ggsave(file.path(P$rep_desc, "figures", "f1_mapa_train_test.png"), g1, width = 6.5, height = 7.4, dpi = 300)

# F2. Precio por m2 (mediana en celdas de ~500 m)
g2 <- ggplot(d %>% filter(muestra == "train", !is.na(precio_m2)), aes(lon, lat, z = precio_m2 / 1e6)) + borde +
  stat_summary_2d(fun = function(z) if (length(z) >= 8) median(z) else NA_real_, binwidth = c(.0045, .0045), alpha = .95, na.rm = TRUE) +
  etiquetas + lims +
  scale_fill_gradientn(colors = seq_blue, name = "Mediana precio por m2 (millones COP)", limits = c(2, 10), oob = squish, na.value = NA) +
  guides(fill = guide_colorbar(barwidth = 14, barheight = .5, title.position = "top")) +
  labs(title = "El precio por metro cuadrado crece hacia el nororiente",
       subtitle = "Mediana del precio por m2 en celdas de ~500 m con 8+ anuncios (entrenamiento)", x = NULL, y = NULL, caption = fuente) +
  theme(axis.text = element_blank(), panel.grid.major = element_blank())
ggsave(file.path(P$rep_desc, "figures", "f2_mapa_precio_m2.png"), g2, width = 6.5, height = 7.4, dpi = 300)

# F3. Distribución del precio (truncamiento)
g3 <- ggplot(tr, aes(price / 1e6, fill = property_type)) +
  geom_histogram(binwidth = 25, boundary = 300, color = "#fcfcfb", linewidth = .2) +
  facet_wrap(~ property_type, ncol = 1, scales = "free_y") +
  scale_fill_manual(values = c(Apartamento = c_train, Casa = "#1baf7a"), guide = "none") +
  scale_x_continuous(labels = label_number(big.mark = ".", decimal.mark = ","), breaks = seq(300, 1650, 150)) +
  geom_vline(xintercept = c(300, 1650), linetype = 2, color = c_ink2, linewidth = .3) +
  labs(title = "Los precios están acotados entre 300 y 1.650 millones",
       subtitle = "Distribución del precio de venta (muestra de entrenamiento)", x = "Precio (millones de COP)", y = "Inmuebles", caption = fuente)
ggsave(file.path(P$rep_desc, "figures", "f3_distribucion_precio.png"), g3, width = 7, height = 5, dpi = 300)

# F4. Precio por m2 por localidad
loc_ord <- d %>% filter(muestra == "train", !is.na(localidad), !is.na(precio_m2)) %>% group_by(localidad) %>% filter(n() >= 100) %>% ungroup() %>%
  add_count(localidad) %>% mutate(localidad = paste0(localidad, " (n=", format(n, big.mark = ".", trim = TRUE), ")"), es_chap = str_starts(localidad, "Chapinero"), localidad = fct_reorder(localidad, precio_m2, median))
g4 <- ggplot(loc_ord, aes(precio_m2 / 1e6, localidad, fill = es_chap)) +
  geom_boxplot(outlier.shape = NA, width = .6, color = c_ink2, linewidth = .3) +
  scale_fill_manual(values = c(`FALSE` = "#cde2fb", `TRUE` = c_test), guide = "none") +
  coord_cartesian(xlim = c(0, 14)) +
  labs(title = "Chapinero es la localidad más cara por metro cuadrado",
       subtitle = "Precio por m2 por localidad, localidades con 100+ observaciones (train)", x = "Precio por m2 (millones COP)", y = NULL, caption = fuente)
ggsave(file.path(P$rep_desc, "figures", "f4_precio_m2_localidad.png"), g4, width = 7, height = 5.5, dpi = 300)

# F5. Gradientes de distancia (binned scatter, deciles)
bins <- d %>% filter(muestra == "train", !is.na(precio_m2)) %>%
  select(precio_m2, `Distancia al CBD más cercano` = dist_cbd, `Distancia a TransMilenio` = dist_transmilenio,
         `Distancia a un parque` = dist_parque, `Distancia a centro comercial` = dist_centro_comercial) %>%
  pivot_longer(-precio_m2, names_to = "var", values_to = "dist") %>% group_by(var) %>%
  mutate(b = ntile(dist, 20)) %>% group_by(var, b) %>% summarise(dist = median(dist) / 1000, p = median(precio_m2) / 1e6, .groups = "drop")
g5 <- ggplot(bins, aes(dist, p)) + geom_line(color = c_train, linewidth = .6) + geom_point(color = c_train, size = 2.2) +
  facet_wrap(~ var, scales = "free_x") +
  labs(title = "Gradientes de precio: cercanía a empleo y servicios",
       subtitle = "Mediana del precio por m2 por veintil de distancia (train)", x = "Distancia (km)", y = "Precio por m2 (millones COP)", caption = fuente)
ggsave(file.path(P$rep_desc, "figures", "f5_gradientes_distancia.png"), g5, width = 8, height = 5.5, dpi = 300)

# F6. Coeficientes de amenidades del texto (modelo 4 con EF de localidad)
co <- broom_like <- summary(mods[[4]])$coefficients
co <- tibble(term = rownames(co), b = co[, 1], se = co[, 2]) %>% filter(str_starts(term, "tx_")) %>%
  mutate(term = str_remove(term, "tx_") %>% str_replace("_", " ") %>% str_to_sentence(), term = fct_reorder(term, b),
         signo = if_else(b > 0, "pos", "neg"))
g6 <- ggplot(co, aes(100 * (exp(b) - 1), term, color = signo)) + geom_vline(xintercept = 0, color = c_muted, linewidth = .3) +
  geom_errorbar(aes(xmin = 100 * (exp(b - 1.96 * se) - 1), xmax = 100 * (exp(b + 1.96 * se) - 1)), width = 0, linewidth = .5) +
  geom_point(size = 2.3) + scale_color_manual(values = c(pos = c_train, neg = c_test), guide = "none") +
  labs(title = "Lo que dice el anuncio también tiene precio",
       subtitle = "Diferencia % en precio asociada a mencionar cada atributo, con controles\nde área, habitaciones, baños, tipo, año, distancias y localidad (IC 95%)",
       x = "Diferencia en el precio (%)", y = NULL, caption = fuente)
ggsave(file.path(P$rep_desc, "figures", "f6_amenidades_texto.png"), g6, width = 7, height = 6, dpi = 300)

# F7. Recuperación del área desde el texto
g7 <- d %>% count(muestra, fuente_area) %>% group_by(muestra) %>% mutate(p = n / sum(n),
  fuente_area = factor(fuente_area, c("Variable observada", "Extraída del texto", "Faltante")),
  tinta = if_else(fuente_area == "Variable observada", "white", c_ink)) %>%
  ggplot(aes(p, muestra, fill = fuente_area)) +
  geom_col(width = .55, color = "#fcfcfb", linewidth = .6, position = position_stack(reverse = TRUE)) +
  geom_text(aes(label = percent(p, 1), color = tinta, group = fuente_area), position = position_stack(vjust = .5, reverse = TRUE), size = 3.2) +
  scale_color_identity() +
  scale_fill_manual(values = c(`Variable observada` = c_train, `Extraída del texto` = "#86b6ef", Faltante = "#e1e0d9"), name = NULL) +
  scale_x_continuous(labels = percent) + scale_y_discrete(labels = c(train = "Entrenamiento", test = "Prueba")) +
  labs(title = "La descripción permite recuperar parte del área faltante",
       subtitle = "Fuente de la variable de área por muestra", x = NULL, y = NULL, caption = fuente)
ggsave(file.path(P$rep_desc, "figures", "f7_area_fuente.png"), g7, width = 7, height = 3, dpi = 300)

# F8. Precio y área: relación log-log
d8 <- d %>% filter(muestra == "train", between(area, 25, 800))
m8 <- d8 %>% group_by(property_type) %>% mutate(b = ntile(log(area), 25)) %>% group_by(property_type, b) %>%
  summarise(area = median(area), p = median(price) / 1e6, .groups = "drop")
g8 <- ggplot(d8, aes(area, price / 1e6)) +
  geom_point(alpha = .07, size = .5, color = c_train) +
  geom_line(data = m8, aes(area, p), color = c_test, linewidth = .7) + geom_point(data = m8, aes(area, p), color = c_test, size = 1.8) +
  facet_wrap(~ property_type) + scale_x_log10() + scale_y_log10(labels = label_number(big.mark = ".", decimal.mark = ",")) +
  labs(title = "Más área, mayor precio, hasta chocar con el tope de 1.650 millones",
       subtitle = "Precio vs. área, escala logarítmica; línea = mediana por veinticincoavo de área (train, 25-800 m2)",
       x = "Área (m2, log)", y = "Precio (millones, log)", caption = fuente)
ggsave(file.path(P$rep_desc, "figures", "f8_precio_area.png"), g8, width = 8, height = 4.5, dpi = 300)

# F9. Evolución temporal
g9 <- d %>% filter(muestra == "train") %>% group_by(fecha, property_type) %>% filter(n() >= 50) %>%
  summarise(p = median(precio_m2, na.rm = TRUE) / 1e6, .groups = "drop") %>%
  ggplot(aes(fecha, p, color = property_type)) + geom_line(linewidth = .6) + geom_point(size = 1.6) +
  scale_color_manual(values = c(Apartamento = c_train, Casa = "#1baf7a"), name = NULL) +
  labs(title = "Precios por m2 relativamente estables en el periodo",
       subtitle = "Mediana mensual del precio por m2 (meses con 50+ anuncios, train)", x = NULL, y = "Precio por m2 (millones COP)", caption = fuente)
ggsave(file.path(P$rep_desc, "figures", "f9_tiempo.png"), g9, width = 7, height = 4, dpi = 300)

cat("Correlaciones con log precio (train):\n")
num <- d %>% filter(muestra == "train") %>% select(log_precio, area, bedrooms, banos, starts_with("dist_"), starts_with("n500_"), estrato_txt)
print(sort(round(cor(num, use = "pairwise")[-1, 1], 3), decreasing = TRUE))
cat("Listo.\n")
