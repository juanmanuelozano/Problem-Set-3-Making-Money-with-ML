# =============================================================================
# 95_presentacion.R - Figuras y números de la presentación y compilación del
# .tex (reports/03_presentacion/compare_equipo_4.tex)
# Diapositivas 1-2: el modelo final del equipo, m24_ens_optimo (Kaggle 152,3):
# promedio ponderado de los PRECIOS de m17_nn_star_m2 (53,4%),
# m22_xgb_comparables_m2 (39,9%) y m14_en_enc_tx (6,6%). Pesos de
# 93_pesos_ensamble.R (D22), en la rama validacion-sintetica.
# Diapositiva 4 (moraleja 1, texto): las 4 cargas más altas de las 5 primeras
# componentes del PCA del TF-IDF (03e_pca.R).
# Diapositiva 5 (moraleja 1, cont.): MAE en Kaggle según cómo entra el texto
# (elastic net m53/m12/m14; NN STAR m52/m24).
# Usa las tablas de 96, 97, 98 y 99, que deben correr antes.
# Archivos de commits fijos (desde_git() de 01_setup.R):
#  - VALIDACION_SINTETICA: los de la rama de María José que no están en esta
#    (m22, m24_ens_optimo, su registro, sus OOF y sus puntajes de Kaggle).
#  - ENVIADOS: registro, OOF, envíos y pesos TWCV tal como estaban al subirlos
#    a Kaggle. 00_main.R volvió a entrenar varios de esos modelos (m04, m02b,
#    m12_*, m11...; D27) y sus archivos actuales ya no son los que se
#    calificaron.
# Salidas: output/figures/03_presentacion/*.pdf,
# output/tables/03_presentacion/{*.tex, numeros.tex} y el PDF de la
# presentación (si latexmk está instalado)
# =============================================================================
source(here::here("code", "01_setup.R"))
source(here::here("code", "utils_modelos.R"))

VALIDACION_SINTETICA <- "b4948f0"
ENVIADOS <- "f5786a2"
FUENTE <- "NewCenturySchoolbook" # misma fuente que las diapositivas (Century)
num <- function(x, d = 1) formatC(x, format = "f", digits = d, decimal.mark = ",")
coma_mat <- \(x) sub(",", "{,}", num(x, 2)) # coma decimal dentro de $...$
en_commit <- function(commit, carpeta) {
  system2(
    "git", c("-C", shQuote(RAIZ), "ls-tree", "--name-only", commit, paste0(carpeta, "/")),
    stdout = TRUE
  )
}
subs_enviados <- en_commit(ENVIADOS, "submissions")
# Precio predicho por anuncio, ordenado por property_id: el envío calificado si
# existe; si no, el actual o el de la rama de María José
lee_sub <- function(f) {
  ruta <- file.path("submissions", f)
  d <- if (ruta %in% subs_enviados) {
    lee_csv_git(ENVIADOS, ruta)
  } else if (file.exists(file.path(P$subs, f))) {
    lee_csv(file.path(P$subs, f))
  } else {
    lee_csv_git(VALIDACION_SINTETICA, ruta)
  }
  arrange(d, property_id)$price
}
# Tabla de LaTeX con encabezado de "no editar"
escribe_tex <- function(lineas, archivo) {
  writeLines(
    c("% Generado por code/95_presentacion.R: no editar a mano", lineas),
    file.path(P$tab_pres, archivo)
  )
}
tema_puntos <- function() {
  theme_minimal(base_size = 15, base_family = FUENTE) +
    theme(
      panel.grid.major.y = element_blank(), panel.grid.minor = element_blank(),
      panel.grid.major.x = element_line(colour = "#ecebe8", linewidth = .4),
      axis.text = element_text(colour = "#52514e"),
      axis.title.x = element_text(colour = "#52514e", size = 12, hjust = 1)
    )
}
guarda_fig <- function(g, archivo, width, height) {
  ggsave(
    file.path(P$fig_pres, archivo), g,
    width = width, height = height, device = "pdf", family = FUENTE
  )
}

