# =============================================================================
# 03e_pca.R - PCA por separado para las variables que no son de texto y para el TF-IDF del texto
# Se ajusta con train + test: el PCA no usa el precio, así que no hay fuga (mismo criterio que D11).
# Entradas: data/processed/base_modelo.rds (03), data/processed/tfidf.parquet (03d_tfidf.py)
# Salidas (data/processed/):
#   (1) base_no_texto.csv   variables finales de base_modelo que no vienen del texto
#   (2) pca_no_texto.csv    componentes de (1), estandarizadas (scale = TRUE: unidades distintas)
#   (3) base_texto.rds      TF-IDF como matriz dispersa (dgCMatrix, filas = property_id, columnas = términos)
#   (4) pca_texto.csv       componentes de (3) con irlba: PCA truncado sin volver densa la matriz
#   models/pca_{no_texto,texto}.rds (objetos completos), reports/02_modelos/tables/pca_{varianza,cargas}.csv
# =============================================================================
source("scripts/00_config.R")
suppressMessages(pacman::p_load(arrow, Matrix, irlba, knitr))
K_TX <- 50   # componentes del texto (PCA truncado)

base <- readRDS(file.path(P$processed, "base_modelo.rds"))
D <- base$datos

# ---- (1) Variables que no son de texto ----
# Fuera: las derivadas del texto y lat_rot1/2 (combinaciones lineales de lat/lon: triplicarían el peso de la ubicación)
texto <- c("area_texto", "piso_txt", "antig_txt", "parq_txt", "n_palabras", grep("^tx_", base$vars, value = TRUE))
v_nt <- setdiff(base$vars, c(texto, "lat_rot1", "lat_rot2"))
NT <- D[c("property_id", "muestra", v_nt)]
stopifnot(!anyNA(NT[v_nt]))
write_csv(NT, file.path(P$processed, "base_no_texto.csv"))

# ---- (2) PCA de las variables que no son de texto ----
pca_nt <- prcomp(NT[v_nt], center = TRUE, scale. = TRUE)
S_nt <- as_tibble(pca_nt$x) %>% rename_with(~ sprintf("pc_nt%02d", seq_along(.x)))
write_csv(bind_cols(NT[c("property_id", "muestra")], S_nt), file.path(P$processed, "pca_no_texto.csv"))

# ---- (3) Texto: TF-IDF disperso, en el mismo orden de filas que base_modelo ----
t <- read_parquet(file.path(P$processed, "tfidf.parquet"))
X <- sparseMatrix(i = match(t$property_id, D$property_id), j = as.integer(t$termino), x = t$tfidf,
                  dims = c(nrow(D), nlevels(t$termino)), dimnames = list(D$property_id, levels(t$termino)))
stopifnot(!anyNA(match(t$property_id, D$property_id)))
saveRDS(X, file.path(P$processed, "base_texto.rds"))

# ---- (4) PCA del texto ----
# Centrado sin escalar: el TF-IDF ya pondera los términos, y escalar a varianza 1 inflaría los términos raros.
# irlba centra de forma implícita, sin volver densa la matriz (48.930 x 5.000 densa ocuparía ~2 GB).
set.seed(123)
pca_tx <- prcomp_irlba(X, n = K_TX, center = TRUE, scale. = FALSE)
rownames(pca_tx$rotation) <- colnames(X)
S_tx <- as_tibble(pca_tx$x, .name_repair = "minimal") %>% setNames(sprintf("pc_tx%02d", 1:K_TX))
write_csv(bind_cols(NT[c("property_id", "muestra")], S_tx), file.path(P$processed, "pca_texto.csv"))

saveRDS(pca_nt, file.path(P$models, "pca_no_texto.rds")); saveRDS(pca_tx, file.path(P$models, "pca_texto.rds"))

# ---- Valores propios (lambda = sdev^2) y varianza explicada ----
# No texto: variables estandarizadas, así que los lambda suman el número de variables (criterio de Kaiser: lambda > 1).
var_tx <- sum((colSums(X^2) - nrow(X) * colMeans(X)^2) / (nrow(X) - 1))   # varianza total del TF-IDF centrado
varianza <- bind_rows(
  tibble(pca = "no_texto", componente = seq_along(pca_nt$sdev), lambda = pca_nt$sdev^2, prop = lambda / sum(lambda)),
  tibble(pca = "texto", componente = 1:K_TX, lambda = pca_tx$sdev^2, prop = lambda / var_tx)) %>%
  group_by(pca) %>% mutate(acumulada = cumsum(prop)) %>% ungroup()
