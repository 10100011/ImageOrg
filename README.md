# Image Organisation Scripts

A pair of bash scripts for macOS that work together to **rename** and **organise** images and videos based on their EXIF metadata timestamps. Perfect for managing large image libraries from multiple sources (iPhone, Android, DSLR cameras).

**Special support for Apple Live Photos** - automatically pairs images with their video counterparts using basename matching and ContentIdentifier validation.

## 🚨 WARNING ‼️
> These scripts, and most of the README (except this section), were created by AI. They have been reviwed and tested, and they work ... for me, for my use-case, with my data, on my Mac. _Your Mileage May Vary_: meaning, it may be different for you. You are **strongly** advised to backup your data before use, include the `--dry-run` option at the beginning, and review the dry-run output before inputting valuable data. If it wasn't already clear: no warranty or liability is implied or accepted.

## 📦 What's Included

1. **`rename_images_by_date.sh`** - Renames image files based on EXIF DateTimeOriginal
2. **`organise_files.sh`** - Organises timestamped files into year/month directory structure

## 🎯 Workflow

```
Original Files              After Renaming                        After Organising
--------------              --------------                        ----------------
IMG_1234.heic       →      20251018_142006_IMG_1234.heic  →     2025/
IMG_1234.mov (Live) →      20251018_142006_IMG_1234.mov   →     ├── 2025-06 June/
IMG_5678.mov        →      20250601_102801_IMG_5678.mov   →     │   ├── 20250601_102801_IMG_5678.mov
DSCF5678.RAF        →      20250625_114810_DSCF5678.RAF   →     │   └── 20250625_114810_DSCF5678.RAF
photo.JPEG          →      20251018_142126_photo.JPEG     →     └── 2025-10 October/
                                                                    ├── 20251018_142006_IMG_1234.heic
                                                                    ├── 20251018_142006_IMG_1234.mov
                                                                    └── 20251018_142126_photo.JPEG
```

## 📋 Prerequisites

### Required
- **macOS** (scripts use macOS-specific commands)
- **ExifTool** - Install via Homebrew:
  ```bash
  brew install exiftool
  ```

### Supported File Types
- **Images**: JPEG (`.jpg`, `.jpeg`), HEIC (`.heic`), RAW (`.raf`)
- **Videos**: QuickTime (`.mov`)

Can be extended to support other media types, if those types are readable by ExifTool

---

## 🔧 Script 1: `rename_images_by_date.sh`

Renames image files by prepending `YYYYMMDD_hhmmss_` to the original filename, based on EXIF **DateTimeOriginal** with timezone offset support. Falls back to **CreateDate** for files without DateTimeOriginal (common for videos). This preserves the original filename whilst adding chronological organisation.

**Automatically handles Apple Live Photos** by detecting video files with matching basenames, validating their ContentIdentifier metadata, and renaming them together using the image's timestamp.

### Features

✅ **Timezone-aware renaming** - Uses `OffsetTimeOriginal` to display local capture time  
✅ **CreateDate fallback** - Processes videos and images lacking DateTimeOriginal  
✅ **Preserves original filenames** - Prepends timestamp without replacing filename  
✅ **Apple Live Photo support** - Validates ContentIdentifier to ensure correct pairing  
✅ **Standalone video support** - Processes unpaired videos using CreateDate  
✅ **Idempotent operation** - Files already with timestamps are skipped  
✅ **Dry-run mode** - Preview changes before applying  
✅ **Duplicate handling** - Adds incremental suffixes `(1)`, `(2)`, etc.  
✅ **Recursive processing** - Scans all subdirectories  
✅ **Multiple format support** - JPEG, HEIC, RAF, MOV  

### Usage

```bash
# Make executable
chmod +x rename_images_by_date.sh

# Preview changes (recommended first step)
./rename_images_by_date.sh ~/Pictures --dry-run

# Rename files
./rename_images_by_date.sh ~/Pictures

# Show help
./rename_images_by_date.sh --help
```

### Syntax

