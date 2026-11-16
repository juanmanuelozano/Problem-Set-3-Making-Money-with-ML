# Registro de decisiones metodológicas

Cada decisión registra el contexto, qué se decidió y por qué. Las más recientes van al final.

---

### D1 · Validación con folds espaciales, no aleatorios (2026-11-14)
**Contexto:** el 94% del test está en Chapinero; el train tiene solo 307 observaciones ahí.
**Decisión:** 5 folds por k-means sobre las coordenadas del train. Además del MAE OOF total se reportan el MAE en Chapinero (307 obs) y el MAE en el fold 2 (Usaquén y la mayor parte de Chapinero, el bloque más parecido al test).
**Por qué:** una validación aleatoria premia memorizar barrios vecinos y sobreestima el desempeño fuera de la zona de entrenamiento.

### D2 · Variable objetivo en logaritmo y recorte al soporte (2026-11-14)
**Decisión:** modelar `log(price)`, predecir `exp(ŷ)` y recortar al intervalo [300, 1.650] millones.
**Por qué:** el precio es asimétrico y está truncado. Con una pérdida MAE, `exp` de la media condicional del log se acerca a la mediana condicional.

### D3 · Jerarquía para el área (2026-11-14)
**Decisión:** observada → texto (solo si está entre 0,5 y 2 veces la predicción del modelo de imputación) → imputada con random forest (R² OOB 0,83), más indicadores de la fuente.
**Por qué:** la extracción del texto es ruidosa (captura áreas de terrazas o lotes). La regla de coherencia descarta los casos absurdos.

### D4 · Estrato imputado espacialmente (2026-11-14)
**Decisión:** usar el estrato mencionado en el texto y, si falta, una predicción con coordenadas y entorno (R² OOB 0,79).
**Por qué:** el estrato es central en la literatura de precios en Colombia y es esencialmente espacial. Pendiente: reemplazarlo con el estrato por manzana de los datos abiertos de Bogotá.

### D5 · Se descarta `rooms` (2026-11-14)
**Por qué:** su correlación con `bedrooms` es 0,99 y le falta el 47% de los datos.

### D6 · Combinar tendencia lineal y árboles (2026-11-14)
**Contexto:** con validación espacial, el RF (203 M) y XGBoost (180 M) son peores que el lasso (159 M) en Chapinero. Los árboles no predicen por encima de los valores de las zonas que vieron.
**Decisión:** priorizar los modelos que extrapolan: XGBoost sobre log(precio/m²) e híbrido lasso (`base_margin`) + XGBoost en residuos, con validación anidada.
**Por qué:** el híbrido da el mejor MAE en Chapinero (155 M) sin perder en el total.

### D7 · Métrica de selección: Chapinero sobre total (2026-11-14)
**Decisión:** para elegir el envío pesa más el MAE en las 307 observaciones de Chapinero que el MAE total, teniendo en cuenta su ruido (error estándar de ±8–10 M).
**Por qué:** el test es Chapinero. El MAE total está dominado por Usaquén (55% del train).
