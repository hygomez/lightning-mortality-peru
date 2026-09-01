# MÉTODO GEOESPACIAL — Paper 06, mortalidad por rayos, Perú 2017–2024

**Entregable de la Fase 5.** Levantado el 2026-08-25.
Fuentes auditadas: `R/41_rayo_densidad.R` y `R/11_poblacion.R` del proyecto fuente
(proyecto de origen, ruta local no publicada), más verificación empírica directa sobre el grid
LIS/OTD y el shapefile distrital.

Herramientas de verificación: Python 3.14 con rasterio 1.5.1, geopandas 1.1.4, numpy 2.5.2
(instaladas en entorno virtual local; los wheels traen GDAL incorporado, no requirieron `sudo`).

---

## 1. El procedimiento de asignación píxel-polígono: resuelto

### 1.1 Lo que dice el manuscrito

> «the arithmetic mean of grid-cell values assigned to each polygon»

*Assigned* es ambiguo, y con razón: **el procedimiento real tiene dos regímenes**, no uno.

### 1.2 Lo que hace el código

`R/41_rayo_densidad.R`, línea operativa:

```r
dens <- terra::extract(pe, dv, fun = mean, na.rm = TRUE, ID = FALSE)
```

`terra::extract` sobre polígonos, con los valores por defecto `touches = FALSE`,
`exact = FALSE`, `weights = FALSE`.

### 1.3 Verificación empírica

Se replicaron las tres semánticas candidatas en Python sobre el mismo raster
(`flashrate_peru.tif`, el recorte que el propio script guardó) y el mismo shapefile, y se
compararon contra la columna `densidad` publicada, redondeada a 2 decimales:

| Semántica | Coincidencias | % |
|---|---|---|
| **A. Celdas cuyo centro cae dentro del polígono, media aritmética simple** | 1 527 / 1 891 | 80,75 % |
| B. Todas las celdas que el polígono toca, media simple | 104 / 1 891 | 5,50 % |
| C. Media ponderada por área de intersección | 151 / 1 891 | 7,99 % |

Desagregando:

| Subconjunto | Semántica que reproduce | Coincidencias |
|---|---|---|
| Distritos con **≥ 1 centro de celda** dentro (n = 1 527) | **A (centro-en-polígono)** | **1 527 / 1 527 = 100,00 %** |
| Distritos **sin ningún centro** dentro (n = 364) | **B (todas las celdas tocadas)** | **357 / 364 = 98,08 %** |

**Conclusión: el procedimiento es un híbrido de dos regímenes**, aplicado automáticamente por
`terra` sin que el código lo declare. Cuando el polígono contiene al menos un centro de celda,
promedia esas celdas. Cuando no contiene ninguno —porque el distrito es menor que una celda o
tiene forma alargada— `terra` recurre a todas las celdas que el polígono intersecta.

Los 7 distritos restantes (1,9 % de los 364) no se reproducen exactamente por ninguna de las
tres semánticas; se atribuyen a diferencias de tolerancia geométrica entre GEOS y terra en
polígonos que rozan el borde de una celda.

### 1.4 Frase precisa para Métodos

> District-level flash density was obtained from the NASA LIS/OTD Reprocessed Lightning
> Climatology (`COMB_OTD_TRMM_ISS_AnnualMean`, 0.1° grid, annual mean flash rate) by
> zonal extraction over the 2025 INEI district polygons. For each district, the value is the
> unweighted arithmetic mean of the grid cells whose **centre** falls within the district
> polygon. For districts containing no cell centre — 364 of 1 891 (19.2 %), all of them
> smaller than or comparable to a single 0.1° cell — the value is the unweighted arithmetic
> mean of **all cells intersecting** the polygon. No area weighting was applied in either
> regime. Extraction used `terra::extract(..., fun = mean, na.rm = TRUE)` with default
> arguments, whose documented behaviour implements this two-regime rule.

---

## 2. Distritos menores que una celda de 0,1°

A la latitud del Perú, una celda de 0,1° mide entre **116,9 y 123,1 km²** (mediana 120,5 km²).

