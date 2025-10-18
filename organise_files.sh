#!/bin/bash

# File organiser script - moves files based on timestamp in filename
# Usage: ./organise_files.sh SOURCE_DIR DEST_DIR [OPTIONS]

set -e

# Colour codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

# Function to display usage
usage() {
    cat << EOF
Usage: $(basename "$0") SOURCE_DIR DEST_DIR [OPTIONS]

Organises files with timestamp filenames into year/month subdirectories.
Expected filename format: YYYYMMDD_HHMMSS.extension (or starting with this pattern)
Destination structure: dest_dir/YYYY/YYYY-MM Month/filename

ARGUMENTS:
    SOURCE_DIR      Directory containing files to organise
    DEST_DIR        Destination directory for organised files

OPTIONS:
    --dry-run       Show what would be done without actually moving files
    --delete-source Delete source files if identical copies exist at destination
    -h, --help      Display this help message

EXAMPLES:
    $(basename "$0") ~/Downloads ~/Photos --dry-run
    $(basename "$0") ~/Downloads ~/Photos --delete-source

EOF
    exit 1
}

# Function to get month name
get_month_name() {
    case $1 in
        01) echo "January" ;;
        02) echo "February" ;;
        03) echo "March" ;;
        04) echo "April" ;;
        05) echo "May" ;;
        06) echo "June" ;;
        07) echo "July" ;;
        08) echo "August" ;;
        09) echo "September" ;;
        10) echo "October" ;;
        11) echo "November" ;;
        12) echo "December" ;;
        *) echo "" ;;
    esac
}