# ---- Componentes del ensamble: puntaje público de Kaggle y peso (D22) ----
comp <- tribble(
  ~etiqueta,                 ~archivo,                     ~kaggle,      ~peso,
  "NN STAR",                 "m17_nn_star_m2.csv",         158281022.13, .534,
  "XGBoost con comparables", "m22_xgb_comparables_m2.csv", 162936278.45, .399,
  "Elastic net con texto",   "en_enc_tx.csv",              168831256.43, .066
)
KAGGLE_ENS <- 152328386.28 # m24_ens_optimo.csv
P_comp <- sapply(comp$archivo, lee_sub)
p_ens <- lee_sub("m24_ens_optimo.csv")

# Verificación: el promedio ponderado de los tres archivos reproduce el envío
# del ensamble
p_rep <- drop(P_comp %*% (comp$peso / sum(comp$peso)))
cat(sprintf(
  "Reproducción del ensamble: diferencia relativa mediana %.4f%%, máxima %.3f%%\n",
  100 * median(abs(p_rep / p_ens - 1)), 100 * max(abs(p_rep / p_ens - 1))
))
stopifnot(median(abs(p_rep / p_ens - 1)) < .001)

# Correlación de errores entre la red y el XGBoost en el test, estimada sin
# precios (método de D22): con errores ~normales, sigma = MAE * sqrt(pi/2) y
# E|p1 - p2| = sqrt(2/pi) * sd(e1 - e2), así que
# Cov(e1, e2) = (s1^2 + s2^2 - sd(e1 - e2)^2) / 2
K <- sqrt(pi / 2)
s2 <- (comp$kaggle[1:2] * K)^2
d2 <- (mean(abs(P_comp[, 1] - P_comp[, 2])) * K)^2
rho <- (sum(s2) - d2) / 2 / sqrt(prod(s2))
cat(sprintf("Correlación estimada de los errores NN STAR - XGBoost: %.2f\n", rho))

# ---- Figura: MAE de cada componente y del ensamble ----
# Diagrama de puntos; el eje no empieza en cero a propósito, con etiquetas
fig <- tibble(
  etiqueta = c(comp$etiqueta, "Ensamble"),
  mae = c(comp$kaggle, KAGGLE_ENS) / 1e6
) %>%
  mutate(
    tipo = if_else(etiqueta == "Ensamble", "ensamble", "componente"),
    etiqueta = factor(etiqueta, levels = rev(c("Ensamble", comp$etiqueta)))
  )
g <- ggplot(fig, aes(mae, etiqueta)) +
  geom_segment(aes(x = 145, xend = mae, yend = etiqueta), colour = "#d9d8d4", linewidth = .6) +
  geom_point(aes(colour = tipo), size = 4) +
  geom_text(
    aes(label = number(mae, accuracy = .1, decimal.mark = ",")),
    nudge_y = .34, size = 4.6, colour = "#0b0b0b", family = FUENTE
  ) +
  # gris neutro y el verde de la plantilla
  scale_colour_manual(values = c(componente = "#898781", ensamble = "#1E5631"), guide = "none") +
  scale_x_continuous(
    limits = c(145, 172), breaks = seq(145, 170, 5),
    labels = label_number(decimal.mark = ",")
  ) +
  labs(x = "MAE en Kaggle (millones de pesos)", y = NULL) +
  tema_puntos()
guarda_fig(g, "mae_ensamble.pdf", 4.6, 3.1)

