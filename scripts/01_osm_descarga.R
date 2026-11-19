# Descarga de datos de OpenStreetMap vía API Overpass (sin sf: bloqueado por políticas de Windows)
# Guarda en data/external/osm/: localidades y UPZ (polígonos) y puntos de servicios urbanos (lat/lon)
# Correr desde la raíz del repo. Las respuestas quedan en caché (.json): solo descarga lo que falte.
source("scripts/00_config.R")
suppressMessages(pacman::p_load(httr, jsonlite))

overpass <- function(q, file) {
  if (file.exists(file)) return(fromJSON(file, simplifyVector = FALSE))
  for (url in c("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter")) {
    r <- try(POST(url, body = list(data = q), encode = "form", timeout(300)), silent = TRUE)
    if (!inherits(r, "try-error") && status_code(r) == 200) {
      writeLines(content(r, "text", encoding = "UTF-8"), file)
      Sys.sleep(2)
      return(fromJSON(file, simplifyVector = FALSE))
    }
  }
  stop("Overpass falló: ", file)
}

bbox <- "4.45,-74.25,4.85,-73.98"   # sur, oeste, norte, este (Bogotá urbana)

# ---- 1. Localidades (admin_level 8, "Localidad X") y UPZ (admin_level 9, "UPZ X") ----
q_poly <- function(lvl, pref) sprintf('[out:json][timeout:240];
rel["boundary"="administrative"]["admin_level"="%s"]["name"~"^%s "](%s);
out geom;', lvl, pref, bbox)

# Convierte relaciones a anillos (lista de data.frames lon/lat), uniendo segmentos 'outer'
rings_from_rel <- function(el) {
  segs <- keep(el$members, ~ .x$type == "way" && .x$role %in% c("outer", ""))
  segs <- map(segs, ~ do.call(rbind, map(.x$geometry, function(p) c(p$lon, p$lat))))
  rings <- list()
  while (length(segs) > 0) {
    cur <- segs[[1]]; segs <- segs[-1]
    repeat {
      if (isTRUE(all.equal(cur[1, ], cur[nrow(cur), ]))) break
      end <- cur[nrow(cur), ]; found <- FALSE
      for (i in seq_along(segs)) {
        s <- segs[[i]]
        if (isTRUE(all.equal(s[1, ], end))) { cur <- rbind(cur, s[-1, , drop = FALSE]); found <- TRUE }
        else if (isTRUE(all.equal(s[nrow(s), ], end))) { cur <- rbind(cur, s[nrow(s):1, , drop = FALSE][-1, , drop = FALSE]); found <- TRUE }
        if (found) { segs <- segs[-i]; break }
      }
      if (!found) break
    }
    rings[[length(rings) + 1]] <- cur
  }
  rings
}
to_poly <- function(js, pref) map_dfr(js$elements, function(el) {
  rs <- rings_from_rel(el)
  map_dfr(seq_along(rs), ~ tibble(nombre = str_remove(el$tags$name, paste0("^", pref, " ")),
                                  ring = .x, lon = rs[[.x]][, 1], lat = rs[[.x]][, 2]))
})
loc_poly <- to_poly(overpass(q_poly(8, "Localidad"), file.path(P$osm, "localidades.json")), "Localidad")
upz_poly <- to_poly(overpass(q_poly(9, "UPZ"), file.path(P$osm, "upz.json")), "UPZ")
write_csv(loc_poly, file.path(P$osm, "localidades_poligonos.csv"))
write_csv(upz_poly, file.path(P$osm, "upz_poligonos.csv"))
cat("Localidades:", n_distinct(loc_poly$nombre), " UPZ:", n_distinct(upz_poly$nombre), "\n")
print(count(distinct(loc_poly, nombre, ring), nombre))

# ---- 2. Servicios urbanos (nodos y centroides de vías/polígonos) ----
capas <- list(
  transmilenio = 'nwr["public_transport"="station"]["network"~"TransMilenio",i]',
  parque       = 'nwr["leisure"="park"]',
  centro_comercial = 'nwr["shop"="mall"]',
  universidad  = 'nwr["amenity"="university"]',
  colegio      = 'nwr["amenity"="school"]',
  hospital     = 'nwr["amenity"~"hospital|clinic"]',
  restaurante_bar = 'nwr["amenity"~"restaurant|bar|cafe|pub"]',
  supermercado = 'nwr["shop"="supermarket"]',
  policia      = 'nwr["amenity"="police"]',
  gimnasio     = 'nwr["leisure"="fitness_centre"]',
  banco        = 'nwr["amenity"="bank"]'
)
pts <- imap_dfr(capas, function(sel, nm) {
  q <- sprintf('[out:json][timeout:180];(%s(%s););out center tags;', sel, bbox)
  js <- overpass(q, file.path(P$osm, paste0(nm, ".json")))
  map_dfr(js$elements, function(e) {
    lat <- e$lat %||% e$center$lat; lon <- e$lon %||% e$center$lon
    if (is.null(lat)) return(NULL)
    tibble(capa = nm, osm_id = e$id, tipo = e$type, nombre = e$tags$name %||% NA_character_, lat = lat, lon = lon)
  })
})
write_csv(pts, file.path(P$osm, "servicios_puntos.csv"))
print(count(pts, capa))
