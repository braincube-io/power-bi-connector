#!/bin/bash

# Script pour construire le connecteur Power BI Braincube
# Crée une archive .mez (unsigned) du connecteur
#
# Usage:
#   ./build.sh                              # Crée Braincube.mez (nom par défaut)
#   ./build.sh Braincube3.2.0               # Crée Braincube3.2.0.mez
#   ./build.sh -h, --help                   # Affiche cette aide

set -e

# Couleurs pour l'output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Valeurs par défaut
OUTPUT_NAME="Braincube"

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            echo "Usage: $0 [NAME]"
            echo ""
            echo "Arguments:"
            echo "  NAME                  Nom de sortie (sans extension, défaut: Braincube)"
            echo ""
            echo "Options:"
            echo "  -h, --help            Afficher cette aide"
            echo ""
            echo "Exemples:"
            echo "  $0                              # Crée Braincube.mez"
            echo "  $0 Braincube3.2.0               # Crée Braincube3.2.0.mez"
            exit 0
            ;;
        *)
            # C'est un argument de nom
            if [[ ! "$1" =~ ^-- ]]; then
                OUTPUT_NAME="$1"
                shift
            else
                echo -e "${RED}Erreur: Argument inconnu: $1${NC}"
                exit 1
            fi
            ;;
    esac
done

if [ ! -d "Braincube" ]; then
    echo -e "${RED}Erreur: Répertoire Braincube non trouvé${NC}"
    exit 1
fi

# Vérifier les prérequis
for cmd in zip; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Erreur: $cmd n'est pas installé${NC}"
        exit 1
    fi
done

# Définir les noms de fichiers
MEZ_OUTPUT="${OUTPUT_NAME}.mez"

echo -e "${CYAN}=== Build Braincube ===${NC}\n"

echo -e "${GREEN}Création du .mez (unsigned)...${NC}"

# Créer une copie temporaire du répertoire Braincube avec les fichiers renommés correctement
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

mkdir -p "$TEMP_DIR/braincube_for_zip"
cp -r Braincube/* "$TEMP_DIR/braincube_for_zip/"

# Nettoyer les fichiers inutiles
rm -f "$TEMP_DIR/braincube_for_zip/Braincube.query.pq"
rm -f "$TEMP_DIR/braincube_for_zip/Braincube.mproj"

# Créer l'archive .mez (simple ZIP)
cd "$TEMP_DIR/braincube_for_zip"
zip -q -r "$TEMP_DIR/output.mez" * -x "*.mez" ".*"
cd - > /dev/null

MEZ_SIZE=$(stat -f%z "$TEMP_DIR/output.mez" 2>/dev/null || stat -c%s "$TEMP_DIR/output.mez")
echo "  Fichier: $MEZ_OUTPUT"
echo "  Taille: $MEZ_SIZE bytes"

# Copier le .mez en sortie
cp "$TEMP_DIR/output.mez" "$MEZ_OUTPUT"
echo ""
echo -e "${GREEN}[SUCCESS] Build terminé!${NC}"
echo "Fichier créé: $MEZ_OUTPUT"