# ---- Tabla: cargas del PCA del texto (TF-IDF de 03d, PCA truncado de 03e) ----
pca_tx <- readRDS(file.path(P$models, "pca_texto.rds"))
var_tx <- lee_csv(file.path(P$tab_mod, "pca_varianza.csv")) %>% filter(pca == "texto")
signo <- \(x) sub("^-", "$-$", x) # signo menos de LaTeX
filas <- map_chr(1:5, function(k) {
  r <- pca_tx$rotation[, k]
  o <- order(-abs(r))[1:4]
  cargas <- formatC(r[o], format = "f", digits = 2, decimal.mark = ",", flag = "+")
  terminos <- paste(sprintf("%s (%s)", names(r)[o], signo(cargas)), collapse = ", ")
  sprintf(
    "CP%d & %s\\,\\%% & %s \\\\",
    k, formatC(100 * var_tx$prop[k], format = "f", digits = 1, decimal.mark = ","), terminos
  )
})
escribe_tex(
  c(
    "\\begin{tabular}{l r >{\\raggedright\\arraybackslash}p{.72\\textwidth}}", "\\toprule",
    "Componente & Varianza & Los 4 términos con mayor carga (en valor absoluto) \\\\",
    "\\midrule", filas, "\\bottomrule", "\\end{tabular}"
  ),
  "pca_cargas.tex"
)
var5 <- sum(var_tx$prop[1:5])
# Respaldo de "maximizar la varianza no maximiza la información útil":
# correlación de cada componente con log(precio/m2)
pc <- lee_csv(file.path(P$processed, "pca_texto.csv"))
pc <- pc[match(TR$property_id, pc$property_id), ]
cors <- sapply(
  seq_len(ncol(pca_tx$rotation)),
  \(k) cor(pc[[sprintf("pc_tx%02d", k)]], Y - TR$log_area)
)
rango <- match(seq_along(cors), order(-abs(cors)))
k_max <- which.max(abs(cors))
cat(sprintf(
  "CP1: correlación %.2f, puesto %d de %d | CP3: %.2f, puesto %d | la más correlacionada: CP%d (%.2f)\n",
  cors[1], rango[1], length(cors), cors[3], rango[3], k_max, cors[k_max]
))

# ---- Tabla: MAE en Kaggle según cómo entra el texto ----
# Elastic net con las variables de m02 y la base del 18/11 (m53 de 04g; m12 de
# 04c; m14 de 08b). NN STAR con la configuración de m24 (m52: rama de texto
# apagada, 08l).
ks <- lee_csv(file.path(P$models, "kaggle_scores.csv"))
k_de <- \(m) ks$public_score[ks$modelo == m][1]
tx <- tribble(
  ~bloque, ~fila,                                        ~modelo,
  "en",    "Sin variables de texto",                     "m53_en_sin_texto",
  "en",    "Dummies directas (expresiones regulares)",   "m12_en_m02",
  "en",    "Dummies + PCA del TF-IDF (50 componentes)",  "m12_en_m02_pca_tx",
  "en",    "Dummies + encoder de texto del STAR",        "m14_en_enc_tx",
  "nn",    "Sin rama de texto",                          "m52_nn_star_sin_texto_m2",
  "nn",    "Rama de texto: encoder sobre el TF-IDF",     "m24_nn_star_catastro_m2"
) %>%
  mutate(kaggle = map_dbl(modelo, k_de))
stopifnot(!anyNA(tx$kaggle))
fmt <- function(x, mejor) {
  v <- formatC(x / 1e6, format = "f", digits = 1, decimal.mark = ",")
  ifelse(x == mejor, paste0("\\textbf{", v, "}"), v)
}
linea <- \(d) paste0(d$fila, " & ", fmt(d$kaggle, min(d$kaggle)), " \\\\")
escribe_tex(
  c(
    "\\begin{tabular}{l r}", "\\toprule", "Cómo entra el texto & MAE en Kaggle \\\\", "\\midrule",
    "\\multicolumn{2}{l}{\\textit{Elastic net, mismas variables base}} \\\\",
    linea(filter(tx, bloque == "en")), "\\midrule",
    "\\multicolumn{2}{l}{\\textit{NN STAR}} \\\\",
    linea(filter(tx, bloque == "nn")), "\\bottomrule", "\\end{tabular}"
  ),
  "texto_representaciones.tex"
)
mejora_dum <- (tx$kaggle[1] - tx$kaggle[2]) / 1e6
mejora_enc <- (tx$kaggle[2] - tx$kaggle[4]) / 1e6
nn_txt <- (tx$kaggle[5] - tx$kaggle[6]) / 1e6
enc_pca <- (tx$kaggle[3] - tx$kaggle[4]) / 1e6 # encoder frente a PCA, con las mismas dummies

