-- Assembly-area inadequacy classification
DROP MATERIALIZED VIEW IF EXISTS gis.mahalle_yetersizlik_2025 CASCADE;

CREATE MATERIALIZED VIEW gis.mahalle_yetersizlik_2025 AS

WITH esikler AS (
    SELECT
        percentile_cont(0.25)
        WITHIN GROUP (
            ORDER BY onbin_kisi_basina_toplanma_noktasi
        ) AS q1,

        percentile_cont(0.50)
        WITHIN GROUP (
            ORDER BY onbin_kisi_basina_toplanma_noktasi
        ) AS median

    FROM gis.mahalle_analiz_2025
),

skorlar AS (
    SELECT
        a.*,
      -- Distance Score
        CASE
            WHEN a.mesafe_m <= 500 THEN 0
            WHEN a.mesafe_m <= 1000 THEN 1
            WHEN a.mesafe_m <= 2000 THEN 2
            ELSE 3
        END AS mesafe_skoru,

      -- Density Score
        CASE
            WHEN a.onbin_kisi_basina_toplanma_noktasi = 0 THEN 3
            WHEN a.onbin_kisi_basina_toplanma_noktasi < e.q1 THEN 2
            WHEN a.onbin_kisi_basina_toplanma_noktasi < e.median THEN 1
            ELSE 0
        END AS yogunluk_skoru

    FROM gis.mahalle_analiz_2025 a
    CROSS JOIN esikler e
)

SELECT
    *,
    mesafe_skoru + yogunluk_skoru AS yetersizlik_skoru,

    CASE
        WHEN mesafe_skoru + yogunluk_skoru <= 1 THEN 'İyi'
        WHEN mesafe_skoru + yogunluk_skoru <= 3 THEN 'Orta'
        WHEN mesafe_skoru + yogunluk_skoru = 4 THEN 'Yetersiz'
        ELSE 'Çok Yetersiz'
    END AS yetersizlik_sinifi

FROM skorlar;

-- Creating Indexes
CREATE UNIQUE INDEX IF NOT EXISTS
uq_mahalle_yetersizlik_2025_mahalle_id
ON gis.mahalle_yetersizlik_2025 (mahalle_id);

CREATE INDEX IF NOT EXISTS
idx_mahalle_yetersizlik_2025_geom
ON gis.mahalle_yetersizlik_2025
USING GIST (geom);

-- Population-adjusted intervention priority
DROP MATERIALIZED VIEW IF EXISTS gis.mahalle_oncelik_2025 CASCADE;

CREATE MATERIALIZED VIEW gis.mahalle_oncelik_2025 AS

WITH nufus_esikleri AS (
    SELECT
        percentile_cont(0.25)
        WITHIN GROUP (ORDER BY nufus_2025) AS q1,

        percentile_cont(0.50)
        WITHIN GROUP (ORDER BY nufus_2025) AS median,

        percentile_cont(0.75)
        WITHIN GROUP (ORDER BY nufus_2025) AS q3

    FROM gis.mahalle_yetersizlik_2025
),

skor AS (
    SELECT
        m.*,

        CASE
            WHEN m.nufus_2025 < e.q1 THEN 0
            WHEN m.nufus_2025 < e.median THEN 1
            WHEN m.nufus_2025 < e.q3 THEN 2
            ELSE 3
        END AS nufus_skoru

    FROM gis.mahalle_yetersizlik_2025 m
    CROSS JOIN nufus_esikleri e
)

SELECT
    *,
    yetersizlik_skoru + nufus_skoru AS oncelik_skoru,

    CASE
        WHEN yetersizlik_skoru + nufus_skoru <= 2 THEN 'Düşük'
        WHEN yetersizlik_skoru + nufus_skoru <= 4 THEN 'Orta'
        WHEN yetersizlik_skoru + nufus_skoru <= 6 THEN 'Yüksek'
        ELSE 'Çok Yüksek'
    END AS mudahale_onceligi

FROM skor;

-- Creating Indexes
CREATE UNIQUE INDEX IF NOT EXISTS
uq_mahalle_oncelik_2025_mahalle_id
ON gis.mahalle_oncelik_2025 (mahalle_id);

CREATE INDEX IF NOT EXISTS
idx_mahalle_oncelik_2025_geom
ON gis.mahalle_oncelik_2025
USING GIST (geom);