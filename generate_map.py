import json
import geopandas as gpd
import folium

from folium.plugins import Search


# ------------------------------------------------------
# DATA
# ------------------------------------------------------

DATA_PATH = "data/istanbul_mahalle_analiz_2025.geojson"
OUTPUT_PATH = "web/index.html"

gdf = gpd.read_file(DATA_PATH)

# Web haritaları için WGS84
if gdf.crs.to_epsg() != 4326:
    gdf = gdf.to_crs(epsg=4326)


# ------------------------------------------------------
# MAP
# ------------------------------------------------------

m = folium.Map(
    location=[41.05, 29.00],
    zoom_start=9,
    tiles=None,
    control_scale=True
)


# ------------------------------------------------------
# COLORS
# ------------------------------------------------------
map_css = """
<style>
.leaflet-container {
    background: #f5f5f5 !important;
}
</style>
"""

m.get_root().header.add_child(
    folium.Element(map_css)
)

yetersizlik_colors = {
    "İyi": "#A8D5A2",
    "Orta": "#FFF7AE",
    "Yetersiz": "#F4A259",
    "Çok Yetersiz": "#D7191C",
}

oncelik_colors = {
    "Düşük": "#FF8C69",
    "Orta": "#BD3D80",
    "Yüksek": "#5B1A8B",
    "Çok Yüksek": "#111111",
}


# ------------------------------------------------------
# HELPERS
# ------------------------------------------------------

def format_number(value):
    if value is None:
        return "-"
    try:
        return f"{int(value):,}".replace(",", ".")
    except:
        return str(value)


def style_yetersizlik(feature):

    sinif = feature["properties"].get("yetersizlik_sinifi")

    return {
        "fillColor": yetersizlik_colors.get(sinif, "#cccccc"),
        "color": "#555555",
        "weight": 0.7,
        "fillOpacity": 0.75,
    }


def style_oncelik(feature):

    sinif = feature["properties"].get("mudahale_onceligi")

    return {
        "fillColor": oncelik_colors.get(sinif, "#cccccc"),
        "color": "#555555",
        "weight": 0.7,
        "fillOpacity": 0.78,
    }


def highlight_function(feature):

    return {
        "weight": 3,
        "color": "#222222",
        "fillOpacity": 0.9,
    }


# ------------------------------------------------------
# POPUP
# ------------------------------------------------------

popup_fields = [
    "ILCEADI",
    "mahalle_adi_2025",
    "nufus_2025",
    "toplanma_sayisi",
    "mesafe_m",
    "onbin_kisi_basina_toplanma_noktasi",
    "yetersizlik_sinifi",
    "mudahale_onceligi",
]

popup_aliases = [
    "İlçe:",
    "Mahalle:",
    "Nüfus:",
    "Toplanma noktası:",
    "En yakın alan mesafesi (m):",
    "10.000 kişi başına nokta:",
    "Yetersizlik:",
    "Müdahale önceliği:",
]


# ------------------------------------------------------
# LAYER 1 — YETERSİZLİK
# ------------------------------------------------------

yetersizlik = folium.GeoJson(
    gdf,
    name="Toplanma Alanı Yetersizliği",
    style_function=style_yetersizlik,
    highlight_function=highlight_function,
    tooltip=folium.GeoJsonTooltip(
        fields=[
            "ILCEADI",
            "mahalle_adi_2025",
            "yetersizlik_sinifi",
        ],
        aliases=[
            "İlçe:",
            "Mahalle:",
            "Yetersizlik:",
        ],
        sticky=False,
    ),
    popup=folium.GeoJsonPopup(
        fields=popup_fields,
        aliases=popup_aliases,
        localize=True,
        labels=True,
        style="""
            background-color: white;
            font-family: Arial;
            font-size: 13px;
        """,
    ),
    show=False,
)

yetersizlik.add_to(m)


# ------------------------------------------------------
# LAYER 2 — MÜDAHALE ÖNCELİĞİ
# ------------------------------------------------------

oncelik = folium.GeoJson(
    gdf,
    name="Müdahale Önceliği",
    style_function=style_oncelik,
    highlight_function=highlight_function,
    tooltip=folium.GeoJsonTooltip(
        fields=[
            "ILCEADI",
            "mahalle_adi_2025",
            "mudahale_onceligi",
        ],
        aliases=[
            "İlçe:",
            "Mahalle:",
            "Müdahale Önceliği:",
        ],
        sticky=False,
    ),
    popup=folium.GeoJsonPopup(
        fields=popup_fields,
        aliases=popup_aliases,
        localize=True,
        labels=True,
    ),
    show=True,
)

oncelik.add_to(m)


# ------------------------------------------------------
# SEARCH
# ------------------------------------------------------

Search(
    layer=oncelik,
    search_label="mahalle_adi_2025",
    placeholder="Mahalle ara...",
    collapsed=False,
    search_zoom=13,
).add_to(m)


# ------------------------------------------------------
# LAYER CONTROL
# ------------------------------------------------------

folium.LayerControl(
    collapsed=False
).add_to(m)


# ------------------------------------------------------
# TITLE
# ------------------------------------------------------

title_html = """
<div style="
    position: fixed;
    top: 15px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 9999;
    background: rgba(255,255,255,0.95);
    padding: 10px 20px;
    border-radius: 8px;
    box-shadow: 0 1px 5px rgba(0,0,0,0.25);
    font-family: Arial;
    font-size: 18px;
    font-weight: bold;
">
İstanbul Toplanma Alanları Analizi – 2025
</div>
"""

m.get_root().html.add_child(
    folium.Element(title_html)
)


# ------------------------------------------------------
# INFO BOX
# ------------------------------------------------------

info_html = """
<div style="
    position: fixed;
    bottom: 25px;
    left: 25px;
    z-index: 9999;
    background-color: rgba(255,255,255,0.95);
    padding: 10px 14px;
    border-radius: 6px;
    box-shadow: 0 1px 5px rgba(0,0,0,0.3);
    font-family: Arial;
    font-size: 12px;
    max-width: 310px;
">
<b>Analiz kapsamı</b><br>
963 mahalle<br>
5.599 toplanma noktası<br>
2025 mahalle nüfusu<br><br>

<b>Yöntem</b><br>
PostgreSQL/PostGIS + QGIS + Python
</div>
"""

m.get_root().html.add_child(
    folium.Element(info_html)
)

# ------------------------------------------------------
# BOUNDS
# ------------------------------------------------------

bounds = gdf.total_bounds

m.fit_bounds([
    [bounds[1], bounds[0]],
    [bounds[3], bounds[2]]
])

# ------------------------------------------------------
# SAVE
# ------------------------------------------------------

m.save(OUTPUT_PATH)

print(f"Web haritası oluşturuldu: {OUTPUT_PATH}")