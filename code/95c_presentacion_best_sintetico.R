# =============================================================================
# 95c_presentacion_best_sintetico.R - Sección 11 de la presentación best_equipo_04: por qué no funcionaron las
# variables del Chapinero sintético (TWCV, D16, D29). Diapositivas 15 a 17.
# Complementa a 95b_presentacion_best.R: repite su preparación de datos (secciones 1 y estilo) y solo agrega la
# sección 11, con sus propias cifras en cifras_vs.tex (aparte de cifras.tex para no repetir macros de LaTeX).
# No se vuelve a entrenar ningún modelo de predicción.
# Entradas (D28): OOF, envíos y comparables tal como estaban cuando se calificaron en Kaggle, leídos de commits
#   fijos con desde_git(): ENVIOS_MJ (validacion-sintetica) y ENVIOS_REDES (redes-neuronales).
# Salidas: output/figures/03_presentacion/best_equipo_04/f13_variables_explican.pdf, f14_gemelo.pdf,
#          f15_ablacion_pesos.pdf y output/tables/03_presentacion/best_equipo_04/cifras_vs.tex
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
vb <- vars_balanceo()
nom_vb <- c(estrato = "Estrato", apto = "Tipo de inmueble", habit = "Habitaciones", area = "Área (quintiles del test)",
            dist_cbd = "Distancia al CBD")
cmp <- lee_csv_git(ENVIOS_MJ, "data/processed/comparables.csv")
cmp_te <- cmp %>% filter(muestra == "test") %>% slice(match(ids, property_id))
cmp_tr <- cmp %>% filter(muestra == "train") %>% slice(match(TR$property_id, property_id))
stopifnot(identical(cmp_te$property_id, ids), identical(cmp_tr$property_id, TR$property_id))
# =============================================================================
# 11. ¿Por qué no funcionaron las variables del Chapinero sintético? (D16, D29)
# =============================================================================
# Tres preguntas, sin volver a entrenar: (a) qué tanto explican las 5 variables de balanceo el precio y el error
# fuera de muestra, frente a la ubicación; (b) si, con las mismas 5 variables, Chapinero vale más que su "gemelo"
# del resto de la ciudad (un efecto de nivel que el repeso no ve); (c) qué pasa al repesar con cada variable sola
# o al agregar otras (cerros, comparables, baños): cuánto se acerca la validación a Kaggle y cuánto cuesta en ESS.
cat("\n[J] Variables del Chapinero sintético\n")
e_m17 <- comp_oof[, "m17"] - y # error con signo de la NN STAR (OOF por localidad con buffer), en pesos
ae_m17 <- abs(e_m17)
corta_te <- function(x_tr, x_te, k = 5) { # cortes en los cuantiles del test, como en vars_balanceo()
  br <- unique(quantile(x_te, 0:k / k, na.rm = TRUE))
  br[1] <- -Inf
  br[length(br)] <- Inf
  list(tr = cut(x_tr, br), te = cut(x_te, br))
}
extra <- list(
  cerros = corta_te(TR$dist_cerros, TE$dist_cerros),
  comparables = corta_te(cmp_tr$comp20, cmp$comp20[match(TE$property_id, cmp$property_id)]),
  banos = list(
    tr = cut(TR$banos_final, c(-Inf, 1, 2, 3, Inf)),
    te = cut(TE$banos_final, c(-Inf, 1, 2, 3, Inf))
  )
)
nom_x <- c(
  nom_vb, cerros = "Distancia a los cerros", comparables = "Precio/m² de los comparables",
  banos = "Baños", localidad = "Localidad"
)

