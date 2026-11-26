# =============================================================================
# 95b_presentacion_best.R - Figuras, tablas y cifras de la presentación best_equipo_04 sobre el ensamble óptimo
# (m24_ens_optimo: 53,4% NN STAR m17 + 39,9% XGB con comparables m22 + 6,6% EN con encoder de texto m14; D22),
# y compilación del .tex (reports/03_presentacion/best_equipo_04.tex) si latexmk está instalado (D29).
# No se vuelve a entrenar ningún modelo de predicción:
#  - El OOF del ensamble se ARMA con los OOF guardados de sus tres componentes. Ojo: m17 y m14 vienen de la CV por
#    localidad con buffer (D9) y m22 de la CV aleatoria de 10 folds (D20), que es optimista. Es una aproximación.
#  - La importancia de variables del ensamble se estima con un modelo sustituto (XGBoost que imita la predicción del
#    m24 en el test a partir de las variables observables).
#  - La sección 11 analiza por qué no funcionaron las variables del Chapinero sintético (TWCV, D16).
# Entradas (D28): OOF, envíos, comparables y tablas tal como estaban cuando se calificaron en Kaggle, leídos de
#   commits fijos con desde_git(): ENVIOS_MJ (validacion-sintetica), ENVIOS_REDES (redes-neuronales) y PRES_MJ.
# Salidas: output/figures/03_presentacion/best_equipo_04/*.pdf, output/tables/03_presentacion/best_equipo_04/*.tex,
#          reports/03_presentacion/best_equipo_04.pdf
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))

FIG <- file.path(P$fig_pres, "best_equipo_04")
TAB <- file.path(P$tab_pres, "best_equipo_04")
walk(c(FIG, TAB), dir.create, recursive = TRUE, showWarnings = FALSE)

ENVIOS_MJ <- "589aff9"    # validacion-sintetica: OOF de m22 y m14, envíos m22, m14 y m24, comparables.csv
ENVIOS_REDES <- "f5786a2" # redes-neuronales: OOF, envíos y scores de las redes (m17 y las demás calificadas)
PRES_MJ <- "b4948f0"      # validacion-sintetica: tabla validación-Kaggle usada en la presentación

# ---- Estilo gráfico: sobrio, solo negro y azul, misma tipografía que las diapositivas (Palatino) ----
FAM <- if (.Platform$OS.type == "windows") "Palatino Linotype" else "Palatino"
g_negro <- "#000000"; g_oscuro <- "#1a1a1a"; g_medio <- "#4a78c2"; g_claro <- "#a8c0e6"; g_tenue <- "#e4ecf8"   # negro y tonos de azul
acento <- "#1f4e9c"   # azul fuerte, para el ensamble y lo que se quiere resaltar
tema_pres <- function(base = 8) {
  theme_minimal(base_size = base, base_family = FAM) +
    theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(color = g_tenue, linewidth = .3),
          axis.line.x = element_line(color = g_oscuro, linewidth = .3), axis.ticks.x = element_line(color = g_oscuro, linewidth = .3),
          axis.ticks.length = unit(2, "pt"),
          axis.text = element_text(color = g_oscuro), axis.title = element_text(color = g_negro),
          strip.text = element_text(color = g_negro, face = "italic", hjust = 0, size = base),
          legend.position = "top", legend.justification = "left", legend.location = "plot", legend.title = element_blank(),
          legend.key.size = unit(8, "pt"), legend.text = element_text(color = g_negro),
          plot.caption = element_text(color = g_medio, hjust = 0, size = base - 2),
          plot.margin = margin(4, 6, 2, 2), panel.spacing = unit(10, "pt"))
}
theme_set(tema_pres())
guarda <- function(g, nombre, w = 5.6, h = 2.9) {   # pulgadas: tamaño real en la diapositiva (16:9, 160 × 90 mm)
  ggsave(file.path(FIG, paste0(nombre, ".pdf")), g, width = w, height = h, device = cairo_pdf)
  cat("  figura:", nombre, "\n")
}
mill <- function(x) x / 1e6
num <- function(x, d = 1) sub("^-", "$-$", formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ","))   # signo menos tipográfico para LaTeX
numg <- function(x, d = 1) sub("^-", "−",formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ","))   # para las gráficas
pct <- function(x, d = 0) paste0(num(100 * x, d), "\\%")
lab_m <- label_number(big.mark = ".", decimal.mark = ",")

# Etiquetas legibles de las variables
ETQ <- c(comp20 = "Precio/m² de 20 comparables", comp5 = "Precio/m² de 5 comparables",
         comp_logdist5 = "Distancia a 5 comparables", comp_logdist20 = "Distancia a 20 comparables",
         log_area = "Área (log)", es_apto = "Apartamento", bedrooms = "Habitaciones", banos_final = "Baños",
         estrato_final = "Estrato", dist_cbd = "Distancia al CBD más cercano", dist_parque93 = "Distancia al Parque 93",
         dist_calle72 = "Distancia a la Calle 72", dist_centro_internacional = "Distancia al Centro Internacional",
         dist_cerros = "Distancia a los cerros", dist_transmilenio = "Distancia a TransMilenio",
         n_palabras = "Palabras del anuncio", coordenadas = "Coordenadas",
         parq_txt = "Parqueaderos (texto)", tx_gimnasio = "Gimnasio (texto)", tx_terraza = "Terraza (texto)", tx_balcon = "Balcón (texto)", piso_txt = "Piso (texto)", antig_txt = "Antigüedad (texto)",
         dist_via_principal = "Distancia a vía principal", area_verde500 = "Área verde a 500 m",
         pisos_prom500 = "Pisos promedio a 500 m", year = "Año", month = "Mes",
         area_imputada = "Área imputada", banos_imputado = "Baños imputados", area_texto = "Área del texto")
etq <- function(v) ifelse(v %in% names(ETQ), ETQ[v], str_replace_all(v, "_", " "))

cifras <- list()   # macros de LaTeX con cada cifra citada en el texto
cifra <- function(nombre, valor) cifras[[nombre]] <<- valor

# =============================================================================
# 1. Datos: OOF de los componentes, ensamble y envíos
# =============================================================================
y <- exp(Y)
oof_main <- lee_csv_git(ENVIOS_REDES, "models/oof_predicciones.csv")
oof_rama <- lee_csv_git(ENVIOS_MJ, "models/oof_predicciones.csv")
stopifnot(identical(oof_main$property_id, TR$property_id), identical(oof_rama$property_id, TR$property_id))

