# =============================================================================
# utils_comparables.R - Comparables (precio por m2 de los vecinos del train) para las redes, D23
# Funciones copiadas de la rama validacion-sintetica (utils_modelos.R de María José, D20), con dos cambios:
#  1. Radio mínimo emparejado con el test. En el train, el 70% de los anuncios tiene otro del mismo tipo a menos de
#     15 m (mismo edificio; mediana del 1er vecino 0 m, del 5º 29 m); en el test solo el 18% (106 m y 211 m). A cada
#     anuncio del train se le sortea un radio de la distribución de distancias del test al 1er vecino del train y se
#     excluyen los vecinos más cercanos: así los comparables significan lo mismo en el train y en el test.
#  2. FOLDS_EDIF: CV aleatoria de 5 folds agrupada por edificio (mismas coordenadas, ~11 m). La CV por localidad con
#     buffer (D9) deja sin vecinos a los anuncios evaluados, así que no sirve para modelos con comparables.
# Uso, después de utils_modelos.R: source("scripts/utils_comparables.R"); CMP <- prepara_comparables()
# =============================================================================
suppressMessages(pacman::p_load(RANN))

FOLDS_EDIF <- local({
  set.seed(123); edif <- paste(round(TR$lat, 4), round(TR$lon, 4))
  g <- sample(rep(1:5, length.out = n_distinct(edif)))[match(edif, unique(edif))]
  map(1:5, ~ list(analisis = which(g != .x), evaluacion = which(g == .x)))
})