# (a) Qué explica cada variable: R² de un ANOVA de una vía (log del precio; error absoluto de la red)
r2 <- function(v, f) summary(lm(v ~ f))$r.squared
facs <- c(map(vb, "tr"), map(extra, "tr"), list(localidad = factor(GRUPO)))
expl <- imap_dfr(facs, \(f, nm) tibble(
  var = nm, lbl = nom_x[nm],
  tipo = case_when(nm %in% names(vb) ~ "En el Chapinero sintético", nm == "localidad" ~ "Ubicación (fold)",
                   TRUE ~ "Fuera del Chapinero sintético"),
  r2_precio = r2(Y, f), r2_error = r2(ae_m17, f)
))
print(expl %>% mutate(across(starts_with("r2"), ~ round(.x, 3))))
cifra("rDosErrLoc", pct(expl$r2_error[expl$var == "localidad"], 1))
cifra("rDosErrCinco", pct(r2(ae_m17, interaction(map(vb, "tr"), drop = TRUE)), 1))
cifra("rDosPrecioCinco", pct(r2(Y, interaction(map(vb, "tr"), drop = TRUE)), 0))
cifra("rDosErrMaxVar", pct(max(expl$r2_error[expl$var %in% names(vb)]), 1))
cifra("varErrMax", nom_x[expl$var[expl$var %in% names(vb)][which.max(expl$r2_error[expl$var %in% names(vb)])]])

g_expl <- expl %>%
  pivot_longer(c(r2_precio, r2_error), names_to = "medida", values_to = "r2") %>%
  mutate(
    medida = factor(medida, c("r2_precio", "r2_error"), c("Explica el precio (log)", "Explica el error de la red")),
    lbl = factor(lbl, expl$lbl[order(expl$tipo != "En el Chapinero sintético", expl$r2_precio)]),
    tipo = factor(tipo, c("En el Chapinero sintético", "Fuera del Chapinero sintético", "Ubicación (fold)"))
  ) %>%
  ggplot(aes(r2, lbl)) +
  geom_col(aes(fill = tipo), width = .62) +
  geom_text(aes(label = paste0(num(100 * r2, 0), "%")), nudge_x = .01, hjust = 0, family = FAM, size = 2.4) +
  facet_wrap(~medida, scales = "free_x") +
  scale_fill_manual(values = c(g_negro, g_claro, acento)) +
  scale_x_continuous(labels = label_percent(), expand = expansion(mult = c(0, .25))) +
  labs(x = "R² de un ANOVA de una vía (train)", y = NULL) +
  theme(
    panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3),
    axis.text.y = element_text(color = g_negro)
  )
guarda(g_expl, "f13_variables_explican", w = 5.9, h = 2.15)

# (b) El gemelo sintético: con las mismas 5 variables, ¿cuánto vale Chapinero frente al resto?
lpm2 <- Y - TR$log_area
celda <- interaction(map(vb, "tr"), drop = TRUE)
fit_g <- lm(lpm2 ~ celda + ES_CHAP)
prima <- exp(coef(fit_g)[["ES_CHAPTRUE"]]) - 1
cifra("primaChap", pct(prima, 0))
cel2 <- interaction(vb$estrato$tr, vb$area$tr, drop = TRUE) # celdas más gruesas, para la figura
gem <- tibble(celda = cel2, chap = ES_CHAP, pm2 = exp(lpm2) / 1e6) %>%
  group_by(celda, chap) %>%
  summarise(n = n(), med = median(pm2), .groups = "drop") %>%
  pivot_wider(names_from = chap, values_from = c(n, med)) %>%
  filter(n_TRUE >= 8, n_FALSE >= 8)
cifra("pCeldasArriba", pct(mean(gem$med_TRUE > gem$med_FALSE), 0)); cifra("nCeldas", num(nrow(gem), 0))

# Sesgo de la red: Chapinero real (train) frente a su versión sintética, con y sin los anuncios de Chapinero
w_sin <- W_TWCV * !ES_CHAP
w_sin <- w_sin / sum(w_sin)
ses <- tribble(
  ~serie, ~sesgo, ~mae,
  "Chapinero real\n(307 anuncios del train)", mean(e_m17[ES_CHAP]), mean(ae_m17[ES_CHAP]),
  "Chapinero sintético\n(TWCV)", sum(W_TWCV * e_m17), sum(W_TWCV * ae_m17),
  "Sintético sin los anuncios\nde Chapinero", sum(w_sin * e_m17), sum(w_sin * ae_m17)
) %>% mutate(serie = factor(serie, rev(serie)))
print(ses %>% mutate(across(c(sesgo, mae), ~ round(mill(.x), 1))))
cifra("sesgoChapReal", num(mill(ses$sesgo[1]), 0)); cifra("sesgoSint", num(mill(ses$sesgo[2]), 0))
cifra("sesgoSintSin", num(mill(ses$sesgo[3]), 0)); cifra("maeChapReal", num(mill(ses$mae[1]), 0))
cifra("maeSint", num(mill(ses$mae[2]), 0)); cifra("maeSintSin", num(mill(ses$mae[3]), 0))
cifra("pesoChapSint", pct(sum(W_TWCV[ES_CHAP]), 0))