W <- c(m17 = .534, m22 = .399, m14 = .066); W <- W / sum(W)   # pesos de tables/ensamble_pesos.csv (redondeados)
comp_oof <- cbind(m17 = recorta(exp(oof_main$m17_nn_star_m2)), m22 = recorta(exp(oof_rama$m22_xgb_comparables_m2)),
                  m14 = recorta(exp(oof_rama$m14_en_enc_tx)))
stopifnot(!anyNA(comp_oof))
ens_oof <- drop(comp_oof %*% W)

s24 <- lee_csv_git(ENVIOS_MJ, "submissions/m24_ens_optimo.csv")
ids <- s24$property_id
toma <- function(commit, f) { s <- lee_csv_git(commit, file.path("submissions", f)); stopifnot(setequal(s$property_id, ids)); s$price[match(ids, s$property_id)] }
comp_te <- cbind(m17 = toma(ENVIOS_REDES, "m17_nn_star_m2.csv"), m22 = toma(ENVIOS_MJ, "m22_xgb_comparables_m2.csv"),
                 m14 = toma(ENVIOS_MJ, "en_enc_tx.csv"))
ens_te <- drop(comp_te %*% W)
dif_rel <- max(abs(ens_te - s24$price) / s24$price)
cat(sprintf("Reconstrucción del m24 en el test: diferencia relativa máxima %.4f%%\n", 100 * dif_rel))
stopifnot(dif_rel < .005)
TEo <- TE[match(ids, TE$property_id), ]   # test en el orden del envío

# Kaggle
K <- list(pub = 152328386.28, priv = 153110838.48, est = 153.3e6, cota = 160.8e6,
          m17 = 158281022.13, m22 = 162936278.45, m14 = 168831256.43)

# =============================================================================
# 2. El problema: el test no se parece al train
# =============================================================================
cat("\n[A] Problema\n")
grupos <- list(Train = rep(TRUE, nrow(TR)), `Chapinero (train)` = ES_CHAP)
comp_tab <- function(df) tibble(`Estrato 6` = mean(round(df$estrato_final) == 6), Apartamento = mean(df$es_apto == 1),
                                `A menos de 1,27 km del CBD` = mean(df$dist_cbd < 1270), `Hasta 2 habitaciones` = mean(df$bedrooms <= 2))
compo <- bind_rows(comp_tab(TR) %>% mutate(grupo = "Train"), comp_tab(TR[ES_CHAP, ]) %>% mutate(grupo = "Chapinero (train)"),
                   comp_tab(TE) %>% mutate(grupo = "Test")) %>%
  pivot_longer(-grupo, names_to = "rasgo", values_to = "p") %>%
  mutate(grupo = factor(grupo, c("Train", "Chapinero (train)", "Test")), rasgo = fct_rev(factor(rasgo, unique(rasgo))))
print(compo %>% pivot_wider(names_from = grupo, values_from = p))
cifra("pTrainEstSeis", pct(mean(round(TR$estrato_final) == 6))); cifra("pTestEstSeis", pct(mean(round(TE$estrato_final) == 6)))
cifra("pTrainCBD", pct(mean(TR$dist_cbd < 1270))); cifra("pTestCBD", pct(mean(TE$dist_cbd < 1270)))
cifra("pTestApto", pct(mean(TE$es_apto == 1))); cifra("pTrainApto", pct(mean(TR$es_apto == 1)))
cifra("pTestChap", pct(mean(TE$localidad %in% "Chapinero"))); cifra("nChapTrain", num(sum(ES_CHAP), 0))
cifra("pTrainChap", pct(mean(ES_CHAP), 1)); cifra("nTrain", num(nrow(TR), 0)); cifra("nTest", num(nrow(TE), 0))

# Mapa: dónde está cada muestra
# Límites y nombres de las localidades (polígonos de OSM; el nombre va en la mediana de los anuncios de cada una)
loc_pol <- lee_csv(file.path(P$osm, "localidades_poligonos.csv")) %>% mutate(grupo = paste(nombre, ring))
loc_lbl <- bind_rows(TR, TE) %>% filter(!is.na(localidad)) %>% group_by(localidad) %>%
  summarise(lon = median(lon), lat = median(lat), .groups = "drop") %>%
  bind_rows(loc_pol %>% filter(!nombre %in% c(TR$localidad, TE$localidad)) %>% group_by(localidad = nombre) %>%
              summarise(lon = mean(lon), lat = mean(lat), .groups = "drop")) %>%
  filter(between(lon, -74.21, -73.99), between(lat, 4.54, 4.82)) %>%
  mutate(lbl = str_replace(localidad, "Rafael Uribe Uribe", "Rafael Uribe"), chap = localidad == "Chapinero")
g_mapa <- ggplot() +
  geom_polygon(data = loc_pol, aes(lon, lat, group = grupo), fill = NA, color = g_claro, linewidth = .2) +
  geom_point(data = TR, aes(lon, lat, color = "Train"), size = .12, alpha = .35, stroke = 0) +
  geom_point(data = TE, aes(lon, lat, color = "Test"), size = .12, alpha = .6, stroke = 0) +
  geom_text_repel(data = loc_lbl, aes(lon, lat, label = lbl, fontface = ifelse(chap, "bold", "plain")), family = FAM, size = 1.45,
                  color = g_negro, bg.color = "white", bg.r = .15, box.padding = unit(.8, "pt"), point.padding = 0,
                  min.segment.length = Inf, max.overlaps = Inf, seed = 123) +
  scale_color_manual(values = c(Train = g_claro, Test = g_negro), breaks = c("Train", "Test"),
                     labels = c(paste0("Train (", num(nrow(TR), 0), ")"), paste0("Test (", num(nrow(TE), 0), ")"))) +
  guides(color = guide_legend(override.aes = list(size = 2, alpha = 1))) +
  coord_fixed(ratio = 1.003, xlim = c(-74.215, -73.985), ylim = c(4.53, 4.83), expand = FALSE) +
  theme_void(base_family = FAM, base_size = 9) +
  theme(legend.position = "bottom", legend.title = element_blank(), plot.margin = margin(0, 0, 0, 0),
        legend.text = element_text(color = g_negro), legend.key.size = unit(8, "pt"))
guarda(g_mapa, "f01_mapa", w = 2.3, h = 3.2)

