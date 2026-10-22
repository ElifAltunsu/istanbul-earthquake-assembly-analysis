-- Final 2025 neighborhood dataset 
DROP MATERIALIZED VIEW IF EXISTS gis.mahalleler_2025_final CASCADE;

CREATE MATERIALIZED VIEW gis.mahalleler_2025_final AS

/* =====================================================
   The other 36 district
   ===================================================== */
SELECT
    m."ILCEADI",
    m.mahalle_adi_2025,
    m.nufus_2025,
    m.mahalle_id,

    'mevcut_geometri'::text
        AS geometri_kaynagi,

    ST_Multi(
        ST_CollectionExtract(
            ST_MakeValid(
                ST_CurveToLine(m.geom)
            ),
            3
        )
    )::geometry(MultiPolygon,32635)
        AS geom

FROM gis.mahalleler_2025_temiz m

WHERE m."ILCEADI" NOT IN (
    'ESENLER',
    'ESENYURT',
    'EYÜPSULTAN'
)


UNION ALL


/* =====================================================
   Updated 3 districts
   ===================================================== */
SELECT
    g."ILCEADI",
    n.mahalle_adi
        AS mahalle_adi_2025,

    n.nufus
        AS nufus_2025,

    n.mahalle_id,

    'osm_guncel_3_ilce'::text
        AS geometri_kaynagi,

    ST_Multi(
        ST_CollectionExtract(
            ST_MakeValid(
                ST_CurveToLine(g.geom)
            ),
            3
        )
    )::geometry(MultiPolygon,32635)
        AS geom

FROM gis.guncel_3_ilce_mahalle_hazir g

JOIN gis.mahalle_nufus_2025 n

ON

regexp_replace(
    lower(unaccent(g."ILCEADI")),
    '[^a-z0-9]',
    '',
    'g'
)

=

regexp_replace(
    lower(unaccent(n.ilce_adi)),
    '[^a-z0-9]',
    '',
    'g'
)


AND


regexp_replace(
    regexp_replace(
        lower(unaccent(g.mahalle_adi)),
        '\s+mahallesi.*$',
        ''
    ),
    '[^a-z0-9]',
    '',
    'g'
)

=

regexp_replace(
    regexp_replace(
        lower(unaccent(n.mahalle_adi)),
        '\s+mahallesi.*$',
        ''
    ),
    '[^a-z0-9]',
    '',
    'g'
);

-- Creating Indexes
CREATE INDEX idx_mahalleler_2025_final_geom
ON gis.mahalleler_2025_final
USING GIST (geom);


-- Creating one main analysis table
DROP MATERIALIZED VIEW IF EXISTS gis.mahalle_analiz_2025 CASCADE;

CREATE MATERIALIZED VIEW gis.mahalle_analiz_2025 AS

SELECT
    m.*,

    COALESCE(c.toplanma_sayisi, 0)::integer
        AS toplanma_sayisi,

    nearest.mesafe_m,

    ROUND(
        (
            COALESCE(c.toplanma_sayisi, 0)::numeric
            / NULLIF(m.nufus_2025, 0)
        ) * 10000,
        2
    ) AS onbin_kisi_basina_toplanma_alani

FROM gis.mahalleler_2025_temiz m

LEFT JOIN LATERAL (

    SELECT
        COUNT(*) AS toplanma_sayisi

    FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm" t

    WHERE ST_Covers(
        m.geom,
        t.geom
    )

) c ON TRUE

LEFT JOIN LATERAL (

    SELECT
        ST_Distance(
            ST_PointOnSurface(m.geom),
            t.geom
        ) AS mesafe_m

    FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm" t

    ORDER BY
        ST_PointOnSurface(m.geom) <-> t.geom

    LIMIT 1

) nearest ON TRUE;

-- Creating spatial indexes
CREATE INDEX idx_mahalle_analiz_2025_geom
ON gis.mahalle_analiz_2025
USING GIST (geom);


-- Assigning each assembly point to exactly one neighborhood
DROP MATERIALIZED VIEW IF EXISTS gis.toplanma_mahalle_atama_2025 CASCADE;

CREATE MATERIALIZED VIEW gis.toplanma_mahalle_atama_2025 AS

WITH cover_counts AS (

    SELECT
        t.objectid,
        COUNT(m.mahalle_id) AS cover_count

    FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm" t

    LEFT JOIN gis.mahalleler_2025_final m
        ON ST_Covers(m.geom, t.geom)

    GROUP BY t.objectid
)

SELECT
    t.objectid,
    t.toplanma_alan_ad,

    t.mahalle_adi AS kaynak_mahalle,

    secilen.mahalle_id,
    secilen."ILCEADI",
    secilen.mahalle_adi_2025,

    c.cover_count,

    CASE
        WHEN c.cover_count = 1
            THEN 'spatial_exact'

        WHEN c.cover_count > 1
            THEN 'boundary_resolved'

        ELSE
            'nearest_fallback'
    END AS atama_yontemi,

    ROUND(
        secilen.mesafe_m::numeric,
        2
    ) AS atama_mesafe_m,

    t.geom

FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm" t

JOIN cover_counts c
    ON t.objectid = c.objectid

CROSS JOIN LATERAL (

    SELECT
        m.mahalle_id,
        m."ILCEADI",
        m.mahalle_adi_2025,

        ST_Distance(
            t.geom,
            m.geom
        ) AS mesafe_m

    FROM gis.mahalleler_2025_final m

    ORDER BY

        /* First, the polygon that covers the point*/
        CASE
            WHEN ST_Covers(m.geom, t.geom)
                THEN 0
            ELSE 1
        END,

        /* Second, finding the closest neighborhood geometrically */
        ST_Distance(t.geom, m.geom),

        /* When there's boundary evennes, choosing source neighborhood name */
        CASE
            WHEN regexp_replace(
                    lower(unaccent(m.mahalle_adi_2025)),
                    '[^a-z0-9]',
                    '',
                    'g'
                 )
                 =
                 regexp_replace(
                    lower(unaccent(t.mahalle_adi)),
                    '[^a-z0-9]',
                    '',
                    'g'
                 )
            THEN 0
            ELSE 1
        END,

        ST_Distance(
            t.geom,
            ST_PointOnSurface(m.geom)
        ),

        m.mahalle_id

    LIMIT 1

) secilen;