```
./rename_images_by_date.sh DIRECTORY [OPTIONS]

ARGUMENTS:
  DIRECTORY       Directory containing images to rename (processes recursively)

OPTIONS:
  --dry-run       Show what would be renamed without making changes
  -h, --help      Display this help message
```

### Examples

```bash
# Rename photos from iPhone export
./rename_images_by_date.sh ~/Desktop/iPhone_Photos --dry-run
./rename_images_by_date.sh ~/Desktop/iPhone_Photos

# Process entire image library
./rename_images_by_date.sh ~/Pictures
```

### Renaming Behaviour

The script **prepends** the timestamp to the existing filename:
- `IMG_1234.jpg` → `20251018_142006_IMG_1234.jpg`
- `DSCF0975.RAF` → `20230625_114810_DSCF0975.RAF`
- `photo.heic` → `20251018_142006_photo.heic`
- `standalone.mov` → `20251018_153000_standalone.mov` (using CreateDate)

**Files already starting with timestamps are skipped:**
- `20251018_142006_photo.jpg` → *(no change, already renamed)*
- `20251018_142006(1).jpg` → *(no change, already renamed)*

This makes the script **idempotent** - running it multiple times won't cause unwanted changes.

### Apple Live Photo Support

Live Photos consist of an image (HEIC/JPG) and a video (MOV) component. The script automatically detects and pairs them using:

1. **Basename matching** - Both files must share the same basename (e.g., `IMG_1234.HEIC` and `IMG_1234.MOV`)
2. **Same directory** - Both files must be in the same directory
3. **ContentIdentifier validation** - Verifies Apple's internal pairing metadata matches

**Pairing logic:**
- If **both files have ContentIdentifier metadata**: IDs must match to pair
- If **either file lacks ContentIdentifier**: assumes paired (backward compatibility for older files)
- If **ContentIdentifiers don't match**: processes as separate, unrelated files

**Example:**
```
IMG_1234.HEIC + IMG_1234.MOV (same basename, matching ContentIdentifier)
    ↓
20251018_142006_IMG_1234.HEIC + 20251018_142006_IMG_1234.MOV [PAIRED]

IMG_5678.HEIC + IMG_5678.MOV (same basename, different ContentIdentifier)
    ↓
20251018_142006_IMG_5678.HEIC + 20251018_153000_IMG_5678.MOV [FALLBACK]
(processed separately)
```

Live Photo videos are marked with `[PAIRED]` in cyan in the output for clarity.

**Why this matters:** Apple Live Photo videos often lack `DateTimeOriginal` metadata, causing them to be skipped or separated from their images. The ContentIdentifier validation ensures only genuine Live Photo pairs are renamed together, whilst standalone videos with coincidentally matching basenames are processed independently.

### CreateDate Fallback

For files without `DateTimeOriginal` (common for videos, screenshots, and some edited images), the script automatically falls back to the `CreateDate` field.

Files using this fallback are marked with `[FALLBACK]` in magenta in the output.

**Example:**
```
standalone_video.mov (no DateTimeOriginal, has CreateDate)
    ↓
20251018_153000_standalone_video.mov [FALLBACK]
```

### How Timezone Handling Works

1. Reads `DateTimeOriginal` (e.g., `2023:10:18 14:30:45`)
2. Reads `OffsetTimeOriginal` (e.g., `+03:00` or `-05:00`)
3. Converts timestamp to **local time** where photo was taken
4. If offset is `+00:00` or missing, uses timestamp as-is

**Example:**
- Photo taken in Tokyo (UTC+9) at 14:30 local time
- EXIF: `DateTimeOriginal: 2023:10:18 14:30:45`, `OffsetTimeOriginal: +09:00`
- Result: `20231018_143045_<original_filename>.jpg` (local Tokyo time preserved)

### What Gets Skipped

- Files without `DateTimeOriginal` **or** `CreateDate` EXIF data
- Files already starting with `YYYYMMDD_HHMMSS` timestamp pattern

All skipped files display `[SKIP]` messages with reasons.

---

## 🗂️ Script 2: `organise_files.sh`

Moves files with timestamp-based filenames into organised year/month directories.

