#!/bin/bash

# Script to rename image files based on EXIF DateTimeOriginal with timezone offset
# Format: YYYYMMDD_hhmmss_PREFIX.<extension> (if original filename starts with uppercase prefix)
# Supports JPEG, HEIC, MOV, MP4 and other image formats

set -euo pipefail

# Default values
DRY_RUN=false
DIRECTORY=""

# Colour codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

# Function to display usage
usage() {
    cat << EOF
Usage: $(basename "$0") DIRECTORY [OPTIONS]

Rename image files based on EXIF DateTimeOriginal timestamp with timezone offset.
Files are renamed to format: YYYYMMDD_hhmmss.<extension>
If original filename starts with 1-5 uppercase letters (A-Z), they are appended as suffix.

ARGUMENTS:
    DIRECTORY       Directory containing images to rename (processes recursively)

OPTIONS:
    --dry-run       Show what would be renamed without making changes
    -h, --help      Display this help message

REQUIREMENTS:
    - exiftool must be installed

EXAMPLES:
    # Preview changes without renaming
    $(basename "$0") ~/Pictures --dry-run

    # Rename all images in directory
    $(basename "$0") ~/Pictures

    # Example transformations:
    # DSCF0975.JPG -> 20230625_114810_DSCF.JPG
    # IMG_1687.JPEG -> 20230607_090048_IMG.JPEG
    # photo.jpg -> 20230607_090048.jpg (no prefix)
    # 20230607_090048.jpg -> (skipped, already renamed)

EOF
    exit 0
}

# Function to check if exiftool is installed
check_exiftool() {
    if ! command -v exiftool &> /dev/null; then
        echo -e "${RED}Error: exiftool is not installed.${NC}"
        echo "Please install it using: brew install exiftool"
        exit 1
    fi
}

# Function to check if filename already starts with timestamp format
filename_has_timestamp() {
    local filename="$1"
    # Check if filename starts with YYYYMMDD_HHMMSS pattern
    if [[ "$filename" =~ ^[0-9]{8}_[0-9]{6} ]]; then
        return 0  # True, has timestamp
    else
        return 1  # False, no timestamp
    fi
}

# Function to extract DateTimeOriginal with timezone offset
get_datetime_with_timezone() {
    local file="$1"
    # Get DateTimeOriginal and OffsetTimeOriginal
    local datetime=$(exiftool -s -s -s -DateTimeOriginal "$file" 2>/dev/null)
    local offset=$(exiftool -s -s -s -OffsetTimeOriginal "$file" 2>/dev/null)
    # Return empty if DateTimeOriginal is not found
    if [[ -z "$datetime" ]]; then
        return 1
    fi
    # If no offset found or offset is +00:00, use the datetime as-is (assume local time or UTC)
    if [[ -z "$offset" ]] || [[ "$offset" == "+00:00" ]]; then
        # Return datetime without timezone adjustment
        echo "$datetime"
        return 0
    fi
    # Parse offset (format: +03:00 or -05:00)
    local sign="${offset:0:1}"
    local hours="${offset:1:2}"
    local minutes="${offset:4:2}"
    # Convert datetime to epoch timestamp
    # DateTimeOriginal format: "2023:10:18 14:30:45"
    local year="${datetime:0:4}"
    local month="${datetime:5:2}"
    local day="${datetime:8:2}"
    local hour="${datetime:11:2}"
    local minute="${datetime:14:2}"
    local second="${datetime:17:2}"
    # Create ISO format for date command: YYYY-MM-DDTHH:MM:SS
    local iso_datetime="${year}-${month}-${day}T${hour}:${minute}:${second}"
    # Convert to epoch (UTC)
    local epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$iso_datetime" "+%s" 2>/dev/null)
    if [[ -z "$epoch" ]]; then
        # Fallback: just use the datetime string as-is
        echo "$datetime"
        return 0
    fi
    # Apply timezone offset to get local time
    local offset_seconds=$((hours * 3600 + minutes * 60))
    if [[ "$sign" == "-" ]]; then
        offset_seconds=$((-offset_seconds))
    fi
    local local_epoch=$((epoch + offset_seconds))
    # Convert back to datetime format
    local adjusted_datetime=$(date -j -f "%s" "$local_epoch" "+%Y:%m:%d %H:%M:%S" 2>/dev/null)
    if [[ -z "$adjusted_datetime" ]]; then
        # Fallback: return original datetime
        echo "$datetime"
    else
        echo "$adjusted_datetime"
    fi
    return 0
}