lim_g <- range(c(gem$med_TRUE, gem$med_FALSE)) * c(.9, 1.1)
g_gem <- ggplot(gem, aes(med_FALSE, med_TRUE)) +
  geom_abline(slope = 1, intercept = 0, linetype = "22", color = g_oscuro, linewidth = .4) +
  geom_point(aes(size = n_TRUE), shape = 21, fill = acento, color = "white", stroke = .3) +
  scale_size_area(max_size = 4, guide = "none") +
  scale_x_log10(labels = lab_m) + scale_y_log10(labels = lab_m) +
  coord_fixed(xlim = lim_g, ylim = lim_g) +
  labs(x = "Resto de la ciudad: mediana (M/m²)", y = "Chapinero: mediana (M/m²)") +
  theme(panel.grid.major.x = element_line(color = g_tenue, linewidth = .3))
g_ses <- ses %>%
  pivot_longer(c(sesgo, mae), names_to = "m", values_to = "v") %>%
  mutate(m = factor(m, c("sesgo", "mae"), c("Sesgo medio (predicho − observado)", "MAE"))) %>%
  ggplot(aes(mill(v), serie)) +
  geom_vline(xintercept = 0, color = g_oscuro, linewidth = .3) +
  geom_col(aes(fill = serie), width = .6) +
  geom_text(aes(label = numg(mill(v), 0), hjust = ifelse(v < 0, 1.15, -.15)), family = FAM, size = 2.5) +
  facet_wrap(~m, scales = "free_x") +
  scale_fill_manual(values = c(g_claro, g_medio, g_negro), guide = "none") +
  scale_x_continuous(labels = lab_m, expand = expansion(mult = .28)) +
  labs(x = "Millones de pesos (red neuronal STAR, OOF)", y = NULL) +
  theme(
    panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(color = g_tenue, linewidth = .3),
    axis.text.y = element_text(color = g_negro, hjust = 0, lineheight = .9)
  )
guarda(g_gem + g_ses + plot_layout(widths = c(1, 2.1)), "f14_gemelo", w = 5.9, h = 2)

# (c) Ablación: repesar con cada variable, con las 5 y con más. ¿Se acerca a Kaggle? ¿Cuánto cuesta en ESS?
kg <- lee_csv(file.path(P$models, "kaggle_scores.csv")) %>%
  group_by(modelo) %>%
  summarise(kaggle = min(public_score), .groups = "drop")
oof_g <- bind_cols(oof_main, oof_rama[setdiff(names(oof_rama), names(oof_main))])
excluye <- c("m22_xgb_comparables_m2") # CV aleatoria: no es comparable con la validación por localidad
mods_g <- setdiff(intersect(kg$modelo, names(oof_g)), excluye)
err_g <- sapply(mods_g, \(m) abs(y - recorta(exp(oof_g[[m]]))))
kag_g <- kg$kaggle[match(mods_g, kg$modelo)]
cifra("nModKaggle", num(length(mods_g), 0))
esquemas <- c(
  list(`Sin pesos` = NULL),
  map(set_names(names(vb)), \(nm) vb[nm]),
  list(
    `Las 5 (TWCV)` = vb,
    `5 + cerros` = c(vb, extra["cerros"]),
    `5 + comparables` = c(vb, extra["comparables"]),
    `5 + cerros + comparables + baños` = c(vb, extra)
  )
)
abl <- imap_dfr(esquemas, function(v, nm) {
  w <- if (is.null(v)) rep(1 / nrow(TR), nrow(TR)) else encoge(calcula_twcv(v))
  mae_w <- as.vector(crossprod(w, err_g))
  tibble(
    esquema = nm, n_vars = if (is.null(v)) 0L else length(v), ess = ess(w),
    optimismo = mean(kag_g - mae_w), spearman = cor(mae_w, kag_g, method = "spearman"),
    mae_m17 = sum(w * ae_m17), peso_chap = sum(w[ES_CHAP])
  )
}) %>% mutate(lbl = recode(esquema, !!!nom_vb))
print(abl %>% mutate(across(c(optimismo, mae_m17), ~ round(mill(.x), 1)), across(c(spearman, peso_chap), ~ round(.x, 2))))
ref_chap <- tibble(optimismo = mean(kag_g - colMeans(err_g[ES_CHAP, , drop = FALSE])),
                   spearman = cor(colMeans(err_g[ES_CHAP, , drop = FALSE]), kag_g, method = "spearman"))
