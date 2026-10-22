/*
=====================================================================
ISTANBUL EMERGENCY ASSEMBLY AREA ANALYSIS
01 - DATA PREPARATION
=====================================================================

Purpose
-------
Prepares the final 2025 Istanbul neighborhood dataset used by the
spatial analysis.

Main steps
----------
1. Enable PostGIS / unaccent.
2. Correct CRS issue in the original neighborhood geometry.
3. Filter Istanbul neighborhoods.
4. Match neighborhood polygons with 2025 population data.
5. Resolve historical / naming differences manually.
6. Replace outdated Esenler, Esenyurt and Eyüpsultan geometries
   with updated OSM geometries.
7. Produce the final 963-neighborhood dataset.

Required input tables
---------------------
gis."istanbul_deprem_analizi — mahalleler"
gis.mahalle_nufus_2025
gis.guncel_3_ilce_mahalle

Final output
------------
gis.mahalleler_2025_final

Final expected checks
---------------------
Neighborhoods        : 963
Population           : 15,753,753
Geometry             : MultiPolygon
CRS                  : EPSG:32635
=====================================================================
*/


-- ================================================================
-- 0. EXTENSIONS / SCHEMA
-- ================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS unaccent;

CREATE SCHEMA IF NOT EXISTS gis;



-- ================================================================
-- 1. ORIGINAL GEOMETRY CRS CORRECTION
-- ================================================================
/*
The original neighborhood dataset contained coordinates in
EPSG:3857 (Web Mercator), although the geometry had been labelled
as EPSG:32635.

This was identified from the coordinate extent.

Before correction, coordinates were approximately:

X: 3,100,000 - 3,300,000
Y: 4,980,000 - 5,100,000

These values correspond to Web Mercator coordinates, not UTM 35N.

IMPORTANT:
Run the UPDATE below only once on the originally imported dataset.
*/


-- Diagnostic query used during data preparation:

SELECT
    ST_SRID(geom) AS srid,
    ST_Extent(geom) AS extent
FROM gis."istanbul_deprem_analizi — mahalleler"
GROUP BY ST_SRID(geom);


/*
One-time CRS repair performed on the source dataset:

UPDATE gis."istanbul_deprem_analizi — mahalleler"
SET geom =
    ST_Transform(
        ST_SetSRID(geom, 3857),
        32635
    );

After correction, coordinates are expressed in
EPSG:32635 - WGS 84 / UTM Zone 35N.
*/



-- ================================================================
-- 2. FILTER ISTANBUL NEIGHBORHOODS
-- ================================================================

DROP MATERIALIZED VIEW IF EXISTS gis.mahalleler_istanbul CASCADE;

CREATE MATERIALIZED VIEW gis.mahalleler_istanbul AS

SELECT *
FROM gis."istanbul_deprem_analizi — mahalleler"

WHERE lower(unaccent(trim(iladi))) = 'istanbul';


CREATE INDEX IF NOT EXISTS idx_mahalleler_istanbul_geom
ON gis.mahalleler_istanbul
USING GIST (geom);



-- ================================================================
-- 3. 2025 POPULATION DATA
-- ================================================================
/*
The following table was populated from:

istanbul_mahalle_nufus_2025.csv

Expected structure:

ilce_adi
mahalle_adi
nufus
mahalle_id

Expected values:

39 districts
963 neighborhoods
15,753,753 population
*/


CREATE TABLE IF NOT EXISTS gis.mahalle_nufus_2025 (

    ilce_adi    text,
    mahalle_adi text,
    nufus       integer,
    mahalle_id  integer

);

/*
The CSV was imported through pgAdmin:

Table:
gis.mahalle_nufus_2025

CSV:
istanbul_mahalle_nufus_2025.csv

Format:
CSV

Header:
Yes

Encoding:
UTF-8
*/


-- Population data validation

SELECT
    COUNT(*) AS mahalle_sayisi,
    COUNT(DISTINCT mahalle_id) AS benzersiz_mahalle,
    SUM(nufus) AS toplam_nufus

FROM gis.mahalle_nufus_2025;



-- ================================================================
-- 4. MANUAL NAME MATCHING TABLE
-- ================================================================
/*
Most neighborhoods matched directly using district + neighborhood
name.

944 records matched automatically.

16 historical / naming differences were resolved through this
mapping table.
*/


DROP TABLE IF EXISTS gis.mahalle_ad_eslestirme;

CREATE TABLE gis.mahalle_ad_eslestirme (

    ilce_adi  text,
    eski_ad   text,
    guncel_ad text,
    aciklama  text

);


INSERT INTO gis.mahalle_ad_eslestirme
(
    ilce_adi,
    eski_ad,
    guncel_ad,
    aciklama
)

VALUES

