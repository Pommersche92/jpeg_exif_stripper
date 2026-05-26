//! # JPEG EXIF Metadata Stripper Application
//!
//! A high-performance, modular command-line tool written in Rust to surgically 
//! drop specific EXIF tags (such as `Orientation` or location metadata) or entirely 
//! clear the metadata blocks from JPEG headers without re-encoding pixel data.

use std::env;
use std::io::{self, Write};
use std::path::Path;

mod tag_parser;
mod processor;

/// The running build version pulled from the Cargo context manifest macro.
const VERSION: &str = env!("CARGO_PKG_VERSION");
/// The package application identity pulled from the Cargo context manifest macro.
const APP_NAME: &str = env!("CARGO_PKG_NAME");

/// Outputs structured application help guidelines and runtime examples directly to `stdout`.
fn print_help(program_name: &str) {
    println!("{} - JPEG EXIF Metadata Stripper", APP_NAME);
    println!("\nUSAGE:");
    println!("    {} <input_jpeg_path> [strip_selection]", program_name);
    println!("\nFLAGS:");
    println!("    -h, --h, -help, --help       Prints help information");
    println!("    -v, --v, -version, --version   Prints version information");
    println!("\nSTRIP SELECTIONS:");
    println!("    1                            Strips ALL EXIF metadata completely");
    println!("    <Tag Names>                  Comma-separated list of tags to strip out");
    println!("\nSUPPORTED TAG NAMES:");
    println!("    Orientation, Software, DateTime, Make, Model, Copyright,");
    println!("    UserComment, GPSLatitude, GPSLongitude");
    println!("    * Raw hexadecimal addresses are accepted (e.g., '0x0112')");
}

/// Fallback interactive console framework that catches manual runtime queries.
///
/// Pauses system thread runtime, reads manual lines out of `stdin`, passes inputs 
/// downstream to the tag processing router, and halts context if arguments error.
fn handle_interactive_prompt(tags_to_strip: &mut Vec<exif::Tag>, strip_all: &mut bool) {
    println!("Select metadata removal type:");
    println!("[1] Strip ALL EXIF metadata fields completely");
    println!("[Explicit Names] Pass comma-separated tags (e.g., 'Orientation, Software, DateTime')");
    print!("Enter selection choice: ");
    let _ = io::stdout().flush();

    let mut choice = String::new();
    if io::stdin().read_line(&mut choice).is_err() {
        eprintln!("Failed to read standard input line.");
        std::process::exit(1);
    }
    
    if let Err(err_msg) = tag_parser::parse_selection(&choice, tags_to_strip, strip_all) {
        eprintln!("Interactive evaluation error: {}", err_msg);
        std::process::exit(1);
    }
}

/// Entry pipeline interface orchestrating standard CLI tasks.
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    let program_name = args.first().map(|s| s.as_str()).unwrap_or("jpeg_exif_stripper");

    // 1. Flag Verification Loop
    for arg in args.iter().skip(1) {
        match arg.as_str() {
            "-h" | "--h" | "-help" | "--help" => {
                print_help(program_name);
                std::process::exit(0);
            }
            "-v" | "--v" | "-version" | "--version" => {
                println!("{} v{}", APP_NAME, VERSION);
                std::process::exit(0);
            }
            _ => {}
        }
    }

    // 2. Structural Length Guard
    if args.len() < 2 {
        eprintln!("Error: Missing required input file path.");
        println!("Try '{} --help' for options mapping documentation.", program_name);
        std::process::exit(1);
    }
    
    let input_path_str = &args[1];
    let input_path = Path::new(input_path_str);

    if !input_path.exists() {
        eprintln!("Error: The target file '{}' does not exist.", input_path_str);
        std::process::exit(1);
    }

    let output_path = processor::generate_output_path(input_path);
    let mut tags_to_strip: Vec<exif::Tag> = Vec::new();
    let mut strip_all = false;

    // 3. Automation vs Interactive Dispatch
    if args.len() >= 3 {
        let automated_selection = &args[2];
        if let Err(err_msg) = tag_parser::parse_selection(automated_selection, &mut tags_to_strip, &mut strip_all) {
            eprintln!("Automated routing error: {}", err_msg);
            std::process::exit(1);
        }
    } else {
        handle_interactive_prompt(&mut tags_to_strip, &mut strip_all);
    }

    // 4. Operation Delegation Execution
    processor::execute_metadata_strip(input_path, &output_path, &tags_to_strip, strip_all)?;

    Ok(())
}