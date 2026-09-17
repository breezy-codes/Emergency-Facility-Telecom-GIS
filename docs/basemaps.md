# Map Basemaps

This project uses web map tiles through [Folium](https://python-visualization.github.io/folium/). Recent changes to Folium and basemap providers mean that basemaps should be explicitly configured rather than relying on the previous defaults.

## OpenStreetMap

If you would like to use OpenStreetMap, add the following `TileLayer` to your Folium map:

```python
folium.TileLayer(
    tiles="https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    attr="&copy; <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap</a> contributors",
    name="OpenStreetMap",
    referrer_policy="strict-origin",
).add_to(m)
```

### Rendering locally

To use OSM, the only way to render the map is to do so locally. This is because the OSM tile server does not allow requests from `file://` URLs, which is what happens when you open the generated HTML file directly in a browser.

When opening Folium maps locally, it is necessary to serve the generated HTML through a local HTTP server rather than opening the file directly.

From the project directory, run:

```bash
python -m http.server 8000
```

Then open:

```text
http://localhost:8000/
```

Navigate to the generated Folium HTML file from there.

---

## CARTO

CARTO basemaps now require an API key.

If you would like to use CARTO Voyager, first request your own API key:

[https://carto.com/basemaps/apikey/](https://carto.com/basemaps/apikey/)

The free tier currently provides **5 million tile requests per calendar month**. Keep the CARTO and OpenStreetMap attribution visible on maps when using the service.

Once you have an API key, add the following layer and replace `YOUR_KEY` with your own key:

```python
folium.TileLayer(
    tiles="https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png?key=YOUR_KEY",
    attr='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>, &copy; <a href="https://carto.com/attributions">CARTO</a>',
    subdomains="abcd",
    max_zoom=20,
    name="CARTO Voyager",
).add_to(m)
```

### Important

**Do not commit your CARTO API key to GitHub or other public repositories.**

For public projects, use an environment variable instead:

```python
import os

carto_api_key = os.getenv("CARTO_API_KEY")

folium.TileLayer(
    tiles=f"https://{{s}}.basemaps.cartocdn.com/rastertiles/voyager/{{z}}/{{x}}/{{y}}.png?key={carto_api_key}",
    attr='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>, &copy; <a href="https://carto.com/attributions">CARTO</a>',
    subdomains="abcd",
    max_zoom=20,
    name="CARTO Voyager",
).add_to(m)
```

Set the key before running the project:

```bash
export CARTO_API_KEY="your_api_key_here"
```

For Windows PowerShell:

```powershell
$env:CARTO_API_KEY="your_api_key_here"
```

Add any local `.env` files containing the key to `.gitignore`.

---

## Recommended default

For projects where an API key is undesirable, use **OpenStreetMap**.

For projects requiring the **CARTO Voyager** visual style, obtain a personal CARTO API key and keep it outside the repository.