g_compo <- ggplot(compo, aes(p, rasgo)) +
  geom_line(aes(group = rasgo), color = g_tenue, linewidth = 1.6) +
  geom_point(aes(shape = grupo, fill = grupo), size = 2.3, color = g_negro, stroke = .4) +
  scale_shape_manual(values = c(21, 24, 21)) + scale_fill_manual(values = c("white", g_medio, g_negro)) +
  scale_x_continuous(labels = label_percent(decimal.mark = ","), limits = c(0, 1), expand = expansion(mult = c(0, .03))) +
  labs(x = "Proporción de los anuncios", y = NULL) +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3))
guarda(g_compo + theme(legend.text = element_text(size = 7.5)), "f02_composicion", w = 2.45, h = 2.3)

# =============================================================================
# 3. Chapinero: caro y poco heterogéneo
# =============================================================================
cat("\n[G] Heterogeneidad\n")
TRd <- TR %>% mutate(lpm2 = log(price) - log_area, pm2 = price / exp(log_area))
het <- TRd %>% filter(!is.na(localidad)) %>% group_by(localidad) %>%
  summarise(n = n(), med = median(pm2), p10 = quantile(pm2, .1), p90 = quantile(pm2, .9), sd_l = sd(lpm2), .groups = "drop") %>%
  filter(n >= 100) %>% arrange(med) %>% mutate(localidad = factor(localidad, localidad), chap = localidad == "Chapinero")
print(het %>% arrange(sd_l))
sd_todo <- sd(TRd$lpm2); sd_chap <- het$sd_l[het$chap]
cifra("sdChap", num(sd_chap, 2)); cifra("sdTrain", num(sd_todo, 2))
cifra("rankSdChap", num(rank(het$sd_l)[het$chap], 0)); cifra("nLocHet", num(nrow(het), 0))
cifra("medPmChap", num(mill(het$med[het$chap]), 1)); cifra("medPmTrain", num(mill(median(TRd$pm2)), 1))
cifra("sdCBDTest", num(sd(TE$dist_cbd), 0)); cifra("sdCBDTrain", num(sd(TR$dist_cbd), 0))
cifra("sdEstTest", num(sd(TE$estrato_final), 2)); cifra("sdEstTrain", num(sd(TR$estrato_final), 2))

g_het <- ggplot(het, aes(y = localidad)) +
  geom_segment(aes(x = mill(p10), xend = mill(p90), yend = localidad, color = chap), linewidth = 1.1, lineend = "round") +
  geom_point(aes(x = mill(med), fill = chap), shape = 21, size = 2, color = g_negro, stroke = .4) +
  geom_text(aes(x = 17.5, label = numg(sd_l, 2), fontface = ifelse(chap, "bold", "plain")), family = FAM, size = 2.7,
            color = g_negro, hjust = 1) +
  annotate("text", x = 17.5, y = nrow(het) + .9, label = "DE del log", family = FAM, size = 2.4, hjust = 1, color = g_oscuro) +
  scale_color_manual(values = c(`FALSE` = g_claro, `TRUE` = g_negro), guide = "none") +
  scale_fill_manual(values = c(`FALSE` = "white", `TRUE` = g_negro), guide = "none") +
  scale_x_log10(breaks = c(1, 2, 4, 8), labels = lab_m) +
  coord_cartesian(xlim = c(.9, 17.5), ylim = c(1, nrow(het) + 1), clip = "off") +
  labs(x = "Precio por m² (millones, log): mediana y P10–P90", y = NULL) +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3))
guarda(g_het, "f03_heterogeneidad", w = 3.75, h = 2.55)

# =============================================================================
# 4. Chapinero sintético: rebalanceo TWCV y sus límites
# =============================================================================
cat("\n[B] Chapinero sintético\n")
vb <- vars_balanceo()
nom_vb <- c(estrato = "Estrato", apto = "Tipo de inmueble", habit = "Habitaciones", area = "Área (quintiles del test)",
            dist_cbd = "Distancia al CBD")
lv_bonitos <- list(apto = c("Casa", "Apto."), habit = c("1", "2", "3", "4+"), area = paste0("Q", 1:5), dist_cbd = paste0("Q", 1:5))
reb <- map_dfr(c("estrato", "dist_cbd", "habit", "apto"), function(nm) {
  f_tr <- vb[[nm]]$tr; f_te <- vb[[nm]]$te; lv <- levels(f_tr)
  tibble(var = nom_vb[nm], cat = lv,
         Train = as.vector(prop.table(table(f_tr))), `Train ponderado (TWCV)` = as.vector(tapply(W_TWCV, f_tr, sum))[seq_along(lv)],
         Test = as.vector(prop.table(table(f_te)))) %>%
    mutate(cat = if (nm %in% names(lv_bonitos)) lv_bonitos[[nm]] else cat, orden = row_number())
}) %>% mutate(across(c(Train, `Train ponderado (TWCV)`, Test), ~ replace_na(.x, 0))) %>%
  pivot_longer(c(Train, `Train ponderado (TWCV)`, Test), names_to = "serie", values_to = "p") %>%
  mutate(serie = factor(serie, c("Train", "Train ponderado (TWCV)", "Test")), var = factor(var, unique(var)))
g_reb <- ggplot(reb, aes(reorder(cat, orden), p, group = serie)) +
  geom_col(data = filter(reb, serie == "Test"), fill = g_tenue, width = .75) +
  geom_point(aes(shape = serie), size = 1.9, stroke = .5, color = g_negro, position = position_dodge(width = .55)) +
  scale_shape_manual(values = c(1, 16, 3), labels = c("Train", "Train ponderado (TWCV)", "Test (barras)")) +
  facet_wrap(~ var, nrow = 1, scales = "free_x") +
  scale_y_continuous(labels = label_percent(decimal.mark = ","), expand = expansion(mult = c(0, .05))) +
  labs(x = NULL, y = "Proporción")
guarda(g_reb, "f04_rebalanceo", w = 5.9, h = 1.65)

ess_tw <- ess(W_TWCV)
cifra("essTWCV", num(ess_tw, 0)); cifra("pEssTWCV", pct(ess_tw / nrow(TR), 0))
pl <- tibble(localidad = GRUPO, w = W_TWCV) %>% group_by(localidad) %>% summarise(n = n() / nrow(TR), w = sum(w), .groups = "drop")
cifra("pesoChap", pct(pl$w[pl$localidad == "Chapinero"])); cifra("pesoUsaq", pct(pl$w[pl$localidad == "Usaquén"]))
pl <- pl %>% mutate(loc = ifelse(rank(-w) <= 5, localidad, "Resto")) %>% group_by(loc) %>%
  summarise(n = sum(n), w = sum(w), .groups = "drop") %>% arrange(w) %>% mutate(loc = fct_relevel(factor(loc, loc), "Resto"))

