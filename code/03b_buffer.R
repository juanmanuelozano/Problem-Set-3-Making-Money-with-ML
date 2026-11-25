# =============================================================================
# 03b_buffer.R - Elección del buffer para la validación "dejar una localidad afuera" (D9)
# Tres criterios:
#  1. Distancias al vecino de entrenamiento más cercano: las de la validación deberían parecerse a las del
#     test frente al train (idea de NNDM, Milà et al. 2022).
#  2. Rango de la autocorrelación espacial de los residuos de un modelo hedónico (Roberts et al. 2017).
#  3. Sensibilidad del MAE de validación al buffer (OLS y un random forest liviano).
# Entradas: data/processed/base_modelo.rds
# Salidas:  output/tables/02_modelos/buffer_*.csv, output/figures/02_modelos/m0_*.png
# =============================================================================
source(here::here("code", "01_setup.R")); source(here::here("code", "utils_modelos.R"))
BUFFERS <- c(0, 100, 250, 500, 1000, 1500, 2000)

# ---- 1. Distancia al vecino de entrenamiento más cercano ----
nn_test <- dist_min(TE$lat, TE$lon, TR$lat, TR$lon)
te_chap <- TE$localidad %in% "Chapinero"
set.seed(123); s_all <- sample(length(Y), 5000)
muestra <- union(s_all, which(ES_CHAP))   # muestra aleatoria + Chapinero completo
nn_cv <- map_dfr(BUFFERS, function(b) {
  imap_dfr(folds_localidad(b), function(f, g) {
    ev <- intersect(f$evaluacion, muestra)
    if (!length(ev)) return(NULL)
    tibble(buffer = b, grupo = g, i = ev, nn = dist_min(TR$lat[ev], TR$lon[ev], TR$lat[f$analisis], TR$lon[f$analisis]))
  })
})
ks <- function(x, y) unname(suppressWarnings(ks.test(x, y, exact = FALSE))$statistic)
q <- function(x) sprintf("%.0f / %.0f / %.0f", quantile(x, .25), median(x), quantile(x, .9))
res_nn <- nn_cv %>% group_by(buffer) %>%
  summarise(ks_total = ks(nn[i %in% s_all], nn_test), q_total = q(nn[i %in% s_all]),
            ks_chapinero = ks(nn[ES_CHAP[i]], nn_test[te_chap]), q_chapinero = q(nn[ES_CHAP[i]]))
res_nn <- bind_rows(tibble(buffer = NA, ks_total = 0, q_total = q(nn_test), ks_chapinero = 0, q_chapinero = q(nn_test[te_chap])), res_nn)
cat("\nDistancia al vecino de entrenamiento más cercano (p25 / mediana / p90, m). Fila NA = test frente al train\n")
print(res_nn)
cat("Test con un vecino del train a 0 m (mismas coordenadas):", mean(nn_test == 0), "\n")
write_csv(res_nn, file.path(P$tab_mod, "buffer_distancias.csv"))

# ---- 2. Correlograma de los residuos (OLS hedónico con localidad y coordenadas) ----
L <- matriz_lineal(TR); A <- matriz_arboles(TR)
r <- drop(Y - cbind(1, L) %*% ols_coef(L, seq_along(Y)))
set.seed(123); s <- sample(length(Y), 6000)
dd <- hav(TR$lat[s], TR$lon[s], TR$lat[s], TR$lon[s]); rr <- outer(r[s], r[s]) / var(r)
sup <- upper.tri(dd); dd <- dd[sup]; rr <- rr[sup]
cortes <- c(-1, 0.5, seq(100, 3000, 100))
corr <- tibble(d = dd, rr = rr) %>% filter(d <= 3000) %>% mutate(bin = cut(d, cortes)) %>%
  group_by(bin) %>% summarise(distancia = median(d), correlacion = mean(rr), pares = n(), .groups = "drop")
rm(dd, rr)
cat("\nCorrelograma de residuos (bin 1 = mismas coordenadas):\n"); print(corr, n = 35)
write_csv(corr, file.path(P$tab_mod, "buffer_correlograma.csv"))

