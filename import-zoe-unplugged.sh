#!/bin/bash
# Import Zoé MTV Unplugged Música de Fondo (complete album)
# Runs entirely on Cloudflare — zero local bandwidth

CLI="python3 cli.py"

import_with_retry() {
    local url="$1" title="$2" artist="$3" album="$4"
    local max_attempts=3 attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if $CLI import "$url" --title "$title" --artist "$artist" --album "$album"; then
            return 0
        fi
        echo "  Retry $attempt/$max_attempts after 5s..."
        sleep 5
        ((attempt++))
    done
    echo "  ✗ Failed after $max_attempts attempts: $title"
    return 1
}

echo "Importing Zoé MTV Unplugged Música de Fondo (14 tracks)"
echo "All processing on Cloudflare — zero local bandwidth"
echo ""

failed_count=0

# Track list from official album
import_with_retry "https://www.youtube.com/watch?v=HJqlA_HTEU8" "Soñé (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=7h2ryr_uUEs" "Labios Rotos (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=6W4L2O-JQ-w" "Luna (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=ZBFdkdlhJsI" "Nada (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=g3Ds4cBKe_M" "Nunca (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=EKNAnTFO6gk" "No Me Destruyas (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=GZb0fWHBwQw" "Paula (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=eKz8xZ7W_tQ" "Poli/Love (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=1vb45LxQcpw" "Veneno (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=_Mg9pGpNxzg" "Vía Láctea (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=SBd1zZ_Eris" "Sombras (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=gzmR0s8oZgs" "Dead (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=BdN6fF4m1sE" "Infinito (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))
import_with_retry "https://www.youtube.com/watch?v=QxD9BbSqmWo" "Últimos Días (MTV Unplugged)" "Zoé" "MTV Unplugged Música de Fondo" || ((failed_count++))

echo ""
if [ $failed_count -eq 0 ]; then
    echo "✓ Complete! 14/14 tracks imported to R2 storage via CF infrastructure"
else
    success=$((14 - failed_count))
    echo "⚠ Partial: $success/14 tracks imported, $failed_count failed"
fi
echo "  Stream at: https://audio.vaked.dev/"