# ---- Moraleja 1, diapositiva A: MAE en Kaggle del elastic net según cómo entra el texto ----
fa <- tx %>%
  filter(bloque == "en") %>%
  mutate(
    etiqueta = c("Sin texto", "Dummies", "Dummies + PCA", "Dummies + encoder"),
    mae = kaggle / 1e6,
    tipo = if_else(mae == min(mae), "mejor", "otro"),
    etiqueta = factor(etiqueta, levels = rev(etiqueta))
  )
ga <- ggplot(fa, aes(mae, etiqueta)) +
  geom_segment(aes(x = 160, xend = mae, yend = etiqueta), colour = "#d9d8d4", linewidth = .6) +
  geom_point(aes(colour = tipo), size = 4) +
  geom_text(
    aes(label = number(mae, accuracy = .1, decimal.mark = ",")),
    nudge_y = .34, size = 4.6, colour = "#0b0b0b", family = FUENTE
  ) +
  scale_colour_manual(values = c(otro = "#898781", mejor = "#1E5631"), guide = "none") +
  scale_x_continuous(
    limits = c(160, 202), breaks = seq(160, 200, 10),
    labels = label_number(decimal.mark = ",")
  ) +
  labs(x = "MAE en Kaggle (millones de pesos)", y = NULL) +
  tema_puntos()
guarda_fig(ga, "texto_kaggle_en.pdf", 4.8, 2.6)

# Ejemplo de cargas del PCA: CP1 y CP2 con sus 3 términos de mayor carga y su
# correlación con el precio por m2
filas2 <- map_chr(1:2, function(k) {
  r <- pca_tx$rotation[, k]
  o <- order(-abs(r))[1:3]
  sprintf(
    "CP%d & %s & %s & %d.ª \\\\",
    k, paste(names(r)[o], collapse = ", "), signo(num(cors[k], 2)), rango[k]
  )
})
escribe_tex(
  c(
    "\\begin{tabular}{l l r r}", "\\toprule",
    "& Términos con mayor carga & $r$ con el precio por m$^2$ & Puesto (de 50) \\\\",
    "\\midrule", filas2, "\\bottomrule", "\\end{tabular}"
  ),
  "pca_ejemplo.tex"
)

# ---- Moraleja 1, diapositiva B: ¿la red y los árboles leen el texto igual? (96) ----
cmpn <- lee_csv(file.path(P$tab_pres, "texto_componentes.csv"))
set.seed(123)
mu <- cmpn[sample(nrow(cmpn), 6000), ]
gb <- ggplot(mu, aes(100 * xgb, 100 * nn)) +
  annotate("rect", xmin = 2, xmax = Inf, ymin = -Inf, ymax = -2, fill = "#f1efe9") +
  annotate("rect", xmin = -Inf, xmax = -2, ymin = 2, ymax = Inf, fill = "#f1efe9") +
  geom_hline(yintercept = 0, colour = "#d9d8d4") +
  geom_vline(xintercept = 0, colour = "#d9d8d4") +
  geom_point(colour = "#1E5631", alpha = .18, size = .7, stroke = 0) +
  annotate(
    "text", x = -38, y = 33, label = sprintf("r = %s", num(cor(cmpn$nn, cmpn$xgb), 2)),
    hjust = 0, size = 4.6, family = FUENTE, colour = "#0b0b0b"
  ) +
  coord_cartesian(xlim = c(-40, 40), ylim = c(-40, 40)) +
  labs(x = "Efecto del texto en el XGB STAR (%)", y = "Efecto del texto en la NN STAR (%)") +
  theme_minimal(base_size = 13, base_family = FUENTE) +
  theme(
    panel.grid = element_blank(), axis.text = element_text(colour = "#52514e"),
    axis.title = element_text(colour = "#52514e", size = 11)
  )
guarda_fig(gb, "texto_dispersion.pdf", 3.4, 2.9)

# Términos de ejemplo (correlación del TF-IDF del término con la componente de
# texto de cada modelo). La selección es ilustrativa: dos en que coinciden y
# los dos con más diferencia a favor de cada modelo entre los interpretables.
tt <- lee_csv(file.path(P$tab_pres, "texto_terminos.csv"))
ej <- tribble(
  ~grupo,            ~termino,           ~mostrar,
  "Coinciden",       "cocina abierto",   "cocina abierta",
  "Coinciden",       "cocina integral",  "cocina integral",
  "La red pesa más", "pads",             "PADS (inmobiliaria)",
  "La red pesa más", "rentahouse finca", "Rentahouse (inmobiliaria)",
  "El XGB pesa más", "ascensor privado", "ascensor privado",
  "El XGB pesa más", "estrenar",         "para estrenar"
) %>%
  left_join(tt, by = "termino")
