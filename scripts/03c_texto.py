# =============================================================================
# 03c_texto.py - Preprocesamiento del texto de los anuncios con ConTexto (DNP), etapa 1 de 2
# Pasos: limpieza básica -> reparar tildes/ñ perdidas -> quitar nombres de lugares (D10/D11) -> corrección conservadora
#        -> lematización (spaCy) -> quitar acentos -> stopwords -> palabras cortas -> n-gramas y nubes
# Entradas: data/processed/base_enriquecida.csv, data/external/osm/{localidades,upz}_poligonos.csv,
#           data/external/osm/barrios_nombres.csv (de 01_osm_descarga.R), data/external/dict_lemas.json
# Salidas:  data/processed/texto_limpio.csv, data/external/lugares_texto.csv,
#           reports/01_descriptivas/tables/texto_{correcciones,ngramas}.csv, figures/f11-f14_*_nubes.png
# Uso (desde la raíz): .venv/bin/python scripts/03c_texto.py   (instalación en requirements.txt)
# Después de revisar las nubes: ajustar STOP_EXTRA, LUGARES_EXTRA y dict_lemas.json, y volver a correr.
# =============================================================================
import collections
import collections.abc
collections.Iterable = collections.abc.Iterable  # ConTexto (2021) usa la ruta vieja, que no existe desde Python 3.10

import re
import time
import unicodedata
from collections import Counter

import matplotlib
matplotlib.use("Agg")
import pandas as pd
from spellchecker import SpellChecker
from contexto.limpieza import limpieza_basica, remover_acentos, remover_palabras_cortas, remover_stopwords, lista_stopwords
from contexto.correccion import Corrector
from contexto.lematizacion import LematizadorSpacy
from contexto.exploracion import frecuencia_ngramas, par_nubes

# ---- Listas que se ajustan después de revisar las nubes ----
# Palabras sin contenido propio de los anuncios (revisión de las nubes, 2026-11-19). Se dejan los adjetivos (excelente,
# hermoso): pueden reflejar el segmento. El tipo de inmueble y los números ya están en es_apto, bedrooms, banos y piso_txt.
STOP_EXTRA = ["contar", "tener", "ser", "constar", "encontrar", "ubicado",                       # verbos genéricos
              "vender", "venta", "vendemos", "cod", "codigo", "informacion", "mayor", "pagina", "web",  # venta y contacto
              "apartamento", "casa",                                                            # tipo de inmueble
              "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez",
              "primero", "segundo", "tercero", "quinto"]   # números escritos; "cuarto" no: aquí suele ser habitación
LUGARES_EXTRA = ["rosales", "chico", "nogal", "cabrera", "country", "andino", "unicentro", "zona rosa", "santa barbara",
                 "virrey", "usaquen", "bogota", "santa paula", "san patricio"]   # lugares que las reglas no capturan
NO_STOP = {"sin", "no"}        # se conservan: con bigramas capturan negaciones ("sin ascensor")
COMUN = 1000                   # frecuencia en el diccionario de español desde la que una palabra se considera común

T0 = time.time()
def paso(msg): print(f"[{time.time() - T0:6.0f}s] {msg}", flush=True)
def sin_tildes(s): return unicodedata.normalize("NFD", s).encode("ascii", "ignore").decode()
def norma(s): return remover_acentos(limpieza_basica(s, quitar_numeros=True)).strip()

# ---- 1. Datos y limpieza básica ----
d = pd.read_csv("data/processed/base_enriquecida.csv", usecols=["property_id", "muestra", "price", "title", "description"])
assert d.property_id.is_unique
# ~8.800 entidades HTML llegaron partidas en el crudo, sin & ni ;: "ba ntilde o" (baño), "recepci oacute n". Se vuelven
# a pegar a la letra ("bano", "recepcion") y se quitan nbsp / amp / quot.
ENTIDAD = re.compile(r" ?\b(?:([aeiou])acute|(n)tilde|(u)uml)\b ?")
SOBRA = re.compile(r"\b(?:nbsp|amp|quot)\b")
def entidades(t): return SOBRA.sub(" ", ENTIDAD.sub(lambda m: next(g for g in m.groups() if g), t))
d["texto"] = [entidades(norma(t)) for t in d.title.fillna("") + " " + d.description.fillna("")]
EJEMPLOS = d.sample(5, random_state=123).index
def muestra_ejemplos(etapa): print(f"\n--- {etapa} ---\n" + "\n".join(d.texto[i][:200] for i in EJEMPLOS))
muestra_ejemplos("1. limpieza básica")
n_palabras = d.texto.str.split().str.len().sum()
paso(f"limpieza básica: {len(d)} anuncios, {n_palabras:,} palabras")

