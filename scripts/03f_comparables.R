# =============================================================================
# 03f_comparables.R - Exporta las variables de comparables (D20) para usarlas en otros modelos
# comp5, comp20: log(precio/m2) promedio de los 5 y 20 anuncios del train más cercanos del mismo tipo
#   (apartamento/casa), ponderados por 1/(distancia + 30 m), sin anuncios con la misma descripción.
# comp_logdist5, comp_logdist20: log(1 + distancia media en metros) a esos vecinos.
# Train: cada anuncio con todo el train MENOS él mismo. Test: con todo el train.
# OJO: sirven para el modelo FINAL (entrenar con todo el train y predecir el test). Para validar sin fuga hay
# que recalcularlas dentro de cada fold con comparables_fold() de utils_modelos.R (las del train usan precios
# de anuncios que en la CV estarían en el fold de evaluación).
# Salida: data/processed/comparables.csv
# =============================================================================
source("scripts/00_config.R"); source("scripts/utils_modelos.R")
suppressMessages(pacman::p_load(RANN))

CMP <- prepara_comparables()
out <- bind_rows(tibble(property_id = TR$property_id, muestra = "train") %>% bind_cols(as_tibble(comparables_train(CMP))),
                 tibble(property_id = TE$property_id, muestra = "test") %>% bind_cols(as_tibble(comparables_test(CMP))))
write_csv(out, file.path(P$processed, "comparables.csv"))
print(out %>% group_by(muestra) %>% summarise(n = n(), across(starts_with("comp"), ~ round(median(.x), 2))))