stopifnot(!anyNA(ej$cor_nn))
f2 <- \(x) signo(num(x, 2))
filas_ej <- unlist(map(unique(ej$grupo), function(g) {
  d <- filter(ej, grupo == g)
  c(
    sprintf("\\multicolumn{3}{l}{\\textit{%s}} \\\\", g),
    sprintf("%s & %s & %s \\\\", d$mostrar, f2(d$cor_nn), f2(d$cor_xgb))
  )
}))
escribe_tex(
  c(
    "\\begin{tabular}{l r r}", "\\toprule", "Término & NN STAR & XGB STAR \\\\", "\\midrule",
    filas_ej, "\\bottomrule", "\\end{tabular}"
  ),
  "texto_terminos_ejemplos.tex"
)
cmp <- lee_csv(file.path(P$tab_pres, "texto_comparacion.csv"))

# ---- Modelos tal como se subieron a Kaggle (ENVIADOS) ----
# Lo del commit ENVIADOS tiene prioridad; lo que no estaba (m52, m53...) sale de
# los archivos actuales
reg_actual <- lee_csv(file.path(P$models, "registro_modelos.csv"))
reg_a <- lee_csv_git(ENVIADOS, "models/registro_modelos.csv")
reg_a <- bind_rows(reg_a, filter(reg_actual, !modelo %in% reg_a$modelo))
oof_actual <- lee_csv(file.path(P$models, "oof_predicciones.csv"))
oof_a <- lee_csv_git(ENVIADOS, "models/oof_predicciones.csv")
oof_nuevas <- oof_actual[c("property_id", setdiff(names(oof_actual), names(oof_a)))]
oof_a <- left_join(oof_a, oof_nuevas, by = "property_id")
pw <- lee_csv_git(ENVIADOS, "data/processed/pesos_validacion.csv")
W_tw <- pw$w_twcv[match(TR$property_id, pw$property_id)]
stopifnot(!anyNA(W_tw), abs(sum(W_tw) - 1) < 1e-8)
twcv_de <- \(oof, m) mae_w(oof[[m]][match(TR$property_id, oof$property_id)], W_tw)

# Ablación del texto (TWCV, misma validación para los dos): NN STAR (08l) y XGB
# STAR (m22 frente a m56, 08r)
nn_r <- lee_csv(file.path(P$tab_mod, "nn_star_ramas.csv")) %>% filter(tipo == "variante")
abl_nn <- c(
  nn_r$mae_twcv[nn_r$variante == "m24 reproducida"],
  nn_r$mae_twcv[nn_r$variante == "sin texto"]
) / 1e6
abl_xg <- unname(sapply(c("m22_xgb_star_twcv_m2", "m56_xgb_star_sin_texto_m2"), twcv_de, oof = oof_a)) / 1e6

# ---- Moraleja 1 (datos): importancia SHAP por grupo de datos (97) ----
sh <- lee_csv(file.path(P$tab_pres, "shap_grupos.csv")) %>%
  filter(grupo != "Otras") %>%
  group_by(modelo) %>%
  mutate(part = shap_abs / sum(shap_abs)) %>%
  ungroup() %>%
  mutate(modelo = factor(
    modelo,
    levels = c("nn", "xgb", "en", "ens"),
    labels = c("NN STAR\n53 %", "XGB\n40 %", "ElasticNet\n7 %", "Ensamble")
  ))
orden <- sh %>%
  filter(modelo == "Ensamble") %>%
  arrange(part) %>%
  pull(grupo)