### Features

✅ **Year/Month organisation** - Creates `YYYY/YYYY-MM MonthName/` structure  
✅ **Dry-run mode** - Preview changes before moving  
✅ **Duplicate detection** - MD5 hash comparison  
✅ **Incremental naming** - Automatic rename on collision  
✅ **Optional duplicate deletion** - Remove source if identical copy exists  

### Usage

```bash
# Make executable
chmod +x organise_files.sh

# Preview organisation (recommended first step)
./organise_files.sh ~/Downloads ~/Photos --dry-run

# Organise files
./organise_files.sh ~/Downloads ~/Photos

# Organise and delete duplicates
./organise_files.sh ~/Downloads ~/Photos --delete-source
```

### Syntax

```
./organise_files.sh SOURCE_DIR DEST_DIR [OPTIONS]

ARGUMENTS:
  SOURCE_DIR      Directory containing files to organise
  DEST_DIR        Destination directory for organised files

OPTIONS:
  --dry-run       Show what would be done without actually moving files
  --delete-source Delete source files if identical copies exist at destination
  -h, --help      Display this help message
```

### Expected Filename Format

Files must start with: `YYYYMMDD_HHMMSS` (e.g., `20231018_143045_IMG_1234.jpg`)

This matches the output format of `rename_images_by_date.sh`.

### Destination Structure

```
~/Photos/
├── 2023/
│   ├── 2023-09 September/
│   │   ├── 20230915_120000_photo.jpg
│   │   └── 20230920_143000_IMG_5678.heic
│   └── 2023-10 October/
│       ├── 20231018_142006_IMG_1234.jpg
│       ├── 20231018_142006_IMG_1234.mov (Live Photo video)
│       ├── 20231018_153000_standalone.mov (separate video)
│       ├── 20231018_143045_DSCF0123.RAF
│       └── 20231018_150230_vacation.heic
└── 2024/
    └── 2024-01 January/
        └── 20240101_000000_newyear.jpg
```

### Duplicate Handling

**When file exists at destination:**

1. **Files are identical (MD5 match)**:
   - Without `--delete-source`: Keeps both files, reports duplicate
   - With `--delete-source`: Deletes source file, keeps destination

2. **Files differ (different content)**:
   - Renames with incremental suffix: `20231018_143045_IMG_1234 (1).jpg`

---

## 🚀 Complete Workflow Example

### Step 1: Export images from iPhone
```bash
# Copy images to ~/Downloads/iPhone_Export
# Live Photos will appear as IMG_1234.HEIC + IMG_1234.MOV pairs
```

### Step 2: Rename files with EXIF timestamps
```bash
# Preview what will happen
./rename_images_by_date.sh ~/Downloads/iPhone_Export --dry-run

# Apply renaming
./rename_images_by_date.sh ~/Downloads/iPhone_Export
```

**Before:** `IMG_1234.HEIC`, `IMG_1234.MOV`, `IMG_1235.jpg`, `video.mov`  
**After:** `20231018_143045_IMG_1234.HEIC`, `20231018_143045_IMG_1234.MOV` (paired), `20231018_150230_IMG_1235.jpg`, `20231018_153000_video.mov` (standalone)

The script automatically detected and validated the Live Photo pair, whilst processing the standalone video independently.

### Step 3: Organise into library
```bash
# Preview organisation
./organise_files.sh ~/Downloads/iPhone_Export ~/Photos --dry-run

# Move files (keeping duplicates in source)
./organise_files.sh ~/Downloads/iPhone_Export ~/Photos

# OR move files and delete source duplicates
./organise_files.sh ~/Downloads/iPhone_Export ~/Photos --delete-source
```

**Result:**
```
~/Photos/
└── 2023/
    └── 2023-10 October/
        ├── 20231018_143045_IMG_1234.HEIC
        ├── 20231018_143045_IMG_1234.MOV
        ├── 20231018_150230_IMG_1235.jpg
        └── 20231018_153000_video.mov
```

Live Photo pairs and standalone videos all organised chronologically.