write_csv(varianza, file.path(P$rep_mod, "tables", "pca_varianza.csv"))
cat("\nValores propios y varianza explicada:\n")
print(as.data.frame(varianza %>% mutate(lambda = signif(lambda, 3), across(c(prop, acumulada), ~ round(.x, 3)))))
cat("No texto: componentes con lambda > 1 (Kaiser):", sum(pca_nt$sdev^2 > 1), "de", length(v_nt),
    "| texto: varianza total", signif(var_tx, 3), "\n")

pcas <- list(no_texto = list(pca = pca_nt, titulo = "Variables que no son de texto"),
             texto    = list(pca = pca_tx, titulo = "Texto (TF-IDF)"))

# ---- Gráficas: proporción de la varianza explicada por componente (scree plot) ----
for (nm in names(pcas)) {
  v <- filter(varianza, pca == nm)
  g <- ggplot(v, aes(componente, prop)) +
    geom_line(color = c_train, linewidth = .7) + geom_point(color = c_train, size = 1.8) +
    scale_x_continuous(breaks = c(1, seq(5, nrow(v), 5))) + scale_y_continuous(labels = percent, limits = c(0, NA)) +
    labs(title = sprintf("PCA: %s", pcas[[nm]]$titulo),
         subtitle = sprintf("Proporción de la varianza explicada por componente\nLas %d componentes suman %s%s",
                            nrow(v), percent(max(v$acumulada), 1),
                            if (nm == "no_texto") sprintf("; %d con lambda > 1", sum(v$lambda > 1)) else " (PCA truncado)"),
         x = "Componente principal", y = "Varianza explicada", caption = fuente)
  ggsave(file.path(P$rep_mod, "figures", sprintf("m5_pca_varianza_%s.png", nm)), g, width = 7, height = 4.5, dpi = 250)
}

# ---- Tablas: lambda y las 8 cargas más altas (en valor absoluto, con su signo) de las 10 primeras componentes ----
# El signo de una componente es arbitrario: importa qué variables cargan juntas y si van en el mismo sentido.
# Formato: una columna por componente; la primera fila es lambda y las 8 siguientes, las cargas ordenadas.
for (nm in names(pcas)) {
  p <- pcas[[nm]]$pca
  o <- map(1:10, ~ head(order(-abs(p$rotation[, .x])), 8))   # índices de las 8 cargas más altas de cada componente
  var <- sapply(1:10, \(j) rownames(p$rotation)[o[[j]]])     # matrices 8 x 10
  car <- sapply(1:10, \(j) p$rotation[o[[j]], j])
  lam <- formatC(signif(p$sdev[1:10]^2, 3), digits = 3, format = "fg", flag = "#")   # 3 cifras: 2.30, 0.0197
  top <- rbind(lam, matrix(sprintf("%s (%+.2f)", var, car), 8)) %>% `colnames<-`(paste0("PC", 1:10)) %>%
    as_tibble() %>% mutate(fila = c("lambda", 1:8), .before = 1)
  write_csv(top, file.path(P$rep_mod, "tables", sprintf("pca_top8_%s.csv", nm)))
  # LaTeX (requiere \usepackage{booktabs, graphicx} en el preámbulo). Cada celda: variable arriba, carga abajo.
  celda <- matrix(sprintf("\\begin{tabular}[t]{@{}l@{}}%s\\\\(%+.2f)\\end{tabular}", gsub("_", "\\\\_", var), car), 8)
  tex <- kable(cbind(c("$\\lambda$", 1:8), rbind(lam, celda)), format = "latex", booktabs = TRUE, escape = FALSE, row.names = FALSE,
               align = c("c", rep("l", 10)), col.names = c("", paste0("PC", 1:10)),
               linesep = c("\\midrule", rep("\\addlinespace", 7)))
  writeLines(c("\\begin{table}[htbp]", "\\centering",
               sprintf("\\caption{PCA: %s. Valor propio (primera fila) y las 8 cargas más altas en valor absoluto, de mayor a menor, de las 10 primeras componentes}",
                       pcas[[nm]]$titulo),
               sprintf("\\label{tab:pca_%s}", nm), "\\resizebox{\\textwidth}{!}{%", tex, "}",
               "\\par\\vspace{2pt}\\footnotesize Nota: bajo cada variable, su carga; el signo de una componente es arbitrario. ",
               if (nm == "texto") "PCA truncado (irlba) del TF-IDF centrado sin escalar; ajustado con train y test." else
                 "Variables estandarizadas; ajustado con train y test.",
               "\\end{table}"), file.path(P$rep_mod, "tables", sprintf("pca_top8_%s.tex", nm)))
  cat(sprintf("\n== %s ==\n", pcas[[nm]]$titulo)); print(as.data.frame(top), right = FALSE)
}
cat("\nListo.\n")