sh <- mutate(sh, grupo = factor(grupo, levels = orden))
gs <- ggplot(sh, aes(modelo, grupo, fill = pmin(part, .25))) +
  geom_tile(colour = "white", linewidth = 1.2) +
  geom_text(
    aes(label = ifelse(shap_abs < .0005, "–", paste0(num(100 * part, 0), " %")), colour = part > .14),
    size = 4.2, family = FUENTE
  ) +
  scale_fill_gradient(low = "#eef3ef", high = "#1E5631", limits = c(0, .25), guide = "none") +
  scale_colour_manual(values = c(`TRUE` = "white", `FALSE` = "#0b0b0b"), guide = "none") +
  scale_x_discrete(position = "top") +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 14, base_family = FUENTE) +
  theme(
    panel.grid = element_blank(), axis.text = element_text(colour = "#0b0b0b"),
    axis.text.x = element_text(size = 11)
  )
guarda_fig(gs, "shap_grupos.pdf", 6.6, 3.9)

# ---- Moraleja 2 (interpretabilidad): mapa de la componente de ubicación de la combinación STAR m48 (98) ----
mu <- lee_csv(file.path(P$tab_pres, "mapas_ubicacion.csv"))
cor_ubi <- cor(mu$nn, mu$xgb)
mp <- mu %>%
  pivot_longer(c(nn, xgb), names_to = "modelo", values_to = "ubi") %>%
  mutate(modelo = factor(modelo, c("nn", "xgb"), c("NN STAR (60 %)", "XGB STAR (40 %)")))
lim <- log(c(.5, 2)) # de -50 % a +100 %; los extremos se recortan
loc_poly <- lee_csv(file.path(P$osm, "localidades_poligonos.csv"))
capa <- function(d, col, lw) {
  geom_polygon(
    data = d, aes(lon, lat, group = interaction(nombre, ring)), fill = NA,
    colour = col, linewidth = lw, inherit.aes = FALSE
  )
}
gm <- ggplot(mp, aes(lon, lat, z = pmin(pmax(ubi, lim[1]), lim[2]))) +
  capa(loc_poly, "#c3c2bd", .2) +
  stat_summary_2d(fun = median, binwidth = c(.0045, .0045)) +
  capa(filter(loc_poly, nombre == "Chapinero"), "#0b0b0b", .5) +
  facet_wrap(~modelo) +
  scale_fill_gradient2(
    low = "#2a78d6", mid = "#f0efec", high = "#e34948", midpoint = 0, limits = lim,
    breaks = log(c(.5, .75, 1, 1.5, 2)),
    labels = \(x) paste0(ifelse(x > 0, "+", ""), num(100 * (exp(x) - 1), 0), " %"),
    name = "Efecto de la ubicación sobre el precio por m²"
  ) +
  coord_quickmap(xlim = c(-74.19, -74.015), ylim = c(4.565, 4.775)) +
  guides(fill = guide_colorbar(barwidth = 13, barheight = .45, title.position = "top", title.hjust = .5)) +
  labs(x = NULL, y = NULL) +
  theme_minimal(base_size = 12, base_family = FUENTE) +
  theme(
    axis.text = element_blank(), panel.grid = element_blank(), legend.position = "bottom",
    strip.text = element_text(size = 12, colour = "#0b0b0b"),
    legend.title = element_text(size = 10, colour = "#52514e"),
    legend.text = element_text(size = 9, colour = "#52514e")
  )
guarda_fig(gm, "mapas_ubicacion.pdf", 6.4, 4.3)

# ---- Moraleja 4 (validación): ¿qué medida de validación anticipa el puntaje de Kaggle? ----
# Todos los modelos subidos a Kaggle (kaggle_scores.csv de esta rama y de la de
# María José) con su registro y OOF. Medidas: MAE de la CV por localidad (D9),
# MAE en Chapinero, MAE promedio entre localidades, TWCV (D16) y la predicción
# media en el test. Se excluyen de la tabla los modelos cuya CV no es
# comparable: con comparables (precio de vecinos, que incluyen republicaciones
# del mismo inmueble) o con la CV por edificio, y las combinaciones.
ks_all <- bind_rows(ks, lee_csv_git(VALIDACION_SINTETICA, "models/kaggle_scores.csv")) %>%
  mutate(modelo = sub(" .*", "", modelo)) %>%
  distinct(public_score, .keep_all = TRUE)