# Function to extract uppercase prefix from filename (1-5 uppercase letters A-Z only)
extract_uppercase_prefix() {
    local filename="$1"
    # Extract filename without extension
    local basename="${filename%.*}"
    # Check if basename starts with 1-5 uppercase letters (A-Z only, not a-z)
    if [[ "$basename" =~ ^([A-Z]{1,5})([^A-Z].*|$) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Function to generate new filename with duplicate handling
generate_filename() {
    local dir="$1"
    local base_name="$2"
    local extension="$3"
    local target="${dir}/${base_name}.${extension}"
    # If file doesn't exist, return the base name
    if [[ ! -e "$target" ]]; then
        echo "${base_name}.${extension}"
        return 0
    fi
    # File exists, add incremental suffix
    local counter=1
    while [[ -e "${dir}/${base_name}(${counter}).${extension}" ]]; do
        counter=$((counter + 1))
    done
    echo "${base_name}(${counter}).${extension}"
    return 0
}

# Function to process a single file
process_file() {
    local file="$1"
    local dir=$(dirname "$file")
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    # Skip if file doesn't have an extension
    if [[ "$filename" == "$extension" ]]; then
        echo -e "${YELLOW}[SKIP]${NC} $file - Filename has no extension"
        return 0
    fi
    # Check if filename already starts with timestamp - if so, skip entirely
    if filename_has_timestamp "$filename"; then
        echo -e "${YELLOW}[SKIP]${NC} $file - Timestamp found at beginning of filename"
        return 0
    fi
    # Get DateTimeOriginal with timezone
    local datetime
    if ! datetime=$(get_datetime_with_timezone "$file"); then
        echo -e "${YELLOW}[SKIP]${NC} $file - No DateTimeOriginal found"
        return 0
    fi
    # Convert datetime to filename format: YYYYMMDD_HHMMSS
    # Format: "2023:10:18 14:30:45" -> "20231018_143045"
    local year="${datetime:0:4}"
    local month="${datetime:5:2}"
    local day="${datetime:8:2}"
    local hour="${datetime:11:2}"
    local minute="${datetime:14:2}"
    local second="${datetime:17:2}"
    local base_name="${year}${month}${day}_${hour}${minute}${second}"
    # Extract uppercase prefix from original filename
    local prefix=$(extract_uppercase_prefix "$filename")
    # If prefix exists, append it to base_name
    if [[ -n "$prefix" ]]; then
        base_name="${base_name}_${prefix}"
    fi
    # Generate unique filename if duplicate exists
    local new_filename=$(generate_filename "$dir" "$base_name" "$extension")
    # Skip if filename is already correct
    if [[ "$filename" == "$new_filename" ]]; then
        return 0
    fi
    local new_path="${dir}/${new_filename}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}[DRY RUN]${NC} $file"
        echo -e "          -> $new_filename"
    else
        mv "$file" "$new_path"
        echo -e "${GREEN}[RENAMED]${NC} $filename -> $new_filename"
    fi
    return 0
}

# Parse command line arguments
# First argument should be the directory
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: No directory specified${NC}"
    usage
fi

# Check if first argument is a help flag
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

# First positional argument is the directory
DIRECTORY="$1"
shift

# Parse remaining options
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            usage
            ;;
    esac
done

# Validate directory
if [[ ! -d "$DIRECTORY" ]]; then
    echo -e "${RED}Error: Directory does not exist: $DIRECTORY${NC}"
    exit 1
fi

# Check for exiftool
check_exiftool

# Main processing
echo -e "${GREEN}Starting image renaming...${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No files will be renamed${NC}"
fi
echo ""

# Find all image files (JPEG, JPG, HEIC, RAF, mov) recursively
file_count=0
processed_count=0

# Use find to locate all image files
while IFS= read -r -d $'\0' file; do
    file_count=$((file_count + 1))
    if process_file "$file"; then
        processed_count=$((processed_count + 1))
    fi
done < <(find "$DIRECTORY" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.heic" -o -iname "*.raf" -o -iname "*.mov" \) -print0)

echo ""
echo -e "${GREEN}Complete!${NC}"
echo "Total files found: $file_count"
echo "Files processed: $processed_count"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}This was a dry run. No files were actually renamed.${NC}"
    echo "Run without --dry-run to apply changes."
fi