# Diccionario de español sin tildes (el texto viene sin tildes ni ñ): frecuencias sumadas por forma sin tilde
DIC = Counter()
for w, f in SpellChecker(language="es").word_frequency.dictionary.items():
    DIC[sin_tildes(w)] += f

# ---- 1b. Reparar caracteres perdidos ----
# En ~1/4 de los anuncios las letras con tilde y la ñ se perdieron en vez de transcribirse ("baos", "usaqun", "saln").
# Regla: palabra de 4+ letras que no existe en el diccionario -> se le inserta una vocal o una n; se acepta la versión
# más frecuente del corpus si aparece 10+ veces y al menos 1/10 de lo que aparece la palabra dañada. Las de 3 letras
# son ruidosas (min -> mini), así que van a mano, igual que las que quedaron convertidas en otra palabra real.
REPARA = {"bao": "bano", "aos": "anos", "rea": "area", "vas": "vias", "lavandera": "lavanderia", "lavander": "lavanderia"}
vocab = Counter(w for t in d.texto for w in t.split())
def reparada(w):
    c = [x for x in {w[:i] + v + w[i:] for i in range(len(w) + 1) for v in "aeioun"} if vocab[x] >= 10 and vocab[x] > vocab[w] / 10]
    return max(c, key=vocab.get) if c else None
rep = {w: r for w in vocab if len(w) >= 4 and DIC[w] == 0 and (r := reparada(w))}
rep = {w: rep.get(r, r) for w, r in rep.items()} | REPARA      # una vuelta transitiva: balc -> balcn -> balcon
d["texto"] = [" ".join(rep.get(w, w) for w in t.split()) for t in d.texto]
pd.DataFrame([(w, vocab[w], r) for w, r in rep.items()], columns=["palabra", "frecuencia", "reparada"]).sort_values(
    "frecuencia", ascending=False).to_csv("reports/01_descriptivas/tables/texto_reparaciones.csv", index=False)
paso(f"reparación de caracteres perdidos: {len(rep):,} palabras, {sum(vocab[w] for w in rep) / n_palabras:.1%} de las palabras")
muestra_ejemplos("1b. reparado")

# ---- 2. Quitar nombres de lugares ----
# Frase completa: nombres de localidades, UPZ y barrios de OSM. Si tienen 2+ palabras de contenido se borran siempre
# ("santa ana", "puente largo", "polo club"); si tienen una sola, solo si no es común ("el parque" y "bosque" no se borran).
# Palabra suelta: las palabras de esos nombres que no son comunes en español ("cedritos", "chapinero", "teusaquillo").
nombres = pd.concat([pd.read_csv(f"data/external/osm/{f}.csv").nombre for f in
                     ["localidades_poligonos", "upz_poligonos", "barrios_nombres"]]).dropna().unique()
nombres = {re.sub(r"^(localidad|barrio|upz|urbanizacion) ", "", norma(n)) for n in nombres} - {""}
stop = {sin_tildes(w) for w in lista_stopwords("es")}
def comun(w):   # palabra común del español; los plurales cuentan por su singular ("parques", "buenos", "balcones")
    return len(w) < 4 or w in stop or any(DIC[s] >= COMUN for s in (w, w[:-1] if w.endswith("s") else w, w[:-2] if w.endswith("es") else w))
frases = {n for n in nombres if sum(w not in stop for w in n.split()) >= 2 or not all(comun(w) for w in n.split())}
palabras = {w for n in nombres for w in n.split() if not comun(w)}
lugares = sorted(frases | palabras | set(LUGARES_EXTRA), key=len, reverse=True)
LUG, NMAX = set(lugares), max(len(l.split()) for l in lugares)
quitadas = Counter()
def sin_lugares(t):
    # recorre las palabras y quita la frase de lugar más larga que empiece en cada posición (n-gramas en un set)
    w, out, i = t.split(), [], 0
    while i < len(w):
        n = next((n for n in range(min(NMAX, len(w) - i), 0, -1) if " ".join(w[i:i + n]) in LUG), 0)
        if n:
            quitadas[" ".join(w[i:i + n])] += 1; i += n
        else:
            out.append(w[i]); i += 1
    return " ".join(out)
d["texto"] = [sin_lugares(t) for t in d.texto]
pd.DataFrame({"lugar": lugares,
              "regla": ["manual" if l in LUGARES_EXTRA else "frase" if l in frases else "palabra" for l in lugares],
              "apariciones": [quitadas[l] for l in lugares]}
             ).sort_values("apariciones", ascending=False).to_csv("data/external/lugares_texto.csv", index=False)