reg_b <- lee_csv_git(VALIDACION_SINTETICA, "models/registro_modelos.csv")
oof_b <- lee_csv_git(VALIDACION_SINTETICA, "models/oof_predicciones.csv")
arch <- c(m14_en_enc_tx = "en_enc_tx.csv") # nombres de archivo distintos al del modelo
val <- map_dfr(ks_all$modelo, function(m) {
  ella <- !(m %in% reg_a$modelo)
  reg <- if (ella) reg_b else reg_a
  oof <- if (ella) oof_b else oof_a
  r <- reg[reg$modelo == m, ]
  if (!nrow(r) || !(m %in% names(oof))) {
    return(NULL)
  }
  tibble(
    modelo = m, cv = r$mae_total[1], chap = r$mae_chapinero[1], macro = r$mae_macro[1],
    twcv = twcv_de(oof, m),
    media = mean(lee_sub(if (m %in% names(arch)) arch[[m]] else paste0(m, ".csv")))
  )
}) %>%
  left_join(select(ks_all, modelo, kaggle = public_score), by = "modelo") %>%
  mutate(fam = case_when(
    grepl("nn_|star_nn", modelo) ~ "Redes",
    grepl("xgb|rf|cart", modelo) ~ "Árboles",
    TRUE ~ "ElasticNet"
  ))
no_comp <- c(
  # comparables / CV por edificio
  "m22_xgb_comparables_m2", "m21_en_comparables_m2", "m32_nn_star_comparables_m2",
  "m36_nn_star_vecinos_m2",
  # combinaciones y MCO
  "m39_star_nn_xgbcomp_m2", "m48_star_nn_xgbsq_area_m2", "m37_star_nn_xgb_m2",
  "m06_hibrido_en_xgb", "reg_ols_sin_loc"
)
vt <- filter(val, !modelo %in% no_comp)
cor_k <- function(x) {
  summarise(x, n = n(), across(c(cv, chap, macro, twcv, media), ~ cor(.x, kaggle)))
}
tab_v <- bind_rows(
  vt %>% group_by(fam) %>% cor_k(),
  vt %>% mutate(fam = "Todos") %>% group_by(fam) %>% cor_k()
) %>%
  mutate(fam = factor(fam, c("Árboles", "ElasticNet", "Redes", "Todos"))) %>%
  arrange(fam)
print(as.data.frame(mutate(tab_v, across(where(is.double), ~ round(.x, 2)))))
fam_lab <- c(
  "Árboles" = "Árboles (XGBoost, RF, CART)", ElasticNet = "ElasticNet",
  Redes = "Redes", Todos = "Todos"
)
escribe_tex(
  c(
    "\\begin{tabular}{l c c c c c}", "\\toprule",
    "& & CV por & MAE en & MAE promedio & \\\\",
    "Modelos & $n$ & localidad & Chapinero & por localidad & TWCV \\\\", "\\midrule",
    with(tab_v, sprintf(
      "%s%s & %d & %s & %s & %s & %s \\\\",
      ifelse(fam == "Todos", "\\midrule ", ""), fam_lab[as.character(fam)], n,
      num(cv, 2), num(chap, 2), num(macro, 2), num(twcv, 2)
    )),
    "\\bottomrule", "\\end{tabular}"
  ),
  "validacion_kaggle.tex"
)
v_de <- \(m, col) val[[col]][val$modelo == m] / 1e6
cor_media_todos <- cor(val$media, val$kaggle) # con todos los modelos, incluidos los excluidos de la tabla