# Distancia de predicción d: al anuncio de entrenamiento más cercano (se guarda en caché: tarda unos minutos)
f_d <- file.path(P$processed, "distancias_d_best.rds")   # caché (no se versiona)
if (!file.exists(f_d)) {
  d_val <- numeric(nrow(TR))
  for (f in FOLDS) d_val[f$evaluacion] <- dist_min(TR$lat[f$evaluacion], TR$lon[f$evaluacion], TR$lat[f$analisis], TR$lon[f$analisis], bloque = 300)
  saveRDS(list(val = d_val, test = dist_min(TEo$lat, TEo$lon, TR$lat, TR$lon, bloque = 300)), f_d)
}
dd <- readRDS(f_d)
cifra("dMedTest", num(median(dd$test), 0)); cifra("pTestDqui", pct(mean(dd$test < 500)))
cifra("pValDqui", pct(mean(dd$val < 500), 1)); cifra("dMedVal", num(median(dd$val), 0))
cat(sprintf("ESS %.0f | d test mediana %.0f m, <500 m %.1f%% | d validación mediana %.0f m, <500 m %.2f%%\n",
            ess_tw, median(dd$test), 100 * mean(dd$test < 500), median(dd$val), 100 * mean(dd$val < 500)))

g_pl <- ggplot(pl, aes(y = loc)) +
  geom_segment(aes(x = n, xend = w, yend = loc), color = g_claro, linewidth = .8) +
  geom_point(aes(x = n, shape = "Anuncios del train"), size = 2, color = g_negro, fill = "white") +
  geom_point(aes(x = w, shape = "Peso en el Chapinero sintético"), size = 2, color = g_negro, fill = g_negro) +
  scale_shape_manual(values = c(21, 21)) +
  guides(shape = guide_legend(override.aes = list(fill = c("white", g_negro)))) +
  scale_x_continuous(labels = label_percent(decimal.mark = ","), expand = expansion(mult = c(.02, .05))) +
  labs(x = "Proporción", y = NULL) +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3),
        legend.direction = "vertical")
dist_df <- bind_rows(tibble(d = dd$val, serie = "Validación (una localidad afuera, buffer 500 m)"),
                     tibble(d = dd$test, serie = "Test (vecino más cercano del train)"))
g_d <- ggplot(dist_df, aes(pmax(d, 1), linetype = serie)) +
  annotate("rect", xmin = 1, xmax = 500, ymin = 0, ymax = 1, fill = g_tenue) +
  annotate("text", x = 22, y = .93, label = "Sin anuncios de validación", family = FAM, size = 2.6, color = g_oscuro) +
  stat_ecdf(color = g_negro, linewidth = .5) +
  scale_linetype_manual(values = c("solid", "22")) +
  scale_x_log10(breaks = c(1, 10, 100, 500, 5000), labels = lab_m) +
  scale_y_continuous(labels = label_percent(decimal.mark = ",")) +
  labs(x = "Distancia de predicción d (metros, escala log)", y = "Acumulado") +
  theme(legend.direction = "vertical")
guarda(g_pl + g_d + plot_layout(widths = c(1, 1.25)), "f05_limites_sintetico", w = 5.9, h = 1.85)

# =============================================================================
# 5. El ensamble: pesos y resultado en Kaggle
# =============================================================================
cat("\n[C] Ensamble\n")
cor_te <- cor(log(comp_te)); cifra("corNNXGB", num(cor_te["m17", "m22"], 2))
cifra("difNNXGB", num(mill(mean(abs(comp_te[, "m17"] - comp_te[, "m22"]))), 0))
cifra("kPub", num(mill(K$pub), 1)); cifra("kPriv", num(mill(K$priv), 1)); cifra("kEst", num(mill(K$est), 1))
cifra("kCota", num(mill(K$cota), 1)); cifra("kNN", num(mill(K$m17), 1)); cifra("kXGB", num(mill(K$m22), 1))
cifra("kEN", num(mill(K$m14), 1)); cifra("kPubCompleto", num(K$pub, 2)); cifra("kPrivCompleto", num(K$priv, 2))
cifra("kGapPP", num(mill(K$priv - K$pub), 1)); cifra("kGanaNN", num(mill(K$m17 - K$pub), 1))

kag <- tribble(~etq, ~v, ~tipo,
  "Red neuronal STAR · 53%", K$m17, "Componente",
  "XGBoost con comparables · 40%", K$m22, "Componente",
  "Elastic net con texto · 7%", K$m14, "Componente",
  "Cota garantizada", K$cota, "Referencia",
  "Ensamble: estimado", K$est, "Referencia",
  "Ensamble: privado", K$priv, "Ensamble",
  "Ensamble: público", K$pub, "Ensamble") %>%
  mutate(etq = factor(etq, rev(etq)))
g_kag <- ggplot(kag, aes(mill(v), etq)) +
  geom_segment(aes(x = 150, xend = mill(v), yend = etq), color = g_tenue, linewidth = .8) +
  geom_point(aes(shape = tipo, color = tipo), size = 2.3, stroke = .6, fill = "white") +
  geom_text(aes(label = num(mill(v), 1)), nudge_x = .75, family = FAM, size = 2.7, hjust = 0, color = g_negro) +
  scale_shape_manual(values = c(Componente = 21, Referencia = 4, Ensamble = 16), guide = "none") +
  scale_color_manual(values = c(Componente = g_negro, Referencia = g_oscuro, Ensamble = acento), guide = "none") +
  scale_x_continuous(limits = c(150, 172), expand = expansion(mult = c(0, 0)), labels = lab_m) +
  labs(x = "MAE en el test (millones de pesos)", y = NULL) +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3),
        axis.text.y = element_text(color = g_negro, hjust = 0))
guarda(g_kag, "f06_kaggle", w = 3.65, h = 2.4)