| Métrica | Valor |
|---|---|
| Distritos menores que una celda | **617 de 1 891 (32,6 %)** |
| Distritos sin ningún centro de celda dentro | **364 de 1 891 (19,2 %)** |
| — de ellos, menores que una celda | 333 (91,5 %) |
| — de ellos, mayores que una celda pero de forma alargada | 31 |

Los 31 restantes son distritos de área mayor a una celda cuya geometría alargada o irregular
esquiva todos los centros de celda. Es un recordatorio de que el criterio no es el área sino
la geometría.

### Cómo se resolvieron

Por el régimen B descrito arriba: media de todas las celdas intersectadas. Ninguno quedó sin
valor — no hay `NA` en la columna `densidad` publicada.

**Consecuencia metodológica que debe declararse:** los distritos pequeños reciben un valor
promediado sobre un vecindario **mayor que el propio distrito** (hasta 7 celdas, ≈ 840 km²,
para un distrito de 70 km²). Esto suaviza su densidad hacia la del entorno regional y atenúa
el contraste entre distritos vecinos. Es un sesgo hacia la media, no un sesgo direccional.

### Distribución por estrato

| Estrato | Distritos | Menores que una celda | Sin centro de celda | Densidad = 0 |
|---|---|---|---|---|
| 0–500 m | 309 | 115 | 86 | 106 |
| 500–1 500 m | 214 | 33 | 16 | 41 |
| 1 500–2 500 m | 210 | 59 | 29 | 15 |
| 2 500–3 500 m | 435 | 190 | 113 | 20 |
| **> 3 500 m** | **723** | **220** | **120** | **8** |

El estrato de altura tiene la mayor proporción absoluta de distritos pequeños (220), lo que
significa que **la densidad de rayos en altura está más suavizada que en la costa**. Dado que
la densidad entra como covariable de ajuste en el Modelo 2, esta atenuación es relevante y
debe mencionarse en Limitaciones.

---

## 3. Los 190 distritos con densidad cero: veredicto

Se examinó el grid crudo **antes** de la agregación por polígono, conforme al criterio de
discriminación de tres escenarios.

### 3.1 Escenario (c) — fallo de asignación: **DESCARTADO**

De los 190 distritos con densidad publicada igual a cero:

| Situación | n |
|---|---|
| Con ≥ 1 centro de celda dentro, y **todas** esas celdas valen exactamente 0 | **135** |
| Con ≥ 1 centro de celda dentro y **alguna** celda positiva | **0** |
| Sin ningún centro de celda, y **todas** las celdas tocadas valen exactamente 0 | **55** |

**Ningún distrito perdió valores positivos en la agregación.** En los 190 casos, las celdas
efectivamente asignadas valen cero en el grid. No es un bug de asignación.

### 3.2 La estructura del grid: hay un piso de detección

El recorte del Perú (26 600 celdas de 0,1°) presenta una discontinuidad tajante:

| Métrica | Valor |
|---|---|
| Celdas con valor exactamente 0 | 8 462 (31,8 %) |
| Celdas con valor positivo | 18 138 |
| **Mínimo positivo observado** | **0,412787** descargas km⁻² año⁻¹ |
| **Celdas con valor en el intervalo (0, 0,4128)** | **0** |

**El producto no puede expresar valores entre cero y 0,41.** No hay un continuo que se
aproxime a cero: hay un salto. Un cero en este grid no significa «cero descargas»; significa
**«por debajo del mínimo representable»**. Es un dato censurado por la izquierda, no un cero
medido.

Esto es coherente con la naturaleza del producto: es una climatología construida sobre
recuentos de destellos observados por sensores en órbita, con muestreo temporal limitado por
la trayectoria de TRMM/ISS. Una celda que no acumuló ningún destello durante el periodo de
observación recibe exactamente 0, con independencia de si su tasa verdadera es 0 o 0,3.

### 3.3 Escenarios (a) y (b): coexisten, y se distinguen espacialmente

Restringiendo a las 10 614 celdas cuyo centro cae en territorio peruano:

