#!/bin/bash

# Script to rename image files based on EXIF DateTimeOriginal with timezone offset
# Format: YYYYMMDD_hhmmss_<original_filename>.<extension>
# Supports Apple Live Photos by pairing images with their video counterparts (same basename + matching ContentIdentifier)
# Supports JPEG, HEIC, RAF, MOV and other image formats
# Falls back to CreateDate if DateTimeOriginal is not available

set -euo pipefail

# Default values
DRY_RUN=false
DIRECTORY=""

# Colour codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Colour

# Function to display usage
usage() {
    cat << EOF
Usage: $(basename "$0") DIRECTORY [OPTIONS]

Rename image files based on EXIF DateTimeOriginal timestamp with timezone offset.
Files are renamed by prepending timestamp to existing filename: YYYYMMDD_hhmmss_<original>.<extension>
Files already starting with timestamp pattern are skipped.

Falls back to CreateDate for files without DateTimeOriginal (common for videos).
Automatically handles Apple Live Photos by pairing images with their video counterparts
when they share the same basename AND matching ContentIdentifier metadata.

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
    # IMG_1234.jpg -> 20251018_142006_IMG_1234.jpg
    # IMG_1234.mov -> 20251018_142006_IMG_1234.mov (paired with matching image)
    # video.mov -> 20251018_142006_video.mov (standalone, using CreateDate)
    # DSCF0975.RAF -> 20230625_114810_DSCF0975.RAF
    # 20251018_142006.JPEG -> (skipped, already has timestamp)

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

# Function to extract ContentIdentifier from a file
get_content_identifier() {
    local file="$1"
    local content_id=""

    # Try standard ContentIdentifier first
    content_id=$(exiftool -s -s -s -ContentIdentifier "$file" 2>/dev/null)

    # If not found, try QuickTime-specific tag
    if [[ -z "$content_id" ]]; then
        content_id=$(exiftool -s -s -s -"com.apple.quicktime.content.identifier" "$file" 2>/dev/null)
    fi

    echo "$content_id"
}

# Function to extract DateTimeOriginal with timezone offset, with CreateDate fallback
get_datetime_with_timezone() {
    local file="$1"
    local use_fallback=false

    # Try DateTimeOriginal first
    local datetime=$(exiftool -s -s -s -DateTimeOriginal "$file" 2>/dev/null)
    local offset=$(exiftool -s -s -s -OffsetTimeOriginal "$file" 2>/dev/null)

    # If DateTimeOriginal not found, try CreateDate as fallback
    if [[ -z "$datetime" ]]; then
        datetime=$(exiftool -s -s -s -CreateDate "$file" 2>/dev/null)
        use_fallback=true
    fi

    # Return empty if neither field is found
    if [[ -z "$datetime" ]]; then
        return 1
    fi

    # If no offset found or offset is +00:00, use the datetime as-is (assume local time or UTC)
    if [[ -z "$offset" ]] || [[ "$offset" == "+00:00" ]]; then
        # Return datetime without timezone adjustment
        if [[ "$use_fallback" == true ]]; then
            echo "FALLBACK:$datetime"
        else
            echo "$datetime"
        fi
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
        if [[ "$use_fallback" == true ]]; then
            echo "FALLBACK:$datetime"
        else
            echo "$datetime"
        fi
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
        if [[ "$use_fallback" == true ]]; then
            echo "FALLBACK:$datetime"
        else
            echo "$datetime"
        fi
    else
        echo "$adjusted_datetime"
    fi

    return 0
}

# Function to find paired video for an image and verify ContentIdentifier match
find_paired_video() {
    local image_file="$1"
    local image_filename=$(basename "$image_file")
    local image_dir=$(dirname "$image_file")
    local image_basename="${image_filename%.*}"

    # Check for video with same basename in same directory
    # Try both .mov and .MOV extensions
    local potential_video=""

    if [[ -f "${image_dir}/${image_basename}.mov" ]]; then
        potential_video="${image_dir}/${image_basename}.mov"
    elif [[ -f "${image_dir}/${image_basename}.MOV" ]]; then
        potential_video="${image_dir}/${image_basename}.MOV"
    fi

    # If no video found with matching basename, return
    if [[ -z "$potential_video" ]] || ! [[ -f "$potential_video" ]]; then
        return 1
    fi

    # Skip if video already has timestamp
    if filename_has_timestamp "$(basename "$potential_video")"; then
        return 1
    fi

    # Verify ContentIdentifier match
    local image_id=$(get_content_identifier "$image_file")
    local video_id=$(get_content_identifier "$potential_video")

    # If both have ContentIdentifier, they must match
    if [[ -n "$image_id" ]] && [[ -n "$video_id" ]]; then
        if [[ "$image_id" == "$video_id" ]]; then
            # ContentIdentifiers match - this is a Live Photo pair
            echo "$potential_video"
            return 0
        else
            # ContentIdentifiers don't match - not a Live Photo pair
            return 1
        fi
    fi

    # If either file lacks ContentIdentifier, assume they're paired (basename match)
    # This handles older files or files where the tag wasn't written
    echo "$potential_video"
    return 0
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

# Function to rename a file with timestamp
rename_with_timestamp() {
    local file="$1"
    local datetime_raw="$2"
    local is_paired_video="${3:-false}"

    # Check if this is a fallback (starts with FALLBACK:)
    local is_fallback=false
    local datetime="$datetime_raw"
    if [[ "$datetime_raw" == FALLBACK:* ]]; then
        is_fallback=true
        datetime="${datetime_raw#FALLBACK:}"
    fi

    local dir=$(dirname "$file")
    local filename=$(basename "$file")
    local extension="${filename##*.}"
    local basename_no_ext="${filename%.*}"

    # Convert datetime to filename format: YYYYMMDD_HHMMSS
    local year="${datetime:0:4}"
    local month="${datetime:5:2}"
    local day="${datetime:8:2}"
    local hour="${datetime:11:2}"
    local minute="${datetime:14:2}"
    local second="${datetime:17:2}"
    local timestamp="${year}${month}${day}_${hour}${minute}${second}"

    # Prepend timestamp to original filename (without extension)
    local base_name="${timestamp}_${basename_no_ext}"

    # Generate unique filename if duplicate exists
    local new_filename=$(generate_filename "$dir" "$base_name" "$extension")

    # Skip if filename is already correct
    if [[ "$filename" == "$new_filename" ]]; then
        return 0
    fi

    local new_path="${dir}/${new_filename}"
    local prefix=""
    if [[ "$is_paired_video" == "true" ]]; then
        prefix="  ${CYAN}[PAIRED]${NC} "
    elif [[ "$is_fallback" == "true" ]]; then
        prefix="${MAGENTA}[FALLBACK]${NC} "
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${prefix}${BLUE}[DRY RUN]${NC} $file"
        echo -e "          -> $new_filename"
    else
        mv "$file" "$new_path"
        echo -e "${prefix}${GREEN}[RENAMED]${NC} $filename -> $new_filename"
    fi

    return 0
}

# Function to process a single file
process_file() {
    local file="$1"
    local filename=$(basename "$file")

    # Skip if file doesn't have an extension
    local extension="${filename##*.}"
    if [[ "$filename" == "$extension" ]]; then
        echo -e "${YELLOW}[SKIP]${NC} $file - Filename has no extension"
        return 0
    fi

    # Check if filename already starts with timestamp - if so, skip entirely
    if filename_has_timestamp "$filename"; then
        echo -e "${YELLOW}[SKIP]${NC} $file - Filename already has timestamp"
        return 0
    fi

    # Check if this is a video file
    local ext_lower=$(echo "$extension" | tr '[:upper:]' '[:lower:]')
    local is_video=false
    if [[ "$ext_lower" == "mov" ]]; then
        is_video=true
    fi

    # Get DateTimeOriginal with timezone (or CreateDate fallback)
    local datetime
    echo "$file: $(get_datetime_with_timezone \"$file\")"
    if ! datetime=$(get_datetime_with_timezone "$file"); then
        echo -e "${YELLOW}[SKIP]${NC} $file - No DateTimeOriginal or CreateDate found"
        return 0
    fi

    # If this is a standalone video, check if it has a paired image
    if [[ "$is_video" == "true" ]]; then
        local filename_no_ext="${filename%.*}"
        local file_dir=$(dirname "$file")
        local has_paired_image=false

        # Check for paired image with same basename
        for img_ext in heic HEIC jpg JPG jpeg JPEG raf RAF; do
            if [[ -f "${file_dir}/${filename_no_ext}.${img_ext}" ]]; then
                # Found potential pair - verify ContentIdentifier
                local video_id=$(get_content_identifier "$file")
                local image_id=$(get_content_identifier "${file_dir}/${filename_no_ext}.${img_ext}")

                # If both have IDs, they must match
                if [[ -n "$video_id" ]] && [[ -n "$image_id" ]]; then
                    if [[ "$video_id" == "$image_id" ]]; then
                        has_paired_image=true
                        break
                    fi
                else
                    # No IDs or only one has ID - assume paired
                    has_paired_image=true
                    break
                fi
            fi
        done

        # Skip if this video has a paired image (it will be processed with the image)
        if [[ "$has_paired_image" == "true" ]]; then
            return 0
        fi
    fi

    # Rename the file
    rename_with_timestamp "$file" "$datetime" "false"

    # If this is an image, check for paired video (Live Photo)
    if [[ "$is_video" == "false" ]]; then
        local paired_video
        if paired_video=$(find_paired_video "$file"); then
            rename_with_timestamp "$paired_video" "$datetime" "true"
        fi
    fi

    return 0
}

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    echo -e "${RED}Error: No directory specified${NC}"
    usage
fi

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

DIRECTORY="$1"
shift

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

if [[ ! -d "$DIRECTORY" ]]; then
    echo -e "${RED}Error: Directory does not exist: $DIRECTORY${NC}"
    exit 1
fi

check_exiftool

echo -e "${GREEN}Starting image renaming...${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No files will be renamed${NC}"
fi
echo ""

# Process all image and video files
file_count=0
processed_count=0

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