# =============================================================================
# 6. Métricas de regresión (OOF aproximado)
# =============================================================================
cat("\n[D] Métricas\n")
metricas <- function(p, idx = rep(TRUE, length(y)), w = NULL) {
  yy <- y[idx]; pp <- p[idx]; ww <- if (is.null(w)) rep(1, length(yy)) else w[idx]; ww <- ww / sum(ww)
  e <- pp - yy; ape <- abs(e) / yy; ly <- log(yy)
  c(mae = sum(ww * abs(e)), rmse = sqrt(sum(ww * e^2)), mape = sum(ww * ape), mdape = median(ape), sesgo = sum(ww * e),
    p10 = sum(ww * (ape < .1)), p20 = sum(ww * (ape < .2)),
    r2 = 1 - sum(ww * (log(pp) - ly)^2) / sum(ww * (ly - sum(ww * ly))^2))
}
sens_top <- function(p, idx = rep(TRUE, length(y)), q = .9) {   # del decil real más caro, cuánto pone el modelo en su decil más caro
  yy <- y[idx]; pp <- p[idx]; top <- yy >= quantile(yy, q); mean(pp[top] >= quantile(pp, q))
}
M <- cbind(Total = metricas(ens_oof), Chapinero = metricas(ens_oof, ES_CHAP), TWCV = metricas(ens_oof, w = W_TWCV))
sens <- c(sens_top(ens_oof), sens_top(ens_oof, ES_CHAP), NA)
print(round(M, 3)); print(sens)
fila <- function(nom, v, f) paste(nom, paste(ifelse(is.na(v), "--", f(v)), collapse = " & "), sep = " & ")
fm <- function(x) num(mill(x), 1); fp <- function(x) paste0(num(100 * x, 1), "\\%")
tab_lineas <- c(
  "\\begin{tabular}{@{}lrrr@{}}", "\\toprule",
  " & Train completo & Chapinero (train) & Chapinero sintético \\\\",
  " & {\\footnotesize ($n = \\nTrain$)} & {\\footnotesize ($n = \\nChapTrain$)} & {\\footnotesize (TWCV, $n_{ef} = \\essTWCV$)} \\\\", "\\midrule",
  paste0(fila("MAE (millones)", M["mae", ], fm), " \\\\"),
  paste0(fila("Sesgo medio (millones)", M["sesgo", ], fm), " \\\\"),
  paste0(fila("Error porcentual mediano", M["mdape", ], fp), " \\\\"),
  paste0(fila("Con error $<10\\%$", M["p10", ], fp), " \\\\"),
  paste0(fila("Con error $<20\\%$", M["p20", ], fp), " \\\\"),
  paste0(fila("$R^2$ en logaritmos", M["r2", ], \(x) num(x, 2)), " \\\\"),
  paste0(fila("Sensibilidad del decil más caro", sens, fp), " \\\\"),
  "\\midrule",
  "\\textbf{MAE en Kaggle (millones)} & \\multicolumn{3}{r}{público \\textbf{\\kPub}\\quad privado \\textbf{\\kPriv}} \\\\",
  "\\bottomrule", "\\end{tabular}")
writeLines(tab_lineas, file.path(TAB, "metricas.tex"))
cifra("maeOOF", num(mill(M["mae", "Total"]), 1)); cifra("maeOOFChap", num(mill(M["mae", "Chapinero"]), 1))
cifra("maeOOFTW", num(mill(M["mae", "TWCV"]), 1)); cifra("sensTop", pct(sens[1]))
cifra("maeCompMvii", num(mill(mean(abs(comp_oof[, "m17"] - y))), 1)); cifra("maeCompMxxii", num(mill(mean(abs(comp_oof[, "m22"] - y))), 1))

# =============================================================================
# 7. Variables: modelo sustituto del ensamble en el test
# =============================================================================
cat("\n[E] Modelo sustituto\n")
cmp <- lee_csv_git(ENVIOS_MJ, "data/processed/comparables.csv")
cmp_te <- cmp %>% filter(muestra == "test") %>% slice(match(ids, property_id))
cmp_tr <- cmp %>% filter(muestra == "train") %>% slice(match(TR$property_id, property_id))
stopifnot(identical(cmp_te$property_id, ids), identical(cmp_tr$property_id, TR$property_id))
vc <- c("comp5", "comp_logdist5", "comp20", "comp_logdist20")
X_te <- cbind(matriz_arboles(TEo, vars = vars_sin()), as.matrix(cmp_te[vc]))   # 81 variables de D19
set.seed(123); ent <- sample(nrow(X_te), round(.8 * nrow(X_te)))
pr <- list(objective = "reg:squarederror", eta = .05, max_depth = 5, subsample = .8, colsample_bytree = .7, min_child_weight = 5, nthread = 1)
# Dos sustitutos: (a) log del precio, (b) log del precio por m2 sin el área (qué determina el valor del suelo)
sustituto <- function(y_s, X) {
  f <- xgb.train(pr, xgb.DMatrix(X[ent, ], label = y_s[ent]), nrounds = 800, verbose = 0)
  r2 <- 1 - sum((predict(f, xgb.DMatrix(X[-ent, ])) - y_s[-ent])^2) / sum((y_s[-ent] - mean(y_s[-ent]))^2)
  f <- xgb.train(pr, xgb.DMatrix(X, label = y_s), nrounds = 800, verbose = 0)
  imp <- xgb.importance(model = f) %>% as_tibble() %>%
    mutate(Feature = ifelse(Feature %in% c("lat", "lon", "lat_rot1", "lat_rot2"), "coordenadas", Feature)) %>%
    group_by(Feature) %>% summarise(Gain = sum(Gain), .groups = "drop") %>% arrange(desc(Gain))
  list(r2 = r2, imp = imp)
}
s_p <- sustituto(log(ens_te), X_te)
s_m <- sustituto(log(ens_te) - TEo$log_area, X_te[, !colnames(X_te) %in% c("log_area", "area_imputada", "area_texto")])
cat(sprintf("R2 del sustituto (20%% retenido): precio %.3f | precio por m2 %.3f\n", s_p$r2, s_m$r2))
print(head(s_p$imp, 10)); print(head(s_m$imp, 12))
imp <- s_m$imp   # el de precio por m2 define las variables "principales" para la sección de presencia
cifra("rDosSust", num(s_p$r2, 2)); cifra("rDosSustM", num(s_m$r2, 2))
cifra("gainArea", pct(s_p$imp$Gain[s_p$imp$Feature == "log_area"]))
cifra("gainCompM", pct(sum(s_m$imp$Gain[str_detect(s_m$imp$Feature, "^comp")])))
cifra("gainEstM", pct(s_m$imp$Gain[s_m$imp$Feature == "estrato_final"]))
panel_imp <- function(s, titulo, n = 8) {
  head(s$imp, n) %>% mutate(lbl = etq(Feature), lbl = factor(lbl, rev(lbl)), es_comp = factor(str_detect(Feature, "^comp"), c(FALSE, TRUE))) %>%
    ggplot(aes(Gain, lbl)) +
    geom_col(aes(fill = es_comp), width = .62) +
    geom_text(aes(label = paste0(num(100 * Gain, 0), "%")), nudge_x = .012, hjust = 0, family = FAM, size = 2.5, color = g_negro) +
    scale_fill_manual(values = c(`TRUE` = g_negro, `FALSE` = g_claro), breaks = c("FALSE", "TRUE"),
                      labels = c("Atributos y ubicación", "Comparables (control sintético)"), drop = FALSE) +
    scale_x_continuous(labels = label_percent(), expand = expansion(mult = c(0, .2)), breaks = c(0, .25, .5)) +
    labs(x = "Ganancia", y = NULL, subtitle = sprintf("%s (R² %s)", titulo, num(s$r2, 2))) +
    theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3),
          axis.text.y = element_text(color = g_negro), plot.subtitle = element_text(face = "italic", size = 8.5, color = g_negro))
}
g_imp <- (panel_imp(s_p, "Precio") | panel_imp(s_m, "Precio por m²")) + plot_layout(guides = "collect") &
  theme(legend.position = "bottom")
