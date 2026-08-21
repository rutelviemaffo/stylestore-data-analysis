/* ============================================================
   STYLESTORE V2 — QUERY SQL
   Progetto di analisi dati su dataset e-commerce moda
   (21.555 ordini, 24 mesi, 2024-2025)
   ============================================================
   
   Le query sono organizzate in ordine logico:
   1. Setup e verifica import
   2. Validazione / integrità dei dati
   3. Analisi per categoria
   4. Analisi temporale e window functions
   5. Query avanzate (subquery, CTE)
   ============================================================ */

-- Seleziona il database corretto prima di eseguire qualsiasi query
USE StyleStore;
GO


/* ============================================================
   1. SETUP E VERIFICA IMPORT
   ============================================================ */

-- Verifica che l'import abbia caricato il numero corretto di righe
SELECT COUNT(*) AS TotaleOrdini FROM Ordini;
-- Atteso: 21.555

SELECT COUNT(*) AS TotaleProdotti FROM Prodotti;
-- Atteso: 50


/* ============================================================
   2. VALIDAZIONE / INTEGRITÀ DEI DATI
   ============================================================ */

-- Ricerca ID_Ordine duplicati (anomalia A4)
SELECT ID_Ordine, COUNT(*) AS Occorrenze
FROM Ordini
GROUP BY ID_Ordine
HAVING COUNT(*) > 1;
-- Atteso: 2 ID duplicati

-- Verifica integrità referenziale: ordini "orfani" 
-- (ID_Prodotto che non esiste in Prodotti)
SELECT Ordini.ID_Ordine, Ordini.ID_Prodotto
FROM Ordini
LEFT JOIN Prodotti
    ON Ordini.ID_Prodotto = Prodotti.ID_Prodotto
WHERE Prodotti.ID_Prodotto IS NULL;
-- Atteso: 0 righe (nessun orfano)