# ---- Números que cita el texto de las diapositivas ----
mac <- c(
  maeNN = num(comp$kaggle[1] / 1e6),
  maeXGB = num(comp$kaggle[2] / 1e6),
  maeEN = num(comp$kaggle[3] / 1e6),
  maeEns = num(KAGGLE_ENS / 1e6),
  pesoNN = num(100 * comp$peso[1], 0),
  pesoXGB = num(100 * comp$peso[2], 0),
  pesoEN = num(100 * comp$peso[3], 0),
  corrErrores = num(rho, 2),
  varCincoCP = num(100 * var5),
  nTerminosTfidf = format(nrow(pca_tx$rotation), big.mark = ".", decimal.mark = ","),
  corrCPuno = coma_mat(cors[1]),
  rangoCPuno = rango[1],
  nCP = length(cors),
  cpMax = k_max,
  corrCPmax = coma_mat(cors[k_max]),
  corrCPtres = coma_mat(cors[3]),
  rangoCPtres = rango[3],
  varCPtres = num(100 * var_tx$prop[3]),
  mejoraDumKaggle = num(mejora_dum),
  mejoraEncKaggle = num(mejora_enc),
  encVsPca = num(enc_pca),
  kSinTexto = num(tx$kaggle[1] / 1e6),
  kDummies = num(tx$kaggle[2] / 1e6),
  kPCA = num(tx$kaggle[3] / 1e6),
  kEncoder = num(tx$kaggle[4] / 1e6),
  kNNsin = num(tx$kaggle[5] / 1e6),
  kNNcon = num(tx$kaggle[6] / 1e6),
  corTextoModelos = coma_mat(cmp$cor_componentes),
  corTerminos = coma_mat(cmp$cor_terminos),
  pctOpuestos = num(100 * cmp$pct_opuestos),
  sdTextoNN = num(100 * sd(cmpn$nn)),
  sdTextoXGB = num(100 * sd(cmpn$xgb)),
  ablNNcon = num(abl_nn[1]),
  ablNNsin = num(abl_nn[2]),
  ablXGBcon = num(abl_xg[1]),
  ablXGBsin = num(abl_xg[2]),
  nnTextoKaggle = num(nn_txt),
  kStar = num(k_de("m48_star_nn_xgbsq_area_m2") / 1e6),
  kNNstar = num(k_de("m24_nn_star_catastro_m2") / 1e6),
  corUbicacion = coma_mat(cor_ubi),
  nModKaggle = nrow(val),
  nModTabla = nrow(vt),
  corMedia = coma_mat(tab_v$media[tab_v$fam == "Todos"]),
  corMediaTodos = coma_mat(cor_media_todos),
  corCVTodos = coma_mat(cor(val$cv, val$kaggle)),
  corCVTabla = coma_mat(tab_v$cv[tab_v$fam == "Todos"]),
  cvXGBcomp = num(v_de("m22_xgb_comparables_m2", "cv"), 0),
  kXGBcomp = num(v_de("m22_xgb_comparables_m2", "kaggle"), 0),
  twAfinada = num(v_de("m25_nn_star_catastro_afinada_m2", "twcv")),
  twBase = num(v_de("m24_nn_star_catastro_m2", "twcv")),
  kAfinada = num(v_de("m25_nn_star_catastro_afinada_m2", "kaggle")),
  kBase = num(v_de("m24_nn_star_catastro_m2", "kaggle")),
  mediaAfinada = num(v_de("m25_nn_star_catastro_afinada_m2", "media"), 0),
  mediaBase = num(v_de("m24_nn_star_catastro_m2", "media"), 0),
  kAfinadaUno = num(v_de("m19_nn_star_afinada_m2", "kaggle")),
  kBaseUno = num(v_de("m17_nn_star_m2", "kaggle")),
  nAmenidades = 22L # amenidades de la base del 18/11 (antes de D14), la de estos elastic net
)
escribe_tex(sprintf("\\newcommand{\\%s}{%s}", names(mac), mac), "numeros.tex")

# ---- Compila la presentación ----
tex <- "compare_equipo_4.tex"
if (nzchar(Sys.which("latexmk"))) {
  r <- processx::run(
    "latexmk", c("-pdf", "-interaction=nonstopmode", "-halt-on-error", tex),
    wd = P$pres, error_on_status = FALSE
  )
  if (r$status != 0) {
    warning("latexmk falló; revise ", file.path(P$pres, sub("tex$", "log", tex)))
  } else {
    processx::run("latexmk", c("-c", tex), wd = P$pres) # borra los auxiliares
    cat("Presentación:", file.path(P$pres, sub("tex$", "pdf", tex)), "\n")
  }
} else {
  message("latexmk no está instalado: no se recompila ", tex)
}
cat("Listo: figuras en", P$fig_pres, "y cifras en", file.path(P$tab_pres, "numeros.tex"), "\n")