guarda(g_imp, "f07_importancia", w = 5.9, h = 1.9)

# =============================================================================
# 8. ¿Están presentes esas variables en la validación?
# =============================================================================
cat("\n[F] Presencia en la validación\n")
X_tr_cmp <- cbind(as.data.frame(TR), cmp_tr[vc]); X_te_cmp <- cbind(as.data.frame(TEo), cmp_te[vc])
# Variables continuas u ordinales que encabezan alguno de los dos sustitutos (las dummies de texto no tienen "rango")
vars_f <- c("log_area", "banos_final", "bedrooms", "estrato_final", "comp20", "comp5", "dist_cerros", "dist_cbd")
stopifnot(all(vars_f %in% c(head(s_p$imp$Feature, 8), head(s_m$imp$Feature, 8), "dist_cbd")))
pres <- map_dfr(vars_f, function(v) {
  xtr <- X_tr_cmp[[v]]; xte <- X_te_cmp[[v]]; ok <- !is.na(xtr)
  sdp <- sd(c(xtr, xte), na.rm = TRUE)
  mw <- sum(W_TWCV[ok] * xtr[ok]) / sum(W_TWCV[ok])
  lo <- quantile(xte, .1, na.rm = TRUE); hi <- quantile(xte, .9, na.rm = TRUE)
  tibble(var = v, smd_train = (mean(xte, na.rm = TRUE) - mean(xtr, na.rm = TRUE)) / sdp,
         smd_twcv = (mean(xte, na.rm = TRUE) - mw) / sdp,
         en_rango = mean(xtr[ok] >= lo & xtr[ok] <= hi))
})
print(pres)
# Conjunto: anuncios del train que caen dentro del rango P10–P90 del test en TODAS las variables principales a la vez
dentro <- Reduce(`&`, map(vars_f, function(v) { x <- X_tr_cmp[[v]]; xt <- X_te_cmp[[v]]
  r <- quantile(xt, c(.1, .9), na.rm = TRUE); is.na(x) | (x >= r[1] & x <= r[2]) }))
cifra("pTrainCaja", pct(mean(dentro), 1)); cifra("nTrainCaja", num(sum(dentro), 0)); cifra("nVarsCaja", num(length(vars_f), 0))
cifra("pCajaChap", pct(mean(ES_CHAP[dentro])))
cat(sprintf("Train dentro de la 'caja' P10-P90 del test en %d variables: %.1f%% (%d anuncios; %.0f%% de ellos en Chapinero)\n",
            length(vars_f), 100 * mean(dentro), sum(dentro), 100 * mean(ES_CHAP[dentro])))
pres_l <- pres %>% mutate(lbl = etq(var), lbl = factor(lbl, lbl[order(abs(smd_train))]))
g_smd <- ggplot(pres_l, aes(y = lbl)) +
  geom_vline(xintercept = 0, color = g_oscuro, linewidth = .3) +
  annotate("rect", xmin = -.1, xmax = .1, ymin = -Inf, ymax = Inf, fill = g_tenue) +
  geom_segment(aes(x = smd_train, xend = smd_twcv, yend = lbl), color = g_medio, linewidth = .5,
               arrow = arrow(length = unit(3, "pt"), type = "closed")) +
  geom_point(aes(x = smd_train, shape = "Train"), size = 2, color = g_negro, fill = "white") +
  geom_point(aes(x = smd_twcv, shape = "Train ponderado (TWCV)"), size = 1.6, color = g_negro, fill = g_negro) +
  scale_shape_manual(values = c(21, 21)) +
  guides(shape = guide_legend(override.aes = list(fill = c("white", g_negro)))) +
  labs(x = "Diferencia estandarizada (test − train)", y = NULL) +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3),
        axis.text.y = element_text(color = g_negro))
g_rango <- ggplot(pres_l, aes(en_rango, lbl)) +
  geom_col(fill = g_claro, width = .6) +
  geom_text(aes(label = paste0(num(100 * en_rango, 0), "%")), nudge_x = .02, hjust = 0, family = FAM, size = 2.6) +
  scale_x_continuous(labels = label_percent(), limits = c(0, 1.12), breaks = c(0, .5, 1)) +
  labs(x = "Train en el P10–P90 del test", y = NULL) +
  theme(axis.text.y = element_blank(), panel.grid.major.y = element_blank())
guarda(g_smd + g_rango + plot_layout(widths = c(2.1, 1)), "f08_presencia", w = 5.9, h = 1.85)

# Distancia a los comparables: el train (CV aleatoria) encuentra vecinos mucho más cerca que el test
dc <- bind_rows(tibble(d = expm1(cmp_tr$comp_logdist5), serie = "Train: comparables sin sí mismo (como en la CV aleatoria)"),
                tibble(d = expm1(cmp_te$comp_logdist5), serie = "Test"))
