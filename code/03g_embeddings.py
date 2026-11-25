# =============================================================================
# 03g_embeddings.py - Embeddings de oraciones de los anuncios (D11, D25)
# El diagnóstico de las ramas (08l) muestra que la red usa poco el texto (pendiente 1,43): el TF-IDF solo ve 1.000
# palabras sueltas. Un modelo de oraciones multilingüe resume el sentido de la descripción en un vector denso.
# Modelo: intfloat/multilingual-e5-small (384 dimensiones; prefijo "query: ", vectores normalizados).
# Texto: título + descripción con la misma limpieza básica de 03c (minúsculas, sin tildes ni números ni símbolos, entidades
# HTML reparadas) y SIN nombres de lugares (lista de 03c, data/external/lugares_texto.csv, D10): la rama de texto no debe
# aprender la ubicación. No se lematiza ni se quitan stopwords: el modelo necesita las frases completas.
# Entorno aparte "emb" (requirements-emb.txt; necesita PyTorch y no se mezcla con los de texto ni TensorFlow). Lo crea
# code/00_main.R fuera de la carpeta sincronizada (OneDrive/iCloud). Uso: lo corre el main con PYTHON <- TRUE; a mano,
#   <python del entorno emb> code/03g_embeddings.py
# Salida: data/processed/embeddings_texto.parquet (property_id, e000-e383, float32)
# =============================================================================
import re
from pathlib import Path
import time
import unicodedata
import numpy as np
import pandas as pd
import torch
from sentence_transformers import SentenceTransformer

# Rutas desde la raíz del proyecto (la carpeta que contiene code/)
RAIZ = Path(__file__).resolve().parents[1]

T0 = time.time()
def paso(msg): print(f"[{time.time() - T0:6.0f}s] {msg}", flush=True)
def sin_tildes(s): return unicodedata.normalize("NFD", s).encode("ascii", "ignore").decode()
def norma(s): return re.sub(r"\s+", " ", re.sub(r"[^a-z ]", " ", sin_tildes(s.lower()))).strip()
ENTIDAD = re.compile(r" ?\b(?:([aeiou])acute|(n)tilde|(u)uml)\b ?")   # como en 03c: "ba ntilde o" -> "bano"
SOBRA = re.compile(r"\b(?:nbsp|amp|quot)\b")
def entidades(t): return re.sub(r"\s+", " ", SOBRA.sub(" ", ENTIDAD.sub(lambda m: next(g for g in m.groups() if g), t))).strip()

d = pd.read_csv(RAIZ / "data/processed/base_enriquecida.csv", usecols=["property_id", "title", "description"])
assert d.property_id.is_unique
d["texto"] = [entidades(norma(t)) for t in d.title.fillna("") + " " + d.description.fillna("")]
# Nombres de lugares: la frase más larga que empiece en cada posición (igual que sin_lugares() de 03c)
LUG = set(pd.read_csv(RAIZ / "data/external/lugares_texto.csv").lugar.dropna())
NMAX = max(len(l.split()) for l in LUG)
def sin_lugares(t):
    w, out, i = t.split(), [], 0
    while i < len(w):
        n = next((n for n in range(min(NMAX, len(w) - i), 0, -1) if " ".join(w[i:i + n]) in LUG), 0)
        if n: i += n
        else: out.append(w[i]); i += 1
    return " ".join(out)
d["texto"] = [sin_lugares(t) for t in d.texto]
paso(f"{len(d):,} textos; mediana {int(d.texto.str.split().str.len().median())} palabras. Ejemplo: {d.texto.iloc[0][:150]}")

disp = "mps" if torch.backends.mps.is_available() else "cpu"
m = SentenceTransformer("intfloat/multilingual-e5-small", device=disp)
m.max_seq_length = 256   # ~85% de los textos cabe entero; el resto se trunca
paso(f"modelo cargado ({disp})")
E = m.encode(["query: " + t for t in d.texto], batch_size=64, normalize_embeddings=True, show_progress_bar=False,
             convert_to_numpy=True).astype(np.float32)
paso(f"embeddings: {E.shape}")
out = pd.DataFrame(E, columns=[f"e{k:03d}" for k in range(E.shape[1])])
out.insert(0, "property_id", d.property_id.values)
out.to_parquet(RAIZ / "data/processed/embeddings_texto.parquet", index=False)
paso("Listo: data/processed/embeddings_texto.parquet")
