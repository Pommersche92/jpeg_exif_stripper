//! # Image Processor Module
//!
//! Encapsulates byte-level operations, file IO handling, and interface mutations
//! targeting the underlying structure of the image file.

use img_parts::{jpeg::Jpeg, Bytes, ImageEXIF};
use std::fs::File;
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};

/// Generates the output destination file path directly next to the verified source location.
///
/// Preserves directory hierarchies. For example, an input of `"images/vacation/photo.jpg"`
/// evaluates out to a target path of `"images/vacation/output_processed.jpg"`.
pub fn generate_output_path(input_path: &Path) -> PathBuf {
    match input_path.parent() {
        Some(parent) => parent.join("output_processed.jpg"),
        None => Path::new("output_processed.jpg").to_path_buf(),
    }
}

/// Core processor pipeline that loads a JPEG container, updates its embedded metadata structural
/// slice without pixel degradation, and records changes to disk.
///
/// # Behavior
/// * If `strip_all` is flag configured true, the entire `APP1` EXIF app segment gets removed cleanly.
/// * Otherwise, reads existing values, builds an isolated segment writer loop, drops targeted tags,
///   re-serializes the preserved segment fields, and re-injects the metadata block.
///
/// # Errors
/// Returns an execution dynamic error box wrap if reading files fails, or if the underlying
/// file is corrupted and unable to be parsed as a structured JPEG container.
pub fn execute_metadata_strip(
    input_path: &Path,
    output_path: &Path,
    tags_to_strip: &[exif::Tag],
    strip_all: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut file = File::open(input_path)?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;
    let mut jpeg = Jpeg::from_bytes(Bytes::from(buffer))?;

    if strip_all {
        println!("Stripping all EXIF data fields...");
        jpeg.set_exif(None);
    } else if let Some(exif_bytes) = jpeg.exif() {
        let mut reader = Cursor::new(exif_bytes.as_ref());
        let exifreader = exif::Reader::new();

        if let Ok(exif) = exifreader.read_from_container(&mut reader) {
            let mut writer = exif::experimental::Writer::new();
            let mut stripped_count = 0;

            for field in exif.fields() {
                if tags_to_strip.contains(&field.tag) {
                    stripped_count += 1;
                } else {
                    writer.push_field(field);
                }
            }

            if stripped_count > 0 {
                println!("Stripped {} matching tag(s).", stripped_count);
                let mut new_exif_buffer = Cursor::new(Vec::new());
                writer.write(&mut new_exif_buffer, false)?;
                jpeg.set_exif(Some(Bytes::from(new_exif_buffer.into_inner())));
            } else {
                println!("None of the specified tags were found in this image. Copying intact.");
            }
        }
    } else {
        println!("No active EXIF metadata block found to mutate.");
    }

    let mut output_file = File::create(output_path)?;
    output_file.write_all(&jpeg.encoder().bytes())?;
    println!(
        "Successfully processed and wrote changes to: {}",
        output_path.display()
    );

    Ok(())
}
