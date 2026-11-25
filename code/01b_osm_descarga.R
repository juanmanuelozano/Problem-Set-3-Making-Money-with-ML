# Descarga de datos de OpenStreetMap vía API Overpass (sin sf: bloqueado por políticas de Windows)
# Guarda en data/external/osm/: localidades y UPZ (polígonos) y puntos de servicios urbanos (lat/lon)
# Las respuestas quedan en caché (.json): solo descarga lo que falte.
source(here::here("code", "01_setup.R"))

overpass <- function(q, file) {
  if (file.exists(file)) return(fromJSON(file, simplifyVector = FALSE))
  # Overpass limita las consultas seguidas (429/504): hasta 4 rondas por los dos servidores, esperando entre rondas
  for (ronda in 1:4) {
    for (url in c("https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter")) {
      # Overpass responde 406 al user agent por defecto de httr (2026-11): se envía uno genérico
      r <- try(POST(url, body = list(data = q), encode = "form", timeout(300), user_agent("ps3-texto/1.0")), silent = TRUE)
      if (!inherits(r, "try-error") && status_code(r) == 200) {
        writeLines(content(r, "text", encoding = "UTF-8"), file)
        Sys.sleep(5)
        return(fromJSON(file, simplifyVector = FALSE))
      }
    }
    Sys.sleep(30 * ronda)
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
  banco        = 'nwr["amenity"="bank"]',
  # Zona de lujo y de oficinas (sesión 7, experimental: se concentran en Chapinero y Usaquén, así que casi
  # funcionan como una dummy de localidad; ver D15)
  embajada     = 'nwr[~"^(office|amenity|diplomatic)$"~"^(diplomatic|embassy|consulate)$"]',
  oficina      = 'nwr["office"]',
  hotel        = 'nwr["tourism"="hotel"]',
  club         = 'nwr["leisure"~"^(golf_course|sports_club)$"]'
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

# ---- 3. Nombres de barrios (solo para quitarlos del texto en 03c_texto.py; no son variables) ----
js <- overpass(sprintf('[out:json][timeout:180];node["place"~"neighbourhood|suburb|quarter"](%s);out tags;', bbox),
               file.path(P$osm, "barrios.json"))
barrios <- tibble(nombre = map_chr(js$elements, ~ .x$tags$name %||% NA_character_), tipo = map_chr(js$elements, ~ .x$tags$place)) %>%
  filter(!is.na(nombre)) %>% distinct()
write_csv(barrios, file.path(P$osm, "barrios_nombres.csv"))
cat("Barrios:", nrow(barrios), "\n")

# ---- 4. Geometrías para variables de contexto (sesión 7, D15) ----
# Se guardan como vértices (lon, lat) con un id por línea o polígono. Las distancias a una línea se aproximan
# con la distancia al vértice más cercano, después de densificar los segmentos cada ~25 m (02_descriptivas.R).
# Líneas de un elemento de Overpass con 'out geom': un way trae $geometry; en una relación (multipolígono) los
# miembros 'outer' se unen en anillos cerrados con rings_from_rel(), para poder calcular áreas.
lineas_de <- function(js) {
  out <- list()
  for (e in js$elements) {
    geoms <- if (!is.null(e$geometry)) list(do.call(rbind, map(e$geometry, ~ c(.x$lon, .x$lat))))
             else rings_from_rel(list(members = keep(e$members, ~ !is.null(.x$geometry))))
    for (g in geoms) out[[length(out) + 1]] <- tibble(id = paste(e$type, e$id, length(out), sep = "_"),
                                                     lon = g[, 1], lat = g[, 2])
  }
  bind_rows(out)
}
geo <- list(
  # Cerros orientales: borde de la Reserva Forestal Bosque Oriental de Bogotá. En OSM es la relación 13780896,
  # etiquetada leisure=nature_reserve (no boundary=protected_area). La Avenida Circunvalar no aparece con ese
  # nombre en OSM (solo un tramo "Circunvalar Sur" proyectado), así que no se usa.
  cerros_reserva = '[out:json][timeout:240];rel(13780896);out geom;',
  # Vías principales (troncales y arterias)
  vias_principales = sprintf('[out:json][timeout:240];way["highway"~"^(trunk|primary)$"](%s);out geom;', bbox),
  # Parques como polígonos (para sumar su área, no solo contarlos)
  parques_poligonos = sprintf('[out:json][timeout:240];(way["leisure"="park"](%1$s);rel["leisure"="park"](%1$s););out geom;', bbox)
)
iwalk(geo, function(q, nm) {
  v <- lineas_de(overpass(q, file.path(P$osm, paste0(nm, ".json"))))
  write_csv(v, file.path(P$osm, paste0(nm, ".csv")))
  cat(nm, ": ", n_distinct(v$id), " líneas/polígonos, ", nrow(v), " vértices\n", sep = "")
})

# Edificios con número de pisos (building:levels): solo el centroide y los pisos
js <- overpass(sprintf('[out:json][timeout:300];way["building"]["building:levels"](%s);out center tags;', bbox),
               file.path(P$osm, "edificios_pisos.json"))
edif <- map_dfr(js$elements, function(e) tibble(lat = e$center$lat %||% NA_real_, lon = e$center$lon %||% NA_real_,
                                                 pisos = suppressWarnings(as.numeric(e$tags[["building:levels"]]))))
edif <- filter(edif, !is.na(lat), between(pisos, 1, 60))
write_csv(edif, file.path(P$osm, "edificios_pisos.csv"))
cat("Edificios con pisos:", nrow(edif), "\n")