---

## 🎨 Colour-Coded Output

Both scripts use colour-coded output for better readability:

- 🟢 **Green**: Successful operations, completion messages
- 🔵 **Blue**: Dry-run operations (preview mode)
- 🟡 **Yellow**: Warnings, skipped files, dry-run reminders
- 🔴 **Red**: Errors, deleted files
- 🔵 **Cyan**: Live Photo pairing indicators `[PAIRED]`
- 🟣 **Magenta**: CreateDate fallback indicators `[FALLBACK]`

---

## ⚠️ Important Notes

### macOS Specific
These scripts use macOS-specific commands:
- `date -j -f` (macOS date formatting)
- `md5 -q` (macOS MD5 utility)

For Linux, modifications would be needed.

### Backup First!
Always run with `--dry-run` first to preview changes before modifying your files.

### Files Without EXIF Data
- `rename_images_by_date.sh` will skip files without **both** `DateTimeOriginal` and `CreateDate`
- Screenshots, scanned images, and some heavily edited files may lack both fields
- Check the output for `[SKIP]` messages

### Live Photo Requirements
- Image and video **must have the same basename** (e.g., `IMG_1234.HEIC` + `IMG_1234.MOV`)
- Both files **must be in the same directory**
- **ContentIdentifier validation**: If both files have this metadata, the IDs must match
- Files without ContentIdentifier are assumed to be paired (legacy compatibility)

### Video Files
The script processes standalone `.mov` files using CreateDate fallback. Videos use `QuickTime:CreateDate` or `Keys:CreationDate` instead of `DateTimeOriginal`.

To extend support to other video formats (e.g., `.mp4`), modify the `find` command in the script.

---

## 🐛 Troubleshooting

### "exiftool: command not found"
Install ExifTool:
```bash
brew install exiftool
```

### "No DateTimeOriginal or CreateDate found"
The file lacks both date metadata fields. This is uncommon but can occur for:
- Heavily edited images with stripped metadata
- Corrupt files
- Non-standard file formats

### "Permission denied"
Make scripts executable:
```bash
chmod +x rename_images_by_date.sh
chmod +x organise_files.sh
```

### Files not being renamed
Check that:
1. Files have EXIF date data: `exiftool -DateTimeOriginal -CreateDate image.jpg`
2. You're not in `--dry-run` mode
3. The script has write permissions to the directory
4. Files don't already start with timestamp pattern

### Live Photo videos not pairing
Check:
1. Image and video have **exactly the same basename** (e.g., `IMG_1234.HEIC` and `IMG_1234.MOV`)
2. Both files are in the **same directory**
3. Verify ContentIdentifier match: `exiftool -ContentIdentifier IMG_1234.HEIC IMG_1234.MOV`
4. If ContentIdentifiers differ, they're not a Live Photo pair and will be processed separately
5. Run with `--dry-run` to see pairing messages

### Videos with same basename as photos not pairing
This is by design. If an image and video share the same basename but have **different ContentIdentifiers**, they are unrelated files and will be processed independently. This prevents false pairing of coincidentally named files.

---

## 📝 Licence

These scripts are provided as-is for personal use. Feel free to modify and distribute.

---

## 🙏 Credits

- **ExifTool** by Phil Harvey - https://exiftool.org
- Built for macOS terminal users managing large image libraries

---

## 🔗 Quick Reference

| Task | Command |
|------|---------|
| Rename photos with timestamps | `./rename_images_by_date.sh ~/Pictures --dry-run` |
| Organise renamed files | `./organise_files.sh ~/Downloads ~/Photos --dry-run` |
| Full workflow preview | Run both commands with `--dry-run` |
| Check EXIF date on a file | `exiftool -DateTimeOriginal -CreateDate image.jpg` |
| Check Live Photo ContentIdentifier | `exiftool -ContentIdentifier IMG_1234.HEIC IMG_1234.MOV` |
| Find files without EXIF dates | `exiftool -r -if 'not $DateTimeOriginal and not $CreateDate' ~/Pictures` |

---

**Happy organising! 📸**
