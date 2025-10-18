# Image Organisation Scripts

A pair of bash scripts for macOS that work together to **rename** and **organise** images and videos based on their EXIF metadata timestamps. Perfect for managing large image libraries from multiple sources (iPhone, Android, DSLR cameras).

## 📦 What's Included

1. **`rename_images_by_date.sh`** - Renames image files based on EXIF DateTimeOriginal
2. **`organise_files.sh`** - Organises timestamped files into year/month directory structure

## 🎯 Workflow

```
Original Files              After Renaming                        After Organising
--------------              --------------                        ----------------
IMG_1234.jpg        →      20251018_142006_IMG_1234.jpg   →     2025/
DSCF5678.RAF        →      20250625_114810_DSCF5678.RAF   →     ├── 2025-06 June/
photo.heic          →      20251018_142006_photo.heic     →     │   └── 20250625_114810_DSCF5678.RAF
                                                                └── 2025-10 October/
                                                                    ├── 20251018_142006_IMG_1234.jpg
                                                                    └── 20251018_142006_photo.heic
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

Renames image files by prepending `YYYYMMDD_hhmmss_` to the original filename, based on EXIF **DateTimeOriginal** with timezone offset support. This preserves the original filename whilst adding chronological organisation.

### Features

✅ **Timezone-aware renaming** - Uses `OffsetTimeOriginal` to display local capture time  
✅ **Preserves original filenames** - Prepends timestamp without replacing filename  
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

**Files already starting with timestamps are skipped:**
- `20251018_142006_photo.jpg` → *(no change, already renamed)*
- `20251018_142006(1).jpg` → *(no change, already renamed)*

This makes the script **idempotent** - running it multiple times won't cause unwanted changes.

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

- Files without `DateTimeOriginal` EXIF data
- Files already starting with `YYYYMMDD_HHMMSS` timestamp pattern

Both display `[SKIP]` messages with reasons.

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
```

### Step 2: Rename files with EXIF timestamps
```bash
# Preview what will happen
./rename_images_by_date.sh ~/Downloads/iPhone_Export --dry-run

# Apply renaming
./rename_images_by_date.sh ~/Downloads/iPhone_Export
```

**Before:** `IMG_1234.HEIC`, `IMG_1235.jpg`  
**After:** `20231018_143045_IMG_1234.HEIC`, `20231018_150230_IMG_1235.jpg`

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
        └── 20231018_150230_IMG_1235.jpg
```

---

## 🎨 Colour-Coded Output

Both scripts use colour-coded output for better readability:

- 🟢 **Green**: Successful operations, completion messages
- 🔵 **Blue**: Dry-run operations (preview mode)
- 🟡 **Yellow**: Warnings, skipped files, dry-run reminders
- 🔴 **Red**: Errors, deleted files

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
- `rename_images_by_date.sh` will skip files without `DateTimeOriginal`
- Screenshots, scanned images, and some edited images may lack this data
- Check the output for `[SKIP]` messages

### Video Files
Whilst ExifTool supports video files (MOV, MP4), the current `rename_images_by_date.sh` script includes `.mov` but not `.mp4`. Videos use `QuickTime:CreateDate` or `Keys:CreationDate` instead of `DateTimeOriginal`.

To extend support, modify the `find` command in the script to include additional file types.

---

## 🐛 Troubleshooting

### "exiftool: command not found"
Install ExifTool:
```bash
brew install exiftool
```

### "No DateTimeOriginal found"
The image file lacks EXIF creation date metadata. This is common for:
- Screenshots
- Downloaded images
- Scanned images
- Some edited images

### "Permission denied"
Make scripts executable:
```bash
chmod +x rename_images_by_date.sh
chmod +x organise_files.sh
```

### Files not being renamed
Check that:
1. Files have EXIF `DateTimeOriginal` data: `exiftool -DateTimeOriginal image.jpg`
2. You're not in `--dry-run` mode
3. The script has write permissions to the directory
4. Files don't already start with timestamp pattern

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
| Check EXIF date on a file | `exiftool -DateTimeOriginal -OffsetTimeOriginal image.jpg` |
| Find files without EXIF dates | `exiftool -r -if 'not $DateTimeOriginal' ~/Pictures` |

---

**Happy organising! 📸**
