#!/bin/bash
# Import Zoé MTV Unplugged Música de Fondo (complete album)
# Runs entirely on Cloudflare — zero local bandwidth

set -e

CLI="python3 cli.py"

echo "Importing Zoé MTV Unplugged Música de Fondo (14 tracks)"
echo "All processing happens on Cloudflare infrastructure"
echo ""

# Track list from official album
$CLI import "https://www.youtube.com/watch?v=HJqlA_HTEU8" --title "Soñé (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=7h2ryr_uUEs" --title "Labios Rotos (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=6W4L2O-JQ-w" --title "Luna (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=ZBFdkdlhJsI" --title "Nada (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=g3Ds4cBKe_M" --title "Nunca (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=EKNAnTFO6gk" --title "No Me Destruyas (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=GZb0fWHBwQw" --title "Paula (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=eKz8xZ7W_tQ" --title "Poli/Love (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=1vb45LxQcpw" --title "Veneno (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=_Mg9pGpNxzg" --title "Vía Láctea (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=SBd1zZ_Eris" --title "Sombras (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=gzmR0s8oZgs" --title "Dead (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=BdN6fF4m1sE" --title "Infinito (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"
$CLI import "https://www.youtube.com/watch?v=QxD9BbSqmWo" --title "Últimos Días (MTV Unplugged)" --artist "Zoé" --album "MTV Unplugged Música de Fondo"

echo ""
echo "✓ Complete! 14 tracks imported to R2 storage via CF infrastructure"
echo "  Stream at: https://audio.vaked.dev/"
