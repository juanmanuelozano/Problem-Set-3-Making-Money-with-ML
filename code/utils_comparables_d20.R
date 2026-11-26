# =============================================================================
# utils_comparables_d20.R - Comparables por anuncio (D20): el precio por m2 de los vecinos del train,
# un "control sintético" para cada inmueble. Lo usan 03i, 04f y 06b (m21, m22).
# Uso, después de utils_modelos.R: source(here::here("code", "utils_comparables_d20.R"))
#
# Es la versión original de D20. utils_comparables.R (redes, D23) parte de ella, pero agrega un radio mínimo
# emparejado con el test y folds por edificio, y usa los mismos nombres de funciones. Por eso los dos archivos
# no se cargan en el mismo script: cada uno reproduce sus propios modelos.
# =============================================================================

# CV aleatoria de 10 folds: se parece al test en la distancia a los vecinos (D20). Tiene su propia semilla.
FOLDS_ALEAT <- local({
  set.seed(123)
  g <- sample(rep(1:10, length.out = nrow(TR)))
  map(1:10, ~ list(analisis = which(g != .x), evaluacion = which(g == .x)))
})

# Vecinos candidatos (los k_max anuncios del train más cercanos y del mismo tipo) y claves de descripción
prepara_comparables <- function(k_max = 60, ks = c(5, 20), d0 = 30, usa_duplicados = FALSE) {
  m_lon <- 111320 * cos(4.65 * pi / 180)
  m_lat <- 110574
  xy <- function(df) cbind(df$lon * m_lon, df$lat * m_lat) # coordenadas planas en metros
  # El mismo inmueble publicado dos veces no puede ser su propio comparable
  raw <- bind_rows(
    lee_csv(file.path(P$raw, "train.csv")),
    lee_csv(file.path(P$raw, "test.csv"))
  ) %>%
    transmute(property_id, clave = str_squish(str_to_lower(coalesce(description, ""))))
  clave <- raw$clave[match(c(TR$property_id, TE$property_id), raw$property_id)]
  clave[clave == "" | usa_duplicados] <- NA
  vecinos <- function(q, q_apto) {
    idx <- matrix(NA_integer_, nrow(q), k_max)
    d <- matrix(NA_real_, nrow(q), k_max)
    for (t in 0:1) {
      pool <- which(TR$es_apto == t)
      qi <- which(q_apto == t)
      if (!length(qi)) next
      nn <- RANN::nn2(xy(TR)[pool, ], q[qi, , drop = FALSE], k = min(k_max, length(pool)))
      idx[qi, seq_len(ncol(nn$nn.idx))] <- pool[nn$nn.idx]
      d[qi, seq_len(ncol(nn$nn.idx))] <- nn$nn.dists
    }
    list(idx = idx, d = d)
  }
  list(
    V_tr = vecinos(xy(TR), TR$es_apto),
    V_te = vecinos(xy(TE), TE$es_apto),
    cl_tr = clave[seq_len(nrow(TR))],
    cl_te = clave[nrow(TR) + seq_len(nrow(TE))],
    ym2 = Y - TR$log_area,
    ks = ks,
    d0 = d0
  )
}

# Variables de comparables para unas filas, con referencia solo en el train marcado en en_ref (lógico).
# propio: índice en el train de cada fila (para excluirse a sí misma); NULL para el test.
comparables <- function(V, filas, en_ref, propio, cl_q, cmp) {
  idx <- V$idx[filas, , drop = FALSE]
  d <- V$d[filas, , drop = FALSE]
  K <- ncol(idx)
  idx1 <- replace(idx, is.na(idx), 1L)
  ok <- !is.na(idx) & en_ref[idx1]
  if (!is.null(propio)) ok <- ok & idx != rep(propio, K)
  dup <- cmp$cl_tr[idx1] == rep(cl_q, K)
  ok <- ok & !(!is.na(dup) & dup)
  ok[is.na(ok)] <- FALSE
  rango <- t(apply(ok, 1, cumsum)) # posición del vecino entre los válidos
  yv <- matrix(cmp$ym2[idx1], nrow(idx))
  d[is.na(d)] <- 0
  out <- list()
  ref_media <- mean(cmp$ym2[en_ref])
  for (k in cmp$ks) {
    sel <- ok & rango <= k
    w <- sel / (d + cmp$d0)
    s <- rowSums(w)
    m <- rowSums(w * yv) / s
    m[s == 0] <- ref_media # sin comparables válidos: media de referencia
    dist_k <- rowSums(sel * d) / pmax(rowSums(sel), 1)
    dist_k[s == 0] <- 5000
    out[[paste0("comp", k)]] <- m
    out[[paste0("comp_logdist", k)]] <- log1p(dist_k)
  }
  do.call(cbind, out)
}

# Atajos: train completo (cada uno sin sí mismo), test, y filas de un fold con referencia en a
comparables_train <- function(cmp) {
  comparables(cmp$V_tr, seq_len(nrow(TR)), rep(TRUE, nrow(TR)), seq_len(nrow(TR)), cmp$cl_tr, cmp)
}
comparables_test <- function(cmp) {
  comparables(cmp$V_te, seq_len(nrow(TE)), rep(TRUE, nrow(TR)), NULL, cmp$cl_te, cmp)
}
comparables_fold <- function(cmp, a, filas) {
  en <- logical(nrow(TR))
  en[a] <- TRUE
  comparables(cmp$V_tr, filas, en, filas, cmp$cl_tr[filas], cmp)
}