cifra("dCompTrain", num(median(expm1(cmp_tr$comp_logdist5)), 0)); cifra("dCompTest", num(median(expm1(cmp_te$comp_logdist5)), 0))
# Error del XGB con comparables (m22, OOF de la CV aleatoria) según la distancia a sus comparables
cortes <- c(-Inf, 30, 100, 300, Inf); etq_c <- c("< 30 m", "30–100 m", "100–300 m", "> 300 m")
err_d <- tibble(d = expm1(cmp_tr$comp_logdist5), ape = abs(comp_oof[, "m22"] - y) / y, ape_e = abs(ens_oof - y) / y) %>%
  mutate(b = cut(d, cortes, etq_c)) %>% group_by(b) %>% summarise(m22 = mean(ape), ens = mean(ape_e), n_tr = n() / nrow(TR), .groups = "drop") %>%
  left_join(tibble(b = cut(expm1(cmp_te$comp_logdist5), cortes, etq_c)) %>% count(b) %>% mutate(n_te = n / sum(n)) %>% select(-n), by = "b")
print(err_d)
cifra("pTrMenosTreinta", pct(err_d$n_tr[1])); cifra("pTeMenosTreinta", pct(err_d$n_te[1]))
cifra("mapeXGBcerca", pct(err_d$m22[1])); cifra("mapeXGBlejos", pct(err_d$m22[3]))
g_dc <- ggplot(dc, aes(pmax(d, 1), linetype = serie)) + stat_ecdf(color = g_negro, linewidth = .5) +
  scale_linetype_manual(values = c("solid", "22"), breaks = c("Train: comparables sin sí mismo (como en la CV aleatoria)", "Test"),
                        labels = c("Train (CV aleatoria)", "Test")) +
  scale_x_log10(breaks = c(1, 10, 30, 100, 300, 1000), labels = lab_m) +
  scale_y_continuous(labels = label_percent(decimal.mark = ",")) +
  labs(x = "Distancia media a los 5 comparables (m, log)", y = "Acumulado")
err_l <- err_d %>% select(b, Train = n_tr, Test = n_te) %>% pivot_longer(-b) %>% mutate(name = factor(name, c("Train", "Test")))
g_errd <- ggplot(err_l, aes(b, value)) +
  geom_col(aes(fill = name), position = position_dodge(.72), width = .68) +
  geom_text(data = err_d, aes(b, .72, label = paste0(num(100 * m22, 0), "%")), family = FAM, size = 2.7, inherit.aes = FALSE) +
  annotate("text", x = .45, y = .80, label = "Error medio del XGB con comparables:", family = FAM, size = 2.5, hjust = 0, color = g_oscuro) +
  scale_fill_manual(values = c(Train = g_claro, Test = g_negro)) +
  scale_y_continuous(labels = label_percent(), limits = c(0, .84), breaks = seq(0, .6, .2), expand = expansion(mult = c(0, 0))) +
  labs(x = "Distancia a los comparables", y = "Proporción de anuncios")
guarda(g_dc + g_errd + plot_layout(widths = c(1, 1.2)), "f09_comparables", w = 5.9, h = 1.85)

# =============================================================================
# 9. Dónde falla: contracción hacia la media en los caros
# =============================================================================
cat("\n[H] Dónde falla\n")
de <- tibble(y, p = ens_oof, w = W_TWCV, chap = ES_CHAP)
dec_tot <- de %>% mutate(g = ntile(y, 10)) %>% group_by(g) %>%
  summarise(ymed = median(y), sesgo = mean(p - y), mape = mean(abs(p - y) / y), .groups = "drop") %>% mutate(panel = "Train completo (deciles)")
dec_chap <- de %>% filter(chap) %>% mutate(g = ntile(y, 5)) %>% group_by(g) %>%
  summarise(ymed = median(y), sesgo = mean(p - y), mape = mean(abs(p - y) / y), .groups = "drop") %>% mutate(panel = "Chapinero, train (quintiles)")
print(dec_tot); print(dec_chap)
cifra("sesgoDecTop", num(mill(dec_tot$sesgo[10]), 0)); cifra("sesgoDecBot", num(mill(dec_tot$sesgo[1]), 0))
cifra("sesgoChapTop", num(mill(dec_chap$sesgo[5]), 0)); cifra("ymedChapTop", num(mill(dec_chap$ymed[5]), 0))
cifra("mapeChapTop", pct(dec_chap$mape[5]))
cifra("pTestTecho", pct(mean(ens_te >= 1.5e9), 1)); cifra("pChapTecho", pct(mean(y[ES_CHAP] >= 1.5e9), 1))
dec_all <- bind_rows(dec_tot, dec_chap) %>% mutate(panel = factor(panel, unique(panel)))
g_dec <- ggplot(dec_all, aes(factor(g), mill(sesgo))) +
  geom_hline(yintercept = 0, color = g_oscuro, linewidth = .3) +
  geom_col(aes(fill = sesgo < 0), width = .7) +
  geom_text(aes(label = numg(mill(sesgo), 0), vjust = ifelse(sesgo < 0, 1.3, -.4)), family = FAM, size = 2.4) +
  scale_fill_manual(values = c(`FALSE` = g_claro, `TRUE` = acento), guide = "none") +
  scale_y_continuous(expand = expansion(mult = .15), labels = lab_m) +
  facet_wrap(~ panel, scales = "free_x", nrow = 1) +
  labs(x = "Grupo de precio observado (1 = más barato)", y = "Predicho − observado (millones)")
chap_df <- de %>% filter(chap)
g_po <- ggplot(chap_df, aes(mill(y), mill(p))) +
  geom_abline(slope = 1, intercept = 0, linetype = "22", color = g_oscuro, linewidth = .4) +
  geom_point(shape = 1, size = 1.1, stroke = .35, color = g_negro, alpha = .8) +
  geom_smooth(method = "loess", se = FALSE, color = acento, linewidth = .6, span = .9, formula = y ~ x) +
  scale_x_log10(breaks = c(300, 500, 800, 1300), labels = lab_m) + scale_y_log10(breaks = c(300, 500, 800, 1300), labels = lab_m) +
  coord_fixed(xlim = c(290, 1700), ylim = c(290, 1700)) +
  labs(x = "Observado (millones, log)", y = "Predicho (millones, log)") +
  theme(panel.grid.major.x = element_line(color = g_tenue, linewidth = .3))
guarda(g_po + g_dec + plot_layout(widths = c(1, 2.2)), "f10_donde_falla", w = 5.9, h = 1.85)

# Error por estrato y tipo en el Chapinero sintético
seg <- de %>% mutate(est = pmin(pmax(round(TR$estrato_final), 3), 6), tipo = ifelse(TR$es_apto == 1, "Apto.", "Casa")) %>%
  group_by(est) %>% summarise(peso = sum(w), mape = sum(w * abs(p - y) / y) / sum(w), sesgo = sum(w * (p - y)) / sum(w), .groups = "drop")