-- Ordini con ricavo sopra la media (individua outlier come l'anomalia A3)
SELECT ID_Ordine, Ricavo
FROM Ordini
WHERE Ricavo > (SELECT AVG(Ricavo) FROM Ordini)
ORDER BY Ricavo DESC;
-- Le prime righe mostrano l'anomalia A3 (3 ordini a 8.900€ invece di 89,00€)


/* ============================================================
   3. ANALISI PER CATEGORIA
   ============================================================ */

-- Ricavo totale per categoria
SELECT 
    Categoria,
    SUM(Ricavo) AS RicavoTotale
FROM Ordini
GROUP BY Categoria
ORDER BY RicavoTotale DESC;

-- Tasso di reso per categoria (conteggio condizionale)
SELECT 
    Categoria,
    COUNT(*) AS OrdiniTotali,
    SUM(CASE WHEN Reso = 'SI' THEN 1 ELSE 0 END) AS Resi,
    SUM(CASE WHEN Reso = 'SI' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS TassoResoPct
FROM Ordini
GROUP BY Categoria
ORDER BY TassoResoPct DESC;
-- Risultato: Scarpe 13%, ..., Beauty 2,95% — coerente coi baseline attesi

-- Margine medio per categoria: assoluto (euro) vs relativo (percentuale)
-- Richiede il JOIN con Prodotti per recuperare il Costo_Unitario
SELECT 
    O.Categoria,
    AVG(O.Prezzo_Netto - P.Costo_Unitario) AS MargineMedioEuro,
    AVG((O.Prezzo_Netto - P.Costo_Unitario) * 100.0 / O.Prezzo_Netto) AS MarginePctMedio
FROM Ordini AS O
INNER JOIN Prodotti AS P
    ON O.ID_Prodotto = P.ID_Prodotto
GROUP BY O.Categoria
ORDER BY MarginePctMedio DESC;
-- Risultato: le classifiche per euro e per percentuale si invertono
-- (Borse vince in euro, Beauty vince in percentuale)


/* ============================================================
   4. ANALISI TEMPORALE E WINDOW FUNCTIONS
   ============================================================ */

-- Ricavo e ordini per mese (base per l'analisi di stagionalità)
SELECT 
    YEAR(Data_Ordine) AS Anno,
    MONTH(Data_Ordine) AS Mese,
    COUNT(*) AS NumOrdini,
    SUM(Ricavo) AS RicavoMese,
    AVG(Ricavo) AS RicavoMedio
FROM Ordini
GROUP BY YEAR(Data_Ordine), MONTH(Data_Ordine)
ORDER BY Anno, Mese;
-- Ricavo medio massimo ad agosto (prezzo pieno), minimo gen/lug (saldi)

-- Ricavo cumulato (running total) mese su mese
SELECT 
    YEAR(Data_Ordine) AS Anno,
    MONTH(Data_Ordine) AS Mese,
    SUM(Ricavo) AS RicavoMese,
    SUM(SUM(Ricavo)) OVER (
        ORDER BY YEAR(Data_Ordine), MONTH(Data_Ordine)
    ) AS RicavoCumulato
FROM Ordini
GROUP BY YEAR(Data_Ordine), MONTH(Data_Ordine)
ORDER BY Anno, Mese;
-- Verifica: l'ultima riga deve coincidere col ricavo totale generale (~2.756.708€)

-- Media mobile a 3 mesi (lisciare la stagionalità, rivelare il trend di fondo)
SELECT 
    YEAR(Data_Ordine) AS Anno,
    MONTH(Data_Ordine) AS Mese,
    SUM(Ricavo) AS RicavoMese,
    AVG(SUM(Ricavo)) OVER (
        ORDER BY YEAR(Data_Ordine), MONTH(Data_Ordine)
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS MediaMobile3Mesi
FROM Ordini
GROUP BY YEAR(Data_Ordine), MONTH(Data_Ordine)
ORDER BY Anno, Mese;
-- Trend di fondo: da ~90.895€ a ~166.440€ di media mobile, business in crescita

-- Variazione mese su mese (LAG) — crescita/calo rispetto al mese precedente
SELECT 
    YEAR(Data_Ordine) AS Anno,
    MONTH(Data_Ordine) AS Mese,
    SUM(Ricavo) AS RicavoMese,
    LAG(SUM(Ricavo)) OVER (
        ORDER BY YEAR(Data_Ordine), MONTH(Data_Ordine)
    ) AS RicavoMesePrec,
    SUM(Ricavo) - LAG(SUM(Ricavo)) OVER (
        ORDER BY YEAR(Data_Ordine), MONTH(Data_Ordine)
    ) AS Variazione,
    (SUM(Ricavo) - LAG(SUM(Ricavo)) OVER (
        ORDER BY YEAR(Data_Ordine), MONTH(Data_Ordine)
    )) * 100.0 / LAG(SUM(Ricavo)) OVER (
        ORDER BY YEAR(Data_Ordine), MONTH(Data_Ordine)
    ) AS CrescitaPct
FROM Ordini
GROUP BY YEAR(Data_Ordine), MONTH(Data_Ordine)
ORDER BY Anno, Mese;
-- La prima riga (gen 2024) ha valori NULL: non esiste un mese precedente


/* ============================================================
   5. QUERY AVANZATE (subquery, CTE)
   ============================================================ */

-- Ricavo medio MENSILE (richiede due livelli di aggregazione)
-- Versione con subquery nel FROM
SELECT AVG(RicavoMensile) AS RicavoMedioMensile
FROM (
    SELECT 
        YEAR(Data_Ordine) AS Anno,
        MONTH(Data_Ordine) AS Mese,
        SUM(Ricavo) AS RicavoMensile
    FROM Ordini
    GROUP BY YEAR(Data_Ordine), MONTH(Data_Ordine)
) AS TotaliMensili;
-- Risultato: 114.862,84€

-- Stessa query, versione con CTE (più leggibile quando le analisi si complicano)
WITH TotaliMensili AS (
    SELECT 
        YEAR(Data_Ordine) AS Anno,
        MONTH(Data_Ordine) AS Mese,
        SUM(Ricavo) AS RicavoMensile
    FROM Ordini
    GROUP BY YEAR(Data_Ordine), MONTH(Data_Ordine)
)
SELECT AVG(RicavoMensile) AS RicavoMedioMensile
FROM TotaliMensili;
-- Stesso risultato: 114.862,84€


/* ============================================================
   NOTE
   ============================================================
   - Ogni risultato è stato verificato per coerenza con l'analisi 
     Excel corrispondente (validazione incrociata su due strumenti).
   - Il dataset e la logica delle anomalie pianificate sono descritti 
     nel case study completo (link Notion nel repository).
   ============================================================ */
