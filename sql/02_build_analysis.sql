/*
=====================================================================
ISTANBUL EMERGENCY ASSEMBLY AREA ANALYSIS
02 - SPATIAL ANALYSIS
=====================================================================
*/


-- ================================================================
-- 1. VALIDATE ASSEMBLY POINT DATA
-- ================================================================

SELECT
    COUNT(*) AS total_points,
    COUNT(DISTINCT objectid) AS unique_objectids,
    COUNT(*) - COUNT(DISTINCT objectid) AS duplicate_objectids
FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm";


/*
Expected:

total_points       = 5599
unique_objectids   = 5599
duplicate_objectids = 0
*/



-- ================================================================
-- 2. ASSIGN EACH ASSEMBLY POINT TO ONE NEIGHBORHOOD
-- ================================================================
/*
Most assembly points fall directly inside exactly one neighborhood.

ST_Covers is used instead of ST_Contains so points located directly
on polygon boundaries are also considered.

Assignment logic:

1. One matching neighborhood
      -> spatial_exact

2. More than one matching neighborhood
      -> boundary_resolved

3. No matching neighborhood
      -> nearest_fallback

This guarantees that every assembly point is assigned exactly once.
*/


DROP MATERIALIZED VIEW IF EXISTS
gis.toplanma_mahalle_atama_2025 CASCADE;


CREATE MATERIALIZED VIEW
gis.toplanma_mahalle_atama_2025 AS


WITH candidate_counts AS (

    SELECT
        p.objectid,

        COUNT(m.mahalle_id)
            AS candidate_count

    FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm" p

    LEFT JOIN gis.mahalleler_2025_final m
        ON ST_Covers(m.geom, p.geom)

    GROUP BY p.objectid
),


-- ------------------------------------------------
-- Select one neighborhood from spatial matches
-- ------------------------------------------------

exact_candidates AS (

    SELECT
        p.objectid,
        m.mahalle_id,

        ROW_NUMBER() OVER (
            PARTITION BY p.objectid

            ORDER BY
                ST_Distance(
                    ST_PointOnSurface(m.geom),
                    p.geom
                ),
                m.mahalle_id
        ) AS rn

    FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm" p

    JOIN gis.mahalleler_2025_final m
        ON ST_Covers(m.geom, p.geom)
),


chosen_exact AS (

    SELECT
        objectid,
        mahalle_id

    FROM exact_candidates

    WHERE rn = 1
),


-- ------------------------------------------------
-- Find nearest neighborhood only when no spatial
-- match exists
-- ------------------------------------------------

nearest_fallback AS (

    SELECT
        p.objectid,
        nearest_mahalle.mahalle_id

    FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm" p

    JOIN candidate_counts c
        ON c.objectid = p.objectid

    CROSS JOIN LATERAL (

        SELECT
            m.mahalle_id

        FROM gis.mahalleler_2025_final m

        ORDER BY
            m.geom <-> p.geom,
            m.mahalle_id

        LIMIT 1

    ) nearest_mahalle

    WHERE c.candidate_count = 0
)


SELECT

    p.objectid,

    COALESCE(
        e.mahalle_id,
        n.mahalle_id
    ) AS mahalle_id,

    CASE

        WHEN c.candidate_count = 1
            THEN 'spatial_exact'

        WHEN c.candidate_count > 1
            THEN 'boundary_resolved'

        ELSE 'nearest_fallback'

    END AS assignment_method,

    p.geom

FROM gis."istanbul_deprem_analizi — toplanma_alanlari_utm" p


JOIN candidate_counts c
    ON c.objectid = p.objectid


LEFT JOIN chosen_exact e
    ON e.objectid = p.objectid


LEFT JOIN nearest_fallback n
    ON n.objectid = p.objectid;



-- ================================================================
-- 3. INDEXES
-- ================================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_toplanma_mahalle_atama_2025_objectid
ON gis.toplanma_mahalle_atama_2025 (objectid);


CREATE INDEX IF NOT EXISTS
idx_toplanma_mahalle_atama_2025_mahalle
ON gis.toplanma_mahalle_atama_2025 (mahalle_id);


CREATE INDEX IF NOT EXISTS
idx_toplanma_mahalle_atama_2025_geom
ON gis.toplanma_mahalle_atama_2025
USING GIST (geom);


ANALYZE gis.toplanma_mahalle_atama_2025;