# ---- 3. Sensibilidad del MAE al buffer ----
sens <- map_dfr(BUFFERS, function(b) {
  fo <- folds_localidad(b)
  ols <- cv_oof(function(a, e) cbind(1, L[e, ]) %*% ols_coef(L, a), fo)
  rf <- cv_oof(function(a, e) predict(ranger(x = A[a, ], y = Y[a], num.trees = 150, mtry = 20, min.node.size = 5,
                                             num.threads = 8, seed = 123), A[e, ], num.threads = 8)$predictions, fo)
  cat(sprintf("buffer %4d m listo (análisis medio: %.0f%% del resto)\n", b,
              100 * mean(map_dbl(fo, ~ length(.x$analisis) / (length(Y) - length(.x$evaluacion))))))
  bind_rows(evalua(ols) %>% mutate(modelo = "OLS"), evalua(rf) %>% mutate(modelo = "Random forest")) %>%
    mutate(buffer = b, n_analisis_chap = length(fo$Chapinero$analisis))
})
cat("\nMAE de validación (millones) según el buffer:\n")
print(sens %>% select(modelo, buffer, mae_total, mae_chapinero, mae_macro, n_analisis_chap) %>%
        mutate(across(starts_with("mae"), ~ round(.x / 1e6, 1))) %>% arrange(modelo, buffer))
write_csv(sens, file.path(P$tab_mod, "buffer_sensibilidad.csv"))

# ---- Figuras ----
diag <- bind_rows(
  corr %>% filter(distancia > 1) %>% transmute(panel = "1. Correlación de los residuos", x = distancia, y = correlacion, serie = "Residuos OLS"),
  res_nn %>% filter(!is.na(buffer)) %>% select(buffer, Todo = ks_total, Chapinero = ks_chapinero) %>%
    pivot_longer(-buffer, names_to = "serie") %>% transmute(panel = "2. Distancia KS validación vs. test", x = buffer, y = value, serie),
  sens %>% transmute(panel = "3. MAE de validación (millones)", x = buffer, y = mae_chapinero / 1e6, serie = paste(modelo, "· Chapinero")),
  sens %>% transmute(panel = "3. MAE de validación (millones)", x = buffer, y = mae_total / 1e6, serie = paste(modelo, "· total")))
g <- ggplot(diag, aes(x, y, color = serie)) + geom_hline(yintercept = 0, color = c_grid) +
  geom_line(linewidth = .6) + geom_point(size = 1.4) +
  geom_vline(xintercept = BUFFER_M, linetype = 2, color = c_ink2, linewidth = .3) +
  facet_wrap(~ panel, ncol = 1, scales = "free_y") +
  scale_color_manual(values = c(`Residuos OLS` = c_ink2, Todo = c_train, Chapinero = c_test,
                                `OLS · Chapinero` = c_test, `OLS · total` = c_train,
                                `Random forest · Chapinero` = "#e87ba4", `Random forest · total` = "#86b6ef"), name = NULL) +
  labs(title = "Elección del buffer", subtitle = sprintf("Línea punteada: buffer elegido (%s m)", BUFFER_M),
       x = "Distancia entre anuncios / buffer (m)", y = NULL, caption = fuente) +
  guides(color = guide_legend(nrow = 3))
ggsave(file.path(P$fig_mod, "m0_buffer_diagnostico.png"), g, width = 7, height = 8, dpi = 250)

fc <- FOLDS$Chapinero
mapa <- TR %>% mutate(rol = case_when(GRUPO == "Chapinero" ~ "Evaluación (Chapinero)",
                                       row_number() %in% fc$analisis ~ "Análisis (entrenamiento)",
                                       TRUE ~ sprintf("Excluido por el buffer (%s m)", BUFFER_M)))
g2 <- ggplot(mapa %>% filter(between(lat, 4.58, 4.76), between(lon, -74.12, -74.0)), aes(lon, lat, color = rol)) +
  geom_point(data = TE %>% filter(between(lat, 4.58, 4.76)), color = c_grid, size = .2) +
  geom_point(size = .35, alpha = .7) + coord_quickmap() +
  scale_color_manual(values = setNames(c(c_train, c_test, c_ink), c("Análisis (entrenamiento)", "Evaluación (Chapinero)",
                                                                 sprintf("Excluido por el buffer (%s m)", BUFFER_M))), name = NULL) +
  guides(color = guide_legend(override.aes = list(size = 3, alpha = 1), ncol = 1)) +
  labs(title = "Fold de Chapinero con buffer",
       subtitle = "Validación dejando una localidad afuera (gris claro: test)", x = NULL, y = NULL, caption = fuente) +
  theme(axis.text = element_blank(), panel.grid.major = element_blank())
ggsave(file.path(P$fig_mod, "m0_fold_chapinero.png"), g2, width = 6, height = 7.5, dpi = 250)
cat("Listo.\n")