(
    'BAYRAMPAŞA',
    'ORTAMAHALLE',
    'Orta',
    'İsim varyasyonu'
),

(
    'BEYKOZ',
    'ÇİFTLİK',
    'Çavuşbaşı Çiftlik',
    'Yer adı varyasyonu'
),

(
    'BEYKOZ',
    'CUMHURİYET',
    'Cumhuriyetköy',
    'İsim güncellemesi'
),

(
    'BÜYÜKÇEKMECE',
    'MİMAR SİNAN MERKEZ',
    'Mimarsinan',
    'İsim varyasyonu'
),

(
    'ESENLER',
    'HAVAALANI',
    'Atışalanı',
    'Mahalle adı değişikliği'
),

(
    'SARIYER',
    'KEMER',
    'Bahçeköy Kemer',
    'Yer adı varyasyonu'
),

(
    'SARIYER',
    'KUMKÖY',
    'Kumköy (Kilyos)',
    'Yer adı varyasyonu'
),

(
    'SARIYER',
    'RUMELİ HİSARI',
    'Rumelihisarı',
    'Yazım farkı'
),

(
    'SARIYER',
    'RUMELİ KAVAĞI',
    'Rumelikavağı',
    'Yazım farkı'
),

(
    'SARIYER',
    'MERKEZ',
    'Sarıyer Merkez',
    'Yer adı varyasyonu'
),

(
    'SİLİVRİ',
    'BALABAN',
    'Çanta Balaban',
    'Yer adı varyasyonu'
),

(
    'SİLİVRİ',
    'SANCAKTEPE',
    'Çanta Sancaktepe',
    'Yer adı varyasyonu'
),

(
    'SİLİVRİ',
    'FEVZİPAŞA',
    'Değirmenköy Fevzipaşa',
    'Yer adı varyasyonu'
),

(
    'SİLİVRİ',
    'İSMETPAŞA',
    'Değirmenköy İsmetpaşa',
    'Yer adı varyasyonu'
),

(
    'SİLİVRİ',
    'HÜRRİYET',
    'Kavaklı Hürriyet',
    'Yer adı varyasyonu'
),

(
    'SİLİVRİ',
    'KAVAKLI',
    'Kavaklı İstiklal',
    'Yer adı varyasyonu'
);



-- ================================================================
-- 5. MATCH POPULATION DATA TO EXISTING GEOMETRIES
-- ================================================================

DROP MATERIALIZED VIEW IF EXISTS gis.mahalleler_2025_temiz CASCADE;

CREATE MATERIALIZED VIEW gis.mahalleler_2025_temiz AS


-- ------------------------------------------------
-- Exact matches
-- ------------------------------------------------

WITH exact_match AS (

    SELECT
        m.*,

        n.mahalle_id,

        n.mahalle_adi
            AS mahalle_adi_2025,

        n.nufus
            AS nufus_2025,

        'exact'::text
            AS match_type

    FROM gis.mahalleler_istanbul m

    JOIN gis.mahalle_nufus_2025 n

      ON lower(unaccent(trim(m.ilceadi)))
         =
         lower(unaccent(trim(n.ilce_adi)))

     AND lower(unaccent(trim(m.mahalleadi)))
         =
         lower(unaccent(trim(n.mahalle_adi)))
),


-- ------------------------------------------------
-- Manual matches
-- ------------------------------------------------

manual_match AS (

    SELECT
        m.*,

        n.mahalle_id,

        n.mahalle_adi
            AS mahalle_adi_2025,

        n.nufus
            AS nufus_2025,

        'manual'::text
            AS match_type

    FROM gis.mahalleler_istanbul m

    JOIN gis.mahalle_ad_eslestirme e

      ON lower(unaccent(trim(m.ilceadi)))
         =
         lower(unaccent(trim(e.ilce_adi)))

     AND lower(unaccent(trim(m.mahalleadi)))
         =
         lower(unaccent(trim(e.eski_ad)))


    JOIN gis.mahalle_nufus_2025 n

      ON lower(unaccent(trim(n.ilce_adi)))
         =
         lower(unaccent(trim(e.ilce_adi)))

     AND lower(unaccent(trim(n.mahalle_adi)))
         =
         lower(unaccent(trim(e.guncel_ad)))
)


SELECT *
FROM exact_match


UNION ALL


SELECT *
FROM manual_match;



-- Expected result:
-- exact  = 944
-- manual = 16
-- total  = 960


SELECT
    match_type,
    COUNT(*)

FROM gis.mahalleler_2025_temiz

GROUP BY match_type;