print(seg)

# En el test: dónde discrepan los componentes (incertidumbre sin conocer el precio)
desac <- tibble(lon = TEo$lon, lat = TEo$lat, s = apply(log(comp_te), 1, sd), est = round(TEo$estrato_final), area = exp(TEo$log_area),
                pred = ens_te)
cifra("desacMed", pct(median(desac$s), 1)); cifra("desacPnov", pct(quantile(desac$s, .9), 1))
des_seg <- desac %>% mutate(q = ntile(pred, 5)) %>% group_by(q) %>% summarise(s = median(s), .groups = "drop"); print(des_seg)
cifra("desacTopQ", pct(des_seg$s[5], 1)); cifra("desacBotQ", pct(des_seg$s[1], 1))
# Compresión: las predicciones del test son menos dispersas que los precios observados en Chapinero
dist_p <- bind_rows(tibble(v = y[ES_CHAP], serie = "Chapinero, train: precio observado"),
                    tibble(v = ens_oof[ES_CHAP], serie = "Chapinero, train: predicción OOF"),
                    tibble(v = ens_te, serie = "Test: predicción del ensamble")) %>%
  mutate(serie = factor(serie, unique(serie)))
cifra("sdLogObsChap", num(sd(log(y[ES_CHAP])), 2)); cifra("sdLogPredTest", num(sd(log(ens_te)), 2))
cifra("sdLogPredChap", num(sd(log(ens_oof[ES_CHAP])), 2))
cifra("pObsChapMil", pct(mean(y[ES_CHAP] >= 1.2e9))); cifra("pPredTestMil", pct(mean(ens_te >= 1.2e9)))
g_comp <- ggplot(dist_p, aes(mill(v), linetype = serie, color = serie)) +
  geom_density(linewidth = .55, adjust = 1.1, key_glyph = "path") +
  scale_linetype_manual(values = c("solid", "22", "solid")) + scale_color_manual(values = c(g_medio, g_negro, g_negro)) +
  scale_x_log10(breaks = c(300, 500, 800, 1200, 1650), labels = lab_m) +
  labs(x = "Precio (millones de pesos, escala log)", y = "Densidad") +
  theme(axis.text.y = element_blank(), legend.direction = "vertical")
g_des_area <- desac %>% mutate(q = ntile(pred, 5)) %>% ggplot(aes(factor(q), s)) +
  geom_boxplot(outlier.shape = NA, width = .55, fill = "white", color = g_negro, linewidth = .3) +
  scale_y_continuous(labels = label_percent(accuracy = 1)) + coord_cartesian(ylim = c(0, quantile(desac$s, .97))) +
  labs(x = "Quintil del precio predicho (test)", y = "Desacuerdo entre componentes")
guarda(g_comp + g_des_area + plot_layout(widths = c(1.3, 1)), "f11_compresion_test", w = 5.9, h = 1.85)

# =============================================================================
# 10. Por qué falla el sintético: de la validación a Kaggle
# =============================================================================
cat("\n[I] Brecha validación-Kaggle\n")
br <- tribble(~modelo, ~cv, ~twcv, ~kag, ~esquema,
  "Red neuronal STAR", mean(abs(comp_oof[, "m17"] - y)), sum(W_TWCV * abs(comp_oof[, "m17"] - y)), K$m17, "CV por localidad",
  "XGBoost con comparables", mean(abs(comp_oof[, "m22"] - y)), sum(W_TWCV * abs(comp_oof[, "m22"] - y)), K$m22, "CV aleatoria",
  "Elastic net con texto", mean(abs(comp_oof[, "m14"] - y)), sum(W_TWCV * abs(comp_oof[, "m14"] - y)), K$m14, "CV por localidad",
  "Ensamble óptimo", mean(abs(ens_oof - y)), sum(W_TWCV * abs(ens_oof - y)), K$pub, "Mezcla")
print(br %>% mutate(across(c(cv, twcv, kag), ~ round(mill(.x), 1))))
cifra("brechaEns", num(mill(K$pub - br$twcv[4]), 0)); cifra("brechaNN", num(mill(K$m17 - br$twcv[1]), 0))
cifra("brechaXGB", num(mill(K$m22 - br$twcv[2]), 0)); cifra("twcvEns", num(mill(br$twcv[4]), 1))
cifra("twcvNN", num(mill(br$twcv[1]), 1)); cifra("twcvXGB", num(mill(br$twcv[2]), 1))
vk <- lee_csv_git(PRES_MJ, "reports/02_modelos/tables/validacion_sintetica_vs_kaggle.csv")
cifra("sesgoCVloc", num(-vk$sesgo_medio_M[vk$validacion == "mae_total"], 0)); cifra("sesgoCVtw", num(-vk$sesgo_medio_M[vk$validacion == "mae_twcv"], 0))
br_l <- br %>% mutate(modelo = paste0(modelo, "\n", esquema)) %>% pivot_longer(c(cv, twcv, kag), names_to = "medida", values_to = "v") %>%
  mutate(medida = factor(medida, c("cv", "twcv", "kag"), c("Validación cruzada", "Chapinero sintético (TWCV)", "Kaggle (público)")),
         modelo = factor(modelo, rev(unique(modelo))))
g_br <- ggplot(br_l, aes(mill(v), modelo)) +
  geom_line(aes(group = modelo), color = g_claro, linewidth = .8) +
  geom_point(aes(shape = medida), size = 2.2, color = g_negro, fill = "white", stroke = .5) +
  scale_shape_manual(values = c(21, 16, 15)) +
  scale_x_continuous(labels = lab_m, breaks = seq(80, 170, 20)) +
  labs(x = "MAE (millones de pesos)", y = NULL) +
  theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3),
        axis.text.y = element_text(color = g_negro, hjust = 0, lineheight = .9))
guarda(g_br, "f12_brecha", w = 3.55, h = 2.45)

# =============================================================================
# 11. Macros de cifras
# =============================================================================
writeLines(c("% Generado por code/95b_presentacion_best.R. No editar a mano.",
             sprintf("\\newcommand{\\%s}{%s}", names(cifras), unlist(cifras))), file.path(TAB, "cifras.tex"))
cat("\nCifras:\n"); walk2(names(cifras), cifras, ~ cat(sprintf("  %-16s %s\n", .x, .y)))
cat("Listo.\n")