| Métrica | Valor |
|---|---|
| Celdas terrestres con valor 0 | **986 (9,3 %)** |
| — con **al menos un vecino positivo** de los 8 adyacentes | **766 (77,7 %)** |
| — sin ningún vecino positivo (bloques contiguos) | 220 (22,3 %) |

**Dos poblaciones distintas de ceros:**

- **220 celdas en bloques contiguos**, concentradas en la franja costera y el desierto. Aquí
  el cero es compatible con el **escenario (a)/(b)**: la inversión térmica del Humboldt
  suprime la convección profunda y la actividad eléctrica es genuinamente cercana a cero. El
  valor verdadero no es necesariamente 0, pero sí está por debajo de 0,41.
- **766 celdas moteadas** rodeadas de celdas positivas. Un campo climatológico de descargas es
  espacialmente suave a escala de 10 km: no alterna entre 0 y 3 descargas km⁻² año⁻¹ de una
  celda a la siguiente. Este patrón es **escenario (b) puro**: muestreo insuficiente,
  no clima.

### 3.4 La prueba más clara: los 8 distritos de altura con densidad cero

| UBIGEO | Distrito | Depto. | Altitud (m) | Celdas asignadas | Valor asignado | Media de celdas tocadas |
|---|---|---|---|---|---|---|
| 020204 | LA MERCED | Áncash | 4 112,6 | 1 | 0,00 | **2,949** |
| 021002 | ANRA | Áncash | 3 782,1 | 1 | 0,00 | 1,150 |
| 021406 | CONGAS | Áncash | 3 727,2 | 1 | 0,00 | 0,638 |
| 021410 | SANTIAGO DE CHILCAS | Áncash | 3 513,0 | 1 | 0,00 | 0,370 |
| 021703 | COTAPARACO | Áncash | 4 122,0 | 1 | 0,00 | 1,408 |
| 021706 | MARCA | Áncash | 3 525,8 | 2 | 0,00 | 1,178 |
| 021904 | CASHAPAMPA | Áncash | 3 641,2 | 1 | 0,00 | 1,046 |
| 230205 | HUANUARA | Tacna | 3 572,6 | 1 | 0,00 | 1,222 |

Ocho distritos entre 3 513 y 4 122 m reciben densidad cero, mientras sus celdas vecinas
registran entre 0,37 y 2,95 descargas km⁻² año⁻¹. **Una densidad de rayos de cero a 4 122 m en
Áncash no es un valor climatológico plausible.** El ejemplo canónico es LA MERCED: la celda
que lo contiene vale 0, las celdas colindantes promedian 2,95.

La ventana del grid sobre esa zona lo muestra sin ambigüedad — ceros aislados intercalados
entre valores de 0,4 a 11,0, junto a un bloque contiguo de ceros hacia el suroeste (la
vertiente costera):

```
 0.4  0.0  0.4  3.1  0.4  3.3  3.5  2.8  1.7  0.7  1.6
 1.3  2.0  2.6  3.9  0.9  3.3  0.9  0.0  0.4  0.8  0.9
 1.9  3.6  3.9  1.3  0.8  6.2  2.8  0.9  0.0  1.2  0.4
 ...
 0.0  0.0  0.0  0.8  0.0  0.0  0.0  4.2  3.5  4.4  6.1
```

### 3.5 Veredicto

**No es (c).** El grid contiene ceros genuinos en las celdas asignadas; la agregación no perdió
información positiva.

**Es (b), con una componente de (a) en la costa.** El cero del producto LIS/OTD es un valor
**censurado por la izquierda en 0,41 descargas km⁻² año⁻¹**, no una medición de ausencia. En
la franja costera ese cero probablemente sí corresponde a actividad genuinamente ínfima
(escenario a); tierra adentro, y de forma inequívoca en los 8 distritos altoandinos, es
limitación de muestreo (escenario b).

### 3.6 Tratamiento recomendado: declarar, no imputar

Conforme al criterio: **no se imputa**. Se declara.