# Function to validate date and time
validate_datetime() {
    local datetime_str=$1
    # Extract components
    local year=${datetime_str:0:4}
    local month=${datetime_str:4:2}
    local day=${datetime_str:6:2}
    local hour=${datetime_str:9:2}
    local minute=${datetime_str:11:2}
    local second=${datetime_str:13:2}
    # Basic range checks with base-10 conversion to avoid octal interpretation
    [[ $((10#$year)) -ge 1900 && $((10#$year)) -le 3000 ]] || return 1
    [[ $((10#$month)) -ge 1 && $((10#$month)) -le 12 ]] || return 1
    [[ $((10#$day)) -ge 1 && $((10#$day)) -le 31 ]] || return 1
    [[ $((10#$hour)) -ge 0 && $((10#$hour)) -le 23 ]] || return 1
    [[ $((10#$minute)) -ge 0 && $((10#$minute)) -le 59 ]] || return 1
    [[ $((10#$second)) -ge 0 && $((10#$second)) -le 59 ]] || return 1
    # Use date command to validate the actual date
    # This will catch invalid dates like February 30th
    if ! date -j -f "%Y%m%d%H%M%S" "${year}${month}${day}${hour}${minute}${second}" > /dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Function to calculate MD5 hash of a file
get_file_md5() {
    local filepath=$1
    if command -v md5 > /dev/null 2>&1; then
        # macOS
        md5 -q "$filepath"
    elif command -v md5sum > /dev/null 2>&1; then
        # Linux
        md5sum "$filepath" | cut -d' ' -f1
    else
        echo -e "${RED}Error: No MD5 utility found (md5 or md5sum required)${NC}" >&2
        return 1
    fi
}

# Function to find available filename with incremental suffix
find_available_filename() {
    local base_path=$1
    local filename=$2
    # Extract filename parts
    local basename_no_ext="${filename%.*}"
    local extension="${filename##*.}"
    # If there's no extension, handle differently
    if [[ "$basename_no_ext" == "$filename" ]]; then
        extension=""
        local dest_base="$base_path/$filename"
    else
        local dest_base="$base_path/$basename_no_ext"
        extension=".$extension"
    fi
    local counter=1
    local new_filename
    while true; do
        new_filename="${basename_no_ext} (${counter})${extension}"
        local test_path="$base_path/$new_filename"
        if [[ ! -f "$test_path" ]]; then
            echo "$new_filename"
            return 0
        fi
        ((counter++))
    done
}

# Parse command line arguments
DRY_RUN=false
DELETE_SOURCE=false
ARGS=()

# Check for help first
if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --delete-source)
            DELETE_SOURCE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

# Check if we have the required arguments
if [[ ${#ARGS[@]} -ne 2 ]]; then
    echo -e "${RED}Error: Missing required arguments.${NC}"
    usage
fi

SOURCE_DIR="${ARGS[0]}"
DEST_DIR="${ARGS[1]}"

# Validate source directory
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo -e "${RED}Error: Source directory '$SOURCE_DIR' does not exist.${NC}"
    exit 1
fi

# Validate destination directory (create if it doesn't exist)
if [[ ! -d "$DEST_DIR" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${BLUE}[DRY RUN]${NC} Would create destination directory: $DEST_DIR"
    else
        echo -e "${GREEN}Creating destination directory:${NC} $DEST_DIR"
        mkdir -p "$DEST_DIR"
    fi
fi

echo -e "${GREEN}Starting file organisation...${NC}"
echo "Source: $SOURCE_DIR"
echo "Destination: $DEST_DIR"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No files will be moved${NC}"
fi
if [[ "$DELETE_SOURCE" == true ]]; then
    echo -e "${YELLOW}DELETE SOURCE MODE - Duplicate files will be deleted${NC}"
fi
echo ""

# Initialize counters
processed_count=0
skipped_count=0
error_count=0
deleted_count=0
renamed_count=0

# Process files in source directory
for filepath in "$SOURCE_DIR"/*; do
    # Skip directories
    [[ -f "$filepath" ]] || continue
    # Get just the filename
    filename=$(basename "$filepath")
    # Check if filename starts with timestamp pattern: YYYYMMDD_HHMMSS
    if [[ ! "$filename" =~ ^[0-9]{8}_[0-9]{6} ]]; then
        echo -e "${YELLOW}[SKIP]${NC} '$filename' - doesn't start with timestamp pattern"
        ((skipped_count++))
        continue
    fi
    # Extract the timestamp portion (first 15 characters: YYYYMMDD_HHMMSS)
    timestamp_part="${filename:0:15}"
    # Validate the timestamp
    if ! validate_datetime "$timestamp_part"; then
        echo -e "${YELLOW}[SKIP]${NC} '$filename' - invalid timestamp"
        ((skipped_count++))
        continue
    fi
    # Extract year and month from first 6 digits
    year_month="${timestamp_part:0:6}"
    year="${year_month:0:4}"
    month="${year_month:4:2}"
    # Get month name
    month_name=$(get_month_name "$month")
    if [[ -z "$month_name" ]]; then
        echo -e "${YELLOW}[SKIP]${NC} '$filename' - invalid month: $month"
        ((skipped_count++))
        continue
    fi
    # Construct destination path
    dest_subdir="$DEST_DIR/$year/$year-$month $month_name"
    dest_filepath="$dest_subdir/$filename"
    # Check if destination file already exists
    if [[ -f "$dest_filepath" ]]; then
        echo -e "${YELLOW}[EXISTS]${NC} '$filename' already exists at destination"
        # Compare MD5 hashes (perform even during dry run)
        source_md5=$(get_file_md5 "$filepath")
        dest_md5=$(get_file_md5 "$dest_filepath")
        if [[ "$source_md5" == "$dest_md5" ]]; then
            echo -e "         Files are identical (MD5: ${source_md5:0:8}...)"
            if [[ "$DELETE_SOURCE" == true ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    echo -e "${BLUE}[DRY RUN]${NC} Would delete source file (identical copy exists)"
                else
                    echo -e "${RED}[DELETED]${NC} Source file (identical copy exists)"
                    rm "$filepath"
                fi
                ((deleted_count++))
            else
                echo -e "         Keeping source file (use --delete-source to remove duplicates)"
                ((skipped_count++))
            fi
        else
            echo -e "         Files differ, finding new filename"
            new_filename=$(find_available_filename "$dest_subdir" "$filename")
            new_dest_filepath="$dest_subdir/$new_filename"
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "${BLUE}[DRY RUN]${NC} Would rename and move: $filename -> $year/$year-$month $month_name/$new_filename"
            else
                # Create destination subdirectory if it doesn't exist
                mkdir -p "$dest_subdir"
                # Move the file with new name
                if mv "$filepath" "$new_dest_filepath"; then
                    echo -e "${GREEN}[MOVED]${NC} $filename -> $year/$year-$month $month_name/$new_filename"
                else
                    echo -e "${RED}[ERROR]${NC} Failed to move '$filename' to '$new_filename'"
                    ((error_count++))
                    continue
                fi
            fi
            ((renamed_count++))
        fi
    else
        # Destination doesn't exist, proceed with normal move
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "${BLUE}[DRY RUN]${NC} Would move: $filename -> $year/$year-$month $month_name/"
        else
            # Create destination subdirectory if it doesn't exist
            mkdir -p "$dest_subdir"
            # Move the file
            if mv "$filepath" "$dest_filepath"; then
                echo -e "${GREEN}[MOVED]${NC} $filename -> $year/$year-$month $month_name/"
            else
                echo -e "${RED}[ERROR]${NC} Failed to move '$filename'"
                ((error_count++))
                continue
            fi
        fi
        ((processed_count++))
    fi
done

echo ""
echo -e "${GREEN}Complete!${NC}"
echo "Summary:"
echo "  Moved: $processed_count files"
echo "  Renamed and moved: $renamed_count files"
echo "  Deleted (duplicates): $deleted_count files"
echo "  Skipped: $skipped_count files"
echo "  Errors: $error_count files"

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo -e "${YELLOW}This was a dry run. Run without --dry-run to apply changes.${NC}"
fi