-- ================================================================
-- 4. VALIDATE FINAL ASSIGNMENT
-- ================================================================

SELECT

    COUNT(*) AS total_points,

    COUNT(DISTINCT objectid)
        AS unique_points,

    COUNT(*) FILTER (
        WHERE assignment_method = 'spatial_exact'
    ) AS spatial_exact,

    COUNT(*) FILTER (
        WHERE assignment_method = 'boundary_resolved'
    ) AS boundary_resolved,

    COUNT(*) FILTER (
        WHERE assignment_method = 'nearest_fallback'
    ) AS nearest_fallback

FROM gis.toplanma_mahalle_atama_2025;


/*
Expected:

total_points       = 5599
unique_points      = 5599
spatial_exact      = 5586
boundary_resolved  = 2
nearest_fallback   = 11
*/



-- ================================================================
-- 5. BUILD NEIGHBORHOOD-LEVEL ANALYSIS TABLE
-- ================================================================
/*
The final analysis table contains one record per neighborhood.

Metrics:

toplanma_sayisi
    Number of assigned emergency assembly points.

mesafe_m
    Distance from a representative point inside the neighborhood
    to the nearest assembly point.

onbin_kisi_basina_toplanma_noktasi
    Number of assembly points per 10,000 residents.

Important:
The source dataset contains assembly POINT locations rather than
assembly-area polygons. Therefore, this metric represents point
availability and should not be interpreted as physical capacity.
*/


DROP MATERIALIZED VIEW IF EXISTS
gis.mahalle_analiz_2025 CASCADE;


CREATE MATERIALIZED VIEW
gis.mahalle_analiz_2025 AS


WITH point_counts AS (

    SELECT
        mahalle_id,
        COUNT(*) AS toplanma_sayisi

    FROM gis.toplanma_mahalle_atama_2025

    GROUP BY mahalle_id
)


SELECT

    m.ilceadi,

    m.mahalle_adi_2025,

    m.nufus_2025,

    m.mahalle_id,

    m.geom,


    -- ------------------------------------------------
    -- Number of assembly points
    -- ------------------------------------------------

    COALESCE(
        pc.toplanma_sayisi,
        0
    )::integer
        AS toplanma_sayisi,


    -- ------------------------------------------------
    -- Distance to nearest assembly point
    -- ------------------------------------------------

    ROUND(
        nearest_point.mesafe_m::numeric,
        1
    ) AS mesafe_m,


    -- ------------------------------------------------
    -- Assembly points per 10,000 residents
    -- ------------------------------------------------

    CASE

        WHEN m.nufus_2025 > 0

        THEN ROUND(

            (
                COALESCE(
                    pc.toplanma_sayisi,
                    0
                )::numeric

                / m.nufus_2025::numeric

            ) * 10000,

            3
        )

        ELSE NULL

    END AS onbin_kisi_basina_toplanma_noktasi


FROM gis.mahalleler_2025_final m


LEFT JOIN point_counts pc
    ON pc.mahalle_id = m.mahalle_id


LEFT JOIN LATERAL (

    SELECT

        ST_Distance(
            ST_PointOnSurface(m.geom),
            a.geom
        ) AS mesafe_m

    FROM gis.toplanma_mahalle_atama_2025 a

    ORDER BY
        ST_PointOnSurface(m.geom) <-> a.geom

    LIMIT 1

) nearest_point
ON TRUE;



-- ================================================================
-- 6. FINAL ANALYSIS INDEXES
-- ================================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_mahalle_analiz_2025_mahalle_id
ON gis.mahalle_analiz_2025 (mahalle_id);


CREATE INDEX IF NOT EXISTS
idx_mahalle_analiz_2025_geom
ON gis.mahalle_analiz_2025
USING GIST (geom);


ANALYZE gis.mahalle_analiz_2025;



-- ================================================================
-- 7. FINAL VALIDATION
-- ================================================================

SELECT

    COUNT(*) AS neighborhood_count,

    COUNT(DISTINCT mahalle_id)
        AS unique_neighborhoods,

    SUM(nufus_2025)
        AS total_population,

    SUM(toplanma_sayisi)
        AS assigned_assembly_points

FROM gis.mahalle_analiz_2025;


/*
Expected:

neighborhood_count        = 963
unique_neighborhoods      = 963
total_population          = 15753753
assigned_assembly_points  = 5599
*/