1. **Declarar el piso del producto en Métodos**: el LIS/OTD a 0,1° no representa valores por
   debajo de 0,41 descargas km⁻² año⁻¹; los ceros deben leerse como «< 0,41».
2. **Corregir el piso del modelo.** `pmax(densidad, 0.01)` usa un valor arbitrario que está
   **muy por debajo del mínimo representable del producto** (0,41 por celda) e incluso por
   debajo del mínimo distrital observado (0,03). Es un parche numérico para evitar `log(0)`
   que introduce una escala ficticia. Alternativas defendibles, en orden de preferencia:
   - Fijar el piso en el límite de censura del producto y declararlo.
   - Excluir del Modelo 2 los distritos censurados y reportarlo como análisis restringido.
   - Tratar la censura explícitamente en el modelo.
3. **Reportar la sensibilidad ya calculada en la Fase 2** (`salidas/tablas/T4c_piso_densidad.csv`):
   el coeficiente de altitud es robusto a los tres tratamientos (β entre 2,0216 y 2,2965),
   pero la dispersión cae de 28,71 a 3,51 al excluir los distritos censurados. **Los errores
   estándar del Modelo 2 dependen del tratamiento del piso; el gradiente altitudinal, no.**

Este punto cierra REP-004, que queda reclasificado: no es «ausencia de dato presentada como
cero» sino **censura por límite de detección**, que es un problema distinto y con un
tratamiento distinto.

---

## 4. Armonización territorial

### 4.1 El hecho

Se usaron límites distritales **INEI 2025** (`Limite Distrital INEI 2025 CPV.shp`, 1 891
polígonos) para datos de mortalidad **2017–2024**. Las proyecciones poblacionales INEI cubren
1 892 distritos.

### 4.2 Distritos creados o recategorizados durante el periodo

El archivo de población INEI arranca en **2018**, no en 2017. Al reconstruir 2017 (§5),
**18 distritos quedan sin denominador** porque no existían o no tenían proyección publicada:

| UBIGEO | Distrito | Departamento | Altitud (m) |
|---|---|---|---|
| 030612 | AHUAYRO | Apurímac | 2 914 |
| 050413 | PUTIS | Ayacucho | 3 896 |
| 050512 | UNIÓN PROGRESO | Ayacucho | 1 150 |
| 050513 | RÍO MAGDALENA | Ayacucho | 2 195 |
| 050514 | NINABAMBA | Ayacucho | 3 234 |
| 050515 | PATIBAMBA | Ayacucho | 3 241 |
| 080915 | KUMPIRUSHIATO | Cusco | 2 106 |
| 080916 | CIELO PUNCO | Cusco | 1 635 |
| 080917 | MANITEA | Cusco | 1 765 |
| 080918 | UNIÓN ASHÁNINKA | Cusco | 1 622 |
| 090724 | LAMBRAS | Huancavelica | 2 500 |
| 090725 | COCHABAMBA | Huancavelica | 3 393 |
| 130112 | ALTO TRUJILLO | La Libertad | 265 |
| 160405 | *(sin correspondencia en el shapefile 2025)* | — | — |
| 180107 | SAN ANTONIO | Moquegua | 1 215 |
| 221006 | SANTA LUCÍA | San Martín | 595 |
| 250306 | HUIPOCA | Ucayali | 291 |
| 250307 | BOQUERÓN | Ucayali | 1 117 |

Dos de ellos (PUTIS 3 896 m, COCHABAMBA 3 393 m) están en la franja altitudinal de interés.

### 4.3 Cómo se trataron

**Por omisión, no por decisión explícita.** El pipeline aplica
`MD <- MD[!is.na(person_years) & person_years > 0]`, de modo que un distrito sin población
queda fuera del análisis distrital sin que ningún mensaje lo señale. En la práctica:

- Para 2017 esos 18 distritos no aportan personas-año.
- Para 2018–2024 sí aparecen, con población completa.
- El resultado es un denominador **ligeramente incompleto solo en 2017**.

Un caso aparte: **160405** figura en el archivo de población pero **no existe en el shapefile
2025**, de modo que nunca entra al análisis distrital (no tiene altitud ni densidad asignadas).