fila_abl <- \(nm) abl[abl$esquema == nm, ]
cifra("optSinPesos", num(mill(fila_abl("Sin pesos")$optimismo), 0))
cifra("optCinco", num(mill(fila_abl("Las 5 (TWCV)")$optimismo), 0))
cifra("optTodas", num(mill(fila_abl("5 + cerros + comparables + baños")$optimismo), 0))
cifra("essTodas", num(fila_abl("5 + cerros + comparables + baños")$ess, 0))
cifra("optChapTrain", num(mill(ref_chap$optimismo), 0))
cifra("spSinPesos", num(fila_abl("Sin pesos")$spearman, 2)); cifra("spCinco", num(fila_abl("Las 5 (TWCV)")$spearman, 2))
cifra("spTodas", num(fila_abl("5 + cerros + comparables + baños")$spearman, 2))
una <- abl %>% filter(n_vars == 1) %>% slice_min(optimismo, n = 1, with_ties = FALSE)
cifra("varUnaMejor", una$lbl); cifra("optUnaMejor", num(mill(una$optimismo), 0))

g_abl <- abl %>%
  mutate(grupo = case_when(n_vars <= 1 ~ "Una variable o ninguna", n_vars == 5 ~ "Las 5 del Chapinero sintético",
                           TRUE ~ "Las 5 y más variables"),
         grupo = factor(grupo, c("Una variable o ninguna", "Las 5 del Chapinero sintético", "Las 5 y más variables"))) %>%
  ggplot(aes(ess, mill(optimismo))) +
  geom_hline(yintercept = 0, color = g_oscuro, linewidth = .3) +
  geom_hline(yintercept = mill(ref_chap$optimismo), linetype = "22", color = g_medio, linewidth = .35) +
  annotate("text", x = nrow(TR) * .95, y = mill(ref_chap$optimismo), label = "Solo los 307 de Chapinero",
           family = FAM, size = 2.3, vjust = -.5, hjust = 1, color = g_medio) +
  geom_point(aes(shape = grupo), size = 2.1, color = g_negro, fill = "white", stroke = .5) +
  geom_text_repel(aes(label = lbl), family = FAM, size = 2.2, color = g_oscuro, box.padding = unit(2.5, "pt"),
                  min.segment.length = 0, segment.size = .2, max.overlaps = Inf, seed = 123) +
  scale_shape_manual(values = c(21, 16, 15)) +
  scale_x_log10(labels = lab_m, breaks = c(300, 1000, 3000, 10000, 38000)) +
  scale_y_continuous(labels = lab_m, expand = expansion(mult = c(.05, .12))) +
  labs(x = "Tamaño efectivo de la muestra (anuncios, escala log)",
       y = "Kaggle − validación (M)\n(optimismo promedio)")
guarda(g_abl, "f15_ablacion_pesos", w = 5.9, h = 2.25)
writeLines(c("% Generado por code/95b_presentacion_best.R (seccion 11). No editar a mano.",
             sprintf("\\newcommand{\\%s}{%s}", names(cifras), unlist(cifras))), file.path(TAB, "cifras_vs.tex"))
