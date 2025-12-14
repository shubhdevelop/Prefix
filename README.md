# File Organizer

A Go script that automatically organizes files from a dump directory into destination directories based on filename patterns (prefix/suffix matching) defined in a YAML configuration. Idea of this script comes from the fact that Mac saves all the screenshot and screen recording on Desktop by default and I am lazy enough to find the setting to change the destination folder.

Morever having this also gives joy to  my unonrganised ass, but OCD brain. I love collecting pdfs paper wallpapers, that I might never read and use in future, I love collecting things. Also, I have my hands dirty with creative designing as well, and I am well aware of concept of dump/swipe folders, where people intially dump/swipe things in that folder, and later oragnise them in their intended folders, this step of organising is unavoidable do it now or later and this sometime is dauting and can cause leds to procrastination.

I propose a solution to add a prefix_ to the file being downloaded, which can be sorted later in their intended folders 

## Features

- Move files based on prefix and/or suffix patterns
- YAML-based configuration
- Creates destination directories automatically
- Handles cross-filesystem moves
- Prevents overwriting existing files
- Detailed logging of all operations
- Summary report after completion

## Installation

1. Make sure you have Go installed (version 1.16 or later)

2. Install the required dependency:
```bash
go get gopkg.in/yaml.v3
```

3. Build the script:
```bash
go build -o file-organizer file-organizer.go
```

## Configuration

Create a YAML configuration file with the following structure:

```yaml
dump_directory: "/path/to/dump"

destinations:
  - path: "/path/to/destination1"
    prefix: "file_"          # Optional: match files starting with this
    suffix: ".pdf"           # Optional: match files ending with this
  
  - path: "/path/to/destination2"
    prefix: "report_"
    suffix: ".xlsx"          # Both prefix and suffix (AND logic)
```

### Configuration Options

- `dump_directory`: Source directory containing files to organize
- `destinations`: List of destination rules (processed in order)
  - `path`: Destination directory path
  - `prefix`: (Optional) Files must start with this string
  - `suffix`: (Optional) Files must end with this string
  - If both prefix and suffix are specified, files must match BOTH
  - First matching destination wins

## Usage

Run the script with your configuration file:

```bash
./file-organizer config.yaml
```

Or without building:

```bash
go run file-organizer.go config.yaml
```

## Example

Given this configuration:

```yaml
dump_directory: "/home/user/downloads"

destinations:
  - path: "/home/user/documents/invoices"
    prefix: "invoice_"
    suffix: ".pdf"
  
  - path: "/home/user/documents/reports"
    prefix: "report_"
  
  - path: "/home/user/images"
    suffix: ".jpg"
```

Files will be organized as follows:
- `invoice_2024_01.pdf` → `/home/user/documents/invoices/`
- `invoice_2024_02.xlsx` → Stays in dump (doesn't match suffix)
- `report_quarterly.pdf` → `/home/user/documents/reports/`
- `report_annual.docx` → `/home/user/documents/reports/`
- `photo.jpg` → `/home/user/images/`
- `random.txt` → Stays in dump (no matching rule)

## Behavior

- Files are moved (not copied) to destination directories
- Destination directories are created automatically if they don't exist
- If a file with the same name exists in the destination, the operation is skipped
- Only the first matching destination rule is applied per file
- Directories in the dump folder are ignored
- Detailed logs show each file operation and a summary at the end

## Error Handling

The script will:
- Skip files that can't be moved and continue with others
- Log all errors for review
- Provide a summary of successful and failed operations
- Exit with an error if the dump directory doesn't exist or config is invalid