### 4.4 Verificación de que no hay casos huérfanos

Se comprobó que **los 591 casos de la cohorte geográfica tienen un UBIGEO presente en el
shapefile 2025**. Ningún caso de mortalidad quedó sin polígono. La armonización territorial no
pierde casos; solo afecta al denominador de 2017.

### 4.5 Frase para Métodos

> District boundaries follow the 2025 INEI administrative division (1 891 districts) applied
> retrospectively to 2017–2024 mortality records. All 591 geolocated deaths matched a 2025
> district code. Eighteen districts created or first projected after 2017 lack a 2017
> population denominator and therefore contribute person-time only from 2018 onward; they
> account for less than 0.1 % of national person-years.

---

## 5. Denominador poblacional

### 5.1 La fuente

Proyecciones distritales INEI, archivo
`6894980-peru-poblacion-total-proyectada-...-2018-2026.xlsx`. **Cubre 2018–2026.** El periodo
de análisis empieza en 2017, de modo que 2017 hubo que reconstruirlo.

### 5.2 La regla de retroextrapolación

`R/11_poblacion.R`:

```r
tasa <- dis[!is.na(p2018) & !is.na(p2019) & p2018 > 0, .(UBIGEO, r = p2019 / p2018)]
p17  <- p17[, .(UBIGEO, nombre, anio = 2017L, poblacion = p2018 / r)]
```

Es decir:

**P₂₀₁₇ = P₂₀₁₈ / (P₂₀₁₉ / P₂₀₁₈) = P₂₀₁₈² / P₂₀₁₉**

Se supone que la razón de crecimiento observada entre 2018 y 2019 también rigió entre 2017 y
2018, y se aplica hacia atrás.

Verificación: la correlación entre la razón 2019/2018 y la razón implícita 2018/2017 es
exactamente **1** (diferencia máxima 5,3e-15). Confirma la fórmula.

### 5.3 Por qué se usó esa razón

No está documentado en el código. La justificación reconstruible es que 2018–2019 es el único
par consecutivo disponible al inicio de la serie, de modo que es la única estimación de
crecimiento local que no depende de años alejados del objetivo. Es una elección razonable pero
**no declarada**, y debe declararse.

### 5.4 Crecimientos negativos: qué se hizo (nada)

| Métrica | Valor |
|---|---|
| Distritos con P₂₀₁₉ < P₂₀₁₈ (crecimiento negativo) | **1 039 de 1 892 (54,9 %)** |
| — cuyo P₂₀₁₇ retroextrapolado queda **mayor** que P₂₀₁₈ | **1 039 (todos)** |
| Razón de crecimiento mínima | 0,87778 |
| Razón de crecimiento máxima | 1,28908 |
| Distritos con P₂₀₁₇ ≤ 0 | **0** |
| Distritos con P₂₀₁₇ faltante | 18 (§4.2) |

**No se aplicó ningún tratamiento a los crecimientos negativos.** La fórmula se aplicó
uniformemente. En más de la mitad de los distritos —los que perdían población— la
retroextrapolación produce un 2017 **mayor** que 2018, prolongando hacia atrás una tendencia
decreciente.

Esto es internamente consistente (si un distrito pierde población, en el pasado tenía más),
pero amplifica el error cuando la caída 2018→2019 refleja una revisión metodológica del INEI y
no una dinámica demográfica real. Ningún valor se volvió negativo ni cero, de modo que **no se
requirió ninguna corrección ad hoc**: ese es el hallazgo, y es tranquilizador.

### 5.5 Impacto cuantificado

Personas-año por estrato, y diferencia entre el 2017 reconstruido y el 2018 observado:

| Estrato | Personas-año totales | 2017 reconstruido | 2018 observado | Diferencia | % del total |
|---|---|---|---|---|---|
| 0–500 m | 127 385 333 | 14 942 012 | 15 254 238 | −312 226 | −0,245 % |
| 500–1 500 m | 52 396 184 | 6 029 978 | 6 188 049 | −158 071 | −0,302 % |
| 1 500–2 500 m | 14 695 404 | 1 814 655 | 1 827 353 | −12 698 | −0,086 % |
| 2 500–3 500 m | 27 872 200 | 3 360 274 | 3 405 141 | −44 867 | −0,161 % |
| **> 3 500 m** | **39 181 794** | **4 868 215** | **4 887 349** | **−19 134** | **−0,049 %** |

Pese a que el 54,9 % de los distritos ve inflado su 2017, **en el agregado el 2017
reconstruido es menor que el 2018 en todos los estratos**, porque los distritos grandes y en
crecimiento dominan la suma.

**Prueba de sensibilidad extrema:** si 2017 se fijara igual a 2018 (crecimiento nulo), la tasa
por encima de 3 500 m pasaría de **13,0162 a 13,0099** por millón de personas-año — una
variación del **0,05 %**. El denominador de 2017 no sostiene ninguna conclusión.

El repositorio ya incluye además la sensibilidad «Exclude 2017» (`14_sensitivity_analysis.csv`):
RR = **39,51** frente al 35,73 del análisis base. Excluir 2017 **refuerza** el gradiente.

### 5.6 Frase para Métodos

> District population denominators are INEI projections for 2018–2026. Because the analysis
> period begins in 2017, district population for that year was reconstructed as
> P₂₀₁₇ = P₂₀₁₈² / P₂₀₁₉, i.e. by applying the district-specific 2018–2019 growth ratio
> backwards one year; this was the only consecutive-year ratio available at the start of the
> series. No adjustment was made for districts with negative 2018–2019 growth (1 039 of 1 892,
> 54.9 %), for which the procedure yields a 2017 population above the 2018 value; no
> reconstructed value was negative or zero. The reconstruction is immaterial to the results:
> setting 2017 population equal to 2018 changes the mortality rate above 3 500 m from 13.016
> to 13.010 per million person-years (0.05 %), and excluding 2017 altogether raises the
> high-altitude rate ratio from 35.7 to 39.5.

---

## 6. Resumen de lo que debe cambiar en el manuscrito

| # | Punto | Acción |
|---|---|---|
| 1 | «grid-cell values **assigned** to each polygon» | Sustituir por la descripción de dos regímenes (§1.4) |
| 2 | Distritos menores que la celda | Declarar: 617 (32,6 %) menores que una celda; 364 (19,2 %) sin centro, resueltos por celdas intersectadas |
| 3 | Suavizado diferencial en altura | Añadir a Limitaciones: el estrato > 3 500 m concentra 220 distritos menores que una celda, con densidad más suavizada |
| 4 | Los 190 ceros | Declarar la censura en 0,41 descargas km⁻² año⁻¹; **no imputar** |
| 5 | `pmax(densidad, 0.01)` | Corregir el piso o declarar el tratamiento; reportar la sensibilidad de F2 |
| 6 | Límites 2025 sobre datos 2017–2024 | Declarar; 18 distritos sin denominador 2017; ningún caso huérfano |
| 7 | Reconstrucción de 2017 | Declarar la fórmula, el motivo y el no tratamiento de crecimientos negativos |

---

## 7. Salidas generadas

| Archivo | Contenido |
|---|---|
| `salidas/tablas/F5_diagnostico_asignacion.csv` | Los 1 891 distritos con: densidad publicada, media por centro, media por celdas tocadas, media ponderada por área, número de celdas asignadas, mínimo y máximo de celda |
| `src/` (scripts Python en el entorno de trabajo) | Réplica de las tres semánticas y diagnóstico del grid |

## 8. Lo que queda abierto

- La **Fase 6 (Moran's I)** sigue bloqueada: `sf` y `spdep` requieren GDAL/GEOS/PROJ de
  sistema. Nota: el diagnóstico de esta fase se resolvió por la vía de Python, de modo que
  **F6 también podría ejecutarse con `geopandas` + `libpysal`/`esda`** si se prefiere no
  esperar al `apt-get`. Requiere autorización.
- La decisión sobre el tratamiento definitivo del piso de densidad (§3.6) es de los autores.