# por_tipo = FALSE: vecinos de cualquier tipo (no mezcla la variable es_apto de la estructura). emb: matriz de embeddings
# del texto (filas = c(TR, TE), normalizadas): los vecinos se ponderan por (1 + similitud coseno)/2 y se excluyen los de similitud
# > sim_max (el mismo inmueble con la descripción editada: no es un comparable sino una re-publicación).
prepara_comparables <- function(k_max = 200, ks = c(5, 20), d0 = 30, por_tipo = TRUE, emb = NULL, sim_max = .95) {
  m_lon <- 111320 * cos(4.65 * pi / 180); m_lat <- 110574
  xy <- function(df) cbind(df$lon * m_lon, df$lat * m_lat)     # coordenadas planas en metros
  # Claves de descripción: el mismo inmueble publicado dos veces no puede ser su propio comparable
  raw <- bind_rows(lee_csv(file.path(P$raw, "train.csv")), lee_csv(file.path(P$raw, "test.csv"))) %>%
    transmute(property_id, clave = str_squish(str_to_lower(coalesce(description, ""))))
  clave <- raw$clave[match(c(TR$property_id, TE$property_id), raw$property_id)]
  clave[clave == ""] <- NA
  vecinos <- function(q, q_apto) {   # los k_max anuncios del train más cercanos (y del mismo tipo si por_tipo)
    idx <- matrix(NA_integer_, nrow(q), k_max); d <- matrix(NA_real_, nrow(q), k_max)
    if (!por_tipo) q_apto[] <- 0
    for (t in 0:1) {
      pool <- which(if (por_tipo) TR$es_apto == t else rep(t == 0, nrow(TR))); qi <- which(q_apto == t)
      if (!length(qi)) next
      nn <- RANN::nn2(xy(TR)[pool, ], q[qi, , drop = FALSE], k = min(k_max, length(pool)))
      idx[qi, seq_len(ncol(nn$nn.idx))] <- pool[nn$nn.idx]; d[qi, seq_len(ncol(nn$nn.idx))] <- nn$nn.dists
    }
    list(idx = idx, d = d)
  }
  sim <- function(V, Eq) {   # similitud coseno entre cada fila y cada uno de sus vecinos candidatos
    if (is.null(emb)) return(NULL)
    S <- matrix(NA_real_, nrow(V$idx), ncol(V$idx)); Et <- emb[seq_len(nrow(TR)), , drop = FALSE]
    for (j in seq_len(ncol(V$idx))) { k <- V$idx[, j]; ok <- !is.na(k); S[ok, j] <- rowSums(Eq[ok, , drop = FALSE] * Et[k[ok], , drop = FALSE]) }
    S
  }
  V_tr <- vecinos(xy(TR), TR$es_apto); V_te <- vecinos(xy(TE), TE$es_apto)
  V_tr$S <- sim(V_tr, emb[seq_len(nrow(TR)), , drop = FALSE]); V_te$S <- sim(V_te, emb[nrow(TR) + seq_len(nrow(TE)), , drop = FALSE])
  cmp <- list(V_tr = V_tr, V_te = V_te, sim_max = sim_max,
              cl_tr = clave[seq_len(nrow(TR))], cl_te = clave[nrow(TR) + seq_len(nrow(TE))],
              ym2 = Y - TR$log_area, ks = ks, d0 = d0, r_tr = 0)
  # Radio mínimo del train: distancia del test a su 1er comparable válido, sorteada con reemplazo (semilla 123)
  d1_te <- expm1(comparables(cmp$V_te, seq_len(nrow(TE)), rep(TRUE, nrow(TR)), NULL, cmp$cl_te, modifyList(cmp, list(ks = 1)))[, "comp_logdist1"])
  set.seed(123); cmp$r_tr <- sample(d1_te, nrow(TR), replace = TRUE)
  cmp
}
# Variables de comparables para unas filas, con referencia solo en el train marcado en en_ref (lógico).
# propio: índice en el train de cada fila (para excluirse a sí misma); NULL para el test. r_min: radio mínimo por fila.
comparables <- function(V, filas, en_ref, propio, cl_q, cmp, r_min = 0) {
  idx <- V$idx[filas, , drop = FALSE]; d <- V$d[filas, , drop = FALSE]; K <- ncol(idx)
  idx1 <- replace(idx, is.na(idx), 1L)
  ok <- !is.na(idx) & en_ref[idx1] & !is.na(d) & d >= r_min     # r_min (largo = filas) se recicla por fila
  S <- if (is.null(V$S)) NULL else V$S[filas, , drop = FALSE]
  if (!is.null(S)) ok <- ok & !is.na(S) & S <= cmp$sim_max                # casi idénticos: re-publicaciones
  if (!is.null(propio)) ok <- ok & idx != rep(propio, K)
  dup <- cmp$cl_tr[idx1] == rep(cl_q, K); ok <- ok & !(!is.na(dup) & dup)
  ok[is.na(ok)] <- FALSE
  rango <- t(apply(ok, 1, cumsum))                          # posición del vecino entre los válidos
  yv <- matrix(cmp$ym2[idx1], nrow(idx)); d[is.na(d)] <- 0
  out <- list(); ref_media <- mean(cmp$ym2[en_ref])
  for (k in cmp$ks) {
    sel <- ok & rango <= k; w <- sel / (d + cmp$d0); if (!is.null(S)) w <- w * (1 + S) / 2; s <- rowSums(w)   # coseno centrado: sin relación 0,5; parecido -> 1
    m <- rowSums(w * yv) / s; m[s == 0] <- ref_media           # sin comparables válidos: media de referencia
    dist_k <- rowSums(sel * d) / pmax(rowSums(sel), 1); dist_k[s == 0] <- 5000
    out[[paste0("comp", k)]] <- m; out[[paste0("comp_logdist", k)]] <- log1p(dist_k)
  }
  do.call(cbind, out)
}
# Atajos: train completo (cada uno sin sí mismo y con su radio), test (sin radio), y filas de un fold con referencia en a
comparables_train <- function(cmp) comparables(cmp$V_tr, seq_len(nrow(TR)), rep(TRUE, nrow(TR)), seq_len(nrow(TR)), cmp$cl_tr, cmp, cmp$r_tr)
comparables_test  <- function(cmp) comparables(cmp$V_te, seq_len(nrow(TE)), rep(TRUE, nrow(TR)), NULL, cmp$cl_te, cmp)
comparables_fold  <- function(cmp, a, filas) { en <- logical(nrow(TR)); en[a] <- TRUE
  comparables(cmp$V_tr, filas, en, filas, cmp$cl_tr[filas], cmp, cmp$r_tr[filas]) }
