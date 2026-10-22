/*
=====================================================================
ISTANBUL EMERGENCY ASSEMBLY AREA ANALYSIS
03 - SCORING AND PRIORITY CLASSIFICATION
=====================================================================
*/


-- ================================================================
-- 1. ASSEMBLY AREA INADEQUACY
-- ================================================================


DROP MATERIALIZED VIEW IF EXISTS
gis.mahalle_oncelik_2025 CASCADE;


DROP MATERIALIZED VIEW IF EXISTS
gis.mahalle_yetersizlik_2025 CASCADE;



CREATE MATERIALIZED VIEW
gis.mahalle_yetersizlik_2025 AS


WITH availability_thresholds AS (

    SELECT

        percentile_cont(0.25)
        WITHIN GROUP (
            ORDER BY onbin_kisi_basina_toplanma_noktasi
        )
        FILTER (
            WHERE onbin_kisi_basina_toplanma_noktasi > 0
        )
        AS q1,


        percentile_cont(0.50)
        WITHIN GROUP (
            ORDER BY onbin_kisi_basina_toplanma_noktasi
        )
        FILTER (
            WHERE onbin_kisi_basina_toplanma_noktasi > 0
        )
        AS median

    FROM gis.mahalle_analiz_2025
),


indicator_scores AS (

    SELECT

        a.*,


        -- ========================================================
        -- Distance score
        -- ========================================================

        CASE

            WHEN a.mesafe_m <= 500
                THEN 0

            WHEN a.mesafe_m <= 1000
                THEN 1

            WHEN a.mesafe_m <= 2000
                THEN 2

            ELSE 3

        END AS mesafe_skoru,


        -- ========================================================
        -- Assembly point availability score
        -- ========================================================

        CASE

            -- No assembly point assigned to neighborhood
            WHEN a.toplanma_sayisi = 0
                THEN 3


            -- Below first quartile
            WHEN a.onbin_kisi_basina_toplanma_noktasi < t.q1
                THEN 2


            -- Between first quartile and median
            WHEN a.onbin_kisi_basina_toplanma_noktasi < t.median
                THEN 1


            -- Median or above
            ELSE 0

        END AS yogunluk_skoru


    FROM gis.mahalle_analiz_2025 a

    CROSS JOIN availability_thresholds t
),


total_scores AS (

    SELECT

        s.*,

        (
            s.mesafe_skoru
            +
            s.yogunluk_skoru
        ) AS yetersizlik_skoru

    FROM indicator_scores s
)


SELECT

    t.*,


    CASE

        WHEN t.yetersizlik_skoru <= 1
            THEN 'İyi'

        WHEN t.yetersizlik_skoru <= 3
            THEN 'Orta'

        WHEN t.yetersizlik_skoru = 4
            THEN 'Yetersiz'

        ELSE 'Çok Yetersiz'

    END AS yetersizlik_sinifi


FROM total_scores t;



-- ================================================================
-- 2. INDEXES
-- ================================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_mahalle_yetersizlik_2025_mahalle_id
ON gis.mahalle_yetersizlik_2025 (mahalle_id);


CREATE INDEX IF NOT EXISTS
idx_mahalle_yetersizlik_2025_geom
ON gis.mahalle_yetersizlik_2025
USING GIST (geom);


ANALYZE gis.mahalle_yetersizlik_2025;



-- ================================================================
-- 3. VALIDATE INADEQUACY CLASSIFICATION
-- ================================================================

SELECT

    yetersizlik_sinifi,

    COUNT(*) AS mahalle_sayisi,

    SUM(nufus_2025) AS toplam_nufus

FROM gis.mahalle_yetersizlik_2025

GROUP BY yetersizlik_sinifi

ORDER BY

    CASE yetersizlik_sinifi

        WHEN 'İyi' THEN 1
        WHEN 'Orta' THEN 2
        WHEN 'Yetersiz' THEN 3
        WHEN 'Çok Yetersiz' THEN 4

    END;


/*
Expected:

İyi             583     9,649,650
Orta            361     5,819,151
Yetersiz         17       284,402
Çok Yetersiz      2           550

Total           963    15,753,753
*/



-- ================================================================
-- 4. POPULATION-ADJUSTED INTERVENTION PRIORITY
-- ================================================================


CREATE MATERIALIZED VIEW
gis.mahalle_oncelik_2025 AS


WITH population_thresholds AS (

    SELECT

        percentile_cont(0.25)
        WITHIN GROUP (
            ORDER BY nufus_2025
        )
        AS q1,


        percentile_cont(0.50)
        WITHIN GROUP (
            ORDER BY nufus_2025
        )
        AS median,


        percentile_cont(0.75)
        WITHIN GROUP (
            ORDER BY nufus_2025
        )
        AS q3


    FROM gis.mahalle_yetersizlik_2025
),


population_scores AS (

    SELECT

        y.*,


        CASE

            WHEN y.nufus_2025 <= p.q1
                THEN 0

            WHEN y.nufus_2025 <= p.median
                THEN 1

            WHEN y.nufus_2025 <= p.q3
                THEN 2

            ELSE 3

        END AS nufus_skoru


    FROM gis.mahalle_yetersizlik_2025 y

    CROSS JOIN population_thresholds p
),


priority_scores AS (

    SELECT

        p.*,

        (
            p.yetersizlik_skoru
            +
            p.nufus_skoru
        ) AS oncelik_skoru

    FROM population_scores p
)


SELECT

    p.*,


    CASE

        WHEN p.oncelik_skoru <= 2
            THEN 'Düşük'

        WHEN p.oncelik_skoru <= 4
            THEN 'Orta'

        WHEN p.oncelik_skoru <= 6
            THEN 'Yüksek'

        ELSE 'Çok Yüksek'

    END AS mudahale_onceligi


FROM priority_scores p;



-- ================================================================
-- 5. INDEXES
-- ================================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_mahalle_oncelik_2025_mahalle_id
ON gis.mahalle_oncelik_2025 (mahalle_id);


CREATE INDEX IF NOT EXISTS
idx_mahalle_oncelik_2025_geom
ON gis.mahalle_oncelik_2025
USING GIST (geom);


ANALYZE gis.mahalle_oncelik_2025;



-- ================================================================
-- 6. VALIDATE INTERVENTION PRIORITY
-- ================================================================

SELECT

    mudahale_onceligi,

    COUNT(*) AS mahalle_sayisi,

    SUM(nufus_2025) AS toplam_nufus

FROM gis.mahalle_oncelik_2025

GROUP BY mudahale_onceligi

ORDER BY

    CASE mudahale_onceligi

        WHEN 'Düşük' THEN 1
        WHEN 'Orta' THEN 2
        WHEN 'Yüksek' THEN 3
        WHEN 'Çok Yüksek' THEN 4

    END;


/*
Expected:

Düşük       420     2,894,577
Orta        422     8,605,128
Yüksek      115     4,049,787
Çok Yüksek    6       204,261

Total       963    15,753,753
*/
