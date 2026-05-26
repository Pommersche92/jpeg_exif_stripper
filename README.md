# 📸 JPEG EXIF Metadata Stripper

A high-performance, modular, and completely lossless command-line utility written in Rust to surgically remove EXIF metadata fields from JPEG images. 🚀

By modifying the JPEG's application segments (`APP1`) directly at the byte level, this tool manipulates metadata **without decoding or re-encoding the image pixels**. This ensures zero degradation in image quality and blazing-fast execution speeds. ⚡

---

## ✨ Features

- **🛡️ Lossless Operations:** Strips metadata without altering raw pixel arrays—no compression artifacts or generation loss.
- **🎛️ Flexible Modes:** Run interactively through terminal prompts or fully headlessly via command-line options.
- **🎯 Granular Removal Engine:**
  - Strip **ALL** EXIF metadata fields entirely.
  - Target a **single** specific tag (e.g., `Orientation` or `GPSLatitude`).
  - Pass a **comma-separated list** of specific targets.
- **🔢 Hexadecimal Mapping Fallback:** Input explicit low-level hex tags (e.g., `0x0112`) for advanced or custom metadata payloads.
- **📁 Platform-Agnostic Pathing:** Securely outputs the processed file directly next to the original input source path across both UNIX and Windows directory layouts.

---

## 📥 Installation

### Method 1: Via Cargo Install 🦀 (Recommended for Rust Users)

If you have Cargo installed, you can install the binary globally directly from source or crates.io by running:

```bash
cargo install jpeg-exif-stripper
```

*This compiles the binary with full release optimizations and places it directly into your global ~/.cargo/bin path.*

### Method 2: Via Arch Linux User Repository 🏔️ (AUR)

If you are running Arch Linux or an Arch-based distribution, you can choose from three distinct AUR packages depending on your preference for stability, compilation overhead, or bleeding-edge updates:

| Package | Source Type | Ideal For |
| :--- | :--- | :--- |
| **`jpeg-exif-stripper`** | Latest Stable Release (Source) | Users who prefer stable tagged releases and want to compile locally. |
| **`jpeg-exif-stripper-git`** | Bleeding-Edge Master Branch | Developers or testers who want the absolute latest commits as soon as they hit the repository. |
| **`jpeg-exif-stripper-bin`** | Precompiled Release Binary | Users who want stable releases but want to skip the Rust compilation process for instant installation. |

#### Installing with an AUR Helper (e.g., `yay`)

Simply pass your chosen package flavor to your helper:

```bash
# Install stable version (compiles from release source)
yay -S jpeg-exif-stripper

# Install bleeding-edge version (compiles from latest master commit)
yay -S jpeg-exif-stripper-git

# Install precompiled binary version (downloads prebuilt binary instantly)
yay -S jpeg-exif-stripper-bin
```

#### Installing Manually

If you don't use an AUR helper, you can clone and build any of the packages manually using `makepkg`:

```bash
git clone [https://aur.archlinux.org/jpeg-exif-stripper-bin.git](https://aur.archlinux.org/jpeg-exif-stripper-bin.git)
cd jpeg-exif-stripper-bin
makepkg -si
```

### Method 3: Download Precompiled Windows Binary 🪟

If you don't want to install Rust or compile the code yourself, you can grab a ready-to-use executable from the GitHub Releases page.

#### 1. Download & Extract

1. Go to the **Releases** section of this GitHub repository.
2. Download the latest `jpeg_exif_stripper-windows-amd64.zip` file.
3. Extract the ZIP file to a permanent folder on your computer (for example: `C:\Program Files\jpeg_exif_stripper\`).

#### 2. Add to Windows System PATH

To run the tool from any command prompt or PowerShell window without typing the full folder path, add it to your environment variables:

1. Press the **Windows Key**, type `env`, and select **Edit the system environment variables**.
2. Click the **Environment Variables...** button at the bottom right.
3. Under **System variables** (bottom section), scroll down, select the **Path** variable, and click **Edit...**.
4. Click **New** on the right side and paste the path to your extracted folder (e.g., `C:\Program Files\jpeg_exif_stripper\`).
5. Click **OK** on all three windows to save your changes.

#### 3. Verify & Run

Open a **new** Command Prompt or PowerShell window (old windows won't register the path change) and verify it works:

```cmd
jpeg_exif_stripper --version
```

You can now use the utility globally just like any native system command:

```dos
jpeg_exif_stripper C:\Users\YourName\Pictures\vacation.jpg 1
```

### Method 4: Compiling Manually from Source 🛠️

#### 1. Clone or download this project directory

```bash
git clone [https://github.com/yourusername/jpeg_exif_stripper.git](https://github.com/yourusername/jpeg_exif_stripper.git)
cd jpeg_exif_stripper
```

#### 2. Compile the production-optimized, stripped release binary

```bash
cargo build --release
```

The compiled local executable will be located at `./target/release/jpeg_exif_stripper`.

## 💻 Usage Syntax

```bash
jpeg_exif_stripper <INPUT_JPEG_PATH> [STRIP_SELECTION]
```

### 🚩 Flags

- `-h`, `--help`: Outputs application layout guidelines and documentation metrics
- `-v`, `--version`: Outputs active compiler package configuration versions

## 💡 Examples

### 1. Interactive Mode 💬

If you omit the second argument, the application drops into an interactive shell console asking for your choice:

```bash
jpeg_exif_stripper my_photo.jpg
```

### 2. Automated Total Wipe 🌪️

Completely strips out the entire EXIF application structure block headlessly:

```bash
jpeg_exif_stripper my_photo.jpg 1
```

### 3. Automated Targeted Tag List 🎯

Drops only the `Orientation` and `Software` flags while leaving camera models, date records, or focal metrics intact:

```bash
jpeg_exif_stripper path/to/image.jpg "Orientation, Software"
```

### 4. Advanced Hexadecimal Targeting 🔮

Mix and match named strings with explicit raw hex markers to remove specific parameters:

```bash
jpeg_exif_stripper image.jpg "Orientation, 0x010f, DateTime"
```

*Note: All mutations will preserve the original file untouched and create an updated clone named* `output_processed.jpg` *inside the source image's parent directory.*

## 🏗️ Architecture Design

The project is split into separate, highly decoupled modules:

- `src/main.rs`: Orchestrates application configuration context parameters and command execution routing.
- `src/tag_parser.rs`: Sanitizes string arguments and safely maps alphanumeric parameters into structured metadata enums.
- `src/processor.rs`: Handles low-level file stream payloads, processes the JPEG binary segment trees via img-parts, and outputs changes safely to disk.

## ⚖️ License

This project is licensed under the **GNU General Public License, Version 3 (GPLv3)**. See the accompanying `LICENSE` file for full legal copy text parameters. 📝

---

<p align="center">
  Made with ❤️ in the German Black Forest 🌲🌲
</p>