-- ================================================================
-- 6. UPDATED GEOMETRIES FOR 3 DISTRICTS
-- ================================================================
/*
The original neighborhood boundary dataset did not contain current
2025 geometry for:

Esenler      - 15 Temmuz
Esenyurt     - Merkez
Eyüpsultan   - 5.Levent

Updated neighborhood polygons for the following districts were
therefore imported from OpenStreetMap:

Esenler       17 neighborhoods
Esenyurt      43 neighborhoods
Eyüpsultan    29 neighborhoods

Total         89 neighborhoods

Imported table:

gis.guncel_3_ilce_mahalle

CRS:
EPSG:32635
*/



-- ================================================================
-- 7. ASSIGN DISTRICT TO UPDATED OSM NEIGHBORHOODS
-- ================================================================

DROP MATERIALIZED VIEW IF EXISTS
gis.guncel_3_ilce_mahalle_hazir CASCADE;


CREATE MATERIALIZED VIEW
gis.guncel_3_ilce_mahalle_hazir AS


WITH ilce_maskeleri AS (

    SELECT
        ilceadi,

        ST_UnaryUnion(
            ST_Collect(geom)
        ) AS geom

    FROM gis.mahalleler_2025_temiz

    WHERE ilceadi IN (
        'ESENLER',
        'ESENYURT',
        'EYÜPSULTAN'
    )

    GROUP BY ilceadi
)


SELECT

    g.name
        AS mahalle_adi,

    d.ilceadi,

    ST_Multi(
        ST_CollectionExtract(
            ST_MakeValid(
                ST_CurveToLine(g.geom)
            ),
            3
        )
    )::geometry(MultiPolygon,32635)
        AS geom


FROM gis.guncel_3_ilce_mahalle g


CROSS JOIN LATERAL (

    SELECT
        i.ilceadi

    FROM ilce_maskeleri i

    ORDER BY
        ST_Area(
            ST_Intersection(
                g.geom,
                i.geom
            )
        ) DESC

    LIMIT 1

) d;



-- Expected district counts:
--
-- ESENLER       17
-- ESENYURT      43
-- EYÜPSULTAN    29


SELECT
    ilceadi,
    COUNT(*) AS mahalle_sayisi

FROM gis.guncel_3_ilce_mahalle_hazir

GROUP BY ilceadi

ORDER BY ilceadi;



-- ================================================================
-- 8. CREATE FINAL 963-NEIGHBORHOOD DATASET
-- ================================================================
/*
The three districts above are removed from the old geometry dataset
and replaced by their updated OSM geometries.

OSM names are normalized before matching.

Example:

"Akevler Mahallesi 7 sok..."

becomes:

"akevler"
*/


DROP MATERIALIZED VIEW IF EXISTS
gis.mahalleler_2025_final CASCADE;


CREATE MATERIALIZED VIEW
gis.mahalleler_2025_final AS


-- ------------------------------------------------
-- Existing geometries for the other 36 districts
-- ------------------------------------------------

SELECT

    m.ilceadi,

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


WHERE m.ilceadi NOT IN (
    'ESENLER',
    'ESENYURT',
    'EYÜPSULTAN'
)



UNION ALL



-- ------------------------------------------------
-- Updated geometries for Esenler / Esenyurt /
-- Eyüpsultan
-- ------------------------------------------------

SELECT

    g.ilceadi,

    n.mahalle_adi
        AS mahalle_adi_2025,

    n.nufus
        AS nufus_2025,

    n.mahalle_id,

    'osm_guncel_3_ilce'::text
        AS geometri_kaynagi,

    g.geom


FROM gis.guncel_3_ilce_mahalle_hazir g


JOIN gis.mahalle_nufus_2025 n


ON


-- Normalize district name

regexp_replace(
    lower(unaccent(g.ilceadi)),
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


-- Normalize neighborhood name

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



-- ================================================================
-- 9. INDEXES
-- ================================================================

CREATE UNIQUE INDEX IF NOT EXISTS
uq_mahalleler_2025_final_mahalle_id

ON gis.mahalleler_2025_final
(mahalle_id);


CREATE INDEX IF NOT EXISTS
idx_mahalleler_2025_final_geom

ON gis.mahalleler_2025_final
USING GIST (geom);


ANALYZE gis.mahalleler_2025_final;



-- ================================================================
-- 10. FINAL VALIDATION
-- ================================================================

SELECT
    COUNT(*) AS mahalle_sayisi,

    COUNT(DISTINCT mahalle_id)
        AS benzersiz_mahalle,

    SUM(nufus_2025)
        AS toplam_nufus

FROM gis.mahalleler_2025_final;


/*
Expected:

mahalle_sayisi     = 963
benzersiz_mahalle  = 963
toplam_nufus       = 15753753
*/


SELECT
    ST_GeometryType(geom)
        AS geometry_type,

    ST_SRID(geom)
        AS srid,

    COUNT(*)
        AS adet

FROM gis.mahalleler_2025_final

GROUP BY 1, 2;


/*
Expected:

ST_MultiPolygon | 32635 | 963
*/