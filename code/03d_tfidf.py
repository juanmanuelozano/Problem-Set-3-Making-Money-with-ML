# =============================================================================
# 03d_tfidf.py - TF-IDF del texto limpio (ConTexto -> scikit-learn), etapa 2 de 2
# Unigramas y bigramas; se ajusta con train + test (no usa el precio: no hay fuga, D11).
# Entradas: data/processed/texto_limpio.csv (de 03c_texto.py)
# Salida:   data/processed/tfidf.parquet, formato largo y disperso: property_id, termino, tfidf (float32), solo celdas != 0
# En R:  t <- arrow::read_parquet(here::here("data", "processed", "tfidf.parquet"))
#        X <- Matrix::sparseMatrix(i = match(t$property_id, ids), j = as.integer(factor(t$termino)), x = t$tfidf)
# Uso: lo corre code/00_main.R con el entorno "texto". A mano: <python del entorno texto> code/03d_tfidf.py
# =============================================================================
import collections
import collections.abc
collections.Iterable = collections.abc.Iterable  # ConTexto (2021) usa la ruta vieja, que no existe desde Python 3.10

import os
from pathlib import Path
import numpy as np
import pandas as pd
from contexto.vectorizacion import VectorizadorFrecuencias

# Rutas desde la raíz del proyecto (la carpeta que contiene code/)
RAIZ = Path(__file__).resolve().parents[1]

d = pd.read_csv(RAIZ / "data/processed/texto_limpio.csv", keep_default_na=False)   # texto vacío = "" y no NaN

# min_df: términos en al menos 20 anuncios; max_df: sin términos en más del 90%; sublinear_tf: 1 + log(tf)
vec = VectorizadorFrecuencias(tipo="tfidf", rango_ngramas=(1, 2), max_elementos=5000,
                              min_df=20, max_df=0.9, sublinear_tf=True, dtype=np.float32)
vec.ajustar(d.texto)
X = vec.vectorizar(d.texto, disperso=True).tocoo()
voc = vec.vocabulario().sort_values("posición").palabra.to_numpy()

t = pd.DataFrame({"property_id": d.property_id.to_numpy()[X.row], "termino": voc[X.col], "tfidf": X.data})
t["termino"] = t.termino.astype("category")
t.to_parquet(RAIZ / "data/processed/tfidf.parquet", index=False)

print(f"Matriz {X.shape[0]} x {X.shape[1]} | celdas != 0: {X.nnz:,} ({X.nnz / np.prod(X.shape):.2%}) | "
      f"bigramas: {sum(' ' in v for v in voc)} | anuncios sin términos: {X.shape[0] - len(set(X.row))} | "
      f"archivo: {os.path.getsize(RAIZ / 'data/processed/tfidf.parquet') / 1e6:.1f} MB")