paso(f"lugares: {len(lugares)} nombres, {sum(quitadas.values()):,} apariciones borradas "
     f"({sum(len(m.split()) * c for m, c in quitadas.items()) / n_palabras:.1%} de las palabras). "
     f"Más frecuentes: {', '.join(m for m, _ in quitadas.most_common(12))}")
muestra_ejemplos("2. sin lugares")

# ---- 3. Corrección ortográfica conservadora, sobre el vocabulario ----
# Solo palabras raras (<= 3 apariciones, 4+ letras) desconocidas, y solo hacia una candidata (distancia 1) frecuente en
# el corpus (>= 10). Al diccionario se suman las palabras frecuentes del corpus para que las del gremio cuenten
# como correctas ("parqueadero", "apartaestudio").
vocab = Counter(w for t in d.texto for w in t.split())
# Se pasa una lista y no un dict: con dict, ConTexto hace load_words([palabra] * frecuencia) (cientos de millones de
# elementos, ~15 min). Las frecuencias no hacen falta: la candidata se elige por su frecuencia en el corpus.
corrector = Corrector("es", diccionario=list(DIC) + [w for w, f in vocab.items() if f >= 10], distancia=1)
desconocidas = corrector.palabras_desconocidas(" ".join(vocab))
mapa = {}
for w in desconocidas:
    if vocab[w] <= 3 and len(w) >= 4:
        cands = [c for c in (corrector.palabras_candidatas(w) or ()) if vocab[c] >= 10]
        if cands:
            mapa[w] = max(cands, key=vocab.get)
d["texto"] = [" ".join(mapa.get(w, w) for w in t.split()) for t in d.texto]
pd.DataFrame([(w, vocab[w], c, vocab[c]) for w, c in mapa.items()],
             columns=["palabra", "frecuencia", "correccion", "frecuencia_correccion"]
             ).sort_values("frecuencia_correccion", ascending=False
             ).to_csv("reports/01_descriptivas/tables/texto_correcciones.csv", index=False)
paso(f"corrección: {len(desconocidas):,} desconocidas, {len(mapa):,} corregidas "
     f"({sum(vocab[w] for w in mapa) / n_palabras:.2%} de las palabras)")

# ---- 4. Lematización (spaCy es_core_news_md vía ConTexto, con lemas propios del dominio) ----
lem = LematizadorSpacy("es", "md", dict_lemmas="data/external/dict_lemas.json")   # se carga una sola vez
d["texto"] = [lem.lematizar(t, limpiar=False) for t in d.texto]
paso("lematización")
muestra_ejemplos("4. lematizado")

# ---- 5-7. Acentos (los lemas de spaCy traen tilde), stopwords y palabras cortas ----
lista_stop = sorted(stop - NO_STOP | set(STOP_EXTRA))
d["texto"] = [remover_palabras_cortas(remover_stopwords(remover_acentos(t), lista_palabras=lista_stop), 3).strip()
              for t in d.texto]
muestra_ejemplos("7. final")
d[["property_id", "muestra", "texto"]].to_csv("data/processed/texto_limpio.csv", index=False)
paso(f"texto final: {d.texto.str.split().str.len().sum():,} palabras, "
     f"vocabulario {len(set(w for t in d.texto for w in t.split())):,}; vacíos: {(d.texto == '').sum()}")

# ---- 8. Exploración: n-gramas y nubes por grupo ----
# train vs test (el test es casi todo Chapinero) y, dentro del train, viviendas caras (precio > p75) vs baratas (< p25)
tr = d[d.muestra == "train"]
p25, p75 = tr.price.quantile([.25, .75])
grupos = {"f11_train": tr, "f12_test": d[d.muestra == "test"], "f13_caras": tr[tr.price > p75], "f14_baratas": tr[tr.price < p25]}
print(f"Precio p25 = {p25 / 1e6:,.0f} M, p75 = {p75 / 1e6:,.0f} M; caras: {len(grupos['f13_caras'])}, baratas: {len(grupos['f14_baratas'])}")
filas = []
for nombre, g in grupos.items():
    m = nombre.split("_")[1]
    junto = " ".join(g.texto)   # ponytail: une anuncios; se cuela un bigrama falso por anuncio, despreciable
    for n in (1, 2):
        filas += [(m, n, k, v) for k, v in frecuencia_ngramas(junto, n, n_max=100).items()]
    par_nubes(junto, n1=1, n2=2, graficar=False, ubicacion_archivo=f"reports/01_descriptivas/figures/{nombre}_nubes.png")
pd.DataFrame(filas, columns=["muestra", "n", "ngrama", "frecuencia"]).to_csv(
    "reports/01_descriptivas/tables/texto_ngramas.csv", index=False)
paso("n-gramas y nubes. Listo.")
