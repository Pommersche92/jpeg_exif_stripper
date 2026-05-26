//! # Tag Parser Module
//!
//! Provides text-parsing utilities to map command-line strings and numeric options
//! into structured EXIF tags used by the application framework.

/// Maps case-insensitive string representations or hexadecimal strings into an explicit [`exif::Tag`].
///
/// # Supported Core Named Tags
/// * `orientation`
/// * `software`
/// * `datetime` / `date_time`
/// * `make`
/// * `model`
/// * `gpslatitude` / `gps_longitude`
/// * `copyright`
/// * `usercomment`
///
/// # Fallback
/// If the text isn't matching a standard name but begins with `0x`, this function 
/// will parse the trailing characters as a hexadecimal `u16` tag code instead.
///
/// # Examples
/// ```
/// let tag = parse_tag_name("orientation");
/// assert_eq!(tag, Some(exif::Tag::Orientation));
///
/// let hex_tag = parse_tag_name("0x0112");
/// assert_eq!(hex_tag, Some(exif::Tag::Orientation));
/// ```
pub fn parse_tag_name(name: &str) -> Option<exif::Tag> {
    match name.trim().to_lowercase().as_str() {
        "orientation" => Some(exif::Tag::Orientation),
        "software" => Some(exif::Tag::Software),
        "datetime" | "date_time" => Some(exif::Tag::DateTime),
        "make" => Some(exif::Tag::Make),
        "model" => Some(exif::Tag::Model),
        "gpslatitude" | "gps_latitude" => Some(exif::Tag::GPSLatitude),
        "gpslongitude" | "gps_longitude" => Some(exif::Tag::GPSLongitude),
        "copyright" => Some(exif::Tag::Copyright),
        "usercomment" | "user_comment" => Some(exif::Tag::UserComment),
        _ => {
            // Hex fallback (e.g., "0x0112")
            if name.trim().starts_with("0x") {
                if let Ok(num) = u16::from_str_radix(name.trim().trim_start_matches("0x"), 16) {
                    // FIX: Construct the Tag tuple struct directly using TIFF/Exif context standard
                    return Some(exif::Tag(exif::Context::Tiff, num));
                }
            }
            None
        }
    }
}

/// Dispatches raw string input into structural metadata filtering parameters.
///
/// Trims quotation marks, matches macro options like `"1"`, and splits multi-value 
/// comma-separated strings to populate the `tags_to_strip` collection.
///
/// # Errors
/// * Returns an error if the stripped input string turns out entirely empty.
/// * Returns an error if an automated task passes option `"2"` (which requires interactive text).
/// * Returns an error if no valid tags could be deduced from a sequence block.
pub fn parse_selection(
    input: &str, 
    tags_to_strip: &mut Vec<exif::Tag>, 
    strip_all: &mut bool
) -> Result<(), &'static str> {
    let clean_input = input.trim().trim_matches('"').trim();

    if clean_input.is_empty() {
        return Err("Selection input cannot be empty.");
    }

    match clean_input {
        "1" => {
            *strip_all = true;
            Ok(())
        }
        "2" => {
            Err("Option '2' is interactive-only. In automated mode, pass tag names directly instead.")
        }
        _ => {
            for item in clean_input.split(',') {
                let trimmed_item = item.trim();
                if trimmed_item.is_empty() {
                    continue;
                }
                if let Some(tag) = parse_tag_name(trimmed_item) {
                    tags_to_strip.push(tag);
                } else {
                    println!("Warning: Skipping unrecognized tag name '{}'", trimmed_item);
                }
            }
            if !*strip_all && tags_to_strip.is_empty() {
                return Err("No valid EXIF tags could be extracted from your input sequence.");
            }
            Ok(())
        }
    }
}