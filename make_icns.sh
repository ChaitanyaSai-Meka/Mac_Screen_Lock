#!/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_image> <output_name>"
    exit 1
fi

INPUT_IMAGE="$1"
OUTPUT_NAME="$2"
ICONSET_DIR="${OUTPUT_NAME}.iconset"

rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

# Convert and resize using sips
echo "Generating iconset..."
sips -s format png -z 16 16     "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "${INPUT_IMAGE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null

echo "Converting to .icns..."
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_NAME}.icns"

rm -rf "${ICONSET_DIR}"
echo "Done: ${OUTPUT_NAME}.icns"